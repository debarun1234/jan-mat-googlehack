-- JanMat — Cloud SQL PostgreSQL Operational Schema
-- Run against: janmat database
-- Purpose: Real-time tracking, MP auth, department routing
-- Analytics (citizen_grievances, hotspots, scoring) lives in BigQuery

-- ─────────────────────────────────────────
-- Extensions
-- ─────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";       -- For fuzzy text search

-- ─────────────────────────────────────────
-- Departments
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS departments (
    department_id   UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
    code            VARCHAR(20) NOT NULL UNIQUE,  -- EDUCATION, HEALTH, ROADS, WATER, SANITATION
    name            VARCHAR(100) NOT NULL,
    sla_hours       INT         NOT NULL DEFAULT 72,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO departments (code, name, sla_hours) VALUES
    ('EDUCATION',   'Education Department',           96),
    ('HEALTH',      'Health & Family Welfare',        48),
    ('ROADS',       'Public Works Department (Roads)',72),
    ('WATER',       'Water Resources & Supply',       24),
    ('SANITATION',  'Urban Local Bodies / Sanitation',48)
ON CONFLICT (code) DO NOTHING;

-- ─────────────────────────────────────────
-- MP Accounts (dashboard login)
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mp_accounts (
    mp_id               UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
    name                VARCHAR(200) NOT NULL,
    email               VARCHAR(200) NOT NULL UNIQUE,
    phone               VARCHAR(20),
    constituency_id     VARCHAR(50)  NOT NULL,
    constituency_name   VARCHAR(200),
    password_hash       TEXT         NOT NULL,
    is_active           BOOLEAN      DEFAULT TRUE,
    created_at          TIMESTAMPTZ  DEFAULT NOW(),
    last_login          TIMESTAMPTZ
);

-- Demo MP account (password: janmat@2024 — hash via bcrypt)
INSERT INTO mp_accounts (name, email, phone, constituency_id, constituency_name, password_hash)
VALUES (
    'Demo MP',
    'mp@janmat.demo',
    '+919000000000',
    'KA-BLR-NORTH-01',
    'Bangalore North',
    '$2b$12$placeholder_hash_replace_before_deploy'
) ON CONFLICT (email) DO NOTHING;

-- ─────────────────────────────────────────
-- Submission Tracking (real-time status)
-- Mirrors key fields from BQ citizen_grievances
-- for fast status lookups without BQ query cost
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS submission_tracking (
    submission_id       UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
    external_id         VARCHAR(100) UNIQUE,  -- BigQuery submission_id for cross-reference
    status              VARCHAR(30)  NOT NULL DEFAULT 'PENDING',
    -- PENDING → PROCESSING → PROCESSED → ERROR
    input_type          VARCHAR(10)  NOT NULL,  -- text | audio | image
    category            VARCHAR(20),
    constituency_id     VARCHAR(50),
    submitted_at        TIMESTAMPTZ  DEFAULT NOW(),
    processed_at        TIMESTAMPTZ,
    error_message       TEXT,
    pubsub_message_id   VARCHAR(200),
    retry_count         INT          DEFAULT 0,

    CONSTRAINT status_valid CHECK (status IN ('PENDING', 'PROCESSING', 'PROCESSED', 'ERROR'))
);

CREATE INDEX idx_submission_status ON submission_tracking(status);
CREATE INDEX idx_submission_constituency ON submission_tracking(constituency_id);
CREATE INDEX idx_submission_submitted_at ON submission_tracking(submitted_at DESC);

-- ─────────────────────────────────────────
-- Evidence Cache
-- Gemini Evidence Logs are expensive to regenerate
-- Cache them here per hotspot_id
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS evidence_cache (
    cache_id            UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
    hotspot_id          VARCHAR(100) NOT NULL UNIQUE,
    constituency_id     VARCHAR(50)  NOT NULL,
    category            VARCHAR(20)  NOT NULL,
    evidence_log        TEXT         NOT NULL,
    priority_score      DECIMAL(6,4),
    priority_rank       INT,
    suggested_project   VARCHAR(500),
    generated_at        TIMESTAMPTZ  DEFAULT NOW(),
    expires_at          TIMESTAMPTZ  DEFAULT NOW() + INTERVAL '6 hours',
    gemini_model_used   VARCHAR(100)
);

CREATE INDEX idx_evidence_constituency ON evidence_cache(constituency_id);
CREATE INDEX idx_evidence_expires ON evidence_cache(expires_at);

-- ─────────────────────────────────────────
-- API Rate Limiting (per IP / per session)
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rate_limit_buckets (
    bucket_key      VARCHAR(100) PRIMARY KEY,  -- ip:endpoint or session_id:endpoint
    request_count   INT          DEFAULT 0,
    window_start    TIMESTAMPTZ  DEFAULT NOW(),
    blocked_until   TIMESTAMPTZ
);

-- ─────────────────────────────────────────
-- Audit Log
-- ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
    log_id          UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
    event_type      VARCHAR(50)  NOT NULL,
    actor           VARCHAR(200),
    resource_id     VARCHAR(200),
    resource_type   VARCHAR(50),
    details         JSONB,
    created_at      TIMESTAMPTZ  DEFAULT NOW()
);

CREATE INDEX idx_audit_event ON audit_log(event_type, created_at DESC);
