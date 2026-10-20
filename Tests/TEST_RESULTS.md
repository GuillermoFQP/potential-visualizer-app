# Verification — version 1.3

Added Copy view in the top control row. It renders a separate scene with a transparent background, using the current camera and display resolution, and supplies PNG and TIFF clipboard formats. The top row reserves the complete button height so its edges are clickable.

The GUI smoke test clicked the button and read back both image formats from a private test clipboard, leaving the user's clipboard intact. All four combinations of light/dark appearance and grid on/off produced transparent 2168 × 1196 images with nonempty opaque surfaces and partially transparent antialiased edges. PNG and TIFF decoded pixels agree within one channel value. Camera transform, zoom scale, orbit target, theme, and grid state remained unchanged after copying. A transparent output and the compact-window layout were visually reviewed.

The existing pointer-zoom, reset, shading, grid, appearance, header, and compact control hit-area checks also passed. No third-party document app was automated. The rebuilt app passed signature verification.

# Previous verification — version 1.2.6

Zoom now keeps the world point under the pointer fixed on screen by translating the orthographic camera as its scale changes. The orbit target moves by the same amount, preserving the viewing direction. Both scroll and magnification handlers convert their event's window location into surface coordinates. The calculation uses the camera's current model projection so successive events do not depend on rendering latency.

The GUI regression checks passed for vertical Shift-scroll, horizontally remapped Shift-scroll, and pinch; zoom in and out; two off-center pointer locations; grid on and off; a rotated camera; and both 1120 × 800 and 920 × 620 windows. These checks inject events into the handlers, render between measurements, and independently project a fixed world point back onto the viewport. Its screen position stayed within 0.5 points of its original position in every case. Reset view and the existing UI checks also passed. Physical trackpad interaction was not automated. The app rebuilt and passed signature verification.

# Previous verification — version 1.2.5

Reproduced the zoom failure before the fix: passing a native Shift-scroll NSEvent into the surface view did not decrease the orthographic projection scale. Added explicit scrollWheel and magnify handlers that update orthographicScale. Shift-scroll accepts either the vertical or horizontal delta, and pinch magnification uses the same bounded scale adjustment. Other scrolling remains with SceneKit. Reset view restores the fitted scale.

The GUI smoke test passed after the fix. It injects native scroll events into the view's scroll handler and synthetic magnification events into its pinch handler, checking zoom in/out with grid visibility both off and on, horizontal Shift-scroll, and a real Reset view button click after zoom. This verifies event-handler behavior; physical trackpad gestures were not automated. Existing grid, labels, shading, camera reset, appearance, header, and compact-window checks also passed. The app rebuilt and passed signature verification.

# Previous verification — version 1.2.4

Show grid now toggles the grid lines, tick numbers, and axis titles together. All are hidden on launch. The existing GUI smoke test passed with checks for both visibility states and for preservation through height and appearance changes. The grid-off screenshot was visually reviewed to confirm that no axis labels remain.

# Previous verification — version 1.2.3

Added Show grid, unchecked on launch. The GUI smoke test passed with real mouse clicks, including control hit areas at the minimum window size. Axis titles and ticks remain visible when the grid is hidden. Grid visibility survives height and appearance changes, file replacement, and resolution changes. Both enabled and disabled states were exercised through the asynchronous file-load path.

Rendered grid-on and grid-off screenshots differ in 4,270 pixels by more than 5/255 in at least one RGB channel. The default-off and manually toggled-off screenshots match exactly. The compact-window screenshot was visually reviewed. Existing shading replacement pixel comparisons and camera reset checks also passed. The rebuilt app's signature was verified.

# Previous verification — version 1.2.2

Reproduced the reported bug using the real asynchronous FITS load path: load the constrained file, click Shading off, then load the unconstrained file. The checkbox and material property both reported shading off, but the rendered image matched the shaded state. Changing grid resolution while shading was off reproduced the same mismatch.

The fix creates the final display material on the main thread with the requested lighting mode before attaching the new geometry. Mesh construction no longer creates a default Lambert material on a background thread.

The new `--shading-reload-test` sequence and `Tests/test_shading_reload.py` compare actual rendered pixels, not just checkbox/material properties. Before the fix, the mean absolute RGB difference between the initially loaded image and the image after manually toggling off was 8.196403 for file replacement and 8.108532 for a grid rebuild (0–255 channels). After the fix, both differences are exactly zero. Loading with shading enabled also matches the manually enabled rendering exactly. Toggling between on and off still produces a significant image difference in every case.

The regression uses `figure-3/smpout-cnst.fits` and `figure-3/smpout-uncnst.fits`. Captures are in `shading-reload/`. The app rebuilt successfully and its local signature was verified before installation. The earlier layout screenshots below remain from version 1.2.1; this fix does not change that layout.

## Previous verification — version 1.2.1

Rebuilt successfully and passed the existing GUI smoke tests. Verified the centered color bar in screenshots at 1120 × 800 and 920 × 620 window sizes: its midpoint matches the window midpoint to within one screenshot pixel, and its width remains 50% of the window width. The height formula remains left-aligned. Current screenshots are in `preview/`.

## Previous verification — version 1.2

The app rebuilt successfully and passed the existing GUI smoke tests on 2026-10-15. The updated bottom layout was visually reviewed at 1120 × 800 and 920 × 620 window sizes, in light and dark appearances. The color-bar width is constrained to 50% of the window width. The height formula is first in the left-aligned row; the standalone V label and coordinate-status suffix are removed; the navigation hint and status separators match the requested wording.

The screenshots in `preview/` show version 1.2. FITS parsing and surface rendering code are unchanged from version 1.1.

## Previous verification — version 1.1

Verified on this Intel Mac on 2026-10-15.

## GUI regression checks

The executable's `--smoke-test` was run against `plots/figure-3/smpout-cnst.fits`.
It passed checks for:

- Loading the image and rendering the 256 × 256 surface.
- Changing the height divisor from 6 to 12 and back.
- Hit-testing the center and top/bottom edges of Shading and Reset view.
- Sending mouse-down/up events through the window to toggle Shading off and on; checking both checkbox state and material lighting mode.
- Changing the camera's orbit, pan and orthographic zoom, then sending a mouse click to Reset view and verifying the restored transform (within float roundoff), zoom, controller binding and stopped inertia.
- Repeating interaction checks after switching views and resizing to a compact window.
- Light mode, Dark mode, and System mode, including simulated changes to the application's inherited appearance.
- Displaying the primary FITS header.
- Presence of the bundled math axis titles and four numerical tick labels.

The light, dark, header and compact-window screenshots in `preview/` were visually reviewed. Dark mode changes both the native interface and the rendered canvas; headers remain monospaced. The rendered axes use Computer Modern lettering with the requested superscripts and subscripts.

Shaded and unshaded surface screenshots differ visibly (over 380,000 pixels differ by more than 5/255 in at least one RGB channel). The palette JSON is byte-for-byte identical to the preceding version.

## FITS reader regression checks

`test_reader.py` passed for BITPIX 8, 16, 32, 64, −32 and −64; a primary image with NaN; scaled integers with BLANK; a zero image; and rejection of invalid/truncated inputs. It also passed Astropy comparisons for the real constrained and unconstrained figure-3 FITS files.

The app is locally ad-hoc signed. A clean signature verification was performed before installation.
