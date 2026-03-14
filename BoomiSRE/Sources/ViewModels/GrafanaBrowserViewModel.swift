import Foundation
import SwiftUI

@MainActor
final class GrafanaBrowserViewModel: ObservableObject, AIAnalyzable {
    @Published var dashboards: [GrafanaDashboard] = []
    @Published var selectedDashboard: GrafanaDashboard?
    @Published var panels: [GrafanaPanel] = []
    @Published var alertRules: [GrafanaAlertRule] = []
    @Published var isLoadingDashboards = false
    @Published var isLoadingPanels = false
    @Published var isLoadingAlerts = false
    @Published var error: String?
    @Published var searchText: String = ""
    // AI
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?

    private let grafanaService = GrafanaService()
    private let claudeService  = ClaudeService()
    private var depthHint: String = ""

    func loadDashboards(appState: AppState) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint
        guard !appState.grafanaToken.isEmpty else {
            error = "Grafana not configured. Add credentials in Settings."; return
        }
        isLoadingDashboards = true; error = nil
        do {
            async let dashTask  = grafanaService.searchDashboards(baseURL: appState.grafanaURL, token: appState.grafanaToken)
            async let alertTask = grafanaService.listAlertRules(baseURL: appState.grafanaURL, token: appState.grafanaToken)
            dashboards  = try await dashTask
            alertRules  = (try? await alertTask) ?? []
        } catch { self.error = error.localizedDescription }
        isLoadingDashboards = false
    }

    func loadPanels(dashboard: GrafanaDashboard, appState: AppState) async {
        selectedDashboard = dashboard; panels = []; aiAnalysis = nil
        isLoadingPanels = true
        do {
            panels = try await grafanaService.getDashboard(
                uid: dashboard.uid, baseURL: appState.grafanaURL, token: appState.grafanaToken
            )
        } catch { self.error = error.localizedDescription }
        isLoadingPanels = false
    }

    var filteredDashboards: [GrafanaDashboard] {
        guard !searchText.isEmpty else { return dashboards }
        let q = searchText.lowercased()
        return dashboards.filter {
            $0.title.lowercased().contains(q) ||
            $0.folderTitle.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var alertingCount: Int {
        alertRules.filter { $0.state.lowercased() == "alerting" }.count
    }

    // MARK: - AI

    func explainDashboard() async {
        guard let dash = selectedDashboard, !panels.isEmpty else { return }
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured."; return
        }
        let panelList = panels.map { p in
            var line = "  • [\(p.type)] \(p.title)"
            if !p.description.isEmpty { line += " — \(p.description.prefix(100))" }
            if !p.targets.isEmpty { line += "\n    Queries: " + p.targets.prefix(3).joined(separator: " | ") }
            return line
        }.joined(separator: "\n")

        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Explain what this Grafana dashboard monitors and what it tells an SRE.

            Dashboard: \(dash.title)
            Folder: \(dash.folderTitle)
            Tags: \(dash.tags.joined(separator: ", "))

            PANELS (\(panels.count)):
            \(panelList)

            Provide:
            1. **Purpose** — what service/system this dashboard monitors
            2. **Key Signals** — what the most important panels measure and why they matter
            3. **Alert Thresholds** — what values would indicate a problem (based on the queries)
            4. **When to Use** — what incidents or investigations this dashboard helps with
            5. **Gaps** — any obvious monitoring blind spots based on the panel set

            Be specific about the PromQL queries and what they measure.
            """)],
            systemPrompt: "You are an SRE and observability expert explaining Grafana dashboards. Be specific about metrics and their meaning." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
            maxTokens: 1024
        )
    }

    func analyzeAlerts() async {
        guard !alertRules.isEmpty else { return }
        guard claudeService.discoverAPIKey() != nil else {
            aiError = "No Anthropic API key configured."; return
        }
        let alertList = alertRules.prefix(30).map { a in
            "  • [\(a.state.uppercased())] \(a.title)" +
            (a.summary.isEmpty ? "" : " — \(a.summary.prefix(100))")
        }.joined(separator: "\n")

        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Analyze these Grafana alert rules for Boomi's APIM SRE team.

            ALERT RULES (\(alertRules.count) total, \(alertingCount) currently alerting):
            \(alertList)

            Provide:
            1. **Currently Firing** — list and explain any alerts in "ALERTING" state
            2. **Coverage Assessment** — what does this alert set cover well?
            3. **Gaps** — critical signals that appear to be missing (e.g. SLA breaches, saturation)
            4. **Noise Risk** — any alerts that look like they might produce false positives
            5. **Recommended Actions** — for any currently firing alerts, what should the on-call do?
            """)],
            systemPrompt: "You are an SRE observability expert reviewing Grafana alerts. Be specific and actionable." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
            maxTokens: 1024
        )
    }
}
