#!/usr/bin/env bash
set -e

echo "Installing dependencies..."

# Check and install Fish if necessary
if ! command -v fish >/dev/null 2>&1; then
    echo "Fish shell not found. Installing fish..."
    if command -v brew >/dev/null 2>&1; then
        brew install fish
    else
        echo "Homebrew is not installed. Please install fish manually."
        exit 1
    fi
fi

# Check and install FFmpeg if necessary
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "FFmpeg not found. Installing ffmpeg..."
    if command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
    else
        echo "Homebrew is not installed. Please install ffmpeg manually."
        exit 1
    fi
fi

# Check and install Python 3.12 if necessary
if ! command -v python3.12 >/dev/null 2>&1; then
    echo "Python 3.12 not found. Installing python3.12..."
    if command -v brew >/dev/null 2>&1; then
        brew install python@3.12
    else
        echo "Homebrew is not installed. Please install Python 3.12 manually."
        exit 1
    fi
fi

# Create virtual environment if it doesn't already exist using Python 3.12
if [ ! -d "venv" ]; then
    echo "Creating virtual environment with Python 3.12..."
    python3.12 -m venv venv
fi

echo "Activating virtual environment..."
# Activate the virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install WhisperX in the virtual environment
if ! command -v whisperx >/dev/null 2>&1; then
    echo "whisperx not found in the virtual environment. Installing whisperx..."
    pip install whisperx
fi

# Verify whisperx installation
if ! command -v whisperx >/dev/null 2>&1; then
    echo "Error: whisperx was not installed correctly."
    exit 1
fi

echo "Dependencies installed and WhisperX configured in the virtual environment."

echo "Configuring cron job..."

# Dynamically resolve the full path to fish
fish_path=$(command -v fish)

# Modify the cron command to activate the virtual environment before executing the fish script
CRON_CMD="* * * * * cd /Users/seb/Git/auto_transcript && . ./venv/bin/activate && $fish_path auto_transcribe.fish >> /Users/seb/Git/auto_transcript/cron.log 2>&1"
( crontab -l 2>/dev/null | grep -F "$CRON_CMD" ) || ( ( crontab -l 2>/dev/null; echo "$CRON_CMD" ) | crontab - )

echo "Installation complete."