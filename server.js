const express = require("express");
const session = require("express-session");
const { spawn } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const multer = require("multer");

const app = express();
const clients = new Set();
let ffmpeg = null;

const soundsDir = path.join(__dirname, "sounds");
if (!fs.existsSync(soundsDir)) {
  fs.mkdirSync(soundsDir, { recursive: true });
}

const publicDir = path.join(__dirname, "public");

/* ------------------------------------------------------------------ *
 * Authentication configuration (local auth)
 *
 * Credentials come from environment variables so nothing secret is
 * committed to the repo:
 *   SOUNDTAG_USER    – username (default "admin")
 *   SOUNDTAG_PASS    – password (if unset, a random one is generated
 *                      and printed to the console on startup)
 *   SESSION_SECRET   – cookie signing secret (random if unset)
 * ------------------------------------------------------------------ */
const AUTH_USER = process.env.SOUNDTAG_USER || "admin";
let AUTH_PASS = process.env.SOUNDTAG_PASS;
if (!AUTH_PASS) {
  AUTH_PASS = crypto.randomBytes(9).toString("base64url");
  console.log("\n[SoundTag] No SOUNDTAG_PASS set — generated a temporary password:");
  console.log(`[SoundTag]   username: ${AUTH_USER}`);
  console.log(`[SoundTag]   password: ${AUTH_PASS}`);
  console.log("[SoundTag] Set SOUNDTAG_USER / SOUNDTAG_PASS to choose your own.\n");
}

/* Constant-time credential comparison to avoid timing leaks. */
function safeEqual(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(
  session({
    secret: process.env.SESSION_SECRET || crypto.randomBytes(16).toString("hex"),
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: "lax",
      maxAge: 1000 * 60 * 60 * 12, // 12 hours
    },
  })
);

/* Require a logged-in session on an API route (always 401 JSON). */
function requireAuth(req, res, next) {
  if (req.session && req.session.authed) return next();
  return res.status(401).json({ error: "Authentication required" });
}

/* Require a logged-in session on an HTML page (redirect to /login). */
function requirePage(req, res, next) {
  if (req.session && req.session.authed) return next();
  return res.redirect("/login");
}

/* ------------------------------------------------------------------ *
 * Auth routes
 * ------------------------------------------------------------------ */
app.post("/api/login", (req, res) => {
  const { username, password } = req.body || {};
  if (safeEqual(username || "", AUTH_USER) && safeEqual(password || "", AUTH_PASS)) {
    req.session.authed = true;
    req.session.user = AUTH_USER;
    return res.json({ ok: true });
  }
  return res.status(401).json({ error: "Invalid username or password" });
});

app.post("/api/logout", (req, res) => {
  req.session.destroy(() => res.json({ ok: true }));
});

app.get("/api/me", (req, res) => {
  res.json({ authed: !!(req.session && req.session.authed), user: req.session?.user || null });
});

/* Control panel page is gated; everything else in /public is public. */
app.get(["/control", "/control.html"], requirePage, (req, res) => {
  res.sendFile(path.join(publicDir, "control.html"));
});

app.use(express.static(publicDir, { index: false }));

/* ------------------------------------------------------------------ *
 * Public streaming endpoint (listeners need this without a login)
 * ------------------------------------------------------------------ */
app.get("/stream", (req, res) => {
  res.writeHead(200, {
    "Content-Type": "audio/mpeg",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });
  clients.add(res);
  req.on("close", () => {
    clients.delete(res);
  });
});

/* ------------------------------------------------------------------ *
 * ffmpeg stream helpers
 * ------------------------------------------------------------------ */
function pipeFfmpeg(proc) {
  proc.stdout.on("data", (chunk) => {
    for (const client of clients) {
      client.write(chunk);
    }
  });
  proc.stderr.on("data", () => {});
  proc.on("error", (err) => {
    console.error("[SoundTag] ffmpeg failed to start:", err.message);
  });
}

function startSilence() {
  if (ffmpeg) ffmpeg.kill("SIGKILL");
  ffmpeg = spawn("ffmpeg", [
    "-f", "lavfi",
    "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
    "-f", "mp3",
    "pipe:1",
  ]);
  pipeFfmpeg(ffmpeg);
}

function startFile(filePath) {
  if (ffmpeg) ffmpeg.kill("SIGKILL");
  ffmpeg = spawn("ffmpeg", ["-re", "-i", filePath, "-f", "mp3", "pipe:1"]);
  pipeFfmpeg(ffmpeg);
}

/* ------------------------------------------------------------------ *
 * Protected control API
 * ------------------------------------------------------------------ */
const AUDIO_RE = /\.(mp3|wav|ogg|m4a)$/i;

const upload = multer({
  dest: soundsDir,
  limits: { fileSize: 30 * 1024 * 1024 }, // 30 MB
  fileFilter: (req, file, cb) => {
    cb(null, AUDIO_RE.test(file.originalname));
  },
});

app.get("/files", requireAuth, (req, res) => {
  fs.readdir(soundsDir, (err, files) => {
    if (err) {
      return res.status(500).json({ error: "Failed to read sounds directory" });
    }
    res.json(files.filter((f) => AUDIO_RE.test(f)));
  });
});

app.post("/upload", requireAuth, upload.single("file"), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "No audio file uploaded" });
  }
  // Strip any path components and unsafe characters from the name.
  const safeName = path
    .basename(req.file.originalname)
    .replace(/[^\w.-]/g, "_");
  if (!AUDIO_RE.test(safeName)) {
    fs.unlink(req.file.path, () => {});
    return res.status(400).json({ error: "Unsupported file type" });
  }
  const targetPath = path.join(soundsDir, safeName);
  fs.rename(req.file.path, targetPath, (err) => {
    if (err) {
      return res.status(500).json({ error: "Failed to save file" });
    }
    res.json({ success: true, file: safeName });
  });
});

app.post("/play/:file", requireAuth, (req, res) => {
  // Reject path traversal: resolve and confirm the file stays in soundsDir.
  const safeName = path.basename(req.params.file);
  const fullPath = path.join(soundsDir, safeName);
  if (path.dirname(fullPath) !== soundsDir || !AUDIO_RE.test(safeName)) {
    return res.status(400).json({ error: "Invalid file name" });
  }
  if (!fs.existsSync(fullPath)) {
    return res.status(404).json({ error: "File not found" });
  }
  startFile(fullPath);
  res.json({ success: true });
});

app.post("/stop", requireAuth, (req, res) => {
  startSilence();
  res.json({ success: true });
});

/* ------------------------------------------------------------------ */
const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`SoundTag server running on port ${PORT}`);
  console.log("Sign in:      /login");
  console.log("Control panel: /control");
  console.log("Listener page: /listener");
  startSilence();
});
