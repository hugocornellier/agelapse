"""Builds a zip of phone-sized face photos for the Android bulk import test.

Issue #15 was a zip of about 600 photos imported on a phone, which crashed
partway through stabilization. This makes a comparable zip from the 20 seed
photos in samples_for_testing/hugocornellier-first20pics: each output photo
is one seed upscaled to 4032x3024 (12 MP, a typical phone camera), with its
own small shift, zoom and brightness change, plus sensor-like noise. That
gives every file different bytes (the importer skips duplicates) and a file
size close to a real camera JPEG. Files are named by date, one day apart,
the way a daily photo project looks.

Usage: python3 -I tool/testlab/make_bulk_zip.py COUNT OUT.zip
"""

import io
import os
import sys
import zipfile
from datetime import date, timedelta
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageEnhance

WIDTH, HEIGHT = 4032, 3024
SEED_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    '..', '..', 'samples_for_testing', 'hugocornellier-first20pics',
)
START = date(2023, 1, 1)


def seeds():
    names = sorted(n for n in os.listdir(SEED_DIR) if n.lower().endswith('.jpg'))
    assert len(names) == 20, names
    return [os.path.join(SEED_DIR, n) for n in names]


def make_photo(args):
    index, seed_path = args
    rng = np.random.default_rng(index)
    seed = Image.open(seed_path).convert('RGB')
    # A little zoom and shift, so the face is not at the exact same spot.
    zoom = rng.uniform(1.0, 1.08)
    crop_w, crop_h = seed.width / zoom, seed.height / zoom
    left = rng.uniform(0, seed.width - crop_w)
    top = rng.uniform(0, seed.height - crop_h)
    seed = seed.crop((left, top, left + crop_w, top + crop_h))
    photo = seed.resize((WIDTH, HEIGHT), Image.LANCZOS)
    photo = ImageEnhance.Brightness(photo).enhance(rng.uniform(0.9, 1.1))
    pixels = np.asarray(photo, dtype=np.int16)
    pixels = pixels + rng.normal(0, 6, pixels.shape).astype(np.int16)
    photo = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
    out = io.BytesIO()
    photo.save(out, 'JPEG', quality=90)
    name = (START + timedelta(days=index)).isoformat() + '.jpg'
    return name, out.getvalue()


def main():
    count, out_path = int(sys.argv[1]), sys.argv[2]
    paths = seeds()
    jobs = [(i, paths[i % len(paths)]) for i in range(count)]
    total = 0
    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        with Pool() as pool:
            for done, (name, data) in enumerate(pool.imap(make_photo, jobs), 1):
                archive.writestr(name, data)
                total += len(data)
                if done % 50 == 0 or done == count:
                    print(f'{done}/{count} photos, {total / 1e6:.0f} MB', flush=True)
    print(f'wrote {out_path}: {count} photos, '
          f'{os.path.getsize(out_path) / 1e6:.0f} MB zip')


if __name__ == '__main__':
    main()
