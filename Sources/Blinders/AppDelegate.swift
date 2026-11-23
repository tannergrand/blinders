import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: BlindersModel!
    private var hotKey: HotKey?
    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = BlindersModel()
        model.shake.onShake = { [weak self] in self?.toggle() }
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
        NSApp.mainMenu = makeMainMenu()

        // Opened at login: run quietly in the Dock. Opened by hand: show the window.
        if !launchedAsLoginItem() && !CommandLine.arguments.contains("--background") {
            showWindow()
        }
    }

    // Clicking the Dock icon always brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // Closing the window keeps Blinders running for the hotkey and shake.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(title: model.isOn ? "Turn Blinders Off" : "Turn Blinders On",
                              action: #selector(toggle), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func toggle() { model.isOn.toggle() }

    @objc func showWindow() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.title = "Blinders"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("BlindersSettings")   // restores the last position if there is one
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let host = URL(string: s)?.host else { return }
        switch host {
        case "on": model.isOn = true
        case "off": model.isOn = false
        case "toggle": toggle()
        case "settings": showWindow()
        default: break
        }
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Blinders", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let toggleItem = appMenu.addItem(withTitle: "Turn Blinders On or Off", action: #selector(toggle), keyEquivalent: "b")
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        toggleItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Blinders", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Blinders", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(title: "Blinders", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let settings = windowMenu.addItem(withTitle: "Blinders Settings", action: #selector(showWindow), keyEquivalent: "0")
        settings.target = self
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }
}
