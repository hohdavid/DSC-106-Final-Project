#!/bin/sh
# Download the NASA GIBS MODIS images used in the prototypes.
set -eu
cd "$(dirname "$0")"
mkdir -p assets
get_event() {
  event="$1"; bounds="$2"; shift 2
  for date in "$@"; do
    for type in true false; do
      if [ "$type" = true ]; then layer=MODIS_Terra_CorrectedReflectance_TrueColor; else layer=MODIS_Terra_CorrectedReflectance_Bands721; fi
      if [ "$event" = kenya ]; then filename="$date-$type.jpg"; else filename="$event-$date-$type.jpg"; fi
      if [ -s "assets/$filename" ]; then continue; fi  # already downloaded
      # Plain (not URL-encoded) query string: GIBS answers 400 to the encoded form from some curl versions.
      curl --fail --http1.1 --location --silent --show-error --output "assets/$filename" \
        "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=$layer&STYLES=&FORMAT=image/jpeg&CRS=EPSG:4326&BBOX=$bounds&WIDTH=960&HEIGHT=640&TIME=$date"
    done
  done
}
get_event dixie '39.4,-122.0,40.4,-120.5' 2021-07-10 2021-08-15 2021-09-21 2021-10-10
get_event pakistan '27.7,68.5,29,70.45' 2012-09-01 2012-09-08 2012-09-13 2012-09-20
get_event kenya '-0.45,36.65,0.35,37.85' 2019-02-15 2019-02-20 2019-02-23 2019-02-27 2019-03-15
get_event riogrande '-30.8,-53,-28.8,-50' 2024-04-20 2024-05-06 2024-05-14 2024-06-12
get_event kangaroo '-36.52,136.3,-35.18,138.31' 2019-12-16 2020-01-03 2020-01-07 2020-01-14 2020-02-04
# Chapters added for the final project (Earth and Ice): the clearest of the candidate dates we checked.
get_event tohoku '37.55,139.81,38.75,142.09' 2011-02-26 2011-03-12 2011-03-13 2011-03-24 2011-04-01
get_event iceland '60,-26,66,-6.2' 2010-03-29 2010-04-14 2010-04-15 2010-04-19 2010-05-11
get_event petermann '80.3,-66.7,81.5,-55.3' 2010-07-28 2010-08-05 2010-08-11 2010-08-16 2010-08-20
