import SwiftUI

struct AboutSettingsContent: View {
    @EnvironmentObject var updateVM: UpdateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // App identity
            HStack(spacing: 20) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Boomi SRE")
                        .font(.title.bold())
                    Text("Version \(updateVM.currentVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("macOS SRE Command Center")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\u{201C}You\u{2019}re only limited by your imagination!\u{201D}")
                        .font(.system(.callout, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, 4)

            Divider()

            // Update section
            VStack(alignment: .leading, spacing: 12) {
                Text("Updates").font(.headline)

                if let update = updateVM.availableUpdate {
                    // Update available card
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

            // Resources
            VStack(alignment: .leading, spacing: 8) {
                Text("Resources").font(.headline)
                HStack(spacing: 16) {
                    Link("GitHub Repository",
                         destination: URL(string: "https://github.com/ascarcel-boomi/Boomi-SRE")!)
                    Link("Release Notes",
                         destination: URL(string: "https://github.com/ascarcel-boomi/Boomi-SRE/releases")!)
                }
                .font(.callout)
            }

            Divider()

            // Authors
            VStack(alignment: .leading, spacing: 10) {
                Text("Authors").font(.headline)

                authorRow(name: "Adam Scarcella", role: "Lead Idea Generator")
                authorRow(name: "Claude Opus",    role: "Ph.D PM with a 250 AIQ")
                authorRow(name: "Claude Sonnet",  role: "Master Coder")
            }

            // Copyright
            Text("© \(Calendar.current.component(.year, from: Date())) Boomi, Ltd. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
    }

    private func authorRow(name: String, role: String) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.callout.bold())
            Text("·").foregroundStyle(.tertiary)
            Text(role).font(.caption).foregroundStyle(.secondary)
        }
    }
}
