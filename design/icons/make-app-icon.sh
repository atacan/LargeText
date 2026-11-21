#!/bin/sh
# Builds the macOS app icon set from the full-bleed master artwork.
#
#   design/icons/make-app-icon.sh            # uses design/icons/AppIcon-master.png
#   design/icons/make-app-icon.sh other.png  # try another square image
#
# The master is square, full-bleed art (no rounded corners). This script gives it the macOS icon
# shape: an 824 px rounded square centred on a 1024 px canvas, with a soft shadow, then writes
# every size the asset catalog needs. Requires ImageMagick (`brew install imagemagick`).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
master=${1:-"$here/AppIcon-master.png"}
iconset="$repo/xcode/LargeText/LargeText/Assets.xcassets/AppIcon.appiconset"

command -v magick >/dev/null || { echo "ImageMagick (magick) is required" >&2; exit 1; }
[ -f "$master" ] || { echo "No such file: $master" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Apple's macOS icon grid: 824 px body on a 1024 px canvas, corner radius about 185 px.
body=824
radius=185

magick "$master" -resize "${body}x${body}!" \
  \( -size "${body}x${body}" xc:none -fill white \
     -draw "roundrectangle 0,0 $((body - 1)),$((body - 1)) $radius,$radius" \) \
  -alpha off -compose CopyOpacity -composite "$work/body.png"

magick -size 1024x1024 xc:none \
  \( "$work/body.png" -background black -shadow 30x14+0+10 \) -gravity center -composite \
  "$work/body.png" -gravity center -composite \
  "$work/icon-1024.png"

for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
            256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  px=${spec%%:*}
  name=${spec#*:}
  magick "$work/icon-1024.png" -resize "${px}x${px}" -strip "$iconset/icon_${name}.png"
done

cat > "$iconset/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Wrote $iconset"
