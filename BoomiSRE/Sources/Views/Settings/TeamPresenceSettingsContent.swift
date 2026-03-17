import SwiftUI

struct TeamPresenceSettingsContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var presenceVM: TeamPresenceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Team Presence").font(.title2.bold())
            Text("See other Boomi SRE app users on your local network. No central server needed — uses Bonjour/mDNS for zero-config discovery.")
                .font(.callout).foregroundStyle(.secondary)

            SettingsSection("Enable") {
                Toggle("Broadcast my presence on the local network", isOn: Binding(
                    get: { appState.peerPresenceEnabled },
                    set: { enabled in
                        appState.peerPresenceEnabled = enabled
                        appState.saveConfig()
                        Task {
                            if enabled {
                                await presenceVM.start(appState: appState)
                            } else {
                                await presenceVM.stop()
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)

                if appState.peerPresenceEnabled {
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Broadcasting — \(presenceVM.onlineCount) peer\(presenceVM.onlineCount == 1 ? "" : "s") online")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }

            if appState.peerPresenceEnabled {
                SettingsSection("What is shared") {
                    VStack(alignment: .leading, spacing: 6) {
                        sharedField("Display Name", appState.userProfile.displayName)
                        sharedField("Email", appState.userProfile.email)
                        sharedField("Role", appState.userProfile.role.displayName)
                        sharedField("Team", appState.userProfile.team)
                        sharedField("Active Product", "Changes as you switch products")
                        sharedField("Current Screen", "Updates as you navigate")
                        sharedField("App Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                    }
                }

                SettingsSection("Privacy") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("All communication stays on your local network (LAN)", systemImage: "lock.shield")
                            .font(.caption)
                        Label("No data is sent to any server or the internet", systemImage: "icloud.slash")
                            .font(.caption)
                        Label("Discovery uses standard Bonjour/mDNS protocol", systemImage: "bonjour")
                            .font(.caption)
                        Label("Other users must also have the app running with presence enabled", systemImage: "person.2")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                // Online peers
                if !presenceVM.peers.isEmpty {
                    SettingsSection("Currently Online (\(presenceVM.onlineCount))") {
                        ForEach(presenceVM.peers.sorted { $0.displayName < $1.displayName }) { peer in
                            HStack(spacing: 8) {
                                Circle().fill(peer.isStale ? Color.secondary : Color.green).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(peer.displayName).font(.callout.bold())
                                    Text("\(peer.role) · \(peer.team)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(peer.product).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private func sharedField(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.bold()).frame(width: 100, alignment: .leading)
            Text(value.isEmpty ? "(not set)" : value).font(.caption).foregroundStyle(.secondary)
        }
    }
}
