import AppKit
import SwiftUI

/// Headless checks: `Blinders.app/Contents/MacOS/Blinders --selftest`
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool) {
        print(ok ? "PASS" : "FAIL", name)
        if !ok { failures += 1 }
    }

    /// Simulates a cursor sweeping back and forth `legs` times at 120 Hz.
    private static func fires(amplitude: CGFloat, legSeconds: Double, legs: Int, start: Double = 0,
                              vertical: Bool = false, detector: inout ShakeDetector) -> Int {
        let hz = 120.0
        var count = 0
        var t = start
        for leg in 0..<legs {
            let steps = max(1, Int(legSeconds * hz))
            for i in 1...steps {
                let p = CGFloat(i) / CGFloat(steps)
                let v = leg % 2 == 0 ? 500 + amplitude * p : 500 + amplitude * (1 - p)
                // A little drift on the other axis, like a real hand.
                let drift = CGFloat(i % 7) - 3
                t += 1 / hz
                let hit = vertical ? detector.feed(x: 400 + drift, y: v, t: t)
                                   : detector.feed(x: v, y: 400 + drift, t: t)
                if hit { count += 1 }
            }
        }
        return count
    }

    static func run() -> Int32 {
        var d = ShakeDetector()
        check("fast wide shake fires once", fires(amplitude: 150, legSeconds: 0.1, legs: 6, detector: &d) == 1)

        d = ShakeDetector()
        check("slow back-and-forth does not fire", fires(amplitude: 300, legSeconds: 0.5, legs: 8, detector: &d) == 0)

        d = ShakeDetector()
        check("small fast jitter does not fire", fires(amplitude: 30, legSeconds: 0.05, legs: 12, detector: &d) == 0)

        d = ShakeDetector()
        check("single sweep does not fire", fires(amplitude: 800, legSeconds: 0.3, legs: 1, detector: &d) == 0)

        d = ShakeDetector()
        check("long shake inside cooldown fires once", fires(amplitude: 150, legSeconds: 0.1, legs: 9, detector: &d) == 1)

        d = ShakeDetector()
        _ = fires(amplitude: 150, legSeconds: 0.1, legs: 6, detector: &d)
        check("second shake after cooldown fires again",
              fires(amplitude: 150, legSeconds: 0.1, legs: 6, start: 3, detector: &d) == 1)

        d = ShakeDetector(sensitivity: .high)
        check("High fires on a small shake", fires(amplitude: 30, legSeconds: 0.06, legs: 6, detector: &d) == 1)
        d = ShakeDetector(sensitivity: .medium)
        check("Medium ignores that small shake", fires(amplitude: 30, legSeconds: 0.06, legs: 6, detector: &d) == 0)
        d = ShakeDetector(sensitivity: .medium)
        check("Medium fires on a mid-size shake", fires(amplitude: 60, legSeconds: 0.08, legs: 6, detector: &d) == 1)
        d = ShakeDetector(sensitivity: .low)
        check("Low ignores that mid-size shake", fires(amplitude: 60, legSeconds: 0.08, legs: 6, detector: &d) == 0)
        d = ShakeDetector(sensitivity: .low)
        check("Low fires on a big shake", fires(amplitude: 150, legSeconds: 0.1, legs: 6, detector: &d) == 1)
        d = ShakeDetector(sensitivity: .high)
        check("wide sweeps slower than 0.3 s per leg never fire",
              fires(amplitude: 300, legSeconds: 0.35, legs: 10, detector: &d) == 0)

        d = ShakeDetector()
        check("vertical shake fires once", fires(amplitude: 150, legSeconds: 0.1, legs: 6, vertical: true, detector: &d) == 1)
        d = ShakeDetector()
        check("slow vertical back-and-forth does not fire",
              fires(amplitude: 300, legSeconds: 0.5, legs: 8, vertical: true, detector: &d) == 0)
        d = ShakeDetector()
        _ = fires(amplitude: 150, legSeconds: 0.1, legs: 6, detector: &d)
        check("vertical shake inside horizontal's cooldown does not double-fire",
              fires(amplitude: 150, legSeconds: 0.1, legs: 6, start: 0.65, vertical: true, detector: &d) == 0)

        check("SkyLight blur symbols resolve", Blur.isAvailable)

        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        print("INFO frontmost pid \(pid) top window \(FrontWindow.topWindow(of: pid).map(String.init) ?? "none")")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        return failures == 0 ? 0 : 1
    }

    /// Dev aid: renders tint + grain over a sample backdrop, one panel per Grain
    /// setting, at 2x. The SkyLight blur is the compositor's, so it can't appear here.
    static func renderSample(to path: String) -> Int32 {
        let panel = NSSize(width: 300, height: 200)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: panel.width * 3, height: panel.height))
        root.wantsLayer = true
        for (i, g) in Grain.allCases.enumerated() {
            let frame = NSRect(x: CGFloat(i) * panel.width, y: 0, width: panel.width, height: panel.height)
            let backdrop = NSView(frame: frame)
            backdrop.wantsLayer = true
            let gradient = CAGradientLayer()
            gradient.frame = backdrop.bounds
            gradient.colors = [NSColor.systemIndigo.cgColor, NSColor.systemPink.cgColor, NSColor.systemOrange.cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            backdrop.layer?.addSublayer(gradient)
            let tint = NSView(frame: backdrop.bounds)
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(Strength.medium.tint).cgColor
            backdrop.addSubview(tint)
            let grain = GrainView(frame: backdrop.bounds)
            grain.grain = g
            backdrop.addSubview(grain)
            let label = NSTextField(labelWithString: "Grain: \(g.title)")
            label.textColor = .white
            label.font = .boldSystemFont(ofSize: 15)
            label.frame = NSRect(x: 14, y: 12, width: 200, height: 20)
            backdrop.addSubview(label)
            root.addSubview(backdrop)
        }
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width * 2), pixelsHigh: Int(root.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = root.bounds.size
        root.cacheDisplay(in: root.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: path))) != nil else { return 1 }
        print("wrote \(path)")
        return 0
    }

    /// Dev aid: renders the settings window's content to a PNG, light or dark.
    static func renderWindow(to path: String, dark: Bool) -> Int32 {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: SettingsView(model: BlindersModel(live: false)))
        host.frame.size = host.fittingSize
        let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: path))) != nil else { return 1 }
        print("wrote \(path) \(Int(host.bounds.width))x\(Int(host.bounds.height))")
        return 0
    }
}
