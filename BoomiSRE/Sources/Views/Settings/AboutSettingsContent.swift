import SwiftUI

struct AboutSettingsContent: View {
    @EnvironmentObject var updateVM: UpdateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // App identity
            HStack(spacing: 16) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Boomi SRE")
                        .font(.title2.bold())
                    Text("Version \(updateVM.currentVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("macOS SRE Command Center")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 4)

            Divider()

            // Update section
            VStack(alignment: .leading, spacing: 12) {
                Text("Updates").font(.headline)

                if let update = updateVM.availableUpdate {
                    // Update available
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                            Text("Version \(update.version) is available")
                                .font(.callout.bold())
                        }
                        if !update.body.isEmpty {
                            Text(update.body.prefix(300) + (update.body.count > 300 ? "…" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                        if let err = updateVM.error {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.red)
                        }
                        HStack(spacing: 12) {
                            if updateVM.isDownloading {
                                ProgressView(value: updateVM.downloadProgress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 180)
                                Text("\(Int(updateVM.downloadProgress * 100))%")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if updateVM.isApplying {
                                ProgressView().scaleEffect(0.8)
                                Text("Applying update…").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("Download & Install") { Task { await updateVM.downloadAndApply() } }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.2)))

                } else if updateVM.isChecking {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Checking for updates…").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Boomi SRE is up to date.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let err = updateVM.error {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    }
                }

                HStack(spacing: 12) {
                    Button("Check for Updates") { Task { await updateVM.checkForUpdate() } }
                        .buttonStyle(.bordered)
                        .disabled(updateVM.isChecking)
                    if let checked = updateVM.lastChecked {
                        Text("Last checked: \(Formatters.shortDateTime.string(from: checked))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            // Links
            VStack(alignment: .leading, spacing: 8) {
                Text("Resources").font(.headline)
                HStack(spacing: 16) {
                    Link("GitHub Repository", destination: URL(string: "https://github.com/ascarcel-boomi/Boomi-SRE")!)
                    Link("Release Notes", destination: URL(string: "https://github.com/ascarcel-boomi/Boomi-SRE/releases")!)
                }
                .font(.callout)
            }
        }
    }
}
