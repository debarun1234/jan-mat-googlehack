-- ════════════════════════════════════════════════════════════════════
-- JanMat — User Profiles & Transparency
-- Migration 002: citizen user profiles + OTP tracking
-- ════════════════════════════════════════════════════════════════════

-- Citizen user profiles (collected at registration)
CREATE TABLE IF NOT EXISTS user_profiles (
    user_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid    VARCHAR(128) UNIQUE NOT NULL,   -- Firebase Auth UID
    phone_number    VARCHAR(20) UNIQUE NOT NULL,    -- E.164 format: +919876543210
    full_name       VARCHAR(200) NOT NULL,
    town            VARCHAR(200),
    city            VARCHAR(200) NOT NULL,
    state           VARCHAR(100) NOT NULL,
    pin_code        VARCHAR(10) NOT NULL,
    constituency_id VARCHAR(50),                    -- auto-assigned from pin_code
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ,
    submission_count INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT pin_code_format CHECK (pin_code ~ '^[1-9][0-9]{5}$')
);

CREATE INDEX IF NOT EXISTS idx_user_profiles_constituency ON user_profiles(constituency_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_state ON user_profiles(state);
CREATE INDEX IF NOT EXISTS idx_user_profiles_city ON user_profiles(city);
CREATE INDEX IF NOT EXISTS idx_user_profiles_created ON user_profiles(created_at DESC);

-- Link submissions to users (optional — maintains anonymity if user_id is NULL)
ALTER TABLE submission_tracking
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES user_profiles(user_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_submission_user ON submission_tracking(user_id);

-- Pincode → constituency mapping (seed for Bangalore North area)
CREATE TABLE IF NOT EXISTS pincode_constituency (
    pin_code        VARCHAR(10) PRIMARY KEY,
    constituency_id VARCHAR(50) NOT NULL,
    constituency_name VARCHAR(200) NOT NULL,
    district        VARCHAR(100),
    state           VARCHAR(100)
);

INSERT INTO pincode_constituency (pin_code, constituency_id, constituency_name, district, state) VALUES
    ('560064', 'KA-BLR-NORTH-01', 'Bangalore North', 'Bangalore Urban', 'Karnataka'),
    ('560065', 'KA-BLR-NORTH-01', 'Bangalore North', 'Bangalore Urban', 'Karnataka'),
    ('560092', 'KA-BLR-NORTH-01', 'Bangalore North', 'Bangalore Urban', 'Karnataka'),
    ('560097', 'KA-BLR-NORTH-01', 'Bangalore North', 'Bangalore Urban', 'Karnataka'),
    ('560024', 'KA-BLR-NORTH-01', 'Bangalore North', 'Bangalore Urban', 'Karnataka'),
    ('560043', 'KA-BLR-NORTH-01', 'Bangalore North', 'Bangalore Urban', 'Karnataka'),
    ('560073', 'KA-BLR-NORTH-01', 'Bangalore North', 'Bangalore Urban', 'Karnataka')
ON CONFLICT (pin_code) DO NOTHING;

-- MP accounts — upgraded with Google OAuth fields
ALTER TABLE mp_accounts
    ADD COLUMN IF NOT EXISTS google_sub      VARCHAR(256) UNIQUE,  -- Google OAuth subject
    ADD COLUMN IF NOT EXISTS avatar_url      TEXT,
    ADD COLUMN IF NOT EXISTS last_login_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS allowed_emails  TEXT[]; -- extra authorized emails for this constituency

-- Update demo MP with Google-ready fields
UPDATE mp_accounts
SET allowed_emails = ARRAY['mp@janmat.demo', 'quantumduobuilder@gmail.com']
WHERE constituency_id = 'KA-BLR-NORTH-01';

-- Transparency log — every time MP views citizen data, it's recorded
CREATE TABLE IF NOT EXISTS transparency_log (
    log_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mp_email        VARCHAR(320) NOT NULL,
    action          VARCHAR(100) NOT NULL,  -- 'view_users', 'export_csv', 'view_submission'
    constituency_id VARCHAR(50),
    target_user_id  UUID REFERENCES user_profiles(user_id) ON DELETE SET NULL,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transparency_mp ON transparency_log(mp_email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transparency_user ON transparency_log(target_user_id);

-- Function: auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER IF NOT EXISTS trg_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
