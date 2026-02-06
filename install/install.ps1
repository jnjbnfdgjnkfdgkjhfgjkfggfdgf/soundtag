# SoundTag installer (PowerShell, iex-safe)
$ErrorActionPreference = "Stop"

# Install relative to where the command is run
$BaseDir = Get-Location
$InstallDir = Join-Path $BaseDir "soundtag"

Write-Host "Installing SoundTag to $InstallDir"

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js is required. Install Node.js and re-run."
    return
}

# Warn if ffmpeg missing
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Warning "ffmpeg not found. Audio streaming may not work."
}

# Create folders
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\sounds" | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\public" | Out-Null

Set-Location $InstallDir

# package.json
@"
{
  "name": "soundtag",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "express": "^4.19.2",
    "multer": "^1.4.5-lts.1"
  }
}
"@ | Out-File -Encoding UTF8 package.json

npm install

# server.js
@"
const express = require("express");
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const multer = require("multer");

const app = express();
const clients = new Set();
let ffmpeg = null;

const soundsDir = path.join(__dirname, "sounds");
if (!fs.existsSync(soundsDir)) fs.mkdirSync(soundsDir);

const upload = multer({ dest: soundsDir });

app.use(express.json());
app.use(express.static("public"));

app.get("/stream", (req, res) => {
  res.writeHead(200, {
    "Content-Type": "audio/mpeg",
    "Cache-Control": "no-cache",
    "Connection": "keep-alive"
  });
  clients.add(res);
  req.on("close", () => clients.delete(res));
});

function startSilence() {
  if (ffmpeg) ffmpeg.kill("SIGKILL");
  ffmpeg = spawn("ffmpeg", ["-f","lavfi","-i","anullsrc","-f","mp3","pipe:1"]);
  ffmpeg.stdout.on("data", c => clients.forEach(r => r.write(c)));
}

function startFile(f) {
  if (ffmpeg) ffmpeg.kill("SIGKILL");
  ffmpeg = spawn("ffmpeg", ["-re","-i",f,"-f","mp3","pipe:1"]);
  ffmpeg.stdout.on("data", c => clients.forEach(r => r.write(c)));
}

app.get("/files", (req, res) => {
  res.json(fs.readdirSync(soundsDir).filter(f => /\.(mp3|wav|ogg|m4a)$/i.test(f)));
});

app.post("/upload", upload.single("file"), (req, res) => {
  const name = req.file.originalname.replace(/[^\w.-]/g,"_");
  fs.renameSync(req.file.path, path.join(soundsDir, name));
  res.json({ ok:true });
});

app.post("/play/:file", (req,res)=>{
  startFile(path.join(soundsDir, req.params.file));
  res.json({ ok:true });
});

app.post("/stop", (req,res)=>{
  startSilence();
  res.json({ ok:true });
});

app.listen(3000, ()=>{
  console.log("SoundTag running at http://localhost:3000");
  startSilence();
});
"@ | Out-File -Encoding UTF8 server.js

# listener.html
@"
<!DOCTYPE html>
<html>
<body style="margin:0;background:white;height:100vh">
<script>
const a=new Audio("/stream");
function u(){a.play().catch(()=>{});}
document.addEventListener("click",u,{once:true});
document.addEventListener("touchstart",u,{once:true});
</script>
</body>
</html>
"@ | Out-File -Encoding UTF8 public\listener.html

# control.html
@"
<!DOCTYPE html>
<html>
<body style="margin:0;padding:16px;font-family:system-ui;background:#0b0b10;color:#fff">
<h1>SoundTag</h1>
<input id="u" type="file" accept="audio/*"><br><br>
<div id="list">Loading…</div><br>
<button onclick="fetch('/stop',{method:'POST'})">Stop (Silent)</button>
<script>
async function load(){
  const r=await fetch('/files');
  const f=await r.json();
  list.innerHTML='';
  f.forEach(n=>{
    const d=document.createElement('div');
    d.style.padding='12px';
    d.style.cursor='pointer';
    d.textContent=n;
    d.onclick=()=>fetch('/play/'+encodeURIComponent(n),{method:'POST'});
    list.appendChild(d);
  });
}
u.onchange=async()=>{
  const fd=new FormData();
  fd.append('file',u.files[0]);
  await fetch('/upload',{method:'POST',body:fd});
  load();
};
load();
</script>
</body>
</html>
"@ | Out-File -Encoding UTF8 public\control.html

Write-Host ""
Write-Host "SoundTag installed successfully."
Write-Host "Control:  http://localhost:3000/control"
Write-Host "Listener: http://localhost:3000/listener"
Write-Host ""

node server.js
