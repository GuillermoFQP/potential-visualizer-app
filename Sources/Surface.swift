import AppKit
import SceneKit

final class ColorMap {
    let colors: [[Double]]
    init(url: URL) throws {
        colors = try JSONDecoder().decode([[Double]].self, from: Data(contentsOf: url))
        guard colors.count == 256, colors.allSatisfy({ $0.count == 4 }) else { throw FITSError("Invalid RdBu_r color table.") }
    }
    func index(_ value: Double, limit: Double) -> Int {
        // Matches Matplotlib Normalize(-limit, limit) followed by its 256-entry LUT.
        let t = min(1, max(0, (value + limit)/(2*limit)))
        return min(255, Int(t * 256))
    }
    func color(_ index: Int) -> NSColor {
        let c = colors[index]
        return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
    }
}

struct SurfaceMesh {
    let geometry: SCNGeometry
    let nx: Int
    let ny: Int
    let triangles: Int
}

func makeSurface(_ p: Potential, limit: Int, map: ColorMap) -> SurfaceMesh {
    let nx = min(p.width, limit), ny = min(p.height, limit)
    let xs = (0..<nx).map { Int((Double($0) * Double(p.width-1) / Double(nx-1)).rounded()) }
    let ys = (0..<ny).map { Int((Double($0) * Double(p.height-1) / Double(ny-1)).rounded()) }
    var positions: [SCNVector3] = [], normals: [SCNVector3] = []
    var colors: [Float] = []
    var valid = [Bool](repeating: false, count: nx*ny)
    positions.reserveCapacity(nx*ny); normals.reserveCapacity(nx*ny); colors.reserveCapacity(4*nx*ny)
    let dx = 2*p.lx/Double(p.width), dy = 2*p.ly/Double(p.height)
    for (j, iy) in ys.enumerated() {
        for (i, ix) in xs.enumerated() {
            let v = p.values[iy*p.width+ix]
            let finite = v.isFinite
            valid[j*nx+i] = finite
            let x = -p.lx + (Double(ix)+0.5)*dx
            let y = -p.ly + (Double(iy)+0.5)*dy
            positions.append(SCNVector3(x, y, finite ? v : 0))
            let left = max(0, ix-1), right = min(p.width-1, ix+1)
            let down = max(0, iy-1), up = min(p.height-1, iy+1)
            let gx = (p.values[iy*p.width+right] - p.values[iy*p.width+left]) / (Double(right-left)*dx)
            let gy = (p.values[up*p.width+ix] - p.values[down*p.width+ix]) / (Double(up-down)*dy)
            let length = hypot(hypot(gx, gy), 1)
            normals.append(length.isFinite ? SCNVector3(-gx/length,-gy/length,1/length) : SCNVector3(0,0,1))
            let rgba = map.colors[finite ? map.index(v, limit: p.colorLimit) : 128]
            // SceneKit vertex colors are linear-light. Convert the exact sRGB
            // Matplotlib LUT so an unlit render reproduces its displayed colors.
            colors.append(contentsOf: rgba.prefix(3).map { channel in
                Float(channel <= 0.04045 ? channel/12.92 : pow((channel+0.055)/1.055,2.4))
            })
            colors.append(Float(rgba[3]))
        }
    }
    var indices: [Int32] = []
    indices.reserveCapacity((nx-1)*(ny-1)*6)
    for j in 0..<(ny-1) {
        for i in 0..<(nx-1) {
            let a = j*nx+i, b = a+1, c = a+nx, d = c+1
            if valid[a] && valid[b] && valid[c] { indices += [Int32(a),Int32(b),Int32(c)] }
            if valid[b] && valid[d] && valid[c] { indices += [Int32(b),Int32(d),Int32(c)] }
        }
    }
    let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
    let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: nx*ny,
                                       usesFloatComponents: true, componentsPerVector: 4,
                                       bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                       dataStride: 4*MemoryLayout<Float>.size)
    let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                         SCNGeometrySource(normals: normals), colorSource],
                               elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    // Build only mesh data here. The UI thread creates the display material
    // in install(), with its final shading mode, before attaching the geometry.
    return SurfaceMesh(geometry: geometry, nx: nx, ny: ny, triangles: indices.count/3)
}

final class SurfaceView: SCNView {
    var onDrop: ((URL) -> Void)?
    var fittedScale: Double = 1
    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.shift),
              pointOfView?.camera?.usesOrthographicProjection == true else {
            super.scrollWheel(with:event); return
        }
        // Shift-wheel may arrive on X instead of Y on macOS.
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY : event.scrollingDeltaX
        zoom(by:Double(delta) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1), at:convert(event.locationInWindow,from:nil))
    }
    override func magnify(with event: NSEvent) {
        guard pointOfView?.camera?.usesOrthographicProjection == true else {
            super.magnify(with:event); return
        }
        zoom(by:Double(event.magnification), at:convert(event.locationInWindow,from:nil))
    }
    private func zoom(by amount: Double, at pointer: NSPoint) {
        guard allowsCameraControl, amount.isFinite,
              bounds.width > 0, bounds.height > 0,
              let cameraNode = pointOfView, let camera = cameraNode.camera else { return }
        defaultCameraController.stopInertia()
        let oldScale = camera.orthographicScale
        let newScale = max(fittedScale*1e-4,min(fittedScale*1e4,
            oldScale * exp(-max(-2,min(2,amount)))))
        // Keep the world point beneath the pointer fixed on screen. With an
        // orthographic camera, the same translation works at every depth.
        // Read the model projection directly so consecutive gesture events do
        // not depend on the renderer having drawn the previous event yet.
        let projection = camera.projectionTransform(withViewportSize:bounds.size)
        let x = 2*(pointer.x-bounds.minX)/bounds.width-1
        let y = (isFlipped ? -1.0 : 1.0)*(2*(pointer.y-bounds.minY)/bounds.height-1)
        let fraction = 1-newScale/oldScale
        let offset = SCNVector3(Double(x/projection.m11)*fraction,
                                Double(y/projection.m22)*fraction,0)
        let shift = cameraNode.convertVector(offset,to:nil)
        var transform = cameraNode.simdWorldTransform
        transform.columns.3 += SIMD4<Float>(Float(shift.x),Float(shift.y),Float(shift.z),0)
        let target = defaultCameraController.target
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        camera.orthographicScale = newScale
        // Move the orbit pivot too, retaining the viewing direction after zoom.
        defaultCameraController.target = SCNVector3(target.x+shift.x,target.y+shift.y,target.z+shift.z)
        cameraNode.simdWorldTransform = transform
        SCNTransaction.commit()
        SCNTransaction.flush()
        needsDisplay = true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let url = urls.first else { return false }
        onDrop?(url); return true
    }
}

final class ColorBar: NSView {
    var map: ColorMap?
    override func draw(_ dirtyRect: NSRect) {
        guard let map = map else { return }
        for i in 0..<256 {
            map.color(i).setFill()
            NSRect(x: bounds.width*Double(i)/256, y: 1, width: bounds.width/256+1, height: bounds.height-2).fill()
        }
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5,dy: 0.5)).stroke()
    }
}

final class SurfaceScene {
    let view = SurfaceView(frame: .zero)
    let scene = SCNScene()
    let surface = SCNNode()
    let axes = SCNNode()
    let grid = SCNNode()
    let camera = SCNNode()
    var potential: Potential?
    var heightScale: Double = 6
    private(set) var darkMode = false

    init() {
        view.scene = scene
        view.backgroundColor = .white
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        // Keep navigation on our camera, rather than an implicit free-camera copy.
        view.cameraControlConfiguration.autoSwitchToFreeCamera = false
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 30
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.worldUp = SCNVector3(0,0,1)
        view.defaultCameraController.target = SCNVector3Zero
        view.autoenablesDefaultLighting = false
        scene.rootNode.addChildNode(surface)
        scene.rootNode.addChildNode(axes)
        grid.isHidden = true
        axes.isHidden = true
        scene.rootNode.addChildNode(grid)
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera
        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.55, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight(); key.light?.type = .directional
        key.light?.color = NSColor(white: 0.65, alpha: 1)
        key.eulerAngles = SCNVector3(-0.6,0.4,-0.5)
        scene.rootNode.addChildNode(key)
    }
    func install(_ mesh: SurfaceMesh, potential: Potential, lighting: Bool) {
        precondition(Thread.isMainThread)
        self.potential = potential
        // Do not attach a Lambert material and then change its lighting model:
        // SceneKit can retain that initial shader when geometry is replaced.
        // A fresh, fully configured material also avoids cross-thread material
        // transactions from the background mesh builder.
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.white
        material.lightingModel = lighting ? .lambert : .constant
        material.isDoubleSided = true
        material.specular.contents = NSColor(white:0.08,alpha:1)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        mesh.geometry.materials = [material]
        surface.geometry = mesh.geometry
        SCNTransaction.commit()
        setHeight(heightScale)
        resetCamera()
    }
    func transparentSnapshot() -> NSImage? {
        guard potential != nil, let activeCamera = view.pointOfView,
              view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        // Render a separate scene so copying never changes the live background,
        // camera, hidden nodes, or the user's navigation state.
        let exportScene = SCNScene()
        exportScene.background.contents = NSColor.clear
        exportScene.rootNode.addChildNode(scene.rootNode.clone())
        let exportCamera = SCNNode()
        exportCamera.camera = activeCamera.camera?.copy() as? SCNCamera
        exportCamera.simdWorldTransform = activeCamera.simdWorldTransform
        exportScene.rootNode.addChildNode(exportCamera)
        let renderer = SCNRenderer(device:view.device,options:nil)
        renderer.scene = exportScene
        renderer.pointOfView = exportCamera
        renderer.autoenablesDefaultLighting = view.autoenablesDefaultLighting
        let factor = view.window?.backingScaleFactor ?? 2
        let size = CGSize(width:(view.bounds.width*factor).rounded(),
                          height:(view.bounds.height*factor).rounded())
        let image = renderer.snapshot(atTime:view.sceneTime,with:size,antialiasingMode:view.antialiasingMode)
        image.size = view.bounds.size
        return image
    }
    func setLighting(_ enabled: Bool) {
        // Apply to every material and commit immediately, including while idle.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        surface.geometry?.materials.forEach { $0.lightingModel = enabled ? .lambert : .constant }
        SCNTransaction.commit()
        SCNTransaction.flush()
        view.needsDisplay = true
    }
    func setGridVisible(_ enabled: Bool) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        grid.isHidden = !enabled
        axes.isHidden = !enabled
        SCNTransaction.commit()
        SCNTransaction.flush()
        view.needsDisplay = true
    }
    func setHeight(_ value: Double) {
        heightScale = value
        surface.scale = SCNVector3(1,1,1/value)
        drawAxes()
        if let p = potential {
            view.pointOfView?.camera?.zFar = max(1000, 100*max(p.lx,p.ly,p.colorLimit/value))
        }
        view.needsDisplay = true
    }
    func resetCamera() {
        guard let p = potential else { return }
        let controller = view.defaultCameraController
        controller.stopInertia()
        // Detach before clearing navigation state; target/world-up updates can
        // otherwise change an already-positioned camera after a previous pan.
        controller.pointOfView = nil
        controller.automaticTarget = false
        controller.target = SCNVector3Zero
        controller.worldUp = SCNVector3(0,0,1)
        camera.removeAllActions()
        camera.removeAllAnimations()
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        camera.transform = SCNMatrix4Identity
        view.pointOfView = camera
        controller.pointOfView = camera
        let radius = max(p.lx,p.ly,p.colorLimit/heightScale)
        let elevation = 35.0 * Double.pi/180, azimuth = -45.0 * Double.pi/180
        camera.position = SCNVector3(4*radius*cos(elevation)*cos(azimuth),
                                     4*radius*cos(elevation)*sin(azimuth),4*radius*sin(elevation))
        camera.look(at: SCNVector3Zero, up: SCNVector3(0,0,1), localFront: SCNVector3(0,0,-1))
        view.fittedScale = 1.5*radius
        camera.camera?.orthographicScale = view.fittedScale
        camera.camera?.zNear = max(radius/10000,1e-8)
        camera.camera?.zFar = max(1000,100*radius)
        SCNTransaction.commit()
        SCNTransaction.flush()
        view.needsDisplay = true
    }
    func setDarkMode(_ enabled: Bool) {
        darkMode = enabled
        view.backgroundColor = enabled ? NSColor(srgbRed:0.10,green:0.11,blue:0.13,alpha:1) : .white
        scene.background.contents = view.backgroundColor
        drawAxes()
        view.needsDisplay = true
    }
    func drawAxes() {
        axes.childNodes.forEach { $0.removeFromParentNode() }
        grid.geometry = nil
        guard let p = potential else { return }
        let z = -p.colorLimit/heightScale
        var vertices: [SCNVector3] = []
        for i in 0...8 {
            let x = -p.lx + 2*p.lx*Double(i)/8, y = -p.ly + 2*p.ly*Double(i)/8
            vertices += [SCNVector3(x,-p.ly,z),SCNVector3(x,p.ly,z),
                         SCNVector3(-p.lx,y,z),SCNVector3(p.lx,y,z)]
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                   elements: [SCNGeometryElement(indices: (0..<vertices.count).map(Int32.init), primitiveType: .line)])
        let mat = SCNMaterial(); mat.diffuse.contents = NSColor(white:darkMode ? 0.35 : 0.78,alpha:1); mat.lightingModel = .constant
        geometry.materials = [mat]
        grid.geometry = geometry
        let size = max(p.lx,p.ly)*0.065
        let names = p.fieldCoordinates ? ["phi1", "phi2"] : ["pixelX","pixelY"]
        let labels: [(String, SCNVector3)] = [
            (names[0],SCNVector3(0,-p.ly*1.22,z)),
            (names[1],SCNVector3(p.lx*1.24,0,z)),
            (String(format:"%.3g",-p.lx),SCNVector3(-p.lx,-p.ly*1.1,z)),
            (String(format:"%.3g",p.lx),SCNVector3(p.lx*0.88,-p.ly*1.18,z)),
            (String(format:"%.3g",-p.ly),SCNVector3(p.lx*1.18,-p.ly*0.88,z)),
            (String(format:"%.3g",p.ly),SCNVector3(p.lx*1.1,p.ly,z))]
        for (index,label) in labels.enumerated() {
            let (title,position) = label
            let geometry: SCNGeometry
            if index < 2 {
                geometry = MathAxes.shared.title(title)
            } else {
                let text = SCNText(string:title,extrusionDepth:0)
                text.font = MathAxes.shared.font(size:1)
                text.flatness = 0.001
                geometry = text
            }
            let material = SCNMaterial()
            material.diffuse.contents = NSColor(white:darkMode ? 0.90 : 0.22,alpha:1)
            material.lightingModel = .constant
            material.isDoubleSided = true
            geometry.materials = [material]
            let node = SCNNode(geometry:geometry)
            node.name = index < 2 ? title : "tick"
            let (lo,hi) = geometry.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((lo.x+hi.x)/2,(lo.y+hi.y)/2,0)
            node.position = position
            node.scale = SCNVector3(size,size,size)
            node.constraints = [SCNBillboardConstraint()]
            axes.addChildNode(node)
        }
    }
}
