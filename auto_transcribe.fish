#!/usr/bin/env fish

# Define the number of threads for certain operations
set -x OMP_NUM_THREADS 8

# Directory containing the audio files and transcriptions
set audio_dir ~/Transcriptions
set log_file "$audio_dir/auto_transcribe.log"

# Function to rotate the log with OS detection
function rotate_log
    if test -f "$log_file"
        set uname (uname)
        if test "$uname" = "Darwin"
            set filesize (stat -f%z "$log_file")
        else if test "$uname" = "Linux"
            set filesize (stat -c%s "$log_file")
        else
            set filesize (stat -f%z "$log_file")
        end

        if test $filesize -gt 5242880
            set timestamp (date "+%Y%m%d%H%M%S")
            mv "$log_file" "$audio_dir/auto_transcribe.log.$timestamp"
            echo (date "+%Y-%m-%d %H:%M:%S") "Log rotation: auto_transcribe.log renamed to auto_transcribe.log.$timestamp"
        end
    end
end

rotate_log

begin

    # --- Global Lock to Prevent Concurrent Runs ---
    set global_lock /tmp/auto_transcribe.lock
    if test -f "$global_lock"
        set old_pid (cat "$global_lock")
        if ps -p $old_pid > /dev/null
            echo (date "+%Y-%m-%d %H:%M:%S") "Another instance is running. Exiting."
            exit 0
        else
            rm -f "$global_lock"
        end
    end

    # Save the current PID in the lock file
    echo $fish_pid > "$global_lock"

    # Remove the lock and terminate the process group on exit
    trap 'kill -TERM -$fish_pid; rm -f "$global_lock"' EXIT

    # Utility to get the base name without extension and prefix a date if necessary
    function get_base_name --argument file
        set original_file (basename "$file")
        set original_base (string replace -r '\.(m4a|wav)$' '' "$original_file")
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
                echo (date "+%Y-%m-%d %H:%M:%S") "Error: target file $new_file already exists. Renaming canceled." >&2
            else
                mv "$audio_file" "$new_file"
                echo (date "+%Y-%m-%d %H:%M:%S") "Renamed $audio_file to $new_file" >&2
                set audio_file "$new_file"
            end
        end
        printf "%s" "$audio_file"
    end

    # Function to transcribe an audio file
    function transcribe_file --argument audio_file
        set base_name (get_base_name "$audio_file")
        set transcription_file "$audio_dir/$base_name.lrc"
        set lock_file "$audio_dir/$base_name.lock"

        if test -f "$transcription_file"
            echo (date "+%Y-%m-%d %H:%M:%S") "Transcription for $audio_file already exists."
            return 0
        end

        if test -f "$lock_file"
            echo (date "+%Y-%m-%d %H:%M:%S") "Transcription already in progress for $audio_file. Skipping."
            return 0
        end

        touch "$lock_file"
        echo (date "+%Y-%m-%d %H:%M:%S") "Transcribing $audio_file..."

        # Convert to WAV if necessary
        if not string match -q -r '\.wav$' "$audio_file"
            set wav_file "$audio_dir/$base_name.wav"
            ffmpeg -y -i "$audio_file" -ar 16000 "$wav_file"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error converting $audio_file to WAV. Please check file integrity and ffmpeg installation." >&2
                rm -f "$lock_file"
                return 1
            end
            set audio_source "$wav_file"
            set converted 1
        else
            set audio_source "$audio_file"
            set converted 0
        end

        # Use a configurable variable for the model path
        if not set -q MODEL_PATH
            set -x MODEL_PATH "$HOME/Git/auto_transcript/models/ggml-large-v3-turbo.bin"
        end

        if not test -f "$MODEL_PATH"
            echo (date "+%Y-%m-%d %H:%M:%S") "Model file not found. Downloading using download-ggml-model.sh..."
            mkdir -p (dirname "$MODEL_PATH")
            set temp_script /tmp/download-ggml-model.sh
            curl -L -o "$temp_script" "https://raw.githubusercontent.com/ggerganov/whisper.cpp/refs/heads/master/models/download-ggml-model.sh"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error downloading the model download script. Please check your network connection." >&2
                rm -f "$lock_file"
                return 1
            end
            chmod +x "$temp_script"
            bash "$temp_script" large-v3-turbo
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error executing the model download script. Please verify the script's permissions and integrity." >&2
                rm -f "$lock_file"
                return 1
            end
            if test -f /tmp/ggml-large-v3-turbo.bin
                mv /tmp/ggml-large-v3-turbo.bin "$MODEL_PATH"
            else
                echo (date "+%Y-%m-%d %H:%M:%S") "Error: ggml-large-v3-turbo.bin not found after download. Aborting transcription." >&2
                rm -f "$lock_file"
                return 1
            end
        end

        # Launch transcription with whisper-cli
        whisper-cli -olrc -m "$MODEL_PATH" -l fr --threads 8 "$audio_source"
        if test $status -ne 0
            echo (date "+%Y-%m-%d %H:%M:%S") "Error transcribing $audio_source. Please check whisper-cli logs." >&2
        end

        # Optionally rename the transcription file
        if test -f "$audio_dir/$base_name.wav.lrc"
            mv "$audio_dir/$base_name.wav.lrc" "$transcription_file"
        end

        if test $converted -eq 1
            rm -f "$audio_source"
        end
        rm -f "$lock_file"
    end

    # Loop through all .m4a files in the directory
    for audio_file in "$audio_dir"/*.m4a
        if test -f "$audio_file"
            set audio_file (rename_if_needed "$audio_file")
            transcribe_file "$audio_file"
        end
    end

end >> "$log_file" 2>&1