import AppKit

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}
if let i = CommandLine.arguments.firstIndex(of: "--render-window"), i + 1 < CommandLine.arguments.count {
    exit(SelfTest.renderWindow(to: CommandLine.arguments[i + 1], dark: CommandLine.arguments.contains("--dark")))
}
if CommandLine.arguments.contains("--shake-bench") {
    exit(ShakeBench.run())
}
if let i = CommandLine.arguments.firstIndex(of: "--render-sample"), i + 1 < CommandLine.arguments.count {
    exit(SelfTest.renderSample(to: CommandLine.arguments[i + 1]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
