#!/bin/sh
# Installe l'Android SDK (ligne de commande) + les composants recommandés par
# la doc Godot 4.7, pour exporter un APK en local ou en CI.
#
# Usage : sh tools/android/setup_android_sdk.sh [chemin_sdk]
#   chemin_sdk : défaut /opt/android-sdk (nécessite les droits d'écriture)
#
# Prérequis : Java 17 (JDK) installé, variable JAVA_HOME positionnée.
set -eu

SDK_ROOT="${1:-/opt/android-sdk}"
CMDLINE_TOOLS_ZIP="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

if [ -z "${JAVA_HOME:-}" ]; then
	echo "ERREUR: JAVA_HOME n'est pas défini. Installe un JDK 17 et exporte JAVA_HOME."
	exit 1
fi

mkdir -p "$SDK_ROOT/cmdline-tools"
cd "$SDK_ROOT"

if [ ! -f cmdline-tools/latest/bin/sdkmanager ]; then
	echo "== Téléchargement des command-line tools Android =="
	curl -fSL -o cmdline-tools.zip "$CMDLINE_TOOLS_ZIP"
	unzip -q -o cmdline-tools.zip -d cmdline-tools
	mv cmdline-tools/cmdline-tools cmdline-tools/latest
	rm -f cmdline-tools.zip
fi

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"

echo "== Acceptation des licences =="
yes | cmdline-tools/latest/bin/sdkmanager --sdk_root="$SDK_ROOT" --licenses > /dev/null

echo "== Installation des composants SDK (build-tools 36.1.0, platform 36, CMake 3.10, NDK 29) =="
cmdline-tools/latest/bin/sdkmanager --sdk_root="$SDK_ROOT" \
	"platform-tools" \
	"build-tools;36.1.0" \
	"platforms;android-36" \
	"cmdline-tools;latest" \
	"cmake;3.10.2.4988404" \
	"ndk;29.0.14206865"

echo "== Terminé. SDK installé dans $SDK_ROOT"
echo "   Exporte ces variables dans ton shell :"
echo "     export ANDROID_SDK_ROOT=$SDK_ROOT"
echo "     export ANDROID_HOME=$SDK_ROOT"
