#!/usr/bin/env python3
import sys
import os
import openai
from openai import OpenAI

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
from datetime import datetime
if os.getenv("OPENAI_API_KEY") is None:
    print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Error: OPENAI_API_KEY environment variable is not set.", file=sys.stderr)
    sys.exit(1)

def main():
    if len(sys.argv) < 2:
        print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Error: Usage: ai-summarize <transcription_file> [title]", file=sys.stderr)
        sys.exit(1)

    transcription_file = sys.argv[1]
    if len(sys.argv) >= 3:
        title = sys.argv[2]
    else:
        title = ""

    if not os.path.exists(transcription_file):
        print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Error: le fichier {transcription_file} n'existe pas.", file=sys.stderr)
        sys.exit(1)

    with open(transcription_file, "r", encoding="utf-8") as f:
        text = f.read().strip()

    if not text:
        print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Error: le fichier de transcription est vide.", file=sys.stderr)
        sys.exit(1)

    try:
        response = client.chat.completions.create(model="gpt-4o-mini-2024-07-18",  # Utilisation du modèle GPT-4o mini
        messages=[
            {"role": "system", "content": "Tu es un assistant expert en synthèse de textes. S'il te plaît, génère le résumé en markdown en utilisant des titres, sous-titres et listes à puces pour structurer l'information et faciliter la lecture. Si des actions ont été évoquées, elles doivent apparaître dans le résumé en utilisant le même ordre que dans les sections de résumé."},
            {"role": "user", "content": f"Voici une transcription{(f' du fichier audio {title}' if title else '')}. Résume-la de manière concise et pertinente, et formate le résultat en markdown pour en faciliter la lecture :\n\n{text}"}
        ],
        temperature=0.5,
        max_tokens=3000)
        summary = response.choices[0].message.content.strip()
        print(summary)
    except Exception as e:
        print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Error lors du résumé : {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()