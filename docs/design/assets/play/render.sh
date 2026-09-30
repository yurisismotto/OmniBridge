#!/usr/bin/env bash
# Renders the Google Play store graphics from the canonical brand files.
# Nothing here is drawn by hand: both images are a canonical SVG placed on a
# brand surface colour from tokens.json. Re-run after any change to the SVGs.
#
#   docs/design/assets/play/render.sh      (needs ImageMagick 7 with librsvg)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
assets="$here/.."

# 512 x 512, 32-bit PNG. The application icon on Dark (#0B1020) — the same
# pairing as the Android launcher's adaptive icon background.
magick -size 512x512 xc:'#0B1020' \
    \( -background none -density 96 RSVG:"$assets/omnibridge-app-icon.svg" -resize 512x512 \) \
    -gravity center -composite PNG32:"$here/play-icon-512.png"

# 1024 x 500, 24-bit PNG without alpha. The lockup (mark, wordmark, tagline)
# is drawn for light surfaces, so it sits on light background #F7F9FC.
magick -size 1024x500 xc:'#F7F9FC' \
    \( -background none -density 192 RSVG:"$assets/omnibridge-logo-lockup.svg" -resize 760x \) \
    -gravity center -composite -alpha off PNG24:"$here/play-feature-graphic-1024x500.png"

magick identify "$here"/play-*.png
