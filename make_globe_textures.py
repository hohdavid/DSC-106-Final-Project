"""Build the globe textures in assets/globe/ from the raw NASA GIBS downloads in assets/globe/raw/.

download_globe.sh saves, for each event's default right-hand date: context images 4x, 16x and 48x the event's
extent (L1, L2, L3), whole-world mosaics for that day and five days around it, and a cloud-free Blue Marble.

Two problems in daily MODIS mosaics are fixed here:
  * Gaps between satellite passes (pure black). In false color, open water is also nearly black, so gaps are
    found from the natural-color image of the same pass, where water is blue and only gaps are black.
  * Sun glint: bright strips over the ocean where sunlight reflects straight into the sensor. They move from
    day to day, so combining several days per pixel, weighted toward the darker (clearer) observations,
    removes them, along with clouds that appear on only one day.

For each event and image type this writes four textures:
  world  = the six days combined as above. Areas MODIS can't see that week (the pole in polar night) are filled
           from the other events' combined imagery, closest time of year first, so the whole globe is MODIS;
           Blue Marble (muted to gray in false color) is only a last resort
  L3     = the widest context image (48x the event's extent), combined over the same six days
  L2, L1 = the event day's context images, gaps filled from the next coarser level, and open ocean
           combined with L3 the same way to remove glint (land keeps the event day as seen)
The page then only has to blend these nested layers (plus the event image) on the GPU.

    python3 make_globe_textures.py        (needs Pillow and NumPy)
"""
import os
from datetime import date, timedelta
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, 'assets', 'globe', 'raw')
OUT = os.path.join(HERE, 'assets', 'globe')
WORLD = (-180.0, -90.0, 180.0, 90.0)
# Event bounding boxes (west, south, east, north) from download_imagery.sh and the default right-hand date.
EVENTS = {
    'dixie': ('2021-09-21', (-122.0, 39.4, -120.5, 40.4)),
    'pakistan': ('2012-09-13', (68.5, 27.7, 70.45, 29.0)),
    'riogrande': ('2024-05-06', (-53.0, -30.8, -50.0, -28.8)),
    'kangaroo': ('2020-01-07', (136.3, -36.52, 138.31, -35.18)),
    'tohoku': ('2011-03-12', (139.81, 37.55, 142.09, 38.75)),
    'iceland': ('2010-04-15', (-26.0, 60.0, -6.2, 66.0)),
    'petermann': ('2010-08-05', (-66.7, 80.3, -55.3, 81.5)),
}
DAY_OFFSETS = (-3, -2, -1, 0, 1, 2)
LEVELS = [('L2', 16), ('L1', 4)]  # event-day context images, coarse to fine (multiples of the event's extent)
SIGMA = 15.0  # brightness scale for favoring darker observations


def load(name):
    return np.asarray(Image.open(os.path.join(RAW, name)).convert('RGB'), dtype=np.float32)


def soft(mask, shrink, blur):
    img = Image.fromarray((mask * 255).astype(np.uint8))
    if shrink:
        img = img.filter(ImageFilter.MinFilter(shrink))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(blur)), dtype=np.float32) / 255.0


def coverage(true_rgb, blur=1.5):
    """1 where the satellite has data, 0 in gaps, with softened edges (from the natural-color image)."""
    shrink = 5 + 2 * int(blur)  # also keep the blend inside the data, away from JPEG ringing at gap edges
    return soft((true_rgb.sum(-1) >= 6).astype(np.float32), shrink, blur)


def brightness(true_rgb):
    return np.asarray(Image.fromarray(true_rgb.mean(-1).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)), dtype=np.float32)


def darker_weights(brights, covers):
    """Per-observation weights favoring the darkest valid observation at each pixel."""
    darkest = np.min([np.where(c > 0.99, b, 1e9) for b, c in zip(brights, covers)], axis=0)
    return [c * np.exp(-np.clip(b - darkest, 0, None) / SIGMA) for b, c in zip(brights, covers)]


def combine_days(name, days, land):
    """Combine one image (e.g. 'world', 'L3') over several days; returns per-band images and how well seen.
    land: 1 over land, 0 over water, at the image's size."""
    trues = [load(f'{name.format(day=d, band="true")}') for d in days]
    # Generous margin around gaps: their edges are darkened by JPEG ringing and would win "darkest".
    covers = [soft((t.sum(-1) >= 6).astype(np.float32), 11, 2) for t in trues]
    # On land, drop observations far darker than the pixel's typical value (plus a 2 px margin): thin gap tips
    # that JPEG compression turned dark gray rather than black. (Over water, dark is the real surface.)
    sharp = np.array([t.mean(-1) for t in trues])
    typical = np.nan_to_num(np.nanmedian(np.where(np.array(covers) > 0.5, sharp, np.nan), axis=0), nan=0.0)
    covers = [c * (1 - land * (1 - soft((v >= 0.5 * typical - 2).astype(np.float32), 5, 0.8))) for c, v in zip(covers, sharp)]
    weights = darker_weights([brightness(t) for t in trues], covers)
    total = np.sum(weights, axis=0)
    out = {}
    for band in ('true', 'false'):
        stack = trues if band == 'true' else [load(name.format(day=d, band='false')) for d in days]
        out[band] = np.sum([s * w[..., None] for s, w in zip(stack, weights)], axis=0) / np.maximum(total, 1e-6)[..., None]
    return out, np.clip(total * 4, 0, 1)[..., None]  # 0 only where no day has data


def around(bbox, factor):
    """bbox scaled about its center, cut off at the edges of the map (one request can't cross 180°)."""
    w, s, e, n = bbox
    cx, cy, hw, hh = (w + e) / 2, (s + n) / 2, (e - w) / 2 * factor, (n - s) / 2 * factor
    return (max(cx - hw, -180.0), max(cy - hh, -90.0), min(cx + hw, 180.0), min(cy + hh, 90.0))


def resample(img, src_extent, dst_extent, size):
    """Cut dst_extent out of an equirectangular image covering src_extent and resize it to size."""
    h, w = img.shape[:2]
    sw, ss, se, sn = src_extent
    dw, ds, de, dn = dst_extent
    box = ((dw - sw) / (se - sw) * w, (sn - dn) / (sn - ss) * h, (de - sw) / (se - sw) * w, (sn - ds) / (sn - ss) * h)
    if img.ndim == 2:
        pil = Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8))
        return np.asarray(pil.transform(size, Image.EXTENT, box, resample=Image.BILINEAR), dtype=np.float32) / 255.0
    pil = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    return np.asarray(pil.transform(size, Image.EXTENT, box, resample=Image.BICUBIC), dtype=np.float32)


def save(img, name):
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name), quality=87, optimize=True)
    print(f'{name}: {os.path.getsize(os.path.join(OUT, name)) // 1024} KB')


blue_marble = load('bluemarble.jpg')
bm = blue_marble
# Open ocean from Blue Marble (blue-dominant), pulled back from coasts so land is never darkened.
water = ((bm[..., 2] > bm[..., 0] + 15) & (bm[..., 2] >= bm[..., 1])).astype(np.float32)
ocean_world = soft(water, 3, 1.5)
land_world = 1 - water
fallback = {'true': blue_marble, 'false': np.repeat(blue_marble.sum(-1, keepdims=True) * 0.12, 3, axis=-1)}

# Pass 1: combine each event's six days of whole-world imagery.
combined_world = {}
for event, (day, bbox) in EVENTS.items():
    days = [(date.fromisoformat(day) + timedelta(days=k)).isoformat() for k in DAY_OFFSETS]
    combined_world[event] = combine_days(event + '-{day}-{band}-world.jpg', days, land_world)


def season_gap(a, b):
    """Days between two dates' times of year (ignoring the year)."""
    d = abs(date.fromisoformat(EVENTS[a][0]).timetuple().tm_yday - date.fromisoformat(EVENTS[b][0]).timetuple().tm_yday)
    return min(d, 365 - d)


# Where each week's coverage ends (the edge of polar night), blend over a few degrees and pull the edge inward:
# the strip nearest the dark pole is dim because the sun is so low, and different seasons' ice shouldn't meet
# in a hard line.
for event, (combined, seen) in combined_world.items():
    combined_world[event] = (combined, soft((seen[..., 0] > 0.5).astype(np.float32), 31, 12)[..., None])

# Pass 2: fill what each event's week couldn't see from the other events, then build the context levels.
for event, (day, bbox) in EVENTS.items():
    days = [(date.fromisoformat(day) + timedelta(days=k)).isoformat() for k in DAY_OFFSETS]
    combined, seen = combined_world[event]
    others = sorted((e for e in EVENTS if e != event), key=lambda e: season_gap(event, e), reverse=True)
    world = {}
    for b in combined:
        base = fallback[b]
        for other in others:  # farthest season first, so the closest season ends up on top
            other_combined, other_seen = combined_world[other]
            base = base * (1 - other_seen) + other_combined[b] * other_seen
        world[b] = combined[b] * seen + base * (1 - seen)
        save(world[b], f'{event}-{day}-{b}-world.jpg')

    l3_extent = around(bbox, 48)
    size = Image.open(os.path.join(RAW, f'{event}-{day}-true-L3.jpg')).size
    combined, seen = combine_days(event + '-{day}-{band}-L3.jpg', days, resample(land_world, WORLD, l3_extent, size))
    filled = {b: combined[b] * seen + resample(world[b], WORLD, l3_extent, size) * (1 - seen) for b in combined}
    for b in filled:
        save(filled[b], f'{event}-{day}-{b}-L3.jpg')
    clear, clear_extent, extent = dict(filled), l3_extent, l3_extent

    for level, factor in LEVELS:
        level_extent = around(bbox, factor)
        raw = {b: load(f'{event}-{day}-{b}-{level}.jpg') for b in ('true', 'false')}
        size = (raw['true'].shape[1], raw['true'].shape[0])
        cover = coverage(raw['true'], blur=12)[..., None]  # wide blend so filled gaps don't read as strips
        level_filled = {b: resample(filled[b], extent, level_extent, size) * (1 - cover) + raw[b] * cover for b in raw}
        reference = {b: resample(clear[b], clear_extent, level_extent, size) for b in raw}
        ocean = resample(ocean_world, WORLD, level_extent, size)[..., None]
        w_day, w_ref = darker_weights([brightness(level_filled['true']), brightness(reference['true'])],
                                      [np.ones(size[::-1], np.float32)] * 2)
        for b in raw:
            deglinted = (level_filled[b] * w_day[..., None] + reference[b] * w_ref[..., None]) / (w_day + w_ref)[..., None]
            level_filled[b] = level_filled[b] * (1 - ocean) + deglinted * ocean
            save(level_filled[b], f'{event}-{day}-{b}-{level}.jpg')
        filled, extent = level_filled, level_extent
