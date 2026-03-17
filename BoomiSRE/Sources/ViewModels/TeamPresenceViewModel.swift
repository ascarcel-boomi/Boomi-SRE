import Foundation
import SwiftUI

@MainActor
final class TeamPresenceViewModel: ObservableObject {

    @Published var peers: [Peer] = []
    @Published var isRunning = false

    var onlineCount: Int { peers.filter { !$0.isStale }.count }

    private let service = PeerPresenceService()

    // MARK: - Start / Stop

    func start(appState: AppState) async {
        guard appState.peerPresenceEnabled, !isRunning else { return }
        isRunning = true

        let profile = buildProfile(appState: appState)

        // Wire callbacks
        await service.setCallbacks(
            onDiscovered: { [weak self] peer in
                Task { @MainActor in self?.addOrUpdate(peer) }
            },
            onLost: { [weak self] endpointId in
                Task { @MainActor in self?.peers.removeAll { $0.id == endpointId } }
            },
            onUpdated: { [weak self] peer in
                Task { @MainActor in self?.addOrUpdate(peer) }
            }
        )

        await service.startAdvertising(profile: profile)
        await service.startBrowsing()
    }

    func stop() async {
        await service.stopAdvertising()
        await service.stopBrowsing()
        peers = []
        isRunning = false
    }

    func updatePresence(appState: AppState) async {
        guard isRunning else { return }
        let profile = buildProfile(appState: appState)
        await service.updateTXTRecord(profile: profile)
    }

    // MARK: - Helpers

    private func addOrUpdate(_ peer: Peer) {
        if let idx = peers.firstIndex(where: { $0.id == peer.id }) {
            peers[idx] = peer
        } else {
            peers.append(peer)
        }
    }

    private func buildProfile(appState: AppState) -> Peer {
        let productName: String
        if appState.activeProductIds.isEmpty {
            productName = "All"
        } else if appState.activeProductIds.count == 1,
                  let p = appState.products.first(where: { $0.id == appState.activeProductIds.first }) {
            productName = p.shortName
        } else {
            productName = "\(appState.activeProductIds.count) products"
        }

        return Peer(
            id: appState.userProfile.email,
            displayName: appState.userProfile.displayName,
            email: appState.userProfile.email,
            role: appState.userProfile.role.displayName,
            team: appState.userProfile.team,
            product: productName,
            screen: appState.currentScreenContext,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            lastSeen: Date()
        )
    }
}

// MARK: - Service callback setter

extension PeerPresenceService {
    func setCallbacks(
        onDiscovered: @escaping @Sendable (Peer) -> Void,
        onLost: @escaping @Sendable (String) -> Void,
        onUpdated: @escaping @Sendable (Peer) -> Void
    ) {
        self.onPeerDiscovered = onDiscovered
        self.onPeerLost = onLost
        self.onPeerUpdated = onUpdated
    }
}
