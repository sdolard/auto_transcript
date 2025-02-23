#!/usr/bin/env fish

set -x HF_TOKEN ""
set -x OMP_NUM_THREADS 8

# Directory containing audio files and results
set audio_dir ~/Transcriptions
set log_file "$audio_dir/auto_transcribe.log"

# Function to rotate log: if file size exceeds 5 MB, it is renamed with a timestamp.
function rotate_log
    if test -f "$log_file"
        # On macOS, stat -f%z returns the file size in bytes
        set filesize (stat -f%z "$log_file")
        # Threshold set to 5 MB (5*1024*1024 = 5242880 bytes)
        if test $filesize -gt 5242880
            set timestamp (date "+%Y%m%d%H%M%S")
            mv "$log_file" "$audio_dir/auto_transcribe.log.$timestamp"
            echo (date "+%Y-%m-%d %H:%M:%S") "Log rotation: auto_transcribe.log renamed to auto_transcribe.log.$timestamp"
        end
    end
end

rotate_log

# Group the script logic in a begin/end block with redirection applied.
begin

    # --- Global Lock to Prevent Concurrent Runs ---
    set global_lock /tmp/auto_transcribe.lock
    if test -f "$global_lock"
        echo (date "+%Y-%m-%d %H:%M:%S") "Another instance is running. Exiting."
        exit 0
    end

    # Save the process PID in the lock file
    echo $fish_pid > "$global_lock"

    # Kill the process group on exit and clean up the global lock
    trap 'kill -TERM -$fish_pid; rm -f "$global_lock"' EXIT

    # Utility function to get the base name without extension.
    # Si le nom ne commence pas par une date, on la préfixe.
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

    # Function to rename the original file si nécessaire, en conservant l'extension.
    # On s'appuie sur get_base_name pour obtenir le nom sans extension.
    function rename_if_needed --argument audio_file
        set original_file (basename "$audio_file")
        # Si le fichier n'est pas déjà préfixé par une date, on le renomme.
        if not string match -q -r '^[0-9]{4}-[0-9]{2}-[0-9]{2}' "$original_file"
            set base_name (get_base_name "$original_file")
            # Extraction de l'extension (tout ce qui suit le dernier point)
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
        # On renvoie le chemin final (sans retour à la ligne superflu)
        printf "%s" "$audio_file"
    end

    # Function for transcription
    function transcribe_file --argument audio_file
        # On récupère le nom de base (sans extension)
        set base_name (get_base_name "$audio_file")
        # Le fichier de transcription aura l'extension .lrc uniquement
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

        # Si le fichier n'est pas en WAV, on le convertit
        if not string match -q -r '\.wav$' "$audio_file"
            set wav_file "$audio_dir/$base_name.wav"
            ffmpeg -y -i "$audio_file" -ar 16000 "$wav_file"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error converting $audio_file to WAV."
                rm -f "$lock_file"
                return 1
            end
            set audio_source "$wav_file"
            set converted 1
        else
            set audio_source "$audio_file"
            set converted 0
        end

        # Vérification du modèle pour la transcription
        set model_path /Users/seb/Git/auto_transcript/models/ggml-large-v3-turbo.bin
        if not test -f "$model_path"
            echo (date "+%Y-%m-%d %H:%M:%S") "Model file not found. Downloading using download-ggml-model.sh..."
            mkdir -p (dirname "$model_path")
            set temp_script /tmp/download-ggml-model.sh
            curl -L -o "$temp_script" "https://raw.githubusercontent.com/ggerganov/whisper.cpp/refs/heads/master/models/download-ggml-model.sh"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error downloading the model download script."
                rm -f "$lock_file"
                return 1
            end
            chmod +x "$temp_script"
            bash "$temp_script" large-v3-turbo
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Error executing the model download script."
                rm -f "$lock_file"
                return 1
            end
            if test -f /tmp/ggml-large-v3-turbo.bin
                mv /tmp/ggml-large-v3-turbo.bin "$model_path"
            else
                echo (date "+%Y-%m-%d %H:%M:%S") "Error: ggml-large-v3-turbo.bin not found after download."
                rm -f "$lock_file"
                return 1
            end
        end

        # Lancement de la transcription avec whisper-cli
        whisper-cli -olrc -m "$model_path" -l fr --threads 8 "$audio_source"
        if test $status -ne 0
            echo (date "+%Y-%m-%d %H:%M:%S") "Error transcribing $audio_source."
        end

        # Si le fichier de transcription a été créé sous la forme .wav.lrc, on le renomme en .lrc
        if test -f "$audio_dir/$base_name.wav.lrc"
            mv "$audio_dir/$base_name.wav.lrc" "$transcription_file"
        end

        if test $converted -eq 1
            rm -f "$audio_source"
        end
        rm -f "$lock_file"
    end

    # Function for diarization (optionnelle)
    function diarize_file --argument audio_file
        set base_name (get_base_name "$audio_file")
        set speakers_file "$audio_dir/$base_name.speakers.txt"
        set speaker_lock_file "$audio_dir/$base_name.speaker.lock"

        if test -f "$speakers_file"
            echo (date "+%Y-%m-%d %H:%M:%S") "Diarization for $audio_file already exists."
            return 0
        end

        if test -f "$speaker_lock_file"
            echo (date "+%Y-%m-%d %H:%M:%S") "Diarization already in progress for $audio_file. Skipping."
            return 0
        end

        touch "$speaker_lock_file"
        echo (date "+%Y-%m-%d %H:%M:%S") "Performing diarization on $audio_file..."
        python ~/Scripts/diarize.py "$audio_file" "$speakers_file"
        if test $status -ne 0
            echo (date "+%Y-%m-%d %H:%M:%S") "Error during diarization of $audio_file."
        end
        rm -f "$speaker_lock_file"
    end

    # Boucle sur tous les fichiers .m4a du dossier
    for audio_file in "$audio_dir"/*.m4a
        if test -f "$audio_file"
            # Renommage si nécessaire
            set audio_file (rename_if_needed "$audio_file")
            # Démarrage de la transcription (et éventuellement la diarisation)
            transcribe_file "$audio_file"
            # diarize_file "$audio_file"
        end
    end

end >> "$log_file" 2>&1