import Foundation
import SwiftUI

@MainActor
final class UpdateViewModel: ObservableObject {
    @Published var availableUpdate: UpdateService.Release?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var isApplying = false
    @Published var error: String?
    @Published var lastChecked: Date?
    @Published var updateBannerDismissed = false

    private let service = UpdateService()

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // MARK: - Check

    func checkForUpdate() async {
        guard !isChecking else { return }
        isChecking = true
        error = nil
        do {
            availableUpdate = try await service.checkForUpdate(currentVersion: currentVersion)
            lastChecked = Date()
            if availableUpdate != nil { updateBannerDismissed = false }
        } catch {
            // Silent fail on auto-check; show error only on manual check
            self.error = error.localizedDescription
        }
        isChecking = false
    }

    // MARK: - Download & Apply

    func downloadAndApply() async {
        guard let release = availableUpdate, !release.dmgURL.isEmpty else {
            error = "No download URL available for this release."; return
        }
        isDownloading = true
        downloadProgress = 0
        error = nil
        do {
            let dmgPath = try await service.downloadUpdate(dmgURL: release.dmgURL) { [weak self] progress in
                Task { @MainActor [weak self] in self?.downloadProgress = progress }
            }
            isDownloading = false
            isApplying = true
            try await service.applyUpdate(dmgPath: dmgPath)
        } catch {
            isDownloading = false
            isApplying = false
            self.error = "Update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Banner

    var showBanner: Bool {
        availableUpdate != nil && !updateBannerDismissed
    }

    func dismissBanner() {
        updateBannerDismissed = true
    }
}
