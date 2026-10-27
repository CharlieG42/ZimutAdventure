#!/bin/sh
# Exporte l'APK Android (debug ou release) en ligne de commande.
#
# Usage :
#   sh tools/android/export_apk.sh debug    # APK debug (signé clé debug auto)
#   sh tools/android/export_apk.sh release  # APK release (signé avec ton keystore)
#
# Prérequis :
#   - Godot 4.7 installé (binaire "godot" dans le PATH, ou variable GODOT)
#   - JDK 17 (JAVA_HOME défini)
#   - Android SDK (ANDROID_SDK_ROOT défini) — voir tools/android/setup_android_sdk.sh
#   - Templates d'export Godot 4.7 installés (Editor > Manage Export Templates)
#   - Pour release : keystore dans .godot/release.keystore et mot de passe dans
#     GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
set -eu

BUILD_TYPE="${1:-debug}"
GODOT_BIN="${GODOT:-godot}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ "$BUILD_TYPE" = "debug" ]; then
	FLAG="--export-debug"
	OUT="$PROJECT_ROOT/build/android/ZimutAdventure-debug.apk"
elif [ "$BUILD_TYPE" = "release" ]; then
	FLAG="--export-release"
	OUT="$PROJECT_ROOT/build/android/ZimutAdventure-release.apk"
	if [ ! -f "$PROJECT_ROOT/.godot/release.keystore" ]; then
		echo "ERREUR: .godot/release.keystore introuvable."
		echo "  Génère-le avec : keytool -genkeypair -keystore .godot/release.keystore -alias zimut -keyalg RSA -keysize 2048 -validity 10000"
		echo "  (voir docs/ANDROID_SIGNING.md)"
		exit 1
	fi
	if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
		echo "ERREUR: variable GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD non définie."
		exit 1
	fi
else
	echo "Usage: sh tools/android/export_apk.sh [debug|release]"
	exit 1
fi

mkdir -p "$PROJECT_ROOT/build/android"

# Pointe Godot vers le JDK et le SDK Android (fichier de settings éditeur).
GODOT_CONFIG_DIR="${GODOT_CONFIG_DIR:-$HOME/.config/godot}"
mkdir -p "$GODOT_CONFIG_DIR"
if [ -n "${JAVA_HOME:-}" ] && [ -n "${ANDROID_SDK_ROOT:-}" ]; then
	cat > "$GODOT_CONFIG_DIR/editor_settings-4.tres" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA_HOME"
export/android/android_sdk_path = "$ANDROID_SDK_ROOT"
EOF
fi

cd "$PROJECT_ROOT"
echo "== Export $BUILD_TYPE -> $OUT"
"$GODOT_BIN" --headless --path . --import
# Installe le template de build Gradle (android/build/) si absent.
# Godot l'installe normalement tout seul lors de l'export, mais en mode
# headless --install-android-build-template reste bloqu\u00e9 sans sortie ;
# on extrait donc android_source.zip depuis les export templates et on
# \u00e9crit les marqueurs attendus par l'export Gradle (.build_version + .gdignore).
GODOT_VERSION_DIR=$(basename "$(dirname "$(dirname "$GODOT_BIN")")" 2>/dev/null || true)
if [ ! -f "$PROJECT_ROOT/android/.build_version" ]; then
	TEMPLATES_DIR="${HOME}/.local/share/godot/export_templates"
	VERSION_DIR=$(ls "$TEMPLATES_DIR" 2>/dev/null | head -1)
	if [ -z "$VERSION_DIR" ] || [ ! -f "$TEMPLATES_DIR/$VERSION_DIR/android_source.zip" ]; then
		echo "ERREUR: android_source.zip introuvable dans $TEMPLATES_DIR. Installe les export templates Godot."
		exit 1
	fi
	mkdir -p "$PROJECT_ROOT/android/build"
	unzip -q -o "$TEMPLATES_DIR/$VERSION_DIR/android_source.zip" -d "$PROJECT_ROOT/android/build"
	echo 'rootProject.name = "GodotAndroid"' >> "$PROJECT_ROOT/android/build/settings.gradle"
	printf '%s' "$VERSION_DIR" > "$PROJECT_ROOT/android/.build_version"
	touch "$PROJECT_ROOT/android/build/.gdignore"
fi
"$GODOT_BIN" --headless --path . $FLAG "Android" "$OUT"

echo "== Vérification de la signature =="
APKSIGNER="$ANDROID_SDK_ROOT/build-tools/36.1.0/apksigner"
if [ -x "$APKSIGNER" ]; then
	"$APKSIGNER" verify --print-certs "$OUT"
fi
ls -lh "$OUT"
echo "== OK : $OUT"
