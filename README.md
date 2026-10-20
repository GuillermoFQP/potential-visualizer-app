# Potential Visualizer

Explore potential landscapes in 3D, inspect their FITS metadata, and copy a view into your notes or presentations. Potential Visualizer is a native macOS app for constrained and unconstrained potential files, with controls that help you see the shape of the landscape.

## Get started

Requires **macOS 12 or newer**. The app runs without Python or additional scientific software. The app currently included in this repository is an Intel build; for a native Apple Silicon build, see [Build the app](DEVELOPMENT.md#build-the-app).

1. Double-click **Potential Visualizer.app**.
2. Choose **Open FITS…** (`Command-O`), or drop a FITS file onto the 3D view.
3. Drag to rotate the surface. Hold **Shift** while scrolling, or pinch on a trackpad, to zoom. Choose **Reset view** to fit the landscape again.

## Explore the landscape

| Control | What it does |
| --- | --- |
| **Height divisor** | Adjusts the displayed height, `V / divisor`. Larger values flatten the surface without changing its colors. The default is 6; you can type a value from 0.1 to 100 and press Return. |
| **Grid** | Chooses how much detail to draw: 128, 256 (default), 512, or the full image. Lower settings make large files easier to explore. |
| **Show grid** | Shows the reference grid, axis titles, and tick labels. Starts off. |
| **Shading** | Adds lighting to emphasize the shape. Turn it off to see the palette colors without lighting. |
| **System / Light mode / Dark mode** | Sets the appearance. Your choice is remembered. |

Use **FITS headers** to read the file's metadata, including comments and history. You can view all sections or select one, then use **Copy header** to copy the displayed text.

Use **Copy view**, then paste with `Command-V`, to share the current surface with a transparent background. It includes visible axes and grid lines, but leaves out the app controls and color bar.

## Understand the display

Colors run from blue for negative values to red for positive values, with a range centered on zero and calculated separately for each complete image. Changing the height or grid resolution does not change that range or modify the file.

The viewer uses the FITS values without an additional physical-amplitude conversion. When valid `LX` and `LY` metadata are present, it uses field coordinates; otherwise, it shows centered pixel coordinates.

The app displays uncompressed 2D FITS images, preferring the image named `V`. Gzip and tile-compressed images are not supported. Surface rendering is limited to 32 million pixels and 16,384 pixels per dimension. For readable files without a renderable surface, you can still inspect the headers.

For building, testing, and details of how files become surfaces, see [DEVELOPMENT.md](DEVELOPMENT.md).
