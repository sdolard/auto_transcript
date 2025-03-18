#!/usr/bin/env fish

# =============================================================================
# Configuration
# =============================================================================

# Définir le nombre de threads pour certaines opérations
set -x OMP_NUM_THREADS 8

# Répertoire contenant les fichiers audio et leurs transcriptions
set audio_dir ~/Transcriptions
set log_file "$audio_dir/auto_transcribe.log"
set script_dir (dirname (status -f))

# =============================================================================
# Fonctions Utilitaires
# =============================================================================

# Rotation du log avec détection du système d'exploitation
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

# Obtenir le nom de base sans extension et préfixer avec la date si nécessaire
function get_base_name --argument file
    set original_file (basename "$file")
    # Suppression insensible à la casse des extensions .m4a ou .wav
    set original_base (string replace -r '(?i)\.(m4a|wav)$' '' "$original_file")
    if not string match -q -r '^[0-9]{4}-[0-9]{2}-[0-9]{2}' "$original_base"
        set base_name (date "+%Y-%m-%d")-"$original_base"
    else
        set base_name "$original_base"
    end
    echo "$base_name"
end

# Renommer le fichier audio si son nom ne commence pas par une date
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

# =============================================================================
# Fonctions de Transcription
# =============================================================================

# Fonction pour créer le résumé en appelant ai-summarize.py avec l'interpréteur du venv et en enregistrant le résultat dans un fichier
function summarize_transcription --argument transcription_file
    set summary_file (string replace -r '\.lrc$' '.summary.md' "$transcription_file")
    /Users/seb/Git/auto_transcript/venv/bin/python3 "$script_dir/ai-summarize.py" "$transcription_file" > "$summary_file"
end

# Transcrire un fichier audio
function transcribe_file --argument audio_file
    set base_name (get_base_name "$audio_file")
    set transcription_file "$audio_dir/$base_name.lrc"
    set lock_file "$audio_dir/$base_name.lock"

    if test -f "$lock_file"
        echo (date "+%Y-%m-%d %H:%M:%S") "Une transcription est déjà en cours pour $audio_file. Passage à l'étape suivante."
        return 0
    end

    touch "$lock_file"

    # ---------------------------------------------
    # Étape 1 : Conversion au format WAV si nécessaire
    # ---------------------------------------------
    set converted 0
    set audio_source ""
    if not string match -q -r '\.wav$' (string lower "$audio_file")
        set wav_file "$audio_dir/$base_name.wav"
        if test -f "$wav_file"
            echo (date "+%Y-%m-%d %H:%M:%S") "Conversion déjà effectuée pour $audio_file (fichier WAV existant: $wav_file)."
            set audio_source "$wav_file"
        else
            echo (date "+%Y-%m-%d %H:%M:%S") "Conversion de $audio_file en format WAV..."
            ffmpeg -y -i "$audio_file" -ar 16000 "$wav_file"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Erreur lors de la conversion de $audio_file en WAV." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
            set audio_source "$wav_file"
            set converted 1
        end
    else
        set audio_source "$audio_file"
    end

    # ---------------------------------------------
    # Étape 2 : Transcription
    # ---------------------------------------------
    if test -f "$transcription_file"
        echo (date "+%Y-%m-%d %H:%M:%S") "Transcription déjà réalisée pour $audio_file ($transcription_file existe)."
    else
        echo (date "+%Y-%m-%d %H:%M:%S") "Transcription de $audio_source..."
        # Vérifier et configurer le chemin du modèle
        if not set -q MODEL_PATH
            set -x MODEL_PATH "$HOME/Git/auto_transcript/models/ggml-large-v3-turbo.bin"
        end
        if not test -f "$MODEL_PATH"
            echo (date "+%Y-%m-%d %H:%M:%S") "Fichier modèle introuvable. Téléchargement en cours..." >> "$audio_dir/auto_transcribe_errors.log"
            mkdir -p (dirname "$MODEL_PATH")
            set temp_script /tmp/download-ggml-model.sh
            curl -L -o "$temp_script" "https://raw.githubusercontent.com/ggerganov/whisper.cpp/refs/heads/master/models/download-ggml-model.sh"
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Erreur lors du téléchargement du script du modèle." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
            chmod +x "$temp_script"
            bash "$temp_script" large-v3-turbo
            if test $status -ne 0
                echo (date "+%Y-%m-%d %H:%M:%S") "Erreur lors de l'exécution du script de téléchargement du modèle." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
            if test -f /tmp/ggml-large-v3-turbo.bin
                mv /tmp/ggml-large-v3-turbo.bin "$MODEL_PATH"
            else
                echo (date "+%Y-%m-%d %H:%M:%S") "Erreur : ggml-large-v3-turbo.bin introuvable après téléchargement." >> "$audio_dir/auto_transcribe_errors.log"
                rm -f "$lock_file"
                return 1
            end
        end

        # Lancer la transcription avec whisper-cli
        whisper-cli -olrc -m "$MODEL_PATH" -l fr --threads 8 "$audio_source"
        if test $status -ne 0
            echo (date "+%Y-%m-%d %H:%M:%S") "Erreur lors de la transcription de $audio_source." >> "$audio_dir/auto_transcribe_errors.log"
            rm -f "$lock_file"
            return 1
        end

        # Renommer le fichier de transcription généré
        if test -f "$audio_dir/$base_name.wav.lrc"
            mv "$audio_dir/$base_name.wav.lrc" "$transcription_file"
        else
            echo (date "+%Y-%m-%d %H:%M:%S") "Erreur : fichier de transcription non généré pour $audio_source." >> "$audio_dir/auto_transcribe_errors.log"
            rm -f "$lock_file"
            return 1
        end
    end

    # ---------------------------------------------
    # Étape 3 : Création du résumé
    # ---------------------------------------------
    set summary_file (string replace -r '\.lrc$' '.summary.md' "$transcription_file")
    if test -f "$summary_file"
        echo (date "+%Y-%m-%d %H:%M:%S") "Résumé déjà créé pour $audio_file ($summary_file existe)."
    else if test -f "$transcription_file"
        echo (date "+%Y-%m-%d %H:%M:%S") "Création du résumé pour $transcription_file..."
        summarize_transcription "$transcription_file"
    end


    rm -f "$lock_file"
end

# =============================================================================
# Exécution Principale
# =============================================================================

# Rotation du log
rotate_log

begin
    # --- Vérification des commandes externes requises ---
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

    # --- Gestion du verrou global pour empêcher les exécutions concurrentes ---
    set global_lock /tmp/auto_transcribe.lock
    if test -f "$global_lock"
        set old_pid (cat "$global_lock")
        # Validation que le contenu est un PID valide
        if test -n "$old_pid" -a (string match -q '[0-9]+' $old_pid)
            if ps -p $old_pid > /dev/null
                echo (date "+%Y-%m-%d %H:%M:%S") "An instance is already running (PID $old_pid). Exiting."
                exit 0
            else
                rm -f "$global_lock"
            end
        else
            # Si le contenu du fichier n'est pas valide, supprimer le verrou
            rm -f "$global_lock"
        end
    end

    # Sauvegarder le PID actuel dans le fichier de verrou
    echo $fish_pid > "$global_lock"

    # Supprimer le verrou et terminer le groupe de processus à la sortie
    trap 'kill -TERM -$fish_pid; rm -f "$global_lock"' EXIT

    # Traiter tous les fichiers .m4a dans le répertoire
    for audio_file in "$audio_dir"/*.m4a
        if test -f "$audio_file"
            set audio_file (rename_if_needed "$audio_file")
            transcribe_file "$audio_file"
        end
    end

end >> "$log_file" 2>&1