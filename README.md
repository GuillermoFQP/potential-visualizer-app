# Potential Visualizer

A native macOS app for inspecting constrained and unconstrained potential FITS files. Double-click **Potential Visualizer.app**. It does not require Python, Astropy, Matplotlib, PyVista, or a local web server to run.

## Use

- **Open FITS…** or **Command-O** opens a file picker for any folder. A FITS file can also be dropped onto the 3D view or opened with this app from Finder.
- **3D surface** shows the potential. Drag to orbit, Shift-scroll or pinch on the trackpad to zoom toward the pointer, and use the native SceneKit pan gesture. **Reset view** restores the 35° elevation / −45° azimuth view and fits the surface.
- **Copy view** copies the current 3D viewport with a transparent background, at the display’s pixel resolution. It preserves the camera angle, zoom, height, shading, and visible grid/axis labels. Paste into a document with Command-V. The clipboard supplies both PNG and TIFF with alpha transparency. The app controls, color bar, and status text are excluded. Copying does not change the live view.
- **Height divisor** is the same parameter as `HEIGHT_SCALE` in `plot-3d-potentials.py`: geometric height is `V / divisor`. The initial value is **6**; increasing it flattens the surface. The slider is logarithmic, and the adjacent number field accepts values from 0.1 to 100. Press Return to apply a typed value. Colors do not change with this setting.
- **Show grid** toggles the reference grid beneath the surface together with the tick numbers and axis titles. It is unchecked on launch; its setting is kept when loading another file, changing resolution, adjusting height, or switching appearance.
- **Grid** controls display resolution: 128, 256 (default), 512, or the full image. It samples the original grid, includes both end rows/columns, and never alters the file. The color limits always come from the complete image.
- **System / Light mode / Dark mode** chooses the app’s appearance. System follows macOS, including changes while the app is open. The choice is remembered.
- **Shading** enables smooth surface lighting. Turn it off to view the unlit palette colors. The selected shading state is preserved when another FITS file is loaded or the grid resolution changes. SceneKit lighting differs from VTK's light kit, so shaded pixels need not match a PyVista screenshot even though their underlying color map is the same.
- **FITS headers** displays all header cards, including comments and HISTORY, in a selectable monospaced text view. The selector can show all HDUs or a single extension. **Copy header** copies the displayed text.

The interface uses macOS's monospaced system font wherever the native controls allow it. Axis titles and tick numbers use bundled Computer Modern math lettering; the physical axis titles are `φ¹ / M_Pl` and `φ² / M_Pl`, with superscripts and subscripts. No LaTeX installation is required. The system file dialog and window title follow macOS conventions.

## FITS data and colors

The default image is the 2D extension named `V`, otherwise the first 2D image, including a primary image. All HDU headers remain accessible even if no supported surface can be made. The viewer reads uncompressed FITS images with BITPIX 8, 16, 32, 64, −32, and −64, respecting BSCALE, BZERO and integer BLANK. Nonfinite samples become holes in the surface. Gzip and tile-compressed FITS images are not supported. Images larger than 32 million pixels are rejected for surface rendering, with their headers still available.

Coordinates use cell centers over `[-LX, LX] × [-LY, LY]`, with LX and LY taken from the image header or the primary header. This matches the reference plotting scripts. If those keywords are absent, centered pixel coordinates are used. Stored potential values are used directly; there is no implicit physical-amplitude conversion.

The bundled 256-entry **RdBu_r** table was exported directly from Matplotlib. This is the map used by both reference scripts' **3D** PyVista blocks and by `plot-3d-potentials.py`. The older unconstrained script's 2D `imshow` block instead uses `seismic`; that is not the 3D map. Each loaded image uses symmetric limits `[-max(abs(V)), +max(abs(V))]`. The height divisor does not affect normalization. SceneKit vertex colors are converted from sRGB to linear light so its renderer reproduces the supplied palette correctly. The color bar shows the unlit sRGB lookup table and is horizontally centered, occupying 50% of the window width. The height formula is aligned at the left of the same row.

## Contents and rebuilding

- `Potential Visualizer.app`: compiled application, locally ad-hoc signed.
- `Sources/`: Swift/AppKit/SceneKit source and native FITS reader.
- `Resources/`: exact palette table, application metadata, icon, Computer Modern font/license, and vector math outlines. `make-math-assets.py` regenerates the font assets using Matplotlib; rebuilding/running the app does not require it.
- `build.sh`: build using the installed Xcode command-line tools.
- `Tests/test_reader.py`: developer tests comparing the native reader to Astropy.

Run `./build.sh` from this folder to rebuild. The binary is built for the current Mac's architecture (this build: Intel x86_64); rebuilding on Apple Silicon produces a native Apple Silicon app. macOS 12 or newer is required. The app is locally built and signed, not notarized for distribution.

The developer tests require NumPy and Astropy. Run `python Tests/test_reader.py --real-file /path/to/file.fits` to test supplied files as well as generated FITS edge cases. The app executable also supports `--inspect /path/to/file.fits` for a JSON inspection and `--smoke-test /path/to/file.fits /path/to/screenshots` for GUI regression tests that exit automatically. These send mouse clicks through the window to the Shading and Reset controls, check camera rotation/pan/zoom restoration, verify light/dark/system appearance and compact-window hit areas, and save screenshots. These are developer facilities, not necessary for normal use.

For the shading replacement regression, run the app executable with `--shading-reload-test /path/to/first.fits /path/to/second.fits /path/to/output`, then run `python Tests/test_shading_reload.py /path/to/output`. This follows the actual asynchronous load path and compares rendered pixels before and after toggling shading, including a grid rebuild and loading with shading enabled. The comparison requires NumPy and Pillow.
