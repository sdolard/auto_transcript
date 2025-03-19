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
        title = sys.argv[2]  # Le titre sera utilisé comme titre principal du résumé en markdown
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
            {
                "role": "system",
                "content": (
                    "Tu es un assistant expert en synthèse de textes. Ta mission est de produire un résumé détaillé sous forme Markdown, en respectant ces consignes :\n\n"
                    "1. Le style doit rester formel mais clair, et viser la concision.\n"
                    "2. Organise le résumé avec titres, sous-titres et listes à puces.\n"
                    "3. Si des actions spécifiques sont mentionnées, liste-les dans l’ordre où elles apparaissent, en utilisant des listes numérotées.\n"
                    "4. Fais ressortir les points importants et conclusifs en les mettant en évidence (par exemple, en gras).\n"
                    "5. Adapte ta réponse pour qu'elle soit facile à parcourir rapidement tout en restant précise."
                )
            },
            {
                "role": "user",
                "content": (
                    f"Voici une transcription du fichier audio intitulé '{title}'. Résume le contenu de manière concise et pertinente, en commençant ton résumé par '# {title}\n\n'.\n"
                    "Respecte scrupuleusement les règles énoncées dans le message système.\n\n"
                    "--- Début de la transcription ---\n"
                    f"{text}\n"
                    "--- Fin de la transcription ---"
                )
            }
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