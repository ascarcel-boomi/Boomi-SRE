import SwiftUI

/// Popover showing online team members discovered via Bonjour.
struct TeamPresencePopover: View {
    @EnvironmentObject var presenceVM: TeamPresenceViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Team Online", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                Text("\(presenceVM.onlineCount)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                    .foregroundStyle(.green)
            }
            .padding(12)

            Divider()

            if presenceVM.peers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.title2).foregroundStyle(.secondary)
                    Text("No team members found on your network")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Others need to enable Team Presence in their app too.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(presenceVM.peers.sorted { $0.displayName < $1.displayName }.enumerated()),
                                id: \.element.id) { idx, peer in
                            peerRow(peer, isEven: idx.isMultiple(of: 2))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption2).foregroundStyle(.green)
                Text("Broadcasting as \(appState.userProfile.displayName)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Settings") {
                    appState.showSettings = true
                    appState.selectedSettingsTab = "presence"
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(10)
        }
        .frame(width: 300)
    }

    private func peerRow(_ peer: Peer, isEven: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(peer.isStale ? Color.secondary : Color.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.callout.bold())
                HStack(spacing: 4) {
                    if !peer.role.isEmpty {
                        Text(peer.role).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !peer.team.isEmpty {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(peer.team).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if !peer.screen.isEmpty {
                    Text(peer.screen)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if peer.product != "All" {
                    HStack(spacing: 4) {
                        Image(systemName: "target").font(.caption2)
                        Text(peer.product).font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isEven ? Color(nsColor: .controlBackgroundColor).opacity(0.4) : Color.clear)
    }
}
