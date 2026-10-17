#!/bin/bash
# cut_sprite.sh in.jpg out.png [scale%]  — key out the flat cream background from all 4 corners, trim.
IN=$1; OUT=$2; SC=${3:-100}
read W H < <(identify -format "%w %h" "$IN")
W=$((W*SC/100-1)); H=$((H*SC/100-1))
convert "$IN" -resize ${SC}% -alpha set -fuzz 9% -fill none \
  -draw "color 0,0 floodfill" -draw "color $W,0 floodfill" -draw "color 0,$H floodfill" -draw "color $W,$H floodfill" \
  -channel A -morphology Erode Disk:1 -blur 0x0.7 +channel -trim +repage "$OUT"
