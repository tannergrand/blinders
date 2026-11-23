import AppKit

enum Strength: String, CaseIterable {
    case light, medium, heavy

    var title: String { rawValue.capitalized }
    var blurRadius: Int {
        switch self { case .light: 12; case .medium: 30; case .heavy: 60 }
    }
    var tint: CGFloat {
        switch self { case .light: 0.08; case .medium: 0.16; case .heavy: 0.26 }
    }
}

enum Grain: String, CaseIterable {
    case off, subtle, strong

    var title: String { rawValue.capitalized }
    var opacity: CGFloat {
        switch self { case .off: 0; case .subtle: 0.10; case .strong: 0.20 }
    }
}

/// A tile of random grey pixels. 256 px drawn at 128 pt, so each speck is one
/// device pixel on a Retina screen, which is what reads as film grain.
enum GrainTexture {
    static let image: NSImage = make(pixels: 256)

    static func make(pixels: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 2, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceWhite, bytesPerRow: pixels * 2, bitsPerPixel: 16
        )!
        let data = rep.bitmapData!
        for i in 0..<(pixels * pixels) {
            data[i * 2] = UInt8.random(in: 0...255)
            data[i * 2 + 1] = 255
        }
        let image = NSImage(size: NSSize(width: pixels / 2, height: pixels / 2))
        image.addRepresentation(rep)
        return image
    }
}

/// Fills itself with the grain tile. Drawn once per resize, then cached by its layer.
final class GrainView: NSView {
    // Opacity is applied while drawing, not through alphaValue, so the overlay
    // and the --render-sample snapshot composite it the same way.
    var grain: Grain = .subtle {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard grain != .off, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAlpha(grain.opacity)
        NSColor(patternImage: GrainTexture.image).setFill()
        // dirtyRect can extend past this view in snapshot renders; never paint outside bounds.
        bounds.intersection(dirtyRect).fill(using: .sourceOver)
        ctx.restoreGState()
    }
}

/// Window background blur through SkyLight (private). Looked up at runtime so a
/// missing symbol degrades to the public NSVisualEffectView fallback, not a crash.
enum Blur {
    typealias ConnFn = @convention(c) () -> Int32
    typealias RadiusFn = @convention(c) (Int32, Int32, Int32) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let connection: ConnFn? = symbol("SLSMainConnectionID") ?? symbol("CGSMainConnectionID")
    private static let setRadius: RadiusFn? = symbol("SLSSetWindowBackgroundBlurRadius") ?? symbol("CGSSetWindowBackgroundBlurRadius")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static var isAvailable: Bool { connection != nil && setRadius != nil }

    @discardableResult
    static func apply(to window: NSWindow, radius: Int) -> Bool {
        guard let connection, let setRadius, window.windowNumber > 0 else { return false }
        return setRadius(connection(), Int32(window.windowNumber), Int32(radius)) == 0
    }
}

enum FrontWindow {
    /// The topmost normal-layer, visible window owned by `pid`, in global z-order.
    static func topWindow(of pid: pid_t, excluding skip: Set<CGWindowID> = []) -> CGWindowID? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let n = info[kCGWindowNumber as String] as? Int,
                  !skip.contains(CGWindowID(n)) else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.01 { continue }
            if let b = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
               rect.width < 40 || rect.height < 40 { continue }
            if let n = info[kCGWindowNumber as String] as? Int { return CGWindowID(n) }
        }
        return nil
    }

    /// A window's frame in AppKit screen coordinates (origin bottom-left of the main screen).
    static func cocoaFrame(of wid: CGWindowID) -> NSRect? {
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, wid) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let b = info[kCGWindowBounds as String] as? [String: Any],
              let r = CGRect(dictionaryRepresentation: b as CFDictionary),
              let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        return NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }
}

enum SwitchStyle: String, CaseIterable {
    case crossfade, instant
    var title: String { rawValue.capitalized }
}

enum MotionSpeed: String, CaseIterable {
    case fast, normal, slow
    var title: String { rawValue.capitalized }
    /// A full on/off fade.
    var fade: Double {
        switch self { case .fast: 0.2; case .normal: 0.35; case .slow: 0.6 }
    }
    /// Moving the focus from one window to another.
    var switchDuration: Double {
        switch self { case .fast: 0.15; case .normal: 0.28; case .slow: 0.45 }
    }
}

/// A set of click-through blurred windows: one per screen, or a single patch.
final class OverlayLayer {
    private(set) var windows: [NSWindow] = []
    private(set) var level: CGFloat = 0     // 0 hidden … 1 full blur
    var strength: Strength = .medium
    var grain: Grain = .subtle
    var ids: Set<CGWindowID> { Set(windows.map { CGWindowID($0.windowNumber) }) }

    func rebuild(frames: [NSRect]) {
        windows.forEach { $0.orderOut(nil) }
        windows = frames.map(Self.makeWindow)
        level = 0
        applyStyle()
    }

    private static func makeWindow(_ frame: NSRect) -> NSWindow {
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.title = "Blinders Overlay"
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.isExcludedFromWindowsMenu = true
        w.level = .normal
        // .transient: Mission Control and Exposé hide the overlay, so every window
        // shows clearly there. (.stationary would pin it on screen like the desktop.)
        w.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        w.alphaValue = 0
        w.setFrame(frame, display: false)
        return w
    }

    func applyStyle() {
        for w in windows {
            w.backgroundColor = NSColor.black.withAlphaComponent(strength.tint)
            if Blur.apply(to: w, radius: radius) {
                if !(w.contentView is GrainView) { w.contentView = GrainView() }
            } else if !(w.contentView is NSVisualEffectView) {
                let v = NSVisualEffectView()
                v.blendingMode = .behindWindow
                v.material = .fullScreenUI
                v.state = .active
                w.contentView = v
                v.addSubview(GrainView(frame: v.bounds))
            }
            let g = (w.contentView as? GrainView) ?? w.contentView?.subviews.compactMap { $0 as? GrainView }.first
            g?.grain = grain
        }
    }

    private var radius: Int { Int((CGFloat(strength.blurRadius) * level).rounded()) }

    /// Opacity and blur radius move together, so the blur grows in rather than
    /// popping in at full strength behind a fading tint.
    func setLevel(_ l: CGFloat) {
        level = l
        for w in windows {
            w.alphaValue = l
            Blur.apply(to: w, radius: radius)
        }
    }

    func setFrame(_ frame: NSRect) { windows.forEach { $0.setFrame(frame, display: false) } }
    func order(below wid: CGWindowID) { windows.forEach { $0.order(.below, relativeTo: Int(wid)) } }
    func order(above wid: CGWindowID) { windows.forEach { $0.order(.above, relativeTo: Int(wid)) } }
    func orderOut() { windows.forEach { $0.orderOut(nil) } }
}

/// Keeps the blur directly behind the frontmost window so only that window is sharp.
///
/// Switching focus: macOS raises the new window above the blur the instant you
/// click, so it is already sharp. Blinders never re-blurs it. Instead the old
/// window fades into the blur under a patch sized to its frame, then the
/// full-screen layer moves up and the patch goes away:
///   new window   (sharp from the first frame)
///   patch        ← blur over the old window's frame only, fading in (ordered above the old window)
///   old window
///   primary      ← full-screen layer, unchanged until the hand-off
final class OverlayController {
    private(set) var isOn = false
    var strength: Strength = .medium {
        didSet { allLayers.forEach { $0.strength = strength; $0.applyStyle() } }
    }
    var grain: Grain = .subtle {
        didSet { allLayers.forEach { $0.grain = grain; $0.applyStyle() } }
    }
    var switchStyle: SwitchStyle = .crossfade
    var speed: MotionSpeed = .normal

    private let primary = OverlayLayer()
    private let patch = OverlayLayer()
    private var allLayers: [OverlayLayer] { [primary, patch] }
    private var overlayIDs: Set<CGWindowID> { allLayers.reduce(into: []) { $0.formUnion($1.ids) } }

    private struct Animation {
        let isFade: Bool
        let stop: () -> Void      // freeze where it is
        let finish: () -> Void    // jump to the end
    }
    private var anim: Animation?

    private var timer: Timer?
    private var lastFront: CGWindowID = 0
    private var shown = false
    private var ticks = 0
    private var lastExternalPID: pid_t?
    private let myPID = ProcessInfo.processInfo.processIdentifier

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
        // Activating Blinders (Dock click) brings all its windows forward, overlays
        // included. Put them back behind the focus window straight away.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.tick(force: true) }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.tick(force: true)
                // The window list can trail the notification by a frame or two.
                for delay in [0.04, 0.12] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.tick(force: false) }
                }
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != myPID {
            lastExternalPID = front.processIdentifier
        }
    }

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        if on {
            if primary.windows.isEmpty { rebuild() }
            lastFront = 0
            tick(force: true)
            // 10 Hz catches window switches inside one app, which post no notification.
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.tick(force: false)
            }
        } else {
            timer?.invalidate()
            timer = nil
            lastFront = 0
            fade(to: 0)
        }
    }

    private func rebuild() {
        finishAnimation()
        let frames = NSScreen.screens.map(\.frame)
        primary.rebuild(frames: frames)
        patch.rebuild(frames: [NSScreen.screens.first?.frame ?? .zero])
        shown = false
        if isOn {
            lastFront = 0
            tick(force: true)
        }
    }

    private func tick(force: Bool) {
        guard isOn else { return }
        ticks += 1
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        var target: CGWindowID?
        if front.processIdentifier == myPID {
            // Blinders' own window in front stays sharp like any other app's.
            target = FrontWindow.topWindow(of: myPID, excluding: overlayIDs)
        } else {
            lastExternalPID = front.processIdentifier
        }
        // Blinders active with no window of its own (Dock click, a blinders:// URL):
        // keep focusing whatever app was in front before.
        if target == nil, let pid = lastExternalPID {
            target = FrontWindow.topWindow(of: pid)
        }

        if ticks % 10 == 0 || force { debug("tick front=\(front.localizedName ?? "?") target=\(target.map(String.init) ?? "nil") last=\(lastFront) shown=\(shown)") }
        guard let wid = target else {
            // Desktop or a windowless app has focus: nothing to single out.
            lastFront = 0
            fade(to: 0)
            return
        }
        if !shown {
            lastFront = wid
            primary.order(below: wid)
            primary.applyStyle()
            fade(to: 1)
            return
        }
        if wid != lastFront {
            debug("switch \(lastFront) -> \(wid) front=\(front.localizedName ?? "?") anim=\(anim.map { $0.isFade ? "fade" : "switch" } ?? "none")")
            let old = lastFront
            lastFront = wid
            if anim?.isFade == true {
                primary.order(below: wid)   // still fading in: just move it
            } else {
                switchFocus(from: old, to: wid)
            }
            return
        }
        // Re-assert the order about once a second in case a window slipped in between.
        if anim == nil && (force || ticks % 10 == 0) {
            primary.order(below: wid)
        }
    }

    private func switchFocus(from old: CGWindowID, to wid: CGWindowID) {
        finishAnimation()
        guard switchStyle == .crossfade,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              primary.level > 0.99,
              old != 0,
              let frame = FrontWindow.cocoaFrame(of: old) else {
            debug("instant: style=\(switchStyle) level=\(primary.level) old=\(old) frame=\(String(describing: FrontWindow.cocoaFrame(of: old)))")
            primary.order(below: wid)
            return
        }
        let primary = self.primary, patch = self.patch
        patch.setFrame(frame)
        patch.setLevel(0)
        // Above the old window, not below the new one: the activation notice can land
        // before macOS has raised the new window, and "below it" would then bury the
        // patch under the full-screen layer.
        patch.order(above: old)
        debug("patch over \(old) at \(frame)")
        animate(speed.switchDuration, isFade: false, curve: .easeOut, step: { e in
            patch.setLevel(e)
        }, done: { [weak self] in
            self?.debug("hand-off below \(wid)")
            primary.order(below: wid)    // the patch was already blurring that region
            patch.orderOut()
        })
    }

    /// On/off fade of the main layer. Reversing mid-fade starts from wherever it is.
    private func fade(to target: CGFloat) {
        let wantShown = target > 0
        if wantShown == shown && anim == nil && primary.level == target { return }
        shown = wantShown
        if anim?.isFade == true { anim?.stop(); anim = nil } else { finishAnimation() }

        let layer = primary, from = layer.level
        animate(speed.fade * Double(abs(target - from)), isFade: true, curve: .easeInOut, step: { e in
            layer.setLevel(from + (target - from) * e)
        }, done: { [weak self] in
            guard let self, !self.shown else { return }
            self.allLayers.forEach { $0.orderOut() }
        })
    }

    private let debugOn = UserDefaults.standard.bool(forKey: "debugLog")
    private let debugStart = CACurrentMediaTime()
    private func debug(_ m: @autoclosure () -> String) {
        guard debugOn else { return }
        let line = String(format: "%8.3f ", CACurrentMediaTime() - debugStart) + m() + "\n"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Blinders.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func finishAnimation() {
        let a = anim
        anim = nil
        a?.finish()
    }

    enum Curve {
        case easeInOut   // on/off: gentle at both ends
        case easeOut     // switching: moves straight away, settles softly
        func callAsFunction(_ p: Double) -> Double {
            switch self {
            case .easeInOut: p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            case .easeOut: 1 - pow(1 - p, 3)
            }
        }
    }

    /// Runs on the main run loop's common mode, so it keeps going while a menu is open.
    private func animate(_ duration: Double, isFade: Bool, curve: Curve,
                         step: @escaping (CGFloat) -> Void, done: @escaping () -> Void) {
        guard duration > 0.01 else { step(1); done(); return }
        let start = CACurrentMediaTime()
        var over = false
        let complete = { if !over { over = true; step(1); done() } }
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            let p = min(1, (CACurrentMediaTime() - start) / duration)
            if p >= 1 {
                t.invalidate()
                self?.anim = nil
                complete()
            } else {
                step(CGFloat(curve(p)))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        anim = Animation(isFade: isFade,
                         stop: { t.invalidate(); over = true },
                         finish: { t.invalidate(); complete() })
    }
}
