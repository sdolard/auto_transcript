#!/usr/bin/env bash
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
set -e

echo "Installing dependencies..."

# Installer fish si nécessaire
if ! command -v fish >/dev/null 2>&1; then
    echo "Fish shell not found. Installing fish..."
    if command -v brew >/dev/null 2>&1; then
        brew install fish
    else
        echo "$(date "+%Y-%m-%d %H:%M:%S") Error: Homebrew is not installed. Please install fish manually." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    fi
fi

# Installer ffmpeg si nécessaire
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "FFmpeg not found. Installing ffmpeg..."
    if command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
    else
        echo "$(date "+%Y-%m-%d %H:%M:%S") Error: Homebrew is not installed. Please install ffmpeg manually." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    fi
fi

# Installer python3 si nécessaire
if ! command -v python3 >/dev/null 2>&1; then
    echo "Python3 not found. Installing python3..."
    if command -v brew >/dev/null 2>&1; then
        brew install python
    else
        echo "$(date "+%Y-%m-%d %H:%M:%S")" "Error: Homebrew is not installed. Please install python3 manually." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    fi
fi

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

# Add installation for whisper-cli
if ! command -v whisper-cli >/dev/null 2>&1; then
    echo "whisper-cli not found. Installing whisper-cli..."
    if command -v brew >/dev/null 2>&1; then
        brew install whisper-cpp
    else
        echo "$(date "+%Y-%m-%d %H:%M:%S") Error: Homebrew is not installed. Please install whisper-cpp manually." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    fi
fi

echo "Dependencies installed."

echo "Configuring cron job..."

# Dynamically resolve the full path to fish
fish_path=$(command -v fish)

CRON_CMD="* * * * * export PATH=/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin && source \"$ROOT_DIR/venv/bin/activate\" && $fish_path \"$ROOT_DIR/auto_transcribe.fish\" >> \"$ROOT_DIR/cron.log\" 2>&1"
( crontab -l 2>/dev/null | grep -F "$CRON_CMD" ) || ( ( crontab -l 2>/dev/null; echo "$CRON_CMD" ) | crontab - )

echo "Installation completed."
