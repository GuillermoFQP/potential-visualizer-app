import AppKit
import SceneKit
import UniformTypeIdentifiers

func monoLabel(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .monospacedSystemFont(ofSize: size, weight: weight)
    return label
}

    func check(_ condition: @autoclosure () -> Bool, _ message: String = "GUI check failed", line: UInt = #line) {
        if !condition() { fputs("\(message) (main.swift:\(line))\n",stderr); exit(1) }
    }

// NSEvent has no public factory for trackpad magnification events.
final class ZoomTestEvent: NSEvent {
    var point = NSPoint.zero
    var wheelX: CGFloat = 0
    var wheelY: CGFloat = 10
    override var modifierFlags: NSEvent.ModifierFlags { [.shift] }
    override var scrollingDeltaX: CGFloat { wheelX }
    override var scrollingDeltaY: CGFloat { wheelY }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var locationInWindow: NSPoint { point }
    var pinch: CGFloat = 0.2
    override var magnification: CGFloat { pinch }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    let surface = SurfaceScene()
    var map: ColorMap!
    var document: FITSDocument?
    var potential: Potential?
    var generation = UUID()
    var busy = false
    var resetCount = 0
    var startURL: URL?
    var smokeDirectory: URL?
    var smokeStarted = false
    var reloadTestFile: URL?
    var reloadTestDirectory: URL?
    var reloadTestStage = 0
    let filename = monoLabel("Choose a FITS file to begin", size: 13, weight: .medium)
    let status = monoLabel("Open a file or drop one onto the surface view.",size: 11)
    let mode = NSSegmentedControl(labels: ["3D surface", "FITS headers"], trackingMode: .selectOne, target: nil, action: nil)
    let heightSlider = NSSlider(value: log10(6), minValue: log10(0.1), maxValue: log10(100), target: nil, action: nil)
    let heightField = NSTextField(string: "6")
    let resolution = NSPopUpButton(frame: .zero, pullsDown: false)
    let appearanceSelection = NSPopUpButton(frame:.zero,pullsDown:false)
    var imagePasteboard = NSPasteboard.general
    let copyViewButton = NSButton(title:"Copy view",target:nil,action:nil)
    let resetButton = NSButton(title:"Reset view",target:nil,action:nil)
    let headerSelection = NSPopUpButton(frame: .zero, pullsDown: false)
    let showGrid = NSButton(checkboxWithTitle: "Show grid", target: nil, action: nil)
    let lighting = NSButton(checkboxWithTitle: "Shading", target: nil, action: nil)
    let headerText = NSTextView()
    let headerScroll = NSScrollView()
    let headerControls = NSStackView()
    let surfaceControls = NSStackView()
    let colorControls = NSView()
    let colorBar = ColorBar()
    let negativeColor = monoLabel("−", size: 11)
    let positiveColor = monoLabel("+", size: 11)
    let help = monoLabel("Drag to orbit -- SHIFT + scroll to zoom -- Reset view to fit",size: 11)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let url = Bundle.main.url(forResource: "RdBu_r", withExtension: "json") else { throw FITSError("Missing RdBu_r color table.") }
            map = try ColorMap(url: url)
        } catch { fatalError(error.localizedDescription) }
        buildMenu()
        buildWindow()
        if let url = startURL { load(url) }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if window == nil { startURL = url } else { load(url) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
    func button(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        return b
    }
    func row(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = spacing
        return stack
    }
    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Potential Visualizer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Potential Visualizer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); menu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        let open = fileMenu.addItem(withTitle: "Open FITS…", action: #selector(openFile), keyEquivalent: "o"); open.target = self
        let reset = fileMenu.addItem(withTitle: "Reset View", action: #selector(resetView), keyEquivalent: "0"); reset.target = self
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:1120,height:800),
                          styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.title = "Potential Visualizer"
        window.minSize = NSSize(width:920,height:620)
        window.center()
        let root = AppearanceView()
        root.wantsLayer = true
        root.appearanceChanged = { [weak self] in self?.refreshAppearance() }
        window.contentView = root
        let open = button("Open FITS…",action:#selector(openFile))
        filename.lineBreakMode = .byTruncatingMiddle
        filename.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let top = row([open,filename])
        top.heightAnchor.constraint(greaterThanOrEqualToConstant:32).isActive = true
        mode.selectedSegment = 0; mode.target = self; mode.action = #selector(changeMode)
        mode.font = .monospacedSystemFont(ofSize:12,weight:.medium)
        top.addArrangedSubview(mode)
        appearanceSelection.addItems(withTitles:["System","Light mode","Dark mode"])
        appearanceSelection.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        appearanceSelection.target = self; appearanceSelection.action = #selector(changeAppearance)
        appearanceSelection.toolTip = "System follows macOS appearance. Light and Dark override it for this app."
        appearanceSelection.selectItem(withTitle:UserDefaults.standard.string(forKey:"Appearance") ?? "System")
        top.addArrangedSubview(appearanceSelection)
        copyViewButton.target = self; copyViewButton.action = #selector(copyView)
        copyViewButton.bezelStyle = .rounded
        copyViewButton.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        copyViewButton.toolTip = "Copy the current 3D view with a transparent background."
        top.addArrangedSubview(copyViewButton)
        resetButton.target = self; resetButton.action = #selector(resetView)
        resetButton.bezelStyle = .rounded
        resetButton.font = .monospacedSystemFont(ofSize:12,weight:.regular)

        heightSlider.target = self; heightSlider.action = #selector(changeHeight)
        heightSlider.isContinuous = true
        heightSlider.widthAnchor.constraint(equalToConstant:180).isActive = true
        heightField.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        heightField.widthAnchor.constraint(equalToConstant:64).isActive = true
        heightField.target = self; heightField.action = #selector(commitHeight); heightField.delegate = self
        resolution.addItems(withTitles:["128 × 128", "256 × 256", "512 × 512", "Full grid"])
        resolution.selectItem(at:1); resolution.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        resolution.target = self; resolution.action = #selector(changeResolution)
        showGrid.state = .off; showGrid.target = self; showGrid.action = #selector(changeGrid)
        showGrid.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        showGrid.toolTip = "Show the reference grid, tick numbers, and axis titles."
        lighting.state = .on; lighting.target = self; lighting.action = #selector(changeLighting)
        lighting.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        surfaceControls.setViews([monoLabel("Height divisor"), heightSlider, heightField,
                                  monoLabel("Grid"),resolution,lighting,showGrid,
                                  resetButton],in:.leading)
        // Reserve the entire visual button height so edges are clickable, too.
        surfaceControls.heightAnchor.constraint(greaterThanOrEqualToConstant:32).isActive = true
        surfaceControls.orientation = .horizontal; surfaceControls.alignment = .centerY; surfaceControls.spacing = 10
        heightSlider.toolTip = "Same as HEIGHT_SCALE: the displayed height is V / divisor. Larger values flatten the surface."
        heightField.toolTip = heightSlider.toolTip
        resolution.toolTip = "Rendering resolution only. Color limits always use the full image. Full grid preserves every pixel."
        lighting.toolTip = "Turn off shading to show the unlit RdBu_r colors."

        headerSelection.addItem(withTitle:"All HDUs")
        headerSelection.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        headerSelection.target = self; headerSelection.action = #selector(changeHeader)
        headerControls.setViews([monoLabel("Header"),headerSelection,button("Copy header",action:#selector(copyHeader))],in:.leading)
        headerControls.orientation = .horizontal; headerControls.alignment = .centerY; headerControls.spacing = 10
        headerControls.isHidden = true

        let canvas = NSView()
        surface.view.translatesAutoresizingMaskIntoConstraints = false
        headerScroll.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(surface.view); canvas.addSubview(headerScroll)
        for view in [surface.view as NSView,headerScroll] {
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:canvas.leadingAnchor),
                                         view.trailingAnchor.constraint(equalTo:canvas.trailingAnchor),
                                         view.topAnchor.constraint(equalTo:canvas.topAnchor),
                                         view.bottomAnchor.constraint(equalTo:canvas.bottomAnchor)])
        }
        headerScroll.hasVerticalScroller = true; headerScroll.hasHorizontalScroller = true
        headerScroll.autohidesScrollers = true; headerScroll.borderType = .bezelBorder
        headerText.isEditable = false; headerText.isSelectable = true; headerText.isRichText = false
        headerText.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        headerText.textContainerInset = NSSize(width:16,height:16)
        headerText.isHorizontallyResizable = true; headerText.isVerticallyResizable = true
        headerText.autoresizingMask = [.width]
        headerText.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        headerText.textContainer?.containerSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        headerText.textContainer?.widthTracksTextView = false
        headerScroll.documentView = headerText
        headerScroll.isHidden = true
        surface.view.onDrop = { [weak self] url in self?.load(url) }

        negativeColor.font = MathAxes.shared.font(size:13)
        positiveColor.font = MathAxes.shared.font(size:13)
        colorBar.map = map
        colorBar.heightAnchor.constraint(equalToConstant:15).isActive = true
        let heightFormula = monoLabel("Height = V / divisor",size:11)
        for item in [heightFormula,negativeColor,colorBar,positiveColor] {
            item.translatesAutoresizingMaskIntoConstraints = false
            colorControls.addSubview(item)
            item.centerYAnchor.constraint(equalTo:colorControls.centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            colorControls.heightAnchor.constraint(equalToConstant:20),
            heightFormula.leadingAnchor.constraint(equalTo:colorControls.leadingAnchor),
            negativeColor.trailingAnchor.constraint(equalTo:colorBar.leadingAnchor,constant:-10),
            positiveColor.leadingAnchor.constraint(equalTo:colorBar.trailingAnchor,constant:10)
        ])
        help.textColor = .secondaryLabelColor
        status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let stack = NSStackView(views:[top,surfaceControls,headerControls,canvas,colorControls,help,status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:18),
                                     stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-18),
                                     stack.topAnchor.constraint(equalTo:root.topAnchor,constant:16),
                                     stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-14),
                                     top.widthAnchor.constraint(equalTo:stack.widthAnchor),
                                     surfaceControls.widthAnchor.constraint(equalTo:stack.widthAnchor),
                                     headerControls.widthAnchor.constraint(equalTo:stack.widthAnchor),
                                     colorControls.widthAnchor.constraint(equalTo:stack.widthAnchor),
                                     colorBar.widthAnchor.constraint(equalTo:root.widthAnchor,multiplier:0.5),
                                     colorBar.centerXAnchor.constraint(equalTo:root.centerXAnchor),
                                     canvas.widthAnchor.constraint(equalTo:stack.widthAnchor),
                                     canvas.heightAnchor.constraint(greaterThanOrEqualToConstant:300),
                                     status.widthAnchor.constraint(equalTo:stack.widthAnchor)])
        canvas.setContentHuggingPriority(.defaultLow,for:.vertical)
        changeAppearance()
        updateEnabled()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func updateEnabled() {
        copyViewButton.isEnabled = potential != nil && !busy && mode.selectedSegment == 0
        for control in [heightSlider as NSControl,heightField,resolution,lighting,showGrid,resetButton] { control.isEnabled = potential != nil && !busy }
    }
    @objc func changeAppearance() {
        let selection = appearanceSelection.titleOfSelectedItem ?? "System"
        switch selection {
        case "Light mode": window.appearance = NSAppearance(named:.aqua)
        case "Dark mode": window.appearance = NSAppearance(named:.darkAqua)
        default: window.appearance = nil
        }
        if smokeDirectory == nil && reloadTestDirectory == nil { UserDefaults.standard.set(selection,forKey:"Appearance") }
        refreshAppearance()
    }
    func refreshAppearance() {
        guard let root = window?.contentView else { return }
        let dark = root.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        root.layer?.backgroundColor = (dark ? NSColor(srgbRed:0.14,green:0.15,blue:0.17,alpha:1) : NSColor(srgbRed:0.96,green:0.96,blue:0.97,alpha:1)).cgColor
        surface.setDarkMode(dark)
        headerText.textColor = .textColor
        headerText.backgroundColor = .textBackgroundColor
        headerScroll.backgroundColor = .textBackgroundColor
        root.needsDisplay = true
    }
    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open a potential FITS file"
        panel.allowedContentTypes = ["fits","fit","fts"].compactMap { UTType(filenameExtension:$0) }
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for:window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.load(url) }
        }
    }
    func load(_ url: URL) {
        let request = UUID(); generation = request
        busy = true; updateEnabled(); status.stringValue = "Reading \(url.lastPathComponent)…"
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let doc = try FITSDocument(url:url)
                let result = Result { try doc.potential() }
                DispatchQueue.main.async {
                    guard self.generation == request else { return }
                    self.document = doc
                    self.window.title = "\(url.lastPathComponent) — Potential Visualizer"
                    self.window.representedURL = url
                    self.filename.stringValue = url.lastPathComponent; self.filename.toolTip = url.path
                    self.headerSelection.removeAllItems(); self.headerSelection.addItem(withTitle:"All HDUs")
                    for h in doc.hdus { self.headerSelection.addItem(withTitle:"\(h.index): \(h.name)") }
                    self.changeHeader()
                    switch result {
                    case .success(let p): self.potential = p; self.rebuild()
                    case .failure(let error):
                        self.potential = nil; self.surface.surface.geometry = nil
                        self.surface.potential = nil; self.surface.drawAxes()
                        self.busy = false; self.updateEnabled()
                        self.mode.selectedSegment = 1; self.changeMode()
                        self.status.stringValue = error.localizedDescription
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == request else { return }
                    self.busy = false; self.updateEnabled()
                    self.status.stringValue = "Could not open \(url.lastPathComponent)."
                    self.alert(error.localizedDescription)
                }
            }
        }
    }
    func rebuild() {
        guard let p = potential else { return }
        let limit = [128,256,512,max(p.width,p.height)][resolution.indexOfSelectedItem]
        let request = UUID(); generation = request
        busy = true; updateEnabled(); status.stringValue = "Building the surface…"
        DispatchQueue.global(qos:.userInitiated).async {
            let mesh = makeSurface(p,limit:limit,map:self.map)
            DispatchQueue.main.async {
                guard self.generation == request else { return }
                self.surface.install(mesh,potential:p,lighting:self.lighting.state == .on)
                self.negativeColor.stringValue = String(format:"%.5g",-p.colorLimit)
                self.positiveColor.stringValue = String(format:"+%.5g",p.colorLimit)
                self.status.stringValue = "HDU \(p.hduIndex) -- \(p.width) × \(p.height) pixels -- rendered \(mesh.nx) × \(mesh.ny) -- V range = [\(String(format:"%.5g",p.minimum)), \(String(format:"%.5g",p.maximum))]"
                self.busy = false; self.updateEnabled()
                self.runSmokeIfNeeded()
                self.runReloadTestIfNeeded()
            }
        }
    }
    @objc func changeMode() {
        let headers = mode.selectedSegment == 1
        headerScroll.isHidden = !headers; surface.view.isHidden = headers
        surfaceControls.isHidden = headers; colorControls.isHidden = headers; help.isHidden = headers
        headerControls.isHidden = !headers
        updateEnabled()
    }
    @objc func changeHeader() {
        headerText.string = document?.headerText(index:headerSelection.indexOfSelectedItem > 0 ? headerSelection.indexOfSelectedItem-1 : nil) ?? "No FITS file loaded."
        headerText.scrollToBeginningOfDocument(nil)
    }
    @objc func copyView() {
        guard potential != nil, !busy, mode.selectedSegment == 0 else { return }
        guard let image = surface.transparentSnapshot(),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data:tiff),
              let png = bitmap.representation(using:.png,properties:[:]) else {
            alert("The current view could not be copied."); return
        }
        // PNG and TIFF both preserve alpha; document apps choose their preferred format.
        let item = NSPasteboardItem()
        item.setData(png,forType:.png); item.setData(tiff,forType:.tiff)
        imagePasteboard.clearContents()
        guard imagePasteboard.writeObjects([item]) else {
            alert("The image could not be written to the clipboard."); return
        }
        copyViewButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5) { self.copyViewButton.title = "Copy view" }
    }
    @objc func copyHeader() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(headerText.string,forType:.string) }
    @objc func changeHeight() {
        let value = pow(10,heightSlider.doubleValue)
        heightField.stringValue = String(format:"%.3g",value)
        surface.setHeight(value)
    }
    @objc func commitHeight() {
        guard let value = Double(heightField.stringValue), value.isFinite, value >= 0.1, value <= 100 else {
            heightField.stringValue = String(format:"%.3g",surface.heightScale)
            alert("Enter a height divisor from 0.1 to 100. Larger values flatten the surface."); return
        }
        heightSlider.doubleValue = log10(value); surface.setHeight(value)
    }
    func controlTextDidEndEditing(_ notification: Notification) { if notification.object as? NSTextField === heightField { commitHeight() } }
    @objc func changeResolution() { rebuild() }
    @objc func changeGrid() { surface.setGridVisible(showGrid.state == .on) }
    @objc func changeLighting() { surface.setLighting(lighting.state == .on) }
    @objc func resetView() { resetCount += 1; surface.resetCamera() }
    func alert(_ text: String) {
        let alert = NSAlert(); alert.messageText = "Potential Visualizer"; alert.informativeText = text
        alert.beginSheetModal(for:window)
    }
    func runSmokeIfNeeded() {
        guard let output = smokeDirectory, !smokeStarted else { return }
        smokeStarted = true
        heightField.stringValue = "12"; commitHeight()
        check(abs(Double(surface.surface.scale.z)-1/12.0) < 1e-6)
        heightField.stringValue = "6"; commitHeight(); resetView()
        appearanceSelection.selectItem(withTitle:"Light mode"); changeAppearance()
        DispatchQueue.main.asyncAfter(deadline:.now()+2) {
            do {
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                self.window.contentView?.layoutSubtreeIfNeeded()
                self.assertControlHitAreas()
                self.testZoom()
                self.testPointerZoom()
                self.testCopyView(output)
                check(self.showGrid.state == .off && self.surface.grid.isHidden && self.surface.axes.isHidden)
                check(self.lighting.state == .on)
                self.saveWindow(output.appendingPathComponent("surface-window.png"),includeSurface:true)
                self.saveImage(self.surface.view.snapshot(),to:output.appendingPathComponent("surface.png"))
                self.click(self.showGrid)
                check(self.showGrid.state == .on && !self.surface.grid.isHidden && !self.surface.axes.isHidden)
                self.surface.setHeight(12)
                self.surface.setDarkMode(true)
                check(!self.surface.grid.isHidden && !self.surface.axes.isHidden)
                self.surface.setHeight(6)
                self.surface.setDarkMode(false)
                self.saveImage(self.surface.view.snapshot(),to:output.appendingPathComponent("grid-on.png"))
                self.click(self.showGrid)
                check(self.showGrid.state == .off && self.surface.grid.isHidden && self.surface.axes.isHidden)
                check(self.surface.axes.childNodes.count == 6)
                self.saveImage(self.surface.view.snapshot(),to:output.appendingPathComponent("grid-off.png"))
                self.click(self.lighting)
                check(self.lighting.state == .off)
                check(self.surface.surface.geometry?.firstMaterial?.lightingModel == .constant)
                self.saveImage(self.surface.view.snapshot(),to:output.appendingPathComponent("unlit-surface.png"))
                self.click(self.lighting)
                check(self.lighting.state == .on)
                check(self.surface.surface.geometry?.firstMaterial?.lightingModel == .lambert)
                self.testReset()
                self.appearanceSelection.selectItem(withTitle:"Dark mode"); self.changeAppearance()
                check(self.surface.darkMode)
                self.saveWindow(output.appendingPathComponent("dark-window.png"),includeSurface:true)
                self.mode.selectedSegment = 1; self.changeMode()
                self.headerSelection.selectItem(at:1); self.changeHeader()
                check(self.headerText.string.contains("SIMPLE"))
                self.window.contentView?.layoutSubtreeIfNeeded()
                self.saveWindow(output.appendingPathComponent("header-window.png"),includeSurface:false)
                self.appearanceSelection.selectItem(withTitle:"System"); self.changeAppearance()
                check(self.window.appearance == nil)
                // Simulate the inherited appearance changing in both directions.
                let previous = NSApp.appearance
                NSApp.appearance = NSAppearance(named:.darkAqua)
                check(self.surface.darkMode)
                NSApp.appearance = NSAppearance(named:.aqua)
                check(!self.surface.darkMode)
                NSApp.appearance = previous
                self.mode.selectedSegment = 0; self.changeMode()
                self.window.setContentSize(NSSize(width:920,height:620))
                self.window.contentView?.layoutSubtreeIfNeeded()
                self.assertControlHitAreas()
                self.click(self.lighting); check(self.lighting.state == .off)
                self.testReset()
                self.saveWindow(output.appendingPathComponent("compact-window.png"),includeSurface:true)
                check(self.surface.axes.childNodes.filter { $0.name == "tick" }.count == 4)
                check(self.surface.axes.childNodes.contains { $0.name == "phi1" || $0.name == "pixelX" })
                print("GUI tests passed: Shift-scroll and pinch zoom in both directions with grid on/off; grid defaults off, toggles together with tick numbers and axis titles, and survives height/theme changes; actual mouse clicks toggle shading; reset restores rotated/panned/zoomed camera; light/dark/system appearances; header; compact window hit areas; math axes; height scale.")
                NSApp.terminate(nil)
            } catch { fputs("\(error)\n",stderr); exit(1) }
        }
    }
    // Exercise replacement through the real asynchronous file-load/rebuild path.
    // The companion Python test compares rendered pixels as well as UI state.
    func runReloadTestIfNeeded() {
        guard let output = reloadTestDirectory, let secondFile = reloadTestFile else { return }
        let stage = reloadTestStage
        DispatchQueue.main.asyncAfter(deadline:.now()+0.7) {
            if stage == 0 {
                try! FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                self.appearanceSelection.selectItem(withTitle:"Light mode"); self.changeAppearance()
                self.click(self.lighting)
                check(self.lighting.state == .off)
                check(self.showGrid.state == .off && self.surface.grid.isHidden && self.surface.axes.isHidden)
                self.click(self.showGrid)
                self.reloadTestStage = 1
                self.load(secondFile)
            } else if stage == 1 || stage == 2 {
                check(self.showGrid.state == .on && !self.surface.grid.isHidden && !self.surface.axes.isHidden)
                let name = stage == 1 ? "reload" : "rebuild"
                self.captureReloadTest(name+"-off",lighting:false)
                self.click(self.lighting)
                DispatchQueue.main.asyncAfter(deadline:.now()+0.7) {
                    self.captureReloadTest(name+"-on",lighting:true)
                    self.click(self.lighting)
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.7) {
                        self.captureReloadTest(name+"-toggled-off",lighting:false)
                        if stage == 1 {
                            self.reloadTestStage = 2
                            self.resolution.selectItem(at:0)
                            self.changeResolution()
                        } else {
                            self.click(self.lighting)
                            self.click(self.showGrid)
                            self.reloadTestStage = 3
                            self.load(self.startURL!)
                        }
                    }
                }
            } else {
                check(self.showGrid.state == .off && self.surface.grid.isHidden && self.surface.axes.isHidden)
                self.captureReloadTest("reload-enabled",lighting:true)
                self.click(self.lighting)
                DispatchQueue.main.asyncAfter(deadline:.now()+0.7) {
                    self.captureReloadTest("reload-enabled-off",lighting:false)
                    self.click(self.lighting)
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.7) {
                        self.captureReloadTest("reload-enabled-on",lighting:true)
                        print("Shading reload GUI sequence passed. Compare screenshots with Tests/test_shading_reload.py.")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
    func captureReloadTest(_ name: String, lighting enabled: Bool) {
        check(!busy)
        check(lighting.state == (enabled ? .on : .off),"Checkbox disagrees with shading state")
        check(surface.surface.geometry?.firstMaterial?.lightingModel == (enabled ? .lambert : .constant),"Material disagrees with shading state")
        saveImage(surface.view.snapshot(),to:reloadTestDirectory!.appendingPathComponent(name+".png"))
    }
    func assertControlHitAreas() {
        let root = window.contentView!
        for control in [lighting,showGrid,resetButton,copyViewButton] {
            // Verify the center and visible top/bottom edges, not just the action.
            for y in [control.bounds.midY,control.bounds.minY+4,control.bounds.maxY-4] {
                let point = root.convert(NSPoint(x:control.bounds.midX,y:y),from:control)
                let hit = root.hitTest(point)
                check(hit === control, "Control hit area is clipped: \(control.title) at \(y); got \(String(describing:hit))")
            }
        }
    }
    func testZoom() {
        func scroll(_ x: Int32, _ y: Int32) {
            let raw = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:y,wheel2:x,wheel3:0)!
            raw.flags = .maskShift
            let screenPoint = window.convertPoint(toScreen:surface.view.convert(
                NSPoint(x:surface.view.bounds.midX,y:surface.view.bounds.midY),to:nil))
            raw.location = CGPoint(x:screenPoint.x,y:NSScreen.screens[0].frame.maxY-screenPoint.y)
            surface.view.scrollWheel(with:NSEvent(cgEvent:raw)!)
        }
        for gridEnabled in [false,true] {
            showGrid.state = gridEnabled ? .on : .off; changeGrid()
            surface.resetCamera()
            let initial = surface.camera.camera!.orthographicScale
            scroll(0,10)
            check(surface.camera.camera!.orthographicScale < initial,"Shift-scroll did not zoom in")
            scroll(0,-10)
            check(abs(surface.camera.camera!.orthographicScale/initial-1) < 1e-6,"Reverse scroll did not restore scale")
            // macOS can remap Shift-wheel motion to the horizontal axis.
            scroll(10,0)
            check(surface.camera.camera!.orthographicScale < initial,"Horizontal Shift-scroll did not zoom")
            surface.resetCamera()
            let event = ZoomTestEvent()
            event.point = surface.view.convert(NSPoint(x:surface.view.bounds.midX,y:surface.view.bounds.midY),to:nil)
            surface.view.magnify(with:event)
            check(surface.camera.camera!.orthographicScale < initial,"Trackpad magnification did not zoom in")
            event.pinch = -0.2; surface.view.magnify(with:event)
            check(abs(surface.camera.camera!.orthographicScale/initial-1) < 1e-6,"Reverse magnification did not restore scale")
            event.pinch = 0.2; surface.view.magnify(with:event)
            click(resetButton)
            check(abs(surface.camera.camera!.orthographicScale/initial-1) < 1e-6,"Reset did not undo gesture zoom")
        }
        showGrid.state = .off; changeGrid()
    }
    func testPointerZoom() {
        let view = surface.view
        for compact in [false,true] {
            window.setContentSize(NSSize(width:compact ? 920 : 1120,height:compact ? 620 : 800))
            window.contentView?.layoutSubtreeIfNeeded()
            for gridEnabled in [false,true] {
                showGrid.state = gridEnabled ? .on : .off; changeGrid()
                surface.resetCamera()
                if gridEnabled { view.defaultCameraController.rotateBy(x:25,y:15) }
                for fraction in [NSPoint(x:0.3,y:0.35),NSPoint(x:0.7,y:0.65)] {
                    for gesture in ["scroll", "horizontal", "pinch"] {
                        for direction in [1.0,-1.0] {
                            _ = view.snapshot()
                            let screen = NSPoint(x:view.bounds.width*fraction.x,y:view.bounds.height*fraction.y)
                            let depth = view.projectPoint(SCNVector3Zero).z
                            let anchor = view.unprojectPoint(SCNVector3(screen.x,screen.y,depth))
                            let before = view.projectPoint(anchor)
                            let event = ZoomTestEvent()
                            // SceneKit projection coordinates have their origin at the bottom left.
                            let local = NSPoint(x:screen.x,y:view.isFlipped ? view.bounds.height-screen.y : screen.y)
                            event.point = view.convert(local,to:nil)
                            event.pinch = direction*0.2
                            event.wheelX = gesture == "horizontal" ? direction*20 : 0
                            event.wheelY = gesture == "horizontal" ? 0 : direction*20
                            let scale = surface.camera.camera!.orthographicScale
                            if gesture == "pinch" { view.magnify(with:event) }
                            else { view.scrollWheel(with:event) }
                            _ = view.snapshot()
                            let after = view.projectPoint(anchor)
                            let error = hypot(Double(after.x-before.x),Double(after.y-before.y))
                            check(error < 0.5,"Pointer moved during \(gesture) zoom: \(error) points")
                            check(direction > 0 ? surface.camera.camera!.orthographicScale < scale : surface.camera.camera!.orthographicScale > scale)
                        }
                    }
                }
                testReset()
            }
        }
        window.setContentSize(NSSize(width:1120,height:800))
        window.contentView?.layoutSubtreeIfNeeded()
        showGrid.state = .off; changeGrid()
        print("Pointer zoom passed: scroll, horizontal Shift-scroll, and pinch keep off-center anchors within 0.5 points; grid on/off, rotated camera, two window sizes, both directions.")
    }
    func testCopyView(_ output: URL) {
        // Exercise the button and clipboard formats without replacing the user's clipboard.
        let previousPasteboard = imagePasteboard
        imagePasteboard = NSPasteboard.withUniqueName()
        defer { imagePasteboard.releaseGlobally(); imagePasteboard = previousPasteboard }
        for dark in [false,true] {
            appearanceSelection.selectItem(withTitle:dark ? "Dark mode" : "Light mode"); changeAppearance()
            for gridEnabled in [false,true] {
                showGrid.state = gridEnabled ? .on : .off; changeGrid()
                surface.resetCamera()
                surface.view.defaultCameraController.rotateBy(x:18,y:12)
                let event = ZoomTestEvent()
                event.point = surface.view.convert(NSPoint(x:surface.view.bounds.width*0.4,y:surface.view.bounds.height*0.6),to:nil)
                surface.view.magnify(with:event)
                let transform = surface.camera.simdWorldTransform
                let scale = surface.camera.camera!.orthographicScale
                let target = surface.view.defaultCameraController.target
                _ = surface.view.snapshot()
                click(copyViewButton)
                check(copyViewButton.title == "Copied!")
                let name = "clipboard-" + (dark ? "dark" : "light") + (gridEnabled ? "-grid" : "-surface")
                for (type,ext) in [(NSPasteboard.PasteboardType.png,"png"),(.tiff,"tiff")] {
                    guard let data = imagePasteboard.data(forType:type),let bitmap = NSBitmapImageRep(data:data) else {
                        check(false,"Missing clipboard image"); return
                    }
                    check(bitmap.hasAlpha,"Copied image has no alpha channel")
                    check(bitmap.colorAt(x:0,y:0)!.alphaComponent == 0,"Copied background is opaque")
                    try! data.write(to:output.appendingPathComponent(name+"."+ext))
                }
                check(surface.camera.simdWorldTransform == transform && surface.camera.camera!.orthographicScale == scale)
                check(SCNVector3EqualToVector3(surface.view.defaultCameraController.target,target))
                check(surface.darkMode == dark && surface.grid.isHidden == !gridEnabled)
            }
        }
        copyViewButton.title = "Copy view"
        showGrid.state = .off; changeGrid(); surface.resetCamera()
        appearanceSelection.selectItem(withTitle:"Light mode"); changeAppearance()
        print("Copy view passed: button writes transparent PNG and TIFF; camera, zoom, orbit target, theme, and grid state unchanged.")
    }
    func testReset() {
        surface.resetCamera()
        let expected = surface.camera.transform
        let wanted = surface.camera.simdTransform
        let expectedScale = surface.camera.camera!.orthographicScale
        let controller = surface.view.defaultCameraController
        controller.rotateBy(x:32,y:18)
        controller.translateInCameraSpaceBy(x:0.3,y:0.5,z:0)
        surface.view.pointOfView?.camera?.orthographicScale = expectedScale*0.55
        check(!SCNMatrix4EqualToMatrix4(surface.camera.transform,expected))
        let previousCount = resetCount
        click(resetButton)
        check(resetCount == previousCount+1, "Reset click did not dispatch its action")
        // SceneKit normalizes rotations in float precision; allow roundoff.
        let actual = surface.camera.simdTransform
        for column in 0..<4 {
            for row in 0..<4 {
                check(abs(actual[column][row]-wanted[column][row]) < 1e-5,"Reset did not restore camera transform: actual=\(actual) wanted=\(wanted), count=\(resetCount)")
            }
        }
        check(surface.view.pointOfView === surface.camera)
        check(controller.pointOfView === surface.camera)
        check(abs(surface.camera.camera!.orthographicScale-expectedScale) < 1e-10)
        check(!controller.isInertiaRunning)
    }
    func click(_ control: NSControl) {
        let point = control.convert(NSPoint(x:control.bounds.midX,y:control.bounds.midY),to:nil)
        let down = NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        let up = NSEvent.mouseEvent(with:.leftMouseUp,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime+0.01,windowNumber:window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
        NSApp.postEvent(up,atStart:true)
        NSApp.sendEvent(down)
    }
    func saveImage(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) else { return }
        try? png.write(to:url)
    }
    func saveWindow(_ url: URL, includeSurface: Bool) {
        guard let root = window.contentView,
              let bitmap = root.bitmapImageRepForCachingDisplay(in:root.bounds) else { return }
        root.cacheDisplay(in:root.bounds,to:bitmap)
        let image = NSImage(size:root.bounds.size); image.addRepresentation(bitmap)
        if includeSurface {
            image.lockFocus()
            surface.view.snapshot().draw(in:root.convert(surface.view.bounds,from:surface.view))
            image.unlockFocus()
        }
        saveImage(image,to:url)
    }
}

let arguments = CommandLine.arguments
if arguments.count >= 3 && arguments[1] == "--inspect" {
    do {
        let doc = try FITSDocument(url:URL(fileURLWithPath:arguments[2]))
        let p = try doc.potential()
        let map = try ColorMap(url:Bundle.main.url(forResource:"RdBu_r",withExtension:"json")!)
        let mesh = makeSurface(p,limit:128,map:map)
        let sampleIndices = [0,1,p.width-1,p.width,p.values.count/2,p.values.count-1]
        let summary: [String:Any] = ["hdus":doc.hdus.map { ["index":$0.index,"name":$0.name,"cards":$0.cards.count] as [String:Any] },
                                    "width":p.width,"height":p.height,"lx":p.lx,"ly":p.ly,"hdu":p.hduIndex,
                                    "min":p.minimum,"max":p.maximum,"colorLimit":p.colorLimit,"finiteCount":p.finiteCount,
                                    "samples":sampleIndices.map { ["index":$0,"value":p.values[$0].isFinite ? p.values[$0] as Any : NSNull()] },
                                    "meshTriangles":mesh.triangles,"meshWidth":mesh.nx,"meshHeight":mesh.ny,
                                    "colorIndices":[-p.colorLimit,0,p.colorLimit].map { map.index($0,limit:p.colorLimit) }]
        let json = try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:json,as:UTF8.self))
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
if arguments.count >= 4 && arguments[1] == "--smoke-test" {
    delegate.startURL = URL(fileURLWithPath:arguments[2])
    delegate.smokeDirectory = URL(fileURLWithPath:arguments[3],isDirectory:true)
} else if arguments.count >= 5 && arguments[1] == "--shading-reload-test" {
    delegate.startURL = URL(fileURLWithPath:arguments[2])
    delegate.reloadTestFile = URL(fileURLWithPath:arguments[3])
    delegate.reloadTestDirectory = URL(fileURLWithPath:arguments[4],isDirectory:true)
    DispatchQueue.main.asyncAfter(deadline:.now()+45) { fputs("Shading reload test timed out\n",stderr); exit(1) }
} else if arguments.count >= 2 && !arguments[1].hasPrefix("-") {
    delegate.startURL = URL(fileURLWithPath:arguments[1])
}
app.delegate = delegate
app.run()
