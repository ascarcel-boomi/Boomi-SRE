import Foundation
import SwiftUI

/// Central app state shared across all views.
final class AppState: ObservableObject {
    @Published var selectedReport: ReportItem?
    @Published var sidebarCollapsed = false
    @Published var csvFolder: String
    @Published var viewMode: ViewMode = .chart

    /// Cached report results keyed by ReportItem.id
    @Published var results: [String: ReportResult] = [:]
    @Published var runningReports: Set<String> = []

    private let configURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.configURL = home.appendingPathComponent(".boomi_sre_config.json")
        self.csvFolder = home.appendingPathComponent("Downloads").path

        loadConfig()
    }

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }
        csvFolder = config.csvFolder ?? csvFolder
    }

    func saveConfig() {
        let config = AppConfig(csvFolder: csvFolder)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }
}

struct AppConfig: Codable {
    var csvFolder: String?
}

enum ViewMode: String, CaseIterable {
    case table = "Table"
    case chart = "Chart"
}
