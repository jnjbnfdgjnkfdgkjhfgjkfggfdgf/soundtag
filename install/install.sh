#!/bin/bash
# SoundTag installer for macOS / Linux
# Downloads SoundTag into a ./soundtag folder, installs deps and starts it.
set -e

REPO="https://github.com/soundtag1/soundtag.git"
RAW="https://raw.githubusercontent.com/soundtag1/soundtag/main"
INSTALL_DIR="$(pwd)/soundtag"

echo "Installing SoundTag to $INSTALL_DIR"

# Check Node.js
if ! command -v node >/dev/null 2>&1; then
  echo "[ERROR] Node.js not found. Install Node.js and re-run."
  exit 1
fi

# Warn if ffmpeg missing
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[WARNING] ffmpeg not found. The sound stream may not work until it is installed."
fi

# Fetch the app: prefer a git clone, fall back to downloading the files.
if command -v git >/dev/null 2>&1; then
  if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Updating existing install..."
    git -C "$INSTALL_DIR" pull --ff-only
  else
    git clone --depth 1 "$REPO" "$INSTALL_DIR"
  fi
else
  echo "git not found — downloading files directly."
  mkdir -p "$INSTALL_DIR/public"
  for f in server.js package.json; do
    curl -fsSL "$RAW/$f" -o "$INSTALL_DIR/$f"
  done
  for f in login.html control.html listener.html; do
    curl -fsSL "$RAW/public/$f" -o "$INSTALL_DIR/public/$f"
  done
fi

cd "$INSTALL_DIR"

# Install dependencies from package.json
npm install

echo ""
echo "SoundTag installed."
echo "Tip: set your own control-panel login before starting:"
echo "  export SOUNDTAG_USER=admin"
echo "  export SOUNDTAG_PASS=your-secret-password"
echo "(If unset, a random password is generated and printed below.)"
echo ""
echo "Starting SoundTag at http://localhost:3000"
node server.js
