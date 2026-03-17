import Foundation
import Network

/// Zero-config LAN peer discovery using Bonjour/mDNS.
/// Advertises this user's presence and discovers other Boomi SRE users on the network.
actor PeerPresenceService {

    private let serviceType = "_boomi-sre._tcp"
    private let queue = DispatchQueue(label: "com.boomi.sre.presence")
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var myEmail: String = ""

    // Callbacks — dispatched to MainActor by the view model
    var onPeerDiscovered: (@Sendable (Peer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onPeerUpdated: (@Sendable (Peer) -> Void)?

    // MARK: - Advertise

    func startAdvertising(profile: Peer) {
        myEmail = profile.email
        stopAdvertisingSync()

        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params)
            let txtRecord = Peer.makeTXTRecord(from: profile.toTXTRecord())
            listener?.service = NWListener.Service(
                name: profile.email.replacingOccurrences(of: "@", with: "_at_"),
                type: serviceType,
                txtRecord: txtRecord
            )
            listener?.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    print("[Presence] Listener failed: \(error)")
                default: break
                }
            }
            // We don't accept connections — presence only
            listener?.newConnectionHandler = { connection in
                connection.cancel()
            }
            listener?.start(queue: queue)
        } catch {
            print("[Presence] Failed to start listener: \(error)")
        }
    }

    func updateTXTRecord(profile: Peer) {
        myEmail = profile.email
        guard let listener else { return }
        let txtRecord = Peer.makeTXTRecord(from: profile.toTXTRecord())
        listener.service = NWListener.Service(
            name: profile.email.replacingOccurrences(of: "@", with: "_at_"),
            type: serviceType,
            txtRecord: txtRecord
        )
    }

    func stopAdvertising() {
        stopAdvertisingSync()
    }

    private func stopAdvertisingSync() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Browse

    func startBrowsing() {
        stopBrowsingSync()

        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: descriptor, using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            Task { await self.handleBrowseResults(results: results, changes: changes) }
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("[Presence] Browser failed: \(error)")
            default: break
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        stopBrowsingSync()
    }

    private func stopBrowsingSync() {
        browser?.cancel()
        browser = nil
    }

    // MARK: - Handle Results

    private func handleBrowseResults(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if let peer = extractPeer(from: result), peer.email != myEmail {
                    onPeerDiscovered?(peer)
                }
            case .removed(let result):
                let endpointId = "\(result.endpoint)"
                onPeerLost?(endpointId)
            case .changed(old: _, new: let newResult, flags: _):
                if let peer = extractPeer(from: newResult), peer.email != myEmail {
                    onPeerUpdated?(peer)
                }
            default: break
            }
        }
    }

    private func extractPeer(from result: NWBrowser.Result) -> Peer? {
        guard case .bonjour(let txtRecord) = result.metadata else { return nil }
        let dict = Peer.parseTXTRecord(txtRecord)
        let endpointId = "\(result.endpoint)"
        return Peer.fromTXTRecord(dict, endpointId: endpointId)
    }
}
