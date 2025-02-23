#!/usr/bin/env fish
# Replace current activation
# source ./venv/bin/activate.fish
# Use a Fish-compatible activation:
set -lx VIRTUAL_ENV (pwd)/venv
set -lx PATH $VIRTUAL_ENV/bin $PATH

# Setting the number of threads for some operations
set -x OMP_NUM_THREADS 8

# Directory containing audio files and transcripts
set audio_dir ~/Transcriptions
set log_file "$audio_dir/auto_transcribe.log"

# Log rotation function with OS detection
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
            echo (date "+%Y-%m-%d %H:%M:%S") "Log rotation: log file renamed."
        end
    end
end

rotate_log

begin
    # --- Global lock to prevent concurrent executions ---
    set global_lock /tmp/auto_transcribe.lock
    if test -f "$global_lock"
        set old_pid (cat "$global_lock")
        if ps -p $old_pid > /dev/null
            echo (date "+%Y-%m-%d %H:%M:%S") "Another instance is already running. Exiting."
            exit 0
        else
            rm -f "$global_lock"
        end
    end

    # Save the current PID in the lock file
    echo $fish_pid > "$global_lock"

    # Remove the lock and terminate on exit
    trap 'kill -TERM -$fish_pid; rm -f "$global_lock"' EXIT

    # Function to get the base name of the file with a date prefix if needed
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

    # Function to rename the audio file if necessary
    function rename_if_needed --argument audio_file
        set original_file (basename "$audio_file")
        if not string match -q -r '^[0-9]{4}-[0-9]{2}-[0-9]{2}' "$original_file"
            set base_name (get_base_name "$original_file")
            set extension (string match -r -- '\.[^.]+$' "$original_file")
            set new_file "$audio_dir/$base_name$extension"
            if test -f "$new_file"
                echo (date "+%Y-%m-%d %H:%M:%S") "Error: target file $new_file already exists." >&2
            else
                mv "$audio_file" "$new_file"
                echo (date "+%Y-%m-%d %H:%M:%S") "Renamed $audio_file to $new_file" >&2
                set audio_file "$new_file"
            end
        end
        printf "%s" "$audio_file"
    end

    # Function for transcription and diarization using WhisperX
    function transcribe_file --argument audio_file
        set base_name (get_base_name "$audio_file")
        set transcription_file "$audio_dir/$base_name.txt"
        set diarization_file "$audio_dir/$base_name.diarization.json"
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
        echo (date "+%Y-%m-%d %H:%M:%S") "Transcribing $audio_file with WhisperX..."

        # Converting to WAV if needed
        if not string match -q -r '\.wav$' "$audio_file"
            set wav_file "$audio_dir/$base_name.wav"
            ffmpeg -y -i "$audio_file" -ar 16000 "$wav_file"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error converting $audio_file to WAV." >&2
                rm -f "$lock_file"
                return 1
            end
            set audio_source "$wav_file"
            set converted 1
        else
            set audio_source "$audio_file"
            set converted 0
        end

        # Add a check for the whisperx command before using it
        if not type -q whisperx
            echo "Error: whisperx command not found. Please install whisperx."
            rm -f "$lock_file"
            return 1
        end

        # Call WhisperX for transcription and diarization
        whisperx "$audio_source" --model large-v3-turbo --language fr --diarize --threads 8 --output_dir "$audio_dir"
        if test $status -ne 0
            echo (date "+%Y-%m-%d %H:%M:%S") "Error transcribing $audio_source with WhisperX." >&2
        end

        # Check for the creation of the transcription file
        if test -f "$audio_dir/$base_name.txt"
            echo (date "+%Y-%m-%d %H:%M:%S") "Transcription saved to $audio_dir/$base_name.txt"
        else
            echo (date "+%Y-%m-%d %H:%M:%S") "Error: transcript file not found." >&2
        end

        if test $converted -eq 1
            rm -f "$audio_source"
        end
        rm -f "$lock_file"
    end

    # Loop through all .m4a files in the folder
    for audio_file in "$audio_dir"/*.m4a
        if test -f "$audio_file"
            set audio_file (rename_if_needed "$audio_file")
            transcribe_file "$audio_file"
        end
    end

end >> "$log_file" 2>&1