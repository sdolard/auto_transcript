#!/usr/bin/env fish

# =============================================================================
# Configuration
# =============================================================================

# Function to detect the number of available CPU cores
function get_cpu_count
    set uname (uname)
    set cpu_count 4 # Default fallback value

    if test "$uname" = Darwin
        # macOS: use sysctl to get logical CPU count
        set cpu_count (/usr/sbin/sysctl -n hw.ncpu 2>/dev/null)
    else if test "$uname" = Linux
        # Linux: use nproc --all if available, fallback to /proc/cpuinfo
        if command -v nproc >/dev/null
            set cpu_count (nproc --all 2>/dev/null)
        else
            set cpu_count (grep -c processor /proc/cpuinfo 2>/dev/null)
        end
    end

    # Make sure we have a valid numeric value
    if not test "$cpu_count" -gt 0 2>/dev/null
        set cpu_count 2 # Use default if not a positive number
    end

    echo $cpu_count
end

# Constants for configuration
# Capture the output of get_cpu_count with command substitution
set cpu_threads (get_cpu_count)
set THREADS $cpu_threads
set -x OMP_NUM_THREADS $THREADS
set LOG_MAX_SIZE 5242880 # Log rotation threshold in bytes (5MB)
set LOAD_THRESHOLD $cpu_threads # System load average threshold for deferring transcription

# Directory containing the audio files and their transcriptions
set audio_dir ~/Transcriptions
set log_file "$audio_dir/auto_transcribe.log"
set script_dir (dirname (status -f))

# -----------------------------------------------------------------------------
# Logging Function
# -----------------------------------------------------------------------------
function log_message
    # Logs a message with a timestamp to the log file
    set message $argv
    echo (date "+%Y-%m-%d %H:%M:%S") $message >>"$log_file"
end

# =============================================================================
# Utility Functions
# =============================================================================

# Rotate the log file with OS detection
function rotate_log
    if test -f "$log_file"
        set uname (uname)
        if test "$uname" = Darwin
            set filesize (stat -f%z "$log_file")
        else if test "$uname" = Linux
            set filesize (stat -c%s "$log_file")
        else
            set filesize (stat -f%z "$log_file")
        end

        if test $filesize -gt $LOG_MAX_SIZE
            set timestamp (date "+%Y%m%d%H%M%S")
            mv "$log_file" "$audio_dir/auto_transcribe.log.$timestamp"
            log_message "Log rotation: auto_transcribe.log renamed to auto_transcribe.log.$timestamp"
        end
    end
end

# Get the base name without extension and prefix with the date if needed
function get_base_name --argument file
    set original_file (basename "$file")
    # Remove case-insensitive extensions .m4a or .wav
    set original_base (string replace -r '(?i)\.(m4a|wav)$' '' "$original_file")
    if not string match -q -r '^[0-9]{4}-[0-9]{2}-[0-9]{2}' "$original_base"
        set base_name (date "+%Y-%m-%d")-"$original_base"
    else
        set base_name "$original_base"
    end
    echo "$base_name"
end

# Rename the audio file if its name does not start with a date
function rename_if_needed --argument audio_file
    set original_file (basename "$audio_file")
    if not string match -q -r '^[0-9]{4}-[0-9]{2}-[0-9]{2}' "$original_file"
        set base_name (get_base_name "$original_file")
        set extension (string match -r -- '\.[^.]+$' "$original_file")
        set new_file "$audio_dir/$base_name$extension"
        if test -f "$new_file"
            log_message "Error: target file $new_file already exists. Renaming aborted."
        else
            mv "$audio_file" "$new_file"
            log_message "Renamed $audio_file to $new_file"
            set audio_file "$new_file"
        end
    end
    printf "%s" "$audio_file"
end

# -----------------------------------------------------------------------------
# Download Model Function
# -----------------------------------------------------------------------------
function download_model
    # Downloads the model file if it does not exist and stores it in the models folder
    log_message "Model file not found. Downloading..."
    set model_dir "$script_dir/models"
    mkdir -p "$model_dir"
    set -x MODEL_PATH "$model_dir/ggml-large-v3-turbo.bin"
    set temp_script /tmp/download-ggml-model.sh
    curl -L -o "$temp_script" "https://raw.githubusercontent.com/ggerganov/whisper.cpp/refs/heads/master/models/download-ggml-model.sh"
    if test $status -ne 0
        log_message "Error downloading the model script."
        return 1
    end
    chmod +x "$temp_script"
    bash "$temp_script" large-v3-turbo "$model_dir"
    if test $status -ne 0
        log_message "Error executing the model download script."
        return 1
    end
    if test -f "$model_dir/ggml-large-v3-turbo.bin"
        # Model downloaded directly to the models folder
        log_message "Model downloaded successfully to $model_dir."
    else if test -f /tmp/ggml-large-v3-turbo.bin
        # Fallback: move from /tmp if not directly downloaded
        mv /tmp/ggml-large-v3-turbo.bin "$MODEL_PATH"
        if test $status -ne 0
            log_message "Error moving the downloaded model file from /tmp."
            return 1
        end
    else
        log_message "Error: ggml-large-v3-turbo.bin not found after download."
        return 1
    end
    return 0
end

# Function to create the summary by calling ai-summarize.py with the venv python interpreter and saving the result to a file
function summarize_transcription --argument transcription_file
    set summary_file (string replace -r '\.lrc$' '.summary.md' "$transcription_file")
    set base_title (basename "$transcription_file" .lrc)
    "$script_dir/venv/bin/python3" "$script_dir/ai-summarize.py" "$transcription_file" "$base_title" >"$summary_file"
end

# Transcribe an audio file
function transcribe_file --argument audio_file
    set base_name (get_base_name "$audio_file")
    set transcription_file "$audio_dir/$base_name.lrc"
    set lock_file "$audio_dir/$base_name.lock"

    if test -f "$lock_file"
        log_message "A transcription is already in progress for $audio_file. Skipping."
        return 0
    end

    touch "$lock_file"

    # ---------------------------------------------
    # Step 1: Convert to WAV format if needed
    # ---------------------------------------------
    set converted 0
    set audio_source ""
    if test -f "$transcription_file"
        # Existing transcription: delete the WAV file if it exists
        set wav_file "$audio_dir/$base_name.wav"
        if test -f "$wav_file"
            rm -f "$wav_file"
            log_message "Removed existing WAV file: $wav_file (transcription already exists)."
        end
        set audio_source "$audio_file"
    else
        if not string match -q -r '\.wav$' (string lower "$audio_file")
            set wav_file "$audio_dir/$base_name.wav"
            if test -f "$wav_file"
                log_message "Conversion already performed for $audio_file (existing WAV file: $wav_file)."
                set audio_source "$wav_file"
            else
                log_message "Converting $audio_file to WAV format..."
                ffmpeg -y -i "$audio_file" -af "afftdn, highpass=f=80, lowpass=f=8000, dynaudnorm, acompressor=threshold=-20dB:ratio=3:attack=200:release=1000" -ar 16000 "$wav_file"
                if test $status -ne 0
                    log_message "Error converting $audio_file to WAV."
                    rm -f "$lock_file"
                    return 1
                end
                set audio_source "$wav_file"
                set converted 1
            end
        else
            set audio_source "$audio_file"
        end
    end

    # ---------------------------------------------
    # Step 2: Transcription
    # ---------------------------------------------
    if test -f "$transcription_file"
        log_message "Transcription already exists for $audio_file ($transcription_file exists)."
    else
        log_message "Transcribing $audio_source..."
        # Verify and set the model path if not defined
        if not set -q MODEL_PATH
            set -x MODEL_PATH "$script_dir/models/ggml-large-v3-turbo.bin"
        end
        if not test -f "$MODEL_PATH"
            download_model
            if test $status -ne 0
                rm -f "$lock_file"
                return 1
            end
        end

        # Check system load before transcription
        set os (uname)
        if test "$os" = Linux
            set load_avg (cat /proc/loadavg | cut -d' ' -f1)
        else if test "$os" = Darwin
            set load_avg (uptime | grep -o "load averages: [0-9.]*" | awk '{print $3}')
            if test -z "$load_avg"
                set load_avg (uptime | awk -F'[, ]' '{for (i=1; i<=NF; i++) if (index($i, ".") > 0) {print $i; exit}}')
            end
        else
            set load_avg 0
        end

        # Calculate if load exceeds threshold first, then test the result
        set load_check (echo "$load_avg" | awk -v thresh=$LOAD_THRESHOLD '{if ($1 > thresh) print 1; else print 0}')
        if test $load_check -eq 1
            log_message "High system load ($load_avg). Transcription deferred for $audio_source."
            rm -f "$lock_file"
            return 0
        end

        # Run transcription with whisper-cli
        whisper-cli -olrc \
            -m "$MODEL_PATH" \
            -l fr \
            --threads $THREADS \
            --entropy-thold 2.0 \
            --temperature 0.2 \
            --best-of 5 \
            --suppress-nst \
            --max-context 0 \
            -f "$audio_source"
        if test $status -ne 0
            log_message "Error during transcription of $audio_source."
            rm -f "$lock_file"
            return 1
        end

        # Rename the generated transcription file
        if test -f "$audio_dir/$base_name.wav.lrc"
            mv "$audio_dir/$base_name.wav.lrc" "$transcription_file"
        else
            log_message "Error: transcription file not generated for $audio_source."
            rm -f "$lock_file"
            return 1
        end
    end

    # ---------------------------------------------
    # Step 3: Create Summary
    # ---------------------------------------------
    set summary_file (string replace -r '\.lrc$' '.summary.md' "$transcription_file")
    if test -f "$summary_file"
        log_message "Summary already exists for $audio_file ($summary_file exists)."
    else if test -f "$transcription_file"
        log_message "Creating summary for $transcription_file..."
        summarize_transcription "$transcription_file"
    end

    rm -f "$lock_file"
end

# =============================================================================
# Main Execution
# =============================================================================

# Rotate log file
rotate_log

begin
    # --- Verify required external commands ---
    if not type -q whisper-cli
        log_message "Error: command whisper-cli not found in PATH."
        exit 1
    end
    if not test -f "$script_dir/ai-summarize.py"
        log_message "Error: ai-summarize.py not found in script directory ($script_dir)."
        exit 1
    end
    if not type -q ffmpeg
        log_message "Error: command ffmpeg not found in PATH."
        exit 1
    end
    if not type -q curl
        log_message "Error: command curl not found in PATH."
        exit 1
    end

    # --- Global lock to prevent concurrent executions ---
    set global_lock /tmp/auto_transcribe.lock
    if test -f "$global_lock"
        set old_pid (cat "$global_lock" | string trim)
        if test -n "$old_pid"
            if ps -p $old_pid >/dev/null
                log_message "An instance is already running (PID $old_pid). Exiting."
                exit 0
            else
                rm -f "$global_lock"
            end
        else
            rm -f "$global_lock"
        end
    end

    # Save the current PID into the lock file
    echo $fish_pid >"$global_lock"

    # Log the creation of the global lock
    log_message "Global lock created ($global_lock) with PID $fish_pid"

    # Set a trap to log and remove the global lock upon exit
    trap 'log_message "Removing global lock ($global_lock)"; rm -f "$global_lock"' EXIT

    # Process all .m4a and .mp3 files in the directory
    for audio_file in "$audio_dir"/*.m4a
        if test -f "$audio_file"
            set audio_file (rename_if_needed "$audio_file")
            transcribe_file "$audio_file"
        end
    end

end >>"$log_file" 2>&1
