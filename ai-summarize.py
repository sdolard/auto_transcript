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
        # Première passe : Identifier le type de conversation
        response_type = client.chat.completions.create(
            model="gpt-4o-mini-2024-07-18",
            messages=[
                {
                    "role": "system",
"content": "Tu es un assistant expert en analyse de conversations. Tu reçois la transcription d'une réunion. Détermine la catégorie qui décrit le mieux cette réunion parmi les options suivantes, sans donner d'explications supplémentaires :\n\n1) daily meeting : un point d'équipe (type stand-up), consacré au suivi d'avancement de chaque participant sur ses tâches, à la mention des difficultés éventuelles (blockers) et à la planification immédiate. Il s'agit d'un rendez-vous régulier, souvent quotidien, où chacun partage rapidement son statut.\n2) réunion technique : une réunion centrée sur des problématiques techniques nécessitant une discussion approfondie, par exemple sur le choix ou l'évaluation de solutions d'implémentation, la conception d'architecture, le diagnostic de bugs complexes ou la recherche de solutions outillées. Les échanges sont en détail et ciblés sur des aspects techniques.\n3) revue de code : une réunion durant laquelle on discute de code, on relève les améliorations possibles, on identifie des bugs, etc.\n4) planning stratégique : une réunion où l'on définit ou revoit les objectifs stratégiques, la feuille de route à long terme, et les décisions à fort impact.\n5) brainstorming : une réunion dédiée à la génération ou à l'exploration d'idées nouvelles ou créatives.\n6) autre : si aucune des catégories ci-dessus ne s'applique clairement.\n\nRetourne uniquement le type de réunion parmi : 'daily meeting', 'réunion technique', 'revue de code', 'planning stratégique', 'brainstorming' ou 'autre'."
},
                {
                    "role": "user",
                    "content": f"Voici la transcription de la réunion :\n\n{text}"
                }
            ],
            temperature=0.0,
            max_tokens=50
        )
        conversation_type = response_type.choices[0].message.content.strip().lower()

        # Choix du prompt adapté en fonction du type de conversation
        if conversation_type == "daily meeting":
            system_prompt = ("Tu es un assistant expert en synthèse de textes. Ta mission est de produire un résumé détaillé sous forme Markdown, en respectant ces consignes :\n\n"
                             "1. Le style doit rester formel mais clair, et viser la concision.\n"
                             "2. Organise le résumé avec titres, sous-titres et listes à puces.\n"
                             "3. Si des actions spécifiques sont mentionnées, liste-les dans l’ordre où elles apparaissent, en utilisant des listes numérotées.\n"
                             "4. Fais ressortir les points importants et conclusifs en les mettant en évidence (par exemple, en gras).\n"
                             "5. Adapte ta réponse pour qu'elle soit facile à parcourir rapidement tout en restant précise.")
        elif conversation_type == "réunion technique":
            system_prompt = ("Tu es un assistant expert en synthèse de textes et en analyse de réunions techniques. Ta mission est de produire un résumé détaillé sous forme Markdown, en respectant ces consignes :\n\n"
                             "1. Le style doit rester formel et clair.\n"
                             "2. Organise le résumé en sections avec titres et sous-titres (par exemple, **Points discutés**, **Décisions prises**, **Actions à entreprendre**).\n"
                             "3. Concentre-toi sur l’identification et la synthèse des points techniques abordés, incluant :\n"
                             "   - Les problèmes identifiés,\n"
                             "   - Les solutions proposées,\n"
                             "   - Les décisions prises.\n"
                             "4. Mentionne les technologies, outils, méthodes ou extraits de code évoqués, en les formatant de manière distincte si nécessaire.\n"
                             "5. Si des actions spécifiques sont mentionnées, liste-les dans l’ordre d'apparition à l’aide de listes numérotées.\n"
                             "6. Mets en évidence les points critiques et les conclusions en utilisant le gras.\n"
                             "7. Veille à ce que le résumé soit exhaustif.\n\n"
                             "Retourne uniquement le résumé en Markdown.")
        elif conversation_type == "revue de code":
            system_prompt = ("Tu es un assistant expert en synthèse de textes et en analyse de réunions de revue de code. Ta mission est de produire un résumé détaillé sous forme Markdown, en respectant ces consignes :\n"
                             "1. Le style doit rester formel, clair et précis.\n"
                             "2. Organise le résumé avec titres, sous-titres et listes à puces.\n"
                             "3. Concentre-toi sur les discussions relatives au code, incluant les améliorations proposées, les bugs identifiés et les décisions techniques.\n"
                             "4. Si des extraits de code ou des exemples sont mentionnés, synthétise-les de manière pertinente.\n"
                             "5. Liste les actions spécifiques dans l’ordre d'apparition, en utilisant des listes numérotées.\n"
                             "6. Mets en évidence les points critiques et les conclusions en gras.")
        elif conversation_type == "planning stratégique":
            system_prompt = ("Tu es un assistant expert en synthèse de textes et en analyse de réunions de planning stratégique. Ta mission est de produire un résumé détaillé sous forme Markdown, en respectant ces consignes :\n"
                             "1. Le style doit rester formel, clair et orienté vers la stratégie.\n"
                             "2. Organise le résumé avec titres, sous-titres et listes à puces.\n"
                             "3. Concentre-toi sur les objectifs stratégiques, les enjeux, les décisions clés et les actions à mener.\n"
                             "4. Liste les actions spécifiques dans l’ordre d'apparition, en utilisant des listes numérotées.\n"
                             "5. Mets en évidence les points importants et les conclusions en gras.")
        elif conversation_type == "brainstorming":
            system_prompt = ("Tu es un assistant expert en synthèse de textes et en analyse de séances de brainstorming. Ta mission est de produire un résumé détaillé sous forme Markdown, en respectant ces consignes :\n"
                             "1. Le style doit rester formel mais créatif et ouvert.\n"
                             "2. Organise le résumé avec titres, sous-titres et listes à puces.\n"
                             "3. Concentre-toi sur la synthèse des idées, des suggestions et des propositions évoquées.\n"
                             "4. Si des actions spécifiques ou des pistes d'action sont mentionnées, liste-les dans l’ordre d'apparition, en utilisant des listes numérotées.\n"
                             "5. Mets en évidence les idées les plus innovantes ou marquantes en gras.")
        else:
            # Prompt par défaut
            system_prompt = ("Tu es un assistant expert en synthèse de textes. Ta mission est de produire un résumé détaillé sous forme Markdown, en respectant ces consignes :\n\n"
                             "1. Le style doit rester formel mais clair, et viser la concision.\n"
                             "2. Organise le résumé avec titres, sous-titres et listes à puces.\n"
                             "3. Si des actions spécifiques sont mentionnées, liste-les dans l’ordre où elles apparaissent, en utilisant des listes numérotées.\n"
                             "4. Fais ressortir les points importants et conclusifs en les mettant en évidence (par exemple, en gras).\n"
                             "5. Adapte ta réponse pour qu'elle soit facile à parcourir rapidement tout en restant précise.")

        # Seconde passe : Synthèse de la transcription avec le prompt adapté
        response_summary = client.chat.completions.create(
            model="gpt-4o-mini-2024-07-18",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": (
                    f"Voici une transcription du fichier audio intitulé '{title}'. Résume le contenu de manière concise et pertinente, en commençant ton résumé par '# {title} - {conversation_type}\n\n'.\n"
                    "Respecte scrupuleusement les règles énoncées dans le message système.\n\n"
                    "--- Début de la transcription ---\n"
                    f"{text}\n"
                    "--- Fin de la transcription ---"
                )}
            ],
            temperature=0.5,
            max_tokens=3000
        )
        summary = response_summary.choices[0].message.content.strip()
        print(summary)
    except Exception as e:
        print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} Error lors du traitement : {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()