#!/bin/sh
# Calcule les noms des APK publiés dans la release « build-latest » :
#     <projet>-<debug|release>_<version>-<n° de la dernière PR fusionnée>.apk
# ex. ZimutAdventure-debug_v0.001-22.apk
#
# Entrées (variables d'environnement) :
#   PROJECT_NAME  nom du projet (obligatoire)         APK_VERSION  ex. v0.001 (obligatoire)
#   PR_NUMBER     numéro de PR, s'il est déjà connu (événement pull_request)
#   GITHUB_SHA, GITHUB_REPOSITORY, GH_TOKEN  pour retrouver la PR d'un push sur main
#
# Le numéro de PR vient, dans l'ordre : de PR_NUMBER ; du titre du commit
# (« Merge pull request #22 from ... » ou « Titre (#22) » en squash) ; de l'API GitHub
# (PR associée au commit : rebase, ou titre modifié) ; sinon des 7 premiers caractères
# du commit (push direct, lancement manuel).
# Sortie : lignes « clé=valeur » (format $GITHUB_OUTPUT).
set -eu

PROJECT="${PROJECT_NAME:?PROJECT_NAME manquant}"
VERSION="${APK_VERSION:?APK_VERSION manquant}"
SHA="${GITHUB_SHA:-HEAD}"
PR="${PR_NUMBER:-}"

if [ -z "$PR" ]; then
	SUBJECT=$(git log -1 --format=%s "$SHA" 2>/dev/null || true)
	PR=$(printf '%s\n' "$SUBJECT" | grep -oE '#[0-9]+' | tail -1 | tr -d '#' || true)
fi
if [ -z "$PR" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && command -v gh >/dev/null 2>&1; then
	PR=$(gh api "repos/$GITHUB_REPOSITORY/commits/$SHA/pulls" --jq '.[0].number // empty' 2>/dev/null || true)
fi
if [ -z "$PR" ]; then
	PR=$(printf '%s' "$SHA" | cut -c1-7)
fi
# Uniquement des chiffres ou de l'hexadécimal : le résultat finit dans un nom de fichier.
case "$PR" in
	*[!0-9a-fA-F]*) echo "numéro de PR invalide : $PR" >&2; exit 1 ;;
esac

echo "pr=$PR"
echo "debug_file=${PROJECT}-debug_${VERSION}-${PR}.apk"
echo "release_file=${PROJECT}-release_${VERSION}-${PR}.apk"
