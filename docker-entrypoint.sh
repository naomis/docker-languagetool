#!/usr/bin/env bash
# docker-entrypoint.sh
# Injecte les dictionnaires personnalisés dans les ressources LanguageTool (FR)
# avant de démarrer le serveur.
#
# Chemins dans le conteneur :
#   /dict/perso_spellings_fr.txt   → org/languagetool/resource/fr/hunspell/spelling.txt
#   /dict/perso_ignore_fr.txt      → org/languagetool/resource/fr/hunspell/ignore.txt
#   /dict/perso_prohibited_fr.txt  → org/languagetool/resource/fr/hunspell/prohibit.txt
#
# Référence : https://dev.languagetool.org/hunspell-support

set -euo pipefail

LT_DIR="/LanguageTool"
FR_HUNSPELL="${LT_DIR}/org/languagetool/resource/fr/hunspell"

inject_dict() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [ -f "$src" ] && [ -s "$src" ]; then
        echo "[entrypoint] Injection des mots personnalisés (${label}) → ${dst}"
        # Ajoute un saut de ligne de sécurité puis le contenu du fichier perso
        { echo; cat "$src"; } >> "$dst"
        echo "[entrypoint] $(wc -l < "$src") entrée(s) ajoutée(s) pour ${label}."
    else
        echo "[entrypoint] Fichier absent ou vide, ignoré : ${src}"
    fi
}

# --- Français ---
if [ -d "$FR_HUNSPELL" ]; then
    inject_dict /dict/keran_spellings_fr.txt   "${FR_HUNSPELL}/spelling.txt"  "fr/spelling"
    inject_dict /dict/keran_ignore_fr.txt      "${FR_HUNSPELL}/ignore.txt"    "fr/ignore"
    inject_dict /dict/keran_prohibited_fr.txt  "${FR_HUNSPELL}/prohibit.txt"  "fr/prohibited"
else
    echo "[entrypoint] AVERTISSEMENT : répertoire hunspell FR introuvable (${FR_HUNSPELL})"
fi

echo "[entrypoint] Démarrage de LanguageTool…"
exec "$@"
