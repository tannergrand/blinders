import SwiftUI
import ServiceManagement

/// Every user-facing setting. The window, the Dock menu, the hotkey, the shake,
/// and blinders:// URLs all change state through here, so they never disagree.
final class BlindersModel: ObservableObject {
    let overlay = OverlayController()
    let shake = ShakeWatcher()
    private let defaults = UserDefaults.standard

    @Published var isOn: Bool {
        didSet { overlay.setOn(isOn); defaults.set(isOn, forKey: "isOn") }
    }
    @Published var shakeEnabled: Bool {
        didSet { shake.isEnabled = shakeEnabled; defaults.set(shakeEnabled, forKey: "shakeEnabled") }
    }
    @Published var sensitivity: ShakeSensitivity {
        didSet { shake.sensitivity = sensitivity; defaults.set(sensitivity.rawValue, forKey: "shakeSensitivityPreset") }
    }
    @Published var strength: Strength {
        didSet { overlay.strength = strength; defaults.set(strength.rawValue, forKey: "strength") }
    }
    @Published var grain: Grain {
        didSet { overlay.grain = grain; defaults.set(grain.rawValue, forKey: "grain") }
    }
    @Published var switchStyle: SwitchStyle {
        didSet { overlay.switchStyle = switchStyle; defaults.set(switchStyle.rawValue, forKey: "switchStyle") }
    }
    @Published var speed: MotionSpeed {
        didSet { overlay.speed = speed; defaults.set(speed.rawValue, forKey: "motionSpeed") }
    }
    @Published var openAtLogin: Bool {
        didSet {
            let service = SMAppService.mainApp
            guard openAtLogin != (service.status == .enabled) else { return }
            do {
                if openAtLogin { try service.register() } else { try service.unregister() }
            } catch {
                NSLog("Blinders: login item change failed: \(error.localizedDescription)")
                openAtLogin = service.status == .enabled
            }
        }
    }

    /// live: false builds the model for --render-window without touching the screen.
    init(live: Bool = true) {
        defaults.register(defaults: [
            "shakeEnabled": true, "shakeSensitivityPreset": ShakeSensitivity.medium.rawValue, "isOn": false,
            "strength": Strength.medium.rawValue, "grain": Grain.subtle.rawValue,
            "switchStyle": SwitchStyle.crossfade.rawValue, "motionSpeed": MotionSpeed.normal.rawValue,
        ])
        isOn = defaults.bool(forKey: "isOn") || CommandLine.arguments.contains("--on")
        shakeEnabled = defaults.bool(forKey: "shakeEnabled")
        sensitivity = ShakeSensitivity(rawValue: defaults.string(forKey: "shakeSensitivityPreset") ?? "") ?? .medium
        strength = Strength(rawValue: defaults.string(forKey: "strength") ?? "") ?? .medium
        grain = Grain(rawValue: defaults.string(forKey: "grain") ?? "") ?? .subtle
        switchStyle = SwitchStyle(rawValue: defaults.string(forKey: "switchStyle") ?? "") ?? .crossfade
        speed = MotionSpeed(rawValue: defaults.string(forKey: "motionSpeed") ?? "") ?? .normal
        openAtLogin = SMAppService.mainApp.status == .enabled

        // didSet doesn't run during init, so push the starting values through by hand.
        guard live else { return }
        overlay.strength = strength
        overlay.grain = grain
        overlay.switchStyle = switchStyle
        overlay.speed = speed
        shake.sensitivity = sensitivity
        shake.isEnabled = shakeEnabled
        overlay.setOn(isOn)
    }
}
