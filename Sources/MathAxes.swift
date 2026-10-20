import AppKit
import SceneKit
import CoreText

/// Computer Modern math outlines, generated once; no runtime TeX dependency.
final class MathAxes {
    static let shared = MathAxes()
    private let paths: [String: [[Double]]]
    let fontName: String

    private init() {
        let bundle = Bundle.main
        guard let fontURL = bundle.url(forResource:"cmr10",withExtension:"ttf"),
              let url = bundle.url(forResource:"MathAxes",withExtension:"json"),
              let data = try? Data(contentsOf:url),
              let paths = try? JSONDecoder().decode([String:[[Double]]].self,from:data) else {
            fatalError("Missing bundled math font assets.")
        }
        self.paths = paths
        CTFontManagerRegisterFontsForURL(fontURL as CFURL,.process,nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor]
        fontName = descriptors.flatMap { $0.first }.map { CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor($0,12,nil)) as String } ?? "CMR10"
    }
    func font(size: CGFloat) -> NSFont {
        guard let font = NSFont(name:fontName,size:size) else { fatalError("Could not load bundled Computer Modern font.") }
        return font
    }
    func title(_ name: String) -> SCNGeometry {
        let path = NSBezierPath()
        for command in paths[name]! {
            switch Int(command[0]) {
            case 1: path.move(to:NSPoint(x:command[1],y:command[2]))
            case 2: path.line(to:NSPoint(x:command[1],y:command[2]))
            case 3:
                let start = path.currentPoint
                let control = NSPoint(x:command[1],y:command[2])
                let end = NSPoint(x:command[3],y:command[4])
                path.curve(to:end,
                           controlPoint1:NSPoint(x:start.x+2*(control.x-start.x)/3,y:start.y+2*(control.y-start.y)/3),
                           controlPoint2:NSPoint(x:end.x+2*(control.x-end.x)/3,y:end.y+2*(control.y-end.y)/3))
            case 4:
                path.curve(to:NSPoint(x:command[5],y:command[6]),
                           controlPoint1:NSPoint(x:command[1],y:command[2]),
                           controlPoint2:NSPoint(x:command[3],y:command[4]))
            case 79: path.close()
            default: fatalError("Invalid math outline command.")
            }
        }
        path.flatness = 0.001
        let geometry = SCNShape(path:path,extrusionDepth:0)
        geometry.chamferRadius = 0
        return geometry
    }
}

/// Propagate macOS appearance changes to SceneKit's explicitly colored canvas.
final class AppearanceView: NSView {
    var appearanceChanged: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}
