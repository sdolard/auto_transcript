# auto_transcript

auto_transcript is a tool designed to automate the transcription of audio files. It listens for new audio files (in .m4a format) in a specified directory, renames them appropriately, converts them to WAV if needed, and transcribes them using whisper-cli. A model file (ggml-large-v3-turbo.bin) is downloaded automatically if it isn’t found locally, then moved to the models folder. It also supports optional diarization.

## Installation

Simply run the install script, which installs all required dependencies (Fish Shell, FFmpeg, Python3, and whisper-cli):

```bash
./install.sh
```

## Usage

- Place your audio files (in .m4a format) in the designated directory (default is ~/Transcriptions).
- The script `auto_transcribe.fish` will automatically rename, convert, and transcribe the audio files.
- Transcriptions are saved as .lrc files in the same directory.
- Logs are recorded in the `auto_transcribe.log` file.

The script is set up as a cron job via the install script, ensuring periodic execution.

## Additional Information

- The repository automatically downloads the model if not present and moves it to `/Users/seb/Git/auto_transcript/models`.
- Optional diarization support is available (currently commented out in the script); modify the script to enable it if required.
- For troubleshooting, review the log file and ensure that the install script ran successfully.

For further assistance, please file an issue in the repository.