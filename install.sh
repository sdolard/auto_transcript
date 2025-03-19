#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
set -euo pipefail
LOG_FILE="$ROOT_DIR/auto_transcribe_errors.log"

check_and_install() {
    local cmd="$1"
    local brew_pkg="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd not found. Installing $brew_pkg..."
        if command -v brew >/dev/null 2>&1; then
            brew install "$brew_pkg"
        else
            echo "$(date "+%Y-%m-%d %H:%M:%S") Error: Homebrew is not installed. Please install $brew_pkg manually." >> "$LOG_FILE"
            exit 1
        fi
    fi
}

echo "Installing dependencies..."

check_and_install fish fish
check_and_install ffmpeg ffmpeg
check_and_install python3 python
check_and_install whisper-cli whisper-cpp

# Création et configuration de l'environnement virtuel pour ai-summarize
VENV_DIR="$ROOT_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment in $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

echo "Installing Python dependencies in the virtual environment..."
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"
pip install --upgrade openai
deactivate

# Ajouter l'exécution pour le script ai-summarize (facultatif : définir les permissions)
chmod +x "$ROOT_DIR/ai-summarize.py"

echo "Dependencies installed."

echo "Configuring cron job..."

# Dynamically resolve the full path to fish
fish_path=$(command -v fish)

CRON_CMD="* * * * * export PATH=/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin && source \"$ROOT_DIR/venv/bin/activate\" && $fish_path \"$ROOT_DIR/auto_transcribe.fish\" >> \"$ROOT_DIR/cron.log\" 2>&1"
( crontab -l 2>/dev/null | grep -F "$CRON_CMD" ) || ( ( crontab -l 2>/dev/null; echo "$CRON_CMD" ) | crontab - )

echo "Installation completed."
