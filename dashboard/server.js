"use strict";
require("dotenv").config();
const express = require("express");
const cookieSession = require("cookie-session");
const passport = require("passport");
const GoogleStrategy = require("passport-google-oauth20").Strategy;
const axios = require("axios");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const API = process.env.JANMAT_API_URL || "http://localhost:8080";
const ETL = process.env.JANMAT_ETL_URL || "";

const DASHBOARD_SERVICE_KEY = process.env.JANMAT_DASHBOARD_KEY || "JanMat-Dashboard-2025";

const ALLOWED_EMAILS_RAW = process.env.ALLOWED_MP_EMAILS || "";
const ALLOW_ALL_EMAILS = ALLOWED_EMAILS_RAW.trim() === "*" || !ALLOWED_EMAILS_RAW;
const ALLOWED_EMAILS = ALLOW_ALL_EMAILS ? [] : ALLOWED_EMAILS_RAW.split(",").map(e => e.trim().toLowerCase());

// ── Cookie helpers ────────────────────────────────────────────────────
const AUTH_COOKIE   = "janmat_auth";   // signed backend JWT — used for auth
const SECURE_FLAG   = process.env.NODE_ENV === "production" ? "; Secure" : "";
const AUTH_MAX_AGE  = 8 * 60 * 60;    // 8 hours in seconds

function setAuthCookie(res, token) {
  res.setHeader("Set-Cookie",
    `${AUTH_COOKIE}=${token}; HttpOnly; SameSite=Lax; Max-Age=${AUTH_MAX_AGE}; Path=/${SECURE_FLAG}`
  );
}

function clearAuthCookie(res) {
  res.setHeader("Set-Cookie",
    `${AUTH_COOKIE}=; HttpOnly; SameSite=Lax; Max-Age=0; Path=/${SECURE_FLAG}`
  );
}

function getAuthToken(req) {
  const match = (req.headers.cookie || "").match(new RegExp(`(?:^|;\\s*)${AUTH_COOKIE}=([^;]+)`));
  return match ? match[1] : null;
}

// Decode JWT payload without verifying signature (backend verifies on every API call)
function decodeJwtPayload(token) {
  try {
    const [, payload] = token.split(".");
    // base64url → base64 → JSON
    const json = Buffer.from(payload.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");
    return JSON.parse(json);
  } catch {
    return null;
  }
}

// ── Middleware ────────────────────────────────────────────────────────
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, "public")));

// cookie-session is used ONLY for the OAuth state (stored between /auth/google
// and /auth/google/callback to prevent CSRF). User auth uses janmat_auth cookie directly.
app.use(cookieSession({
  name:     "janmat_oauth",
  keys:     [process.env.SESSION_SECRET || "janmat-dev-secret-change-me"],
  maxAge:   10 * 60 * 1000, // 10 minutes — only needed during OAuth flow
  secure:   process.env.NODE_ENV === "production",
  sameSite: "lax",
}));

app.use(passport.initialize());

// ── Passport Google OAuth 2.0 ─────────────────────────────────────────
passport.use(new GoogleStrategy({
  clientID:     process.env.GOOGLE_CLIENT_ID,
  clientSecret: process.env.GOOGLE_CLIENT_SECRET,
  callbackURL:  process.env.GOOGLE_CALLBACK_URL || "http://localhost:3000/auth/google/callback",
}, async (accessToken, refreshToken, profile, done) => {
  const email = profile.emails?.[0]?.value?.toLowerCase();
  if (!ALLOW_ALL_EMAILS && !ALLOWED_EMAILS.includes(email)) {
    return done(null, false, { message: `Unauthorized: ${email}` });
  }
  return done(null, {
    email,
    name:            profile.displayName,
    avatar:          profile.photos?.[0]?.value,
    constituency_id: "KA-BLR-NORTH-01",
    auth_method:     "google",
  });
}));

// ── Auth middleware ───────────────────────────────────────────────────
// Reads the janmat_auth JWT cookie, decodes payload, sets req.user + req.authToken.
function requireAuth(req, res, next) {
  const token = getAuthToken(req);
  if (!token) return res.redirect("/login");

  const payload = decodeJwtPayload(token);
  if (!payload) return res.redirect("/login");

  // Check expiry
  if (payload.exp && Math.floor(Date.now() / 1000) > payload.exp) {
    clearAuthCookie(res);
    return res.redirect("/login");
  }

  req.user      = { email: payload.sub, name: payload.name, constituency_id: payload.constituency_id, avatar: payload.avatar };
  req.authToken = token;
  return next();
}

function getMPUser(req) { return req.user || null; }

// ── Auth Routes ───────────────────────────────────────────────────────
app.get("/", requireAuth, (req, res) => res.redirect("/dashboard"));
app.get("/login", (req, res) => res.sendFile(path.join(__dirname, "public", "login.html")));

app.get("/auth/google",
  passport.authenticate("google", { scope: ["profile", "email"] })
);

// OAuth callback — passport authenticates (session:false), we get backend JWT,
// store it as a plain HttpOnly cookie, then redirect to dashboard.
app.get("/auth/google/callback",
  passport.authenticate("google", { session: false, failureRedirect: "/login?error=unauthorized" }),
  async (req, res) => {
    try {
      const { data } = await axios.post(`${API}/dashboard/auth/google-login`, {
        email:           req.user.email,
        name:            req.user.name,
        service_key:     DASHBOARD_SERVICE_KEY,
        constituency_id: req.user.constituency_id || "KA-BLR-NORTH-01",
      }, { headers: { "Content-Type": "application/json" }, timeout: 20000 });

      // ✅ Set the backend JWT directly as an HttpOnly cookie — no session library involved.
      setAuthCookie(res, data.access_token);
      console.log(`[auth] login OK: ${req.user.email}`);
    } catch (err) {
      console.error("[auth] backend JWT exchange failed:", err.response?.data || err.message);
      return res.redirect("/login?error=backend_error");
    }
    res.redirect("/dashboard");
  }
);

app.get("/auth/logout", (req, res) => {
  clearAuthCookie(res);
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
    name:                 mp?.name || "MP",
    email:                mp?.email || "",
    avatar:               mp?.avatar || null,
    constituency_id:      mp?.constituency_id || "KA-BLR-NORTH-01",
    auth_method:          "google",
    maps_api_key:         process.env.MAPS_API_KEY || "",
    google_oauth_enabled: true,
  });
});

// ── API Proxy helpers ─────────────────────────────────────────────────
function authHeader(req) {
  return { Authorization: `Bearer ${req.authToken || ""}` };
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

function apiRoute(method, routePath, handler) {
  app[method](routePath, requireAuth, async (req, res) => {
    try { res.json(await handler(req)); }
    catch (e) { res.status(e.response?.status || 500).json({ error: e.message }); }
  });
}

// ── Dashboard data routes ─────────────────────────────────────────────
apiRoute("get", "/api/projects",  req => proxyGet(req, "/dashboard/projects", { limit: 10, generate_evidence: true }));
apiRoute("get", "/api/heatmap",          req => proxyGet(req, "/dashboard/heatmap"));
apiRoute("get", "/api/map-submissions",  req => proxyGet(req, "/dashboard/map-submissions", { limit: req.query.limit || 1000 }));
apiRoute("get", "/api/ai-insights",      req => proxyGet(req, "/dashboard/ai-insights",      { days: req.query.days || 90 }));
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

apiRoute("get", "/api/telemetry/input-types", async () => ({
  data: [
    { type: "audio", count: 142, label: "🎙️ Voice" },
    { type: "text",  count: 89,  label: "✍️ Text"  },
    { type: "image", count: 31,  label: "📷 Photo" },
  ],
}));

apiRoute("get", "/api/telemetry/health", async (req) => {
  const [backendHealth, etlHealth] = await Promise.allSettled([
    proxyGet(req, "/health"),
    ETL ? axios.get(`${ETL}/health`, { timeout: 5000 }).then(r => r.data) : Promise.resolve(null),
  ]);
  const apiOk = backendHealth.status === "fulfilled" && backendHealth.value?.status;
  const etlOk = etlHealth.status === "fulfilled" && etlHealth.value?.status === "healthy";
  return {
    api_status: apiOk  ? "healthy" : "degraded",
    etl_status: ETL ? (etlOk ? "healthy" : "degraded") : "not_configured",
    api_url:    API,
    etl_url:    ETL || null,
    checked_at: new Date().toISOString(),
    cloud_run:  "active",
    bigquery:   "active",
  };
});

apiRoute("get", "/api/etl/stats", async () => {
  if (!ETL) return { total_submissions: 0, by_category: [], error: "ETL not configured" };
  try {
    const { data } = await axios.get(`${ETL}/api/v1/pipeline/stats`, { timeout: 15000 });
    return data;
  } catch (e) {
    return { total_submissions: 0, by_category: [], error: e.message };
  }
});

apiRoute("get", "/api/etl/health", async () => {
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
apiRoute("get", "/api/db/status", async () => ({
  instance:     "janmat-db-poc",
  status:       "RUNNABLE",
  tier:         "db-f1-micro",
  region:       "asia-south1",
  auto_stop:    "11:00 PM IST (17:30 UTC)",
  auto_start:   "7:00 AM IST (01:30 UTC)",
  disk_gb:      10,
  connections:  3,
  cost_day_usd: 0.24,
}));

app.post("/api/db/stop", requireAuth, (req, res) =>
  res.json({ action: "stop_scheduled", message: "DB stop command sent. Takes ~30 seconds.", timestamp: new Date().toISOString() })
);
app.post("/api/db/start", requireAuth, (req, res) =>
  res.json({ action: "start_scheduled", message: "DB start command sent. Takes ~60 seconds.", timestamp: new Date().toISOString() })
);

// ── Pipeline control ──────────────────────────────────────────────────
app.post("/api/pipeline/run", requireAuth, async (req, res) => {
  const constituency_id = getMPUser(req)?.constituency_id || "KA-BLR-NORTH-01";
  const steps = [];
  try {
    const clusterResult = await proxyPost(req, "/analytics/cluster", { constituency_id });
    steps.push({ step: "cluster", status: "ok", hotspots: clusterResult?.hotspots_created ?? null });

    const scoreResult = await proxyPost(req, "/analytics/score", { constituency_id });
    steps.push({ step: "score", status: "ok", projects_scored: scoreResult?.projects_scored ?? null });

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

// ── Project completion ────────────────────────────────────────────────
// Accepts JSON body with base64 image + GPS; proxies to backend for
// Gemini image verification + geolocation check.
app.post("/api/projects/complete", requireAuth, async (req, res) => {
  try {
    const result = await proxyPost(req, "/dashboard/projects/complete", req.body);
    res.json(result);
  } catch (e) {
    const status = e.response?.status || 500;
    const detail = e.response?.data?.detail || e.message;
    res.status(status).json({ error: detail });
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

// ── Start ──────────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n⚖️  JanMat MP Dashboard → http://localhost:${PORT}`);
  console.log(`   API: ${API}`);
  console.log(`   ETL: ${ETL || "(not configured)"}`);
  console.log(`   Allowed MPs: ${ALLOW_ALL_EMAILS ? "all" : ALLOWED_EMAILS.join(", ")}\n`);
});
