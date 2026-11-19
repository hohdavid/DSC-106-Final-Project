# Satellite imagery comparison

An interactive D3 + WebGL visualization comparing NASA MODIS imagery across dates for five wildfire and flood events: the Dixie Fire (California, 2021), the Rio Grande do Sul floods (Brazil, 2024), the Mount Kenya fire (Kenya, 2019), the Indus River floods (Pakistan, 2012) and the Kangaroo Island fires (Australia, 2019–2020).

[View the visualization](https://haydenkellington.github.io/DSC106-Project3/)

The whole page is the visualization: a WebGL globe of NASA imagery fills the screen on a space background, and the story scrolls over it. Scrolling flies from orbit into each event, out again, around the globe and into the next one. At each stop the D3 comparison sits exactly over the event's spot on the globe: choose dates and image type, drag the divider to compare the images, and click a color in the false-color key to isolate it. You can also zoom (buttons, pinch, or Ctrl/⌘ + scroll) and Shift-drag to pan. The top bar jumps to any stop.

The rendered event imagery and libraries (D3, topojson-client) are in `assets/`. Images were obtained from [NASA GIBS](https://nasa-gibs.github.io/gibs-api-docs/access-basics/); `download_imagery.sh` records the requests. These images are not measurements of damage.

The globe is textured with NASA GIBS MODIS imagery from each event's default right-hand date, so each event image blends into the world around it:

1. `download_globe.sh` saves the raw imagery to `assets/globe/raw/` (not committed): context images 4×, 16× and 48× the event's extent, whole-world mosaics (and the 48× image) for the event day and five days around it, and a cloud-free Blue Marble.
2. `make_globe_textures.py` (Pillow and NumPy) writes the textures in `assets/globe/` that the page loads. The world and 48× images combine the six days pixel by pixel, favoring darker, clearer observations, which removes sun glint (bright strips where sunlight reflects off the ocean) and gaps between satellite passes. Areas MODIS could not see that week (the pole in polar darkness) are filled from the other events’ combined imagery, closest time of year first, with Blue Marble only as a last resort. The two closest context images keep the event day as seen, with gaps filled from the next level out and ocean glint removed the same way.
3. A fragment shader in `index.html` draws each pixel of the globe from the most detailed texture covering it, with soft edges between levels. Lighting and the atmosphere fade out as the view zooms in, so the globe matches the event image exactly.

Browsers without WebGL 2 get a plain globe drawn from Natural Earth outlines (`countries-110m.json`, via [world-atlas](https://github.com/topojson/world-atlas)).

To run locally, serve the folder (for example `python3 -m http.server`) and open `http://localhost:8000`. Opening `index.html` directly from disk blocks the globe imagery and color isolation.
