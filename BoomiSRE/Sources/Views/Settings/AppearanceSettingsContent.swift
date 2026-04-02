import SwiftUI

struct AppearanceSettingsContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance").font(.title2.bold())

            SettingsSection("Color Theme") {
                Picker("Color Theme", selection: $appState.appTheme) {
                    Text("System (macOS accent color)").tag("system")
                    Text("Boomi Brand Colors").tag("boomi")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.appTheme) { appState.saveConfig() }

                if appState.appTheme == "boomi" {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            colorSwatch(BoomiColors.boomiPurple, "Accent")
                            colorSwatch(BoomiColors.boomiGreen, "Success")
                            colorSwatch(BoomiColors.boomiCoral, "Warning")
                            colorSwatch(BoomiColors.boomiMagenta, "Danger")
                            colorSwatch(BoomiColors.deepNavy, "Navy")
                        }
                        .padding(.top, 4)

                        Text("Boomi brand colors are applied to buttons, links, toggles, selection highlights, status indicators, and the health bar throughout the app.")
                            .font(.caption).foregroundStyle(.secondary)

                        // Live preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview").font(.caption.bold()).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Button("Primary Button") {}
                                    .buttonStyle(.borderedProminent)
                                Button("Secondary") {}
                                    .buttonStyle(.bordered)
                                Toggle("Toggle", isOn: .constant(true))
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                ProgressView(value: 0.7)
                                    .frame(width: 80)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
            }

        }
    }

    private func colorSwatch(_ color: Color, _ name: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 40, height: 40)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
