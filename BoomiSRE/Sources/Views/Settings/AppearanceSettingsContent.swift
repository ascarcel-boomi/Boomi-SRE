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
                    HStack(spacing: 8) {
                        colorSwatch(BoomiColors.boomiPurple, "Purple")
                        colorSwatch(BoomiColors.boomiGreen, "Green")
                        colorSwatch(BoomiColors.boomiMagenta, "Magenta")
                        colorSwatch(BoomiColors.boomiCoral, "Coral")
                        colorSwatch(BoomiColors.deepNavy, "Navy")
                    }
                    .padding(.top, 8)

                    Text("Boomi brand colors will be used for accents, status indicators, and highlights throughout the app.")
                        .font(.caption).foregroundStyle(.secondary)
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
