# Developing Potential Visualizer

Potential Visualizer brings FITS potential landscapes into a native macOS window using Swift, AppKit, and SceneKit. This guide explains how to build it, check changes, and preserve the meaning of the displayed data. For everyday use, start with the [README](README.md).

## Build the app

You need macOS 12 or newer and the Xcode command-line tools. From the repository directory, run:

```bash
./build.sh
open "Potential Visualizer.app"
```

The script compiles for the current Mac's architecture, copies the bundled resources, and applies an ad-hoc signature. Building on an Intel Mac produces an Intel app; building on Apple Silicon produces a native Apple Silicon app. It rebuilds the app bundle in this directory.

Python is needed only for the developer utilities below. Building and running the app require neither Python nor LaTeX.

The resulting app is locally signed, not notarized for distribution.

## Find your way around

| Location | Purpose |
| --- | --- |
| `Sources/main.swift` | App interface, file loading, clipboard export, and GUI test modes. |
| `Sources/FITS.swift` | Native FITS parsing, image selection, and metadata. |
| `Sources/Surface.swift` | Surface mesh, colors, lighting, camera, and image capture. |
| `Sources/MathAxes.swift` | Computer Modern axis labels and tick lettering. |
| `Resources/` | App metadata, icon, palette, math assets, and font license. |
| `Tests/` | Reader checks, rendering comparisons, and saved test results. |
| `Potential Visualizer.app` | Compiled app bundle. |

## How FITS data becomes a surface

The reader selects the first supported 2D image named `V`, or otherwise the first supported 2D image, including the primary image. Each dimension must contain at least two pixels. The header selector changes only which headers are displayed; it does not select the rendered image.

- **Formats:** uncompressed images with `BITPIX` 8, 16, 32, 64, -32, or -64. Gzip and tile-compressed images are unsupported.
- **Values:** standard `BSCALE`, `BZERO`, and integer `BLANK` are respected. No additional physical-amplitude conversion is applied.
- **Missing data:** nonfinite samples leave holes in the mesh. An image with no finite samples cannot be rendered.
- **Limits:** at most 32 million pixels, with neither dimension exceeding 16,384. Headers remain available if parsing succeeds but surface creation fails.
- **Headers:** all cards, including comments and `HISTORY`, are retained for viewing and copying.

When both `LX` and `LY` are finite and positive, coordinates are cell centers over `[-LX, LX] × [-LY, LY]`. Each keyword is read from the image header, falling back to the primary header if absent. Otherwise, both axes use centered pixel coordinates.

Grid resolution samples the original image and includes its first and last rows and columns. It does not average or rewrite the data. Displayed height is `V / divisor`; the logarithmic control defaults to 6 and accepts 0.1–100.

### Colors and rendering

The bundled 256-entry `RdBu_r` table comes from Matplotlib. Color limits use the full image: `[-max(abs(V)), +max(abs(V))]` over finite values. An all-zero image uses `[-1, +1]`. Height and grid resolution do not affect normalization.

Vertex colors are converted from sRGB to linear light for SceneKit; the color bar uses the unlit sRGB table. Shading changes apparent color, so turn it off when comparing palette colors. SceneKit and PyVista use different lighting, even when given the same palette.

Grid visibility and shading survive file loads and mesh rebuilds. Reset view restores a fitted camera at 35° elevation and -45° azimuth.

Copy view renders a separate transparent scene at the display's pixel resolution and places PNG and TIFF images on the clipboard. It preserves the camera and visible grid/axes without changing the live view, and excludes controls, status text, and the color bar.

## Check your changes

Build first and run these commands from the repository directory. Replace example FITS paths with your own files.

### Reader checks

With NumPy and Astropy installed:

```bash
python3 Tests/test_reader.py
python3 Tests/test_reader.py --real-file "/path/to/file.fits"
```

These compare the native reader with Astropy using generated numeric formats, scaling, missing values, and invalid files. The optional `--real-file` flag also checks your data and can be repeated.

For a JSON summary of one file:

```bash
"Potential Visualizer.app/Contents/MacOS/PotentialVisualizer" \
  --inspect "/path/to/file.fits"
```

### Interface and rendering checks

Run GUI tests in a logged-in macOS desktop session. They open the app, exercise controls, save screenshots, and exit automatically. Output goes under the ignored `.build/` directory.

```bash
"Potential Visualizer.app/Contents/MacOS/PotentialVisualizer" \
  --smoke-test "/path/to/file.fits" ".build/smoke-test"
```

This checks camera gestures and reset, grid visibility, shading, appearance, headers, clipboard export, and controls in a compact window.

To check shading after replacing a file or rebuilding its mesh:

```bash
"Potential Visualizer.app/Contents/MacOS/PotentialVisualizer" \
  --shading-reload-test "/path/to/first.fits" "/path/to/second.fits" \
  ".build/shading-reload"

python3 Tests/test_shading_reload.py ".build/shading-reload"
```

The comparison requires NumPy and Pillow. Use files with visible surface variation so the test can distinguish shaded and unshaded images.

## Regenerate bundled assets

Only run these when changing the assets; ordinary builds use the files already in `Resources/`.

```bash
python3 Resources/make-math-assets.py  # Requires Matplotlib
python3 Resources/make-icon.py        # Requires Pillow
./build.sh
```

The math utility regenerates axis outlines and copies the Computer Modern font and its license. Keep `Resources/LICENSE_BAKOMA` with the font when distributing the app.
