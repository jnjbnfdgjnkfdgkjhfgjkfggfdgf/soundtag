# SoundTag installer (PowerShell, iex-safe)
# Downloads SoundTag into a .\soundtag folder, installs deps and starts it.
$ErrorActionPreference = "Stop"

$Repo = "https://github.com/soundtag1/soundtag.git"
$Raw = "https://raw.githubusercontent.com/soundtag1/soundtag/main"
$InstallDir = Join-Path (Get-Location) "soundtag"

Write-Host "Installing SoundTag to $InstallDir"

# Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js is required. Install Node.js and re-run."
    return
}

# Warn if ffmpeg missing
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Warning "ffmpeg not found. Audio streaming may not work until it is installed."
}

# Fetch the app: prefer a git clone, fall back to downloading the files.
if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path (Join-Path $InstallDir ".git")) {
        Write-Host "Updating existing install..."
        git -C $InstallDir pull --ff-only
    } else {
        git clone --depth 1 $Repo $InstallDir
    }
} else {
    Write-Host "git not found - downloading files directly."
    New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir "public") | Out-Null
    Invoke-WebRequest "$Raw/server.js"   -OutFile (Join-Path $InstallDir "server.js")
    Invoke-WebRequest "$Raw/package.json" -OutFile (Join-Path $InstallDir "package.json")
    foreach ($f in @("login.html", "control.html", "listener.html")) {
        Invoke-WebRequest "$Raw/public/$f" -OutFile (Join-Path $InstallDir "public\$f")
    }
}

Set-Location $InstallDir

# Install dependencies from package.json
npm install

Write-Host ""
Write-Host "SoundTag installed."
Write-Host "Tip: set your own control-panel login before starting:"
Write-Host '  $env:SOUNDTAG_USER = "admin"'
Write-Host '  $env:SOUNDTAG_PASS = "your-secret-password"'
Write-Host "(If unset, a random password is generated and printed on start.)"
Write-Host ""
Write-Host "Control:  http://localhost:3000/control"
Write-Host "Listener: http://localhost:3000/listener"
Write-Host ""

node server.js
