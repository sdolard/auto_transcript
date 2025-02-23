# Auto Transcription et Diarization avec WhisperX

Ce projet permet de transcrire automatiquement des fichiers audio (.m4a) et d'y ajouter une diarization (attribution des segments aux différents locuteurs) à l'aide de [WhisperX](https://github.com/m-bain/whisperX).

## Prérequis

- **Fish Shell** : utilisé pour exécuter le script principal.
- **FFmpeg** : pour convertir les fichiers audio en format WAV si nécessaire.
- **Python3 et pip3** : pour installer WhisperX.
- **WhisperX** : installé via pip.

## Installation

Exécutez le script d'installation pour installer toutes les dépendances et configurer la tâche cron :

```bash
./install.sh