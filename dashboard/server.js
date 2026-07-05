"use strict";
require("dotenv").config();
const express = require("express");
const session = require("express-session");
const passport = require("passport");
const GoogleStrategy = require("passport-google-oauth20").Strategy;
const axios = require("axios");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const API = process.env.JANMAT_API_URL || "http://localhost:8080";
const ETL = process.env.JANMAT_ETL_URL || "";
const ALLOWED_EMAILS_RAW = process.env.ALLOWED_MP_EMAILS || "mp@janmat.demo,quantumduobuilder@gmail.com";
const ALLOW_ALL_EMAILS = ALLOWED_EMAILS_RAW.trim() === "*";
const ALLOWED_EMAILS = ALLOW_ALL_EMAILS ? [] : ALLOWED_EMAILS_RAW.split(",").map(e => e.trim().toLowerCase());
const DEMO_MODE = process.env.DEMO_MODE === "true";

// ── Middleware ────────────────────────────────────────────────────────
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, "public")));
app.use(session({
  secret: process.env.SESSION_SECRET || "janmat-dev-secret-change-me",
  resave: false,
  saveUninitialized: false,
  cookie: { secure: false, maxAge: 8 * 60 * 60 * 1000 },
}));
app.use(passport.initialize());
app.use(passport.session());

// ── Passport Google OAuth 2.0 ─────────────────────────────────────────
if (process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET) {
  passport.use(new GoogleStrategy({
    clientID:     process.env.GOOGLE_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET,
    callbackURL:  process.env.GOOGLE_CALLBACK_URL || "http://localhost:3000/auth/google/callback",
  }, async (accessToken, refreshToken, profile, done) => {
    const email = profile.emails?.[0]?.value?.toLowerCase();
    if (!ALLOW_ALL_EMAILS && !ALLOWED_EMAILS.includes(email)) {
      return done(null, false, { message: `Unauthorized: ${email} is not an authorized MP` });
    }
    const user = {
      google_id:  profile.id,
      email,
      name:       profile.displayName,
      avatar:     profile.photos?.[0]?.value,
      constituency_id: "KA-BLR-NORTH-01",
      auth_method: "google",
    };
    return done(null, user);
  }));
}

passport.serializeUser((user, done) => done(null, user));
passport.deserializeUser((user, done) => done(null, user));

// ── Auth middleware ───────────────────────────────────────────────────
function requireAuth(req, res, next) {
  if (req.isAuthenticated()) return next();
  if (req.session?.mp) return next();        // demo session
  res.redirect("/login");
}

function getMPUser(req) {
  return req.user || req.session?.mp || null;
}

// ── Auth Routes ───────────────────────────────────────────────────────

app.get("/", requireAuth, (req, res) => res.redirect("/dashboard"));

app.get("/login", (req, res) => res.sendFile(path.join(__dirname, "public", "login.html")));

// Google OAuth redirect
app.get("/auth/google",
  passport.authenticate("google", { scope: ["profile", "email"] })
);

// Google OAuth callback
app.get("/auth/google/callback",
  passport.authenticate("google", { failureRedirect: "/login?error=unauthorized" }),
  async (req, res) => {
    // Get API token for this MP
    try {
      const params = new URLSearchParams({ username: req.user.email, password: "JanMat@2025!", grant_type: "password" });
      const { data } = await axios.post(`${API}/dashboard/auth/login`, params.toString(), {
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        timeout: 5000,
      });
      req.session.apiToken = data.access_token;
    } catch (_) { /* API token optional for OAuth users */ }
    res.redirect("/dashboard");
  }
);

// Demo login (password fallback)
app.post("/auth/login", async (req, res) => {
  const { username, password } = req.body;
  if (!DEMO_MODE) return res.redirect("/login?error=Use+Google+Sign+In");
  if (username === process.env.DEMO_USER && password === process.env.DEMO_PASS) {
    // Set session immediately — API token is optional enrichment
    req.session.mp = { name: "Demo MP", email: username, constituency_id: "KA-BLR-NORTH-01", auth_method: "demo" };
    try {
      const params = new URLSearchParams({ username, password, grant_type: "password" });
      const { data } = await axios.post(`${API}/dashboard/auth/login`, params.toString(), {
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        timeout: 3000,
      });
      req.session.apiToken = data.access_token;
    } catch (_) { /* API token optional in demo mode */ }
    return res.redirect("/dashboard");
  }
  res.redirect("/login?error=Invalid+credentials");
});

app.get("/auth/logout", (req, res) => {
  req.logout(() => {});
  req.session.destroy();
  res.redirect("/login");
});

// ── Main SPA ──────────────────────────────────────────────────────────
app.get("/dashboard", requireAuth, (req, res) => {
  res.sendFile(path.join(__dirname, "public", "dashboard.html"));
});

// ── Session info ──────────────────────────────────────────────────────
app.get("/api/session", requireAuth, (req, res) => {
  const mp = getMPUser(req);
  res.json({
    name:            mp?.name || mp?.displayName || "MP",
    email:           mp?.email || "",
    avatar:          mp?.avatar || null,
    constituency_id: mp?.constituency_id || "KA-BLR-NORTH-01",
    auth_method:     mp?.auth_method || "unknown",
    maps_api_key:    process.env.MAPS_API_KEY || "",
    google_oauth_enabled: !!(process.env.GOOGLE_CLIENT_ID),
  });
});

// ── API Proxy helpers ─────────────────────────────────────────────────
function authHeader(req) {
  return { Authorization: `Bearer ${req.session.apiToken || ""}` };
}

async function proxyGet(req, apiPath, params = {}) {
  const { data } = await axios.get(`${API}${apiPath}`, {
    headers: authHeader(req), params, timeout: 30000,
  });
  return data;
}

async function proxyPost(req, apiPath, body = {}) {
  const { data } = await axios.post(`${API}${apiPath}`, body, {
    headers: { ...authHeader(req), "Content-Type": "application/json" },
    timeout: 60000,
  });
  return data;
}

function apiRoute(method, path, handler) {
  app[method](path, requireAuth, async (req, res) => {
    try { res.json(await handler(req)); }
    catch (e) { res.status(e.response?.status || 500).json({ error: e.message }); }
  });
}

// ── Dashboard data routes ─────────────────────────────────────────────

apiRoute("get", "/api/projects",  req => proxyGet(req, "/dashboard/projects", { limit: 10, generate_evidence: true }));
apiRoute("get", "/api/heatmap",   req => proxyGet(req, "/dashboard/heatmap"));
apiRoute("get", "/api/trends",    req => proxyGet(req, "/dashboard/trends", { days: req.query.days || 30 }));
apiRoute("get", "/api/stats/:id", req => proxyGet(req, `/analytics/stats/${req.params.id}`));

// ── Telemetry ─────────────────────────────────────────────────────────

apiRoute("get", "/api/telemetry/overview", async (req) => {
  const constituency_id = getMPUser(req)?.constituency_id || "KA-BLR-NORTH-01";
  const [stats, projects, trends] = await Promise.allSettled([
    proxyGet(req, `/analytics/stats/${constituency_id}`),
    proxyGet(req, "/dashboard/projects", { limit: 10, generate_evidence: false }),
    proxyGet(req, "/dashboard/trends", { days: 30 }),
  ]);
  return {
    stats:    stats.status    === "fulfilled" ? stats.value    : null,
    projects: projects.status === "fulfilled" ? projects.value : null,
    trends:   trends.status   === "fulfilled" ? trends.value   : null,
  };
});

// Submission volume by input type (mock enrichment over stats)
apiRoute("get", "/api/telemetry/input-types", async (req) => {
  return { data: [
    { type: "audio", count: 142, label: "🎙️ Voice" },
    { type: "text",  count: 89,  label: "✍️ Text"  },
    { type: "image", count: 31,  label: "📷 Photo" },
  ]};
});

// System health metrics — checks both backend and ETL
apiRoute("get", "/api/telemetry/health", async (req) => {
  const [backendHealth, etlHealth] = await Promise.allSettled([
    proxyGet(req, "/health"),
    ETL ? axios.get(`${ETL}/health`, { timeout: 5000 }).then(r => r.data) : Promise.resolve(null),
  ]);
  const apiOk = backendHealth.status === "fulfilled" && backendHealth.value?.status;
  const etlOk = etlHealth.status === "fulfilled" && etlHealth.value?.status === "healthy";
  return {
    api_status:  apiOk  ? "healthy" : "degraded",
    etl_status:  ETL ? (etlOk ? "healthy" : "degraded") : "not_configured",
    api_url:     API,
    etl_url:     ETL || null,
    checked_at:  new Date().toISOString(),
    cloud_run:   "active",
    bigquery:    "active",
  };
});

// ETL pipeline stats — submission counts by category from BigQuery (via ETL)
apiRoute("get", "/api/etl/stats", async (req) => {
  if (!ETL) return { total_submissions: 0, by_category: [], error: "ETL not configured" };
  try {
    const { data } = await axios.get(`${ETL}/api/v1/pipeline/stats`, { timeout: 15000 });
    return data;
  } catch (e) {
    return { total_submissions: 0, by_category: [], error: e.message };
  }
});

// ETL health probe
apiRoute("get", "/api/etl/health", async (_req) => {
  if (!ETL) return { status: "not_configured" };
  try {
    const { data } = await axios.get(`${ETL}/health`, { timeout: 5000 });
    return data;
  } catch (e) {
    return { status: "unreachable", error: e.message };
  }
});

// ── User management ───────────────────────────────────────────────────

apiRoute("get", "/api/users", async (req) => {
  const { city, state, limit = 50, offset = 0 } = req.query;
  return proxyGet(req, "/users/admin/list", { city, state, limit, offset });
});

// ── Database control ──────────────────────────────────────────────────

apiRoute("get", "/api/db/status", async (_req) => {
  // In production: call gcloud SQL Admin API
  // For POC: return mock status
  return {
    instance: "janmat-db-poc",
    status: "RUNNABLE",
    tier: "db-f1-micro",
    region: "asia-south1",
    auto_stop:  "11:00 PM IST (17:30 UTC)",
    auto_start: "7:00 AM IST (01:30 UTC)",
    disk_gb: 10,
    connections: 3,
    cost_day_usd: 0.24,
  };
});

app.post("/api/db/stop", requireAuth, async (req, res) => {
  // Production: PATCH sqladmin.googleapis.com/v1/projects/.../instances/... activationPolicy=NEVER
  res.json({ action: "stop_scheduled", message: "DB stop command sent. Takes ~30 seconds.", timestamp: new Date().toISOString() });
});

app.post("/api/db/start", requireAuth, async (req, res) => {
  res.json({ action: "start_scheduled", message: "DB start command sent. Takes ~60 seconds.", timestamp: new Date().toISOString() });
});

// ── Pipeline control ──────────────────────────────────────────────────

// Run the full analytics pipeline:
//   1. Cluster  — group citizen grievances into geographic demand hotspots
//   2. Score    — compute priority scores (P = 0.6×Demand + 0.4×Gap)
//   3. Evidence — generate Gemini Evidence Logs for top-ranked projects
// The ETL service runs independently (triggered by Pub/Sub) and is not called here.
app.post("/api/pipeline/run", requireAuth, async (req, res) => {
  const constituency_id = getMPUser(req)?.constituency_id || "KA-BLR-NORTH-01";
  const steps = [];
  try {
    const clusterResult = await proxyPost(req, "/analytics/cluster", { constituency_id });
    steps.push({ step: "cluster", status: "ok", hotspots: clusterResult?.hotspots_created ?? null });

    const scoreResult = await proxyPost(req, "/analytics/score", { constituency_id });
    steps.push({ step: "score", status: "ok", projects_scored: scoreResult?.projects_scored ?? null });

    // Evidence generation is best-effort — non-fatal if Gemini is slow
    try {
      const evidenceResult = await proxyPost(req, "/analytics/evidence", { constituency_id, top_n: 5 });
      steps.push({ step: "evidence", status: "ok", generated: evidenceResult?.evidence_generated ?? null });
    } catch (evErr) {
      steps.push({ step: "evidence", status: "skipped", reason: evErr.message });
    }

    res.json({ status: "success", constituency_id, steps, ran_at: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ error: e.message, steps });
  }
});

// ── CSV export ────────────────────────────────────────────────────────
app.get("/api/export/csv", requireAuth, async (req, res) => {
  try {
    const response = await axios.get(`${API}/dashboard/export/csv`, {
      headers: authHeader(req), responseType: "stream",
    });
    res.setHeader("Content-Type", "text/csv");
    res.setHeader("Content-Disposition", response.headers["content-disposition"] || "attachment; filename=priorities.csv");
    response.data.pipe(res);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Start ─────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n⚖️  JanMat MP Dashboard → http://localhost:${PORT}`);
  console.log(`   API: ${API}`);
  console.log(`   ETL: ${ETL || "(not configured)"}`);
  console.log(`   Google OAuth: ${process.env.GOOGLE_CLIENT_ID ? "✅ enabled" : "⚠️  not configured (demo mode)"}`);
  console.log(`   Allowed MPs: ${ALLOWED_EMAILS.join(", ")}\n`);
});
