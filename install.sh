#!/usr/bin/env bash
set -e

echo "Installing dependencies..."

# Installer fish si nécessaire
if ! command -v fish >/dev/null 2>&1; then
    echo "Fish shell not found. Installing fish..."
    if command -v brew >/dev/null 2>&1; then
        brew install fish
    else
        echo "Homebrew is not installed. Please install fish manually."
        exit 1
    fi
fi

# Installer ffmpeg si nécessaire
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "FFmpeg not found. Installing ffmpeg..."
    if command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
    else
        echo "Homebrew is not installed. Please install ffmpeg manually."
        exit 1
    fi
fi

# Installer python3 si nécessaire
if ! command -v python3 >/dev/null 2>&1; then
    echo "Python3 not found. Installing python3..."
    if command -v brew >/dev/null 2>&1; then
        brew install python
    else
        echo "Homebrew is not installed. Please install python3 manually."
        exit 1
    fi
fi

# Add installation for whisper-cli
if ! command -v whisper-cli >/dev/null 2>&1; then
    echo "whisper-cli not found. Installing whisper-cli..."
    if command -v brew >/dev/null 2>&1; then
        brew install whisper-cpp
    else
        echo "Homebrew is not installed. Please install whisper-cpp manually."
        exit 1
    fi
fi

echo "Dependencies installed."

echo "Configuring cron job..."

# Dynamically resolve the full path to fish
fish_path=$(command -v fish)

CRON_CMD="* * * * * $fish_path /Users/seb/Git/auto_transcript/auto_transcribe.fish >> /Users/seb/Git/auto_transcript/cron.log 2>&1"
( crontab -l 2>/dev/null | grep -F "$CRON_CMD" ) || ( ( crontab -l 2>/dev/null; echo "$CRON_CMD" ) | crontab - )

echo "Installation completed."
