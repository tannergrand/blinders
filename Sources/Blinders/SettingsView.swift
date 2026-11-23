import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: BlindersModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blinders").font(.title3.weight(.semibold))
                        Text(model.isOn ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Blinders", isOn: $model.isOn)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.large)
                }
                .padding(.vertical, 4)
            }

            Section("Turn On and Off") {
                LabeledContent("Keyboard shortcut") {
                    Text("⌃ ⌥ B")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
                Toggle("Shake the cursor", isOn: $model.shakeEnabled)
                Picker("Shake sensitivity", selection: $model.sensitivity) {
                    ForEach(ShakeSensitivity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!model.shakeEnabled)
            }

            Section("Look") {
                Picker("Blur", selection: $model.strength) {
                    ForEach(Strength.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Grain", selection: $model.grain) {
                    ForEach(Grain.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Fade speed", selection: $model.speed) {
                    ForEach(MotionSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("Open at login", isOn: $model.openAtLogin)
            }
        }
        .pickerStyle(.segmented)
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
