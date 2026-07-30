#!/bin/bash
# Fabrique OtterIsland.dmg : la fenêtre d'installation classique de macOS, avec
# l'app d'un côté, un alias vers Applications de l'autre, et une flèche entre
# les deux.
#
#   ./scripts/make_dmg.sh <chemin/vers/OtterIsland.app> [sortie.dmg]
#
# La mise en page passe par AppleScript et le Finder. Sur une machine sans
# session graphique (certains runners CI), cette étape échoue : le script
# continue alors sans mise en page et affiche l'erreur. On obtient un .dmg
# parfaitement fonctionnel — l'app et le raccourci Applications sont là — juste
# sans le fond ni le placement des icônes. Mieux vaut ça qu'une release qui casse.

set -euo pipefail

APP_PATH="${1:?usage: make_dmg.sh <OtterIsland.app> [sortie.dmg]}"
DMG_PATH="${2:-OtterIsland.dmg}"
VOLUME_NAME="OtterIsland"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -d "$APP_PATH" ] || { echo "error: $APP_PATH introuvable" >&2; exit 1; }

WORK="$(mktemp -d)"
DEVICE=""
cleanup() {
  [ -n "$DEVICE" ] && hdiutil detach "$DEVICE" -quiet -force 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

STAGING="$WORK/staging"
mkdir -p "$STAGING/.background"

echo "▸ Préparation du contenu"
cp -R "$APP_PATH" "$STAGING/OtterIsland.app"
ln -s /Applications "$STAGING/Applications"

# Fond : PNG 1x + 2x fusionnés en TIFF multi-résolution, sinon l'image est
# floue sur un écran Retina.
swift "$SCRIPT_DIR/make_dmg_background.swift" "$WORK/bg.png" >/dev/null
BACKGROUND_FILE=""
if command -v tiffutil >/dev/null 2>&1; then
  if tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" \
       -out "$STAGING/.background/background.tiff" >/dev/null 2>&1; then
    BACKGROUND_FILE="background.tiff"
  fi
fi
if [ -z "$BACKGROUND_FILE" ]; then
  cp "$WORK/bg.png" "$STAGING/.background/background.png"
  BACKGROUND_FILE="background.png"
fi

echo "▸ Création de l'image disque"
RW_DMG="$WORK/rw.dmg"
# +40 Mo de marge : le Finder a besoin de place pour écrire le .DS_Store de
# mise en page, une image pile à la taille du contenu le lui refuse.
SIZE_KB=$(du -sk "$STAGING" | cut -f1)
SIZE_MB=$(( SIZE_KB / 1024 + 40 ))
hdiutil create -quiet -srcfolder "$STAGING" -volname "$VOLUME_NAME" \
  -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW \
  -size "${SIZE_MB}m" "$RW_DMG"

# Montage SANS -mountpoint : le Finder ne sait adresser `disk "X"` que si le
# volume est monté sous /Volumes/X. Avec un point de montage personnalisé dans
# un dossier temporaire, toute la mise en page échouait en silence.
ATTACH=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
DEVICE=$(echo "$ATTACH" | egrep '^/dev/' | head -1 | awk '{print $1}')
MOUNT_DIR=$(echo "$ATTACH" | sed -n 's|.*\(/Volumes/.*\)$|\1|p' | head -1)
# Si un volume du même nom traîne déjà, macOS monte sous « OtterIsland 1 » :
# c'est ce nom réel qu'il faut donner au Finder, pas celui qu'on a demandé.
MOUNTED_NAME=$(basename "$MOUNT_DIR")

echo "▸ Mise en page (Finder)"
LAYOUT_LOG="$WORK/layout.log"
set +e
osascript >"$LAYOUT_LOG" 2>&1 <<APPLESCRIPT
tell application "Finder"
    tell disk "$MOUNTED_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 660×420 de contenu, cohérent avec make_dmg_background.swift
        set the bounds of container window to {200, 120, 860, 562}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:$BACKGROUND_FILE"
        set position of item "OtterIsland.app" of container window to {165, 205}
        set position of item "Applications" of container window to {495, 205}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT
LAYOUT_STATUS=$?
set -e

if [ $LAYOUT_STATUS -ne 0 ]; then
  echo "  ⚠ mise en page ignorée — le .dmg reste utilisable"
  sed 's/^/    /' "$LAYOUT_LOG"
else
  echo "  ✓ fond et positions appliqués"
fi

sync
hdiutil detach "$DEVICE" -quiet -force || hdiutil detach "$DEVICE" -quiet
DEVICE=""

echo "▸ Compression"
rm -f "$DMG_PATH"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

echo "✓ $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
