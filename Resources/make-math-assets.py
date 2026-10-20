#!/usr/bin/env python3
"""Regenerate bundled Computer Modern axis outlines (developer utility only)."""
import json
import shutil
from importlib.metadata import distribution
from pathlib import Path

import matplotlib
from matplotlib.textpath import TextPath

HERE = Path(__file__).resolve().parent
matplotlib.rcParams['mathtext.fontset'] = 'cm'
expressions = {
    'phi1': r'$\phi^{1} / M_{\mathrm{Pl}}$',
    'phi2': r'$\phi^{2} / M_{\mathrm{Pl}}$',
    'pixelX': r'$x\ (\mathrm{pixels})$',
    'pixelY': r'$y\ (\mathrm{pixels})$',
}
paths = {}
for key, expression in expressions.items():
    path = TextPath((0, 0), expression, size=1, usetex=False)
    paths[key] = [[int(code), *map(float, vertices)]
                  for vertices, code in path.iter_segments(curves=True, simplify=False)]
(HERE / 'MathAxes.json').write_text(json.dumps(paths, separators=(',', ':')) + '\n')
shutil.copy2(Path(matplotlib.get_data_path()) / 'fonts/ttf/cmr10.ttf', HERE / 'cmr10.ttf')
dist = distribution('matplotlib')
license_path = next(f for f in dist.files if str(f).endswith('LICENSE_BAKOMA'))
shutil.copy2(dist.locate_file(license_path), HERE / 'LICENSE_BAKOMA')
print('Generated math outlines and copied Computer Modern Roman font and license.')
