#!/bin/sh
# Download NASA GIBS imagery used to texture the scrollytelling globe.
# For each event's default right-hand date: three surrounding context images (4x, 16x and 48x the event's
# extent) and whole-world mosaics for that day and the five days around it (to remove sun glint and fill gaps),
# in both natural color and false color (bands 7-2-1), plus a cloud-free Blue Marble base layer.
# Files go to assets/globe/raw/ (not committed); make_globe_textures.py turns them into the textures the page loads.
# Files that already exist are skipped, so the script can be re-run after a failed request.
set -eu
cd "$(dirname "$0")"
mkdir -p assets/globe/raw
WMS='https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi'
FAILURES=0
fetch() { # fetch <output> <layer> <bbox lat,lon,lat,lon> <width> <height> [time]
  out="$1"; url="$WMS?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=$2&STYLES=&FORMAT=image/jpeg&CRS=EPSG:4326&BBOX=$3&WIDTH=$4&HEIGHT=$5"
  if [ -n "${6:-}" ]; then url="$url&TIME=$6"; fi
  if [ -s "$out" ]; then echo "exists  $out"; return 0; fi
  code=$(curl --http1.1 --location --silent --show-error -A "Mozilla/5.0 (Macintosh) DSC106-Project3" \
    -o "$out.part" -w '%{http_code}' "$url") || code=000
  magic=$(head -c 2 "$out.part" 2>/dev/null | od -An -tx1 | tr -d ' \n') || magic=''
  if [ "$code" = 200 ] && [ "$magic" = ffd8 ]; then
    mv "$out.part" "$out"; echo "saved   $out"
  else
    echo "FAILED  $out (HTTP $code)"; echo "        $url"
    if [ -s "$out.part" ]; then head -c 400 "$out.part" | LC_ALL=C tr -cd '[:print:]\n' || true; echo; fi
    FAILURES=$((FAILURES + 1))
  fi
}
get() { # get <name-prefix> <level> <bbox> <width> <height> <date>
  for type in true false; do
    if [ "$type" = true ]; then layer=MODIS_Terra_CorrectedReflectance_TrueColor; else layer=MODIS_Terra_CorrectedReflectance_Bands721; fi
    fetch "assets/globe/raw/$1-$type-$2.jpg" "$layer" "$3" "$4" "$5" "$6"
  done
}
fetch assets/globe/raw/bluemarble.jpg BlueMarble_ShadedRelief_Bathymetry '-90,-180,90,180' 2048 1024
get dixie-2021-09-21 L1 '37.9,-124.25,41.9,-118.25' 960 640 2021-09-21
get dixie-2021-09-21 L2 '31.9,-133.25,47.9,-109.25' 1440 960 2021-09-21
get dixie-2021-09-21 L3 '15.9,-157.25,63.9,-85.25' 1440 960 2021-09-21
get dixie-2021-09-21 world '-90,-180,90,180' 2048 1024 2021-09-21
get dixie-2021-09-20 world '-90,-180,90,180' 2048 1024 2021-09-20
get pakistan-2012-09-13 L1 '25.75,65.575,30.95,73.375' 960 640 2012-09-13
get pakistan-2012-09-13 L2 '17.95,53.875,38.75,85.075' 1440 960 2012-09-13
get pakistan-2012-09-13 L3 '-2.85,22.675,59.55,116.275' 1440 960 2012-09-13
get pakistan-2012-09-13 world '-90,-180,90,180' 2048 1024 2012-09-13
get pakistan-2012-09-12 world '-90,-180,90,180' 2048 1024 2012-09-12
get kenya-2019-03-15 L1 '-1.65,34.85,1.55,39.65' 960 640 2019-03-15
get kenya-2019-03-15 L2 '-6.45,27.65,6.35,46.85' 1440 960 2019-03-15
get kenya-2019-03-15 L3 '-19.25,8.45,19.15,66.05' 1440 960 2019-03-15
get kenya-2019-03-15 world '-90,-180,90,180' 2048 1024 2019-03-15
get kenya-2019-03-14 world '-90,-180,90,180' 2048 1024 2019-03-14
# Extra days of whole-world imagery: combined per pixel by make_globe_textures.py to remove sun glint
# (bright strips where sunlight reflects off the ocean) and gaps between satellite passes.
for d in 2021-09-18 2021-09-19 2021-09-22 2021-09-23; do get dixie-$d world '-90,-180,90,180' 2048 1024 $d; done
for d in 2012-09-10 2012-09-11 2012-09-14 2012-09-15; do get pakistan-$d world '-90,-180,90,180' 2048 1024 $d; done
for d in 2019-03-12 2019-03-13 2019-03-16 2019-03-17; do get kenya-$d world '-90,-180,90,180' 2048 1024 $d; done
# The widest context image (L3) for the same extra days, combined the same way so it has no glint or gaps either.
for d in 2021-09-18 2021-09-19 2021-09-20 2021-09-22 2021-09-23; do get dixie-$d L3 '15.9,-157.25,63.9,-85.25' 1440 960 $d; done
for d in 2012-09-10 2012-09-11 2012-09-12 2012-09-14 2012-09-15; do get pakistan-$d L3 '-2.85,22.675,59.55,116.275' 1440 960 $d; done
for d in 2019-03-12 2019-03-13 2019-03-14 2019-03-16 2019-03-17; do get kenya-$d L3 '-19.25,8.45,19.15,66.05' 1440 960 $d; done
# Rio Grande do Sul floods (2024) and Kangaroo Island fires (2019-2020): context images for the default right-hand
# date, and the widest context image (L3) and whole-world mosaics for six days around it. Kangaroo Island's L3 stops at
# 180° longitude, which a single request can't cross, so its pixel size is narrower.
get riogrande-2024-05-06 L1 '-33.8,-57.5,-25.8,-45.5' 960 640 2024-05-06
get riogrande-2024-05-06 L2 '-45.8,-75.5,-13.8,-27.5' 1440 960 2024-05-06
for d in 2024-05-03 2024-05-04 2024-05-05 2024-05-06 2024-05-07 2024-05-08; do get riogrande-$d L3 '-77.8,-123.5,18.2,20.5' 1440 960 $d; done
for d in 2024-05-03 2024-05-04 2024-05-05 2024-05-06 2024-05-07 2024-05-08; do get riogrande-$d world '-90,-180,90,180' 2048 1024 $d; done
get kangaroo-2020-01-07 L1 '-38.53,133.29,-33.17,141.32' 960 640 2020-01-07
get kangaroo-2020-01-07 L2 '-46.57,121.23,-25.13,153.38' 1440 960 2020-01-07
for d in 2020-01-04 2020-01-05 2020-01-06 2020-01-07 2020-01-08 2020-01-09; do get kangaroo-$d L3 '-68.01,89.065,-3.69,180' 1357 960 $d; done
for d in 2020-01-04 2020-01-05 2020-01-06 2020-01-07 2020-01-08 2020-01-09; do get kangaroo-$d world '-90,-180,90,180' 2048 1024 $d; done
# Tōhoku tsunami (2011), Eyjafjallajökull eruption (2010) and Petermann Glacier calving (2010). Same layout as above;
# where a context image runs into the map edge or the pole it is cut off there, and it is never coarser than the
# whole-world mosaic.
get tohoku-2011-03-12 L1 '35.75,136.39,40.55,145.51' 960 640 2011-03-12
get tohoku-2011-03-12 L2 '28.55,122.71,47.75,159.19' 1440 960 2011-03-12
for d in 2011-03-09 2011-03-10 2011-03-11 2011-03-12 2011-03-13 2011-03-14; do get tohoku-$d L3 '9.35,86.23,66.95,180' 1234 960 $d; done
for d in 2011-03-09 2011-03-10 2011-03-11 2011-03-12 2011-03-13 2011-03-14; do get tohoku-$d world '-90,-180,90,180' 2048 1024 $d; done
get iceland-2010-04-15 L1 '51,-55.7,75,23.5' 960 640 2010-04-15
get iceland-2010-04-15 L2 '15,-174.5,90,142.3' 1802 750 2010-04-15
for d in 2010-04-12 2010-04-13 2010-04-14 2010-04-15 2010-04-16 2010-04-17; do get iceland-$d L3 '-81,-180,90,180' 2048 973 $d; done
for d in 2010-04-12 2010-04-13 2010-04-14 2010-04-15 2010-04-16 2010-04-17; do get iceland-$d world '-90,-180,90,180' 2048 1024 $d; done
get petermann-2010-08-05 L1 '78.5,-83.8,83.3,-38.2' 960 640 2010-08-05
get petermann-2010-08-05 L2 '71.3,-152.2,90,30.2' 1440 935 2010-08-05
for d in 2010-08-02 2010-08-03 2010-08-04 2010-08-05 2010-08-06 2010-08-07; do get petermann-$d L3 '52.1,-180,90,180' 2048 632 $d; done
for d in 2010-08-02 2010-08-03 2010-08-04 2010-08-05 2010-08-06 2010-08-07; do get petermann-$d world '-90,-180,90,180' 2048 1024 $d; done
echo "Done: $(ls assets/globe/raw/*.jpg 2>/dev/null | wc -l | tr -d ' ') of 225 images in assets/globe/raw ($FAILURES failed)"
echo "Next: python3 make_globe_textures.py  (builds the gap-free textures the page uses)"
