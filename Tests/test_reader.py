#!/usr/bin/env python3
"""Cross-check the native reader against Astropy, including FITS edge cases."""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile
import numpy as np
from astropy.io import fits

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--real-file', action='append', type=Path, default=[])
args = parser.parse_args()
exe = root/'Potential Visualizer.app/Contents/MacOS/PotentialVisualizer'


def check(path):
    result = subprocess.run([str(exe), '--inspect', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, (path, result.stderr)
    result = json.loads(result.stdout)
    with fits.open(path) as hdus:
        hdu = hdus[result['hdu']]
        values = np.asarray(hdu.data, dtype=float)
        assert values.shape == (result['height'], result['width'])
        assert len(hdus) == len(result['hdus'])
        assert np.isclose(result['min'], np.nanmin(values))
        assert np.isclose(result['max'], np.nanmax(values))
        assert result['finiteCount'] == int(np.isfinite(values).sum())
        for point in result['samples']:
            v = values.flat[point['index']]
            assert (point['value'] is None and not np.isfinite(v)) or np.isclose(point['value'],v)
        assert result['colorIndices'] == [0,128,255]
        assert result['meshWidth'] <= 128 and result['meshHeight'] <= 128
        assert 0 < result['meshTriangles'] <= 2*(result['meshWidth']-1)*(result['meshHeight']-1)
    print('PASS', path.name)


with tempfile.TemporaryDirectory(prefix='fits-viewer-tests-') as directory:
    temp = Path(directory)
    for dtype in [np.uint8,np.int16,np.int32,np.int64,np.float32,np.float64]:
        values = np.arange(35,dtype=dtype).reshape(5,7)
        p = fits.PrimaryHDU()
        p.header['LX'] = 1.4; p.header['LY'] = 2.3
        p.header['TEST'] = "slash / and 'quote'"
        image = fits.ImageHDU(values,name='V')
        path = temp/f'{np.dtype(dtype).name}.fits'
        fits.HDUList([p,image,fits.BinTableHDU.from_columns([fits.Column(name='X',format='E',array=[1,2])],name='SPLINE')]).writeto(path)
        check(path)
    values = np.arange(35,dtype=float).reshape(5,7); values[2,3] = np.nan
    path = temp/'primary-with-nan.fits'; fits.PrimaryHDU(values).writeto(path); check(path)
    path = temp/'scaled-integer.fits'
    image = fits.PrimaryHDU(np.arange(35,dtype=np.int16).reshape(5,7))
    image.header['BSCALE'] = 0.25; image.header['BZERO'] = 10; image.header['BLANK'] = 17
    image.writeto(path); check(path)
    path = temp/'zero.fits'; fits.PrimaryHDU(np.zeros((4,5))).writeto(path); check(path)
    bad = temp/'invalid.fits'; bad.write_bytes(b'not a fits file')
    assert subprocess.run([str(exe),'--inspect',str(bad)],capture_output=True).returncode != 0
    truncated = temp/'truncated.fits'; truncated.write_bytes(path.read_bytes()[:2900])
    assert subprocess.run([str(exe),'--inspect',str(truncated)],capture_output=True).returncode != 0
    print('PASS invalid and truncated files rejected')
for path in args.real_file:
    check(path)
print('Native FITS-reader checks passed.')
