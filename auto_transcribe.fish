#!/usr/bin/env fish

# Set the number of threads for certain operations
set -x OMP_NUM_THREADS 8

# Directory containing audio files and their transcriptions
set audio_dir ~/Transcriptions
set log_file "$audio_dir/auto_transcribe.log"
set script_dir (dirname (status -f))

# Function for log rotation with OS detection
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
    # --- Verify required external commands ---
    if not type -q whisper-cli
        echo (date "+%Y-%m-%d %H:%M:%S") "Error: command whisper-cli not found in PATH." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    end
    if not test -f "$script_dir/ai-summarize.py"
        echo (date "+%Y-%m-%d %H:%M:%S") "Error: ai-summarize.py not found in script directory ($script_dir)." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    end
    if not type -q ffmpeg
        echo (date "+%Y-%m-%d %H:%M:%S") "Error: command ffmpeg not found in PATH." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    end
    if not type -q curl
        echo (date "+%Y-%m-%d %H:%M:%S") "Error: command curl not found in PATH." >> "$audio_dir/auto_transcribe_errors.log"
        exit 1
    end

    # --- Global lock to prevent concurrent execution ---
    set global_lock /tmp/auto_transcribe.lock
    if test -f "$global_lock"
        set old_pid (cat "$global_lock")
        # Validate that the content is a valid PID (positive number)
        if test -n "$old_pid" -a (string match -q '[0-9]+' $old_pid)
            if ps -p $old_pid > /dev/null
                echo (date "+%Y-%m-%d %H:%M:%S") "An instance is already running (PID $old_pid). Exiting."
                exit 0
            else
                rm -f "$global_lock"
            end
        else
            # If the content of the file is not valid, remove the lock file
            rm -f "$global_lock"
        end
    end

    # Save the current PID in the lock file
    echo $fish_pid > "$global_lock"

    # Remove the lock and terminate the process group on exit
    trap 'kill -TERM -$fish_pid; rm -f "$global_lock"' EXIT

    # Utility to get the base name without extension and prefix with a date if needed
    function get_base_name --argument file
        set original_file (basename "$file")
        # Case-insensitive removal of .m4a or .wav extensions
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
                echo (date "+%Y-%m-%d %H:%M:%S") "Error: target file $new_file already exists. Renaming aborted." >> "$audio_dir/auto_transcribe_errors.log"
            else
                mv "$audio_file" "$new_file"
                echo (date "+%Y-%m-%d %H:%M:%S") "Renamed $audio_file to $new_file" >> "$audio_dir/auto_transcribe_errors.log"
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
            echo (date "+%Y-%m-%d %H:%M:%S") "The transcription for $audio_file already exists."
            set summary_file (string replace -r '\.lrc$' '.summary.txt' "$transcription_file")
            if not test -f "$summary_file"
                echo (date "+%Y-%m-%d %H:%M:%S") "Summary not found for $audio_file. Generating summary..."
                summarize_transcription "$transcription_file"
            end
            return 0
        end

        if test -f "$lock_file"
            echo (date "+%Y-%m-%d %H:%M:%S") "A transcription is already in progress for $audio_file. Skipping."
            return 0
        end

        touch "$lock_file"
        echo (date "+%Y-%m-%d %H:%M:%S") "Transcribing $audio_file..."

        # Convert to WAV if necessary (case-insensitive check)
        if not string match -q -r '\.wav$' (string lower "$audio_file")
            set wav_file "$audio_dir/$base_name.wav"
            ffmpeg -y -i "$audio_file" -ar 16000 "$wav_file"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error converting $audio_file to WAV. Check the file integrity and ffmpeg installation." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
            set audio_source "$wav_file"
            set converted 1
        else
            set audio_source "$audio_file"
            set converted 0
        end

        # Configurable model path
        if not set -q MODEL_PATH
            set -x MODEL_PATH "$HOME/Git/auto_transcript/models/ggml-large-v3-turbo.bin"
        end

        if not test -f "$MODEL_PATH"
            echo (date "+%Y-%m-%d %H:%M:%S") "Model file not found. Downloading via download-ggml-model.sh..." >> "$audio_dir/auto_transcribe_errors.log"
            mkdir -p (dirname "$MODEL_PATH")
            set temp_script /tmp/download-ggml-model.sh
            curl -L -o "$temp_script" "https://raw.githubusercontent.com/ggerganov/whisper.cpp/refs/heads/master/models/download-ggml-model.sh"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error downloading the model script. Check your network connection." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
            chmod +x "$temp_script"
            bash "$temp_script" large-v3-turbo
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error running the download script. Check its permissions and integrity." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
            if test -f /tmp/ggml-large-v3-turbo.bin
                # Here, you can add a check for file integrity or size
                mv /tmp/ggml-large-v3-turbo.bin "$MODEL_PATH"
            else
                echo (date "+%Y-%m-%d %H:%M:%S") "Error: ggml-large-v3-turbo.bin not found after download. Aborting transcription." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
        end

        # Start transcription using whisper-cli
        whisper-cli -olrc -m "$MODEL_PATH" -l fr --threads 8 "$audio_source"
        if test $status -ne 0
            echo (date "+%Y-%m-%d %H:%M:%S") "Error transcribing $audio_source. Check whisper-cli logs." >> "$audio_dir/auto_transcribe_errors.log"
        end

        # Optionally rename the transcription file if needed
        if test -f "$audio_dir/$base_name.wav.lrc"
            mv "$audio_dir/$base_name.wav.lrc" "$transcription_file"
        end

        # Generate summary from the transcription, if available
        if test -f "$transcription_file"
            summarize_transcription "$transcription_file"
        end

        if test $converted -eq 1
            rm -f "$audio_source"
        end
        rm -f "$lock_file"
    end

    # Function to summarize the transcription using ai-summarize
    function summarize_transcription --argument transcription_file
        set summary_file (string replace -r '\.lrc$' '.summary.txt' "$transcription_file")
        echo (date "+%Y-%m-%d %H:%M:%S") "Creating summary for $transcription_file..."
        set temp_err (mktemp)
        "$script_dir/ai-summarize.py" "$transcription_file" 1> "$summary_file" 2> "$temp_err"
        set error_output (cat $temp_err)
        rm $temp_err
        if test $status -eq 0
            echo (date "+%Y-%m-%d %H:%M:%S") "Summary saved to $summary_file"
        else
            echo (date "+%Y-%m-%d %H:%M:%S") "Error: failed to create summary for $transcription_file. Details: $error_output" >> "$audio_dir/auto_transcribe_errors.log"
        end
    end

    # Process all .m4a files in the directory
    for audio_file in "$audio_dir"/*.m4a
        if test -f "$audio_file"
            set audio_file (rename_if_needed "$audio_file")
            transcribe_file "$audio_file"
        end
    end

end >> "$log_file" 2>&1