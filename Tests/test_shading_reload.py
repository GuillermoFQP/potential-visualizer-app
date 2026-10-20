#!/usr/bin/env python3
"""Check screenshots from --shading-reload-test FILE_A FILE_B OUTPUT_DIR."""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
args = parser.parse_args()


def compare(first, second):
    a = np.asarray(Image.open(args.directory / (first + '.png')).convert('RGB'), dtype=float)
    b = np.asarray(Image.open(args.directory / (second + '.png')).convert('RGB'), dtype=float)
    assert a.shape == b.shape
    return float(np.mean(np.abs(a - b)))


failures = []
for label, initial, restored, opposite in [
    ('Load with shading off', 'reload-off', 'reload-toggled-off', 'reload-on'),
    ('Rebuild with shading off', 'rebuild-off', 'rebuild-toggled-off', 'rebuild-on'),
    ('Load with shading on', 'reload-enabled', 'reload-enabled-on', 'reload-enabled-off'),
]:
    same = compare(initial, restored)
    different = compare(restored, opposite)
    print(f'{label}: repeated-state mean pixel difference = {same:.6f}; '
          f'opposite-state difference = {different:.6f}')
    if same > 0.1:
        failures.append(f'{label}: loaded rendering differs from explicitly toggled rendering')
    if different < 0.5:
        failures.append(f'{label}: shading toggle made no significant visual change')
assert not failures, '\n'.join(failures)
print('PASS: file replacement and grid rebuild preserve actual rendered shading.')
