import './load-env.js';
import bcrypt from "bcryptjs";
import cors from "cors";
import express from "express";
import { OAuth2Client } from "google-auth-library";
import jwt from "jsonwebtoken";
import pg from "pg";
import { readFile } from "node:fs/promises";
import { createMailer } from "./mailer.js";
import { passwordResetRouter } from "./password-reset.js";

const { Pool } = pg;

const port = Number(process.env.PORT || 3001);
const databaseUrl =
  process.env.DATABASE_URL ||
  "postgres://global_village_auth:global_village_auth@localhost:5434/global_village_auth";
const googleClientId = process.env.GOOGLE_WEB_CLIENT_ID || "";
const jwtSecret = process.env.JWT_SECRET || "global-village-dev-secret-change-me";

const pool = new Pool({ connectionString: databaseUrl });
const googleClient = new OAuth2Client();
const app = express();

app.use(cors());
app.use(express.json({ limit: "1mb" }));
app.use("/auth", passwordResetRouter({
  pool,
  mailer: createMailer(),
  secret: process.env.RESET_CODE_SECRET || "",
}));

function clean(value) {
  return typeof value === "string" ? value.trim() : "";
}

function parseBirthDate(value) {
  const input = clean(value);
  if (!input) return null;
  let day;
  let month;
  let year;
  const dmy = input.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (dmy) {
    [, day, month, year] = dmy;
  } else {
    const ymd = input.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!ymd) return null;
    [, year, month, day] = ymd;
  }
  const y = Number(year);
  const m = Number(month);
  const d = Number(day);
  if (y < 1900 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  return `${year}-${month}-${day}`;
}

function parseInterests(value) {
  if (!Array.isArray(value)) return null;
  const cleaned = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const tag = item.trim();
    if (!tag || tag.length > 12) continue;
    if (cleaned.some((e) => e.toLowerCase() === tag.toLowerCase())) continue;
    cleaned.push(tag);
    if (cleaned.length >= 10) break;
  }
  return cleaned;
}

function parseCustomCategories(value, interests) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return {};
  const map = {};
  let count = 0;
  for (const [key, val] of Object.entries(value)) {
    if (typeof key !== "string" || typeof val !== "string") continue;
    const tag = key.trim();
    if (!tag || !interests.includes(tag)) continue;
    const big = val.trim();
    if (!big) continue;
    map[tag] = big;
    if (++count >= 5) break;
  }
  return map;
}

function publicUser(row) {
  let interests = [];
  try {
    const raw = row.interests;
    const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (Array.isArray(parsed)) {
      interests = parsed.filter((e) => typeof e === "string");
    }
  } catch (_) {
    interests = [];
  }
  if (interests.length === 0 && typeof row.interest === "string" && row.interest.trim()) {
    interests = [row.interest.trim()];
  }
  let customCategories = {};
  try {
    const raw = row.custom_categories;
    const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      customCategories = parsed;
    }
  } catch (_) {
    customCategories = {};
  }
  return {
    id: row.id,
    fullName: row.full_name,
    birthDate: row.birth_date instanceof Date
      ? row.birth_date.toISOString().slice(0, 10)
      : row.birth_date,
    interest: row.interest,
    interests,
    customCategories,
    username: row.username,
    email: row.email,
    phone: row.phone,
    community: row.community || "",
    address: row.address || "",
    googlePhotoUrl: row.google_photo_url,
    authProvider: row.auth_provider,
    createdAt: row.created_at,
    lastLoginAt: row.last_login_at,
  };
}

function tokenFor(row) {
  return jwt.sign(
    { sub: row.id, email: row.email, provider: row.auth_provider, version: row.session_version || 0 },
    jwtSecret,
    { expiresIn: "7d" },
  );
}

function authResponse(row) {
  return { token: tokenFor(row), user: publicUser(row) };
}

async function findUserById(id) {
  const result = await pool.query("SELECT * FROM users WHERE id = $1 LIMIT 1", [id]);
  return result.rows[0] || null;
}

async function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) {
    res.status(401).json({ error: "Authentication required." });
    return;
  }
  try {
    req.auth = jwt.verify(token, jwtSecret);
  } catch (_) {
    res.status(401).json({ error: "Invalid or expired session." });
    return;
  }
  try {
    const user = await findUserById(req.auth.sub);
    if (!user || (req.auth.version || 0) !== user.session_version) {
      res.status(401).json({ error: "Session expired. Please sign in again." });
      return;
    }
    next();
  } catch (error) {
    next(error);
  }
}

app.get("/health", async (_req, res, next) => {
  try {
    await pool.query("SELECT 1");
    res.json({ ok: true, service: "global-village-auth-api" });
  } catch (error) {
    next(error);
  }
});

app.post("/auth/register", async (req, res, next) => {
  try {
    const fullName = clean(req.body.fullName);
    const birthDate = parseBirthDate(req.body.birthDate);
    const interest = clean(req.body.interest) || null;
    const username = clean(req.body.username);
    const email = clean(req.body.email).toLowerCase();
    const phone = clean(req.body.phone);
    const password = typeof req.body.password === "string" ? req.body.password : "";
    const securityQuestion = clean(req.body.securityQuestion) || null;
    const securityAnswer = clean(req.body.securityAnswer);

    if (!fullName || !birthDate || !username || !email || !phone || !password) {
      res.status(400).json({ error: "Please complete all required registration fields." });
      return;
    }
    if (password.length < 6) {
      res.status(400).json({ error: "Password must contain at least 6 characters." });
      return;
    }

    const existing = await pool.query(
      `SELECT id, email, username
       FROM users
       WHERE lower(email) = lower($1)
          OR lower(username) = lower($2)
       LIMIT 1`,
      [email, username],
    );
    if (existing.rows.length > 0) {
      const row = existing.rows[0];
      const field = row.email.toLowerCase() === email ? "Email" : "Username";
      res.status(409).json({ error: `${field} is already registered.` });
      return;
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const securityAnswerHash = securityAnswer
      ? await bcrypt.hash(securityAnswer.toLowerCase(), 12)
      : null;

    const result = await pool.query(
      `INSERT INTO users (
        full_name,
        birth_date,
        interest,
        username,
        email,
        phone,
        password_hash,
        security_question,
        security_answer_hash,
        auth_provider
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'local')
      RETURNING *`,
      [
        fullName,
        birthDate,
        interest,
        username,
        email,
        phone,
        passwordHash,
        securityQuestion,
        securityAnswerHash,
      ],
    );

    res.status(201).json({ user: publicUser(result.rows[0]) });
  } catch (error) {
    if (error?.code === "23505") {
      res.status(409).json({ error: "Email or username is already registered." });
      return;
    }
    next(error);
  }
});

app.post("/auth/login", async (req, res, next) => {
  try {
    const account = clean(req.body.account);
    const password = typeof req.body.password === "string" ? req.body.password : "";
    if (!account || !password) {
      res.status(400).json({ error: "Username/email and password are required." });
      return;
    }

    const result = await pool.query(
      `SELECT * FROM users
       WHERE lower(email) = lower($1)
          OR lower(username) = lower($1)
       LIMIT 1`,
      [account],
    );
    const user = result.rows[0];
    if (!user || !user.password_hash) {
      res.status(401).json({ error: "Invalid username/email or password." });
      return;
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      res.status(401).json({ error: "Invalid username/email or password." });
      return;
    }

    const updated = await pool.query(
      `UPDATE users SET last_login_at = now(), updated_at = now()
       WHERE id = $1 AND password_hash = $2 RETURNING *`,
      [user.id, user.password_hash],
    );
    if (!updated.rows.length) {
      res.status(401).json({ error: "Password changed. Please sign in again." });
      return;
    }
    res.json(authResponse(updated.rows[0]));
  } catch (error) {
    next(error);
  }
});

app.post("/auth/google", async (req, res, next) => {
  try {
    const idToken = clean(req.body.idToken);
    if (!idToken) {
      res.status(400).json({ error: "Google ID token is required." });
      return;
    }
    if (!googleClientId) {
      res.status(500).json({ error: "Google login is not configured on the auth server." });
      return;
    }

    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: googleClientId,
    });
    const payload = ticket.getPayload();
    if (!payload?.sub || !payload.email) {
      res.status(401).json({ error: "Google account could not be verified." });
      return;
    }

    const googleSub = payload.sub;
    const email = payload.email.toLowerCase();
    const fullName = clean(payload.name) || email.split("@")[0];
    const photoUrl = clean(payload.picture) || null;

    let userResult = await pool.query(
      "SELECT * FROM users WHERE google_sub = $1 LIMIT 1",
      [googleSub],
    );
    let user = userResult.rows[0];

    if (!user) {
      userResult = await pool.query(
        "SELECT * FROM users WHERE lower(email) = lower($1) LIMIT 1",
        [email],
      );
      user = userResult.rows[0];
    }

    if (user) {
      const provider = user.password_hash ? "local+google" : "google";
      const updated = await pool.query(
        `UPDATE users
         SET google_sub = $1,
             google_photo_url = $2,
             full_name = CASE WHEN full_name = '' THEN $3 ELSE full_name END,
             auth_provider = $4,
             last_login_at = now(),
             updated_at = now()
         WHERE id = $5
         RETURNING *`,
        [googleSub, photoUrl, fullName, provider, user.id],
      );
      res.json(authResponse(updated.rows[0]));
      return;
    }

    const created = await pool.query(
      `INSERT INTO users (
        full_name,
        email,
        google_sub,
        google_photo_url,
        auth_provider,
        last_login_at
      ) VALUES ($1,$2,$3,$4,'google',now())
      RETURNING *`,
      [fullName, email, googleSub, photoUrl],
    );
    res.status(201).json(authResponse(created.rows[0]));
  } catch (error) {
    if (error?.code === "23505") {
      res.status(409).json({ error: "This Google account is already linked to another user." });
      return;
    }
    if (
      typeof error?.message === "string" &&
      (error.message.includes("Wrong recipient") ||
        error.message.includes("Invalid token") ||
        error.message.includes("Token used too late"))
    ) {
      res.status(401).json({ error: "Google sign-in token is invalid or expired." });
      return;
    }
    next(error);
  }
});

app.get("/auth/me", requireAuth, async (req, res, next) => {
  try {
    const user = await findUserById(req.auth.sub);
    if (!user) {
      res.status(404).json({ error: "User not found." });
      return;
    }
    res.json({ user: publicUser(user) });
  } catch (error) {
    next(error);
  }
});

app.patch("/auth/me", requireAuth, async (req, res, next) => {
  try {
    const current = await findUserById(req.auth.sub);
    if (!current) {
      res.status(404).json({ error: "User not found." });
      return;
    }
    const body = req.body && typeof req.body === "object" ? req.body : {};
    const fullName = body.fullName === undefined ? current.full_name : clean(body.fullName);
    const username = body.username === undefined ? current.username : clean(body.username);
    const phone = body.phone === undefined ? current.phone || "" : clean(body.phone);
    const community = body.community === undefined ? current.community || "" : clean(body.community);
    const address = body.address === undefined ? current.address || "" : clean(body.address);
    let birthDate = current.birth_date instanceof Date
      ? current.birth_date.toISOString().slice(0, 10)
      : current.birth_date;
    if (body.birthDate !== undefined) {
      const parsed = parseBirthDate(body.birthDate);
      if (!parsed) {
        res.status(400).json({ error: "Birth date must be YYYY-MM-DD." });
        return;
      }
      birthDate = parsed;
    }
    let interests;
    try {
      const raw = current.interests;
      interests = typeof raw === "string" ? JSON.parse(raw) : raw;
      if (!Array.isArray(interests)) interests = [];
    } catch (_) {
      interests = [];
    }
    if (body.interests !== undefined) {
      const parsed = parseInterests(body.interests);
      if (parsed === null) {
        res.status(400).json({ error: "Interests must be an array of up to 10 tags." });
        return;
      }
      interests = parsed;
    }
    let customCategories = {};
    try {
      const raw = current.custom_categories;
      const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        customCategories = parsed;
      }
    } catch (_) {
      customCategories = {};
    }
    if (body.customCategories !== undefined) {
      customCategories = parseCustomCategories(body.customCategories, interests);
    } else {
      const pruned = {};
      for (const [k, v] of Object.entries(customCategories)) {
        if (interests.includes(k)) pruned[k] = v;
      }
      customCategories = pruned;
    }
    if (!fullName) {
      res.status(400).json({ error: "Name cannot be empty." });
      return;
    }
    if (username) {
      const clash = await pool.query(
        "SELECT id FROM users WHERE lower(username) = lower($1) AND id <> $2 LIMIT 1",
        [username, current.id],
      );
      if (clash.rows.length > 0) {
        res.status(409).json({ error: "Username is already taken." });
        return;
      }
    }
    const legacyInterest = interests.length > 0 ? interests[0] : null;
    const result = await pool.query(
      `UPDATE users SET
        full_name = $1,
        username = $2,
        birth_date = $3,
        phone = $4,
        community = $5,
        address = $6,
        interests = $7::jsonb,
        custom_categories = $8::jsonb,
        interest = $9,
        updated_at = now()
       WHERE id = $10 RETURNING *`,
      [
        fullName,
        username || null,
        birthDate,
        phone || null,
        community || null,
        address || null,
        JSON.stringify(interests),
        JSON.stringify(customCategories),
        legacyInterest,
        current.id,
      ],
    );
    res.json({ user: publicUser(result.rows[0]) });
  } catch (error) {
    if (error?.code === "23505") {
      res.status(409).json({ error: "Username is already taken." });
      return;
    }
    next(error);
  }
});

app.get("/auth/users/search", requireAuth, async (req, res, next) => {
  try {
    const query = clean(req.query.q).toLowerCase();
    if (query.length < 2) {
      res.json({ users: [] });
      return;
    }

    const result = await pool.query(
      `SELECT id, full_name, birth_date, interest, username, email, phone,
              google_photo_url, auth_provider, created_at, last_login_at
       FROM users
       WHERE id::text <> $2
         AND (
           lower(email) LIKE '%' || $1 || '%'
           OR lower(username) LIKE '%' || $1 || '%'
           OR lower(full_name) LIKE '%' || $1 || '%'
         )
       ORDER BY last_login_at DESC NULLS LAST, created_at DESC
       LIMIT 10`,
      [query, req.auth.sub],
    );
    res.json({ users: result.rows.map(publicUser) });
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: "Server error. Please try again." });
});

// Apply additive changes to existing databases before accepting requests.
try { await pool.query(await readFile(new URL("./profile-schema.sql", import.meta.url), "utf8")); }
catch (error) { console.error("Profile schema migration failed.", error); }
const schemaReady = await pool.query(`SELECT
  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'users' AND column_name = 'session_version')
  AND to_regclass('password_reset_codes') IS NOT NULL
  AND to_regclass('auth_rate_limits') IS NOT NULL AS ready`);
if (!schemaReady.rows[0].ready) {
  try { await pool.query(await readFile(new URL("./reset-schema.sql", import.meta.url), "utf8")); }
  catch {
    throw new Error('Password-reset schema is missing. Have the database owner apply auth-server/src/reset-schema.sql once, then restart. Existing database settings were not changed.');
  }
}
const cleanup = setInterval(() => {
  pool.query("DELETE FROM auth_rate_limits WHERE expires_at < now() - interval '1 day'")
    .catch(() => console.error("Rate-limit cleanup failed."));
  pool.query("DELETE FROM password_reset_codes WHERE expires_at < now() - interval '1 day'")
    .catch(() => console.error("Reset-code cleanup failed."));
}, 60 * 60 * 1000);
cleanup.unref();

app.listen(port, "0.0.0.0", () => {
  console.log(`Global Village auth API listening on port ${port}`);
});
