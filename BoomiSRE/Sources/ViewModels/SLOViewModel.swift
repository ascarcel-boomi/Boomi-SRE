import Foundation
import SwiftUI

@Observable
@MainActor
final class SLOViewModel {

    // MARK: - Published

    var statuses: [SLOStatus] = []
    var isLoading = false
    var error: String?
    var lastRefreshed: Date?
    var selectedProductFilter: String? = nil

    // Editor
    var showEditor = false
    var editingDefinition: SLODefinition?
    var showTemplatePicker = false

    // AI
    var aiAnalysis: String?
    var isAnalyzing = false
    var aiError: String?

    // Datasource picker
    var availableDatasources: [(uid: String, name: String, type: String)] = []

    @ObservationIgnored private let grafanaService = GrafanaService()
    @ObservationIgnored private let claudeService = ClaudeService()

    // MARK: - Computed

    var filteredStatuses: [SLOStatus] {
        guard let filter = selectedProductFilter else { return statuses }
        return statuses.filter { $0.definition.productId == filter }
    }

    var statusesByProduct: [(productId: String, statuses: [SLOStatus])] {
        let grouped = Dictionary(grouping: filteredStatuses, by: { $0.definition.productId })
        return grouped.sorted { $0.key < $1.key }.map { (productId: $0.key, statuses: $0.value) }
    }

    var healthyCount: Int { statuses.filter { if case .healthy = $0.health { return true }; return false }.count }
    var warningCount: Int { statuses.filter { if case .warning = $0.health { return true }; return false }.count }
    var criticalCount: Int { statuses.filter { if case .critical = $0.health { return true }; return false }.count }

    // MARK: - Refresh

    func refresh(appState: AppState) async {
        guard !appState.grafanaURL.isEmpty && !appState.grafanaToken.isEmpty else {
            error = "Grafana not configured. Set URL and token in Settings."
            return
        }

        isLoading = true
        error = nil

        let definitions = appState.sloDefinitions.filter { $0.enabled }
        var results: [SLOStatus] = []

        // Discover datasource UID if not set
        if appState.prometheusDataSourceUID.isEmpty {
            if let ds = try? await grafanaService.listDatasources(
                baseURL: appState.grafanaURL, token: appState.grafanaToken
            ) {
                availableDatasources = ds
                // Auto-select first Prometheus datasource
                if let prom = ds.first(where: { $0.type == "prometheus" }) {
                    appState.prometheusDataSourceUID = prom.uid
                    appState.saveConfig()
                }
            }
        }

        let dsUID = appState.prometheusDataSourceUID
        guard !dsUID.isEmpty else {
            error = "No Prometheus datasource found in Grafana. Configure one in Grafana settings."
            isLoading = false
            return
        }

        for definition in definitions {
            guard !definition.metricQuery.isEmpty else {
                results.append(SLOStatus(
                    id: definition.id, definition: definition, currentSLI: nil,
                    health: .noData, errorBudgetRemainingPct: 0, burnRate: 0,
                    lastUpdated: Date(), queryError: "No metric query configured"))
                continue
            }

            do {
                let result = try await grafanaService.queryPrometheus(
                    query: definition.metricQuery,
                    datasourceUID: dsUID,
                    baseURL: appState.grafanaURL,
                    token: appState.grafanaToken,
                    windowDays: definition.windowDays
                )

                if let err = result.error {
                    results.append(SLOStatus(
                        id: definition.id, definition: definition, currentSLI: nil,
                        health: .error(err), errorBudgetRemainingPct: 0, burnRate: 0,
                        lastUpdated: Date(), queryError: err))
                } else {
                    results.append(computeStatus(definition: definition, sliValue: result.value))
                }
            } catch {
                results.append(SLOStatus(
                    id: definition.id, definition: definition, currentSLI: nil,
                    health: .error(error.localizedDescription), errorBudgetRemainingPct: 0, burnRate: 0,
                    lastUpdated: Date(), queryError: error.localizedDescription))
            }
        }

        withAnimation(.none) {
            self.statuses = results
            self.isLoading = false
            self.lastRefreshed = Date()
        }
    }

    // MARK: - Error Budget Math

    private func computeStatus(definition: SLODefinition, sliValue: Double?) -> SLOStatus {
        guard let sli = sliValue else {
            return SLOStatus(id: definition.id, definition: definition, currentSLI: nil,
                             health: .noData, errorBudgetRemainingPct: 0, burnRate: 0,
                             lastUpdated: Date(), queryError: nil)
        }

        let target = definition.target
        let totalBudget = 1.0 - target
        let consumed = max(0, 1.0 - sli)
        let budgetRemainingPct: Double
        let burn: Double

        if totalBudget > 0 {
            budgetRemainingPct = max(0, ((totalBudget - consumed) / totalBudget) * 100.0)
            // Assume we're roughly mid-window for burn rate
            burn = (consumed / totalBudget)
        } else {
            budgetRemainingPct = sli >= target ? 100 : 0
            burn = sli >= target ? 0 : 999
        }

        let health: SLOHealthStatus
        if sli < target || budgetRemainingPct < 10 {
            health = .critical
        } else if budgetRemainingPct < 50 || (sli - target) < (totalBudget * 0.5) {
            health = .warning
        } else {
            health = .healthy
        }

        return SLOStatus(
            id: definition.id, definition: definition, currentSLI: sli,
            health: health, errorBudgetRemainingPct: budgetRemainingPct,
            burnRate: burn, lastUpdated: Date(), queryError: nil)
    }

    // MARK: - CRUD

    func addDefinition(_ def: SLODefinition, appState: AppState) {
        appState.sloDefinitions.append(def)
        appState.saveConfig()
    }

    func updateDefinition(_ def: SLODefinition, appState: AppState) {
        if let idx = appState.sloDefinitions.firstIndex(where: { $0.id == def.id }) {
            appState.sloDefinitions[idx] = def
            appState.saveConfig()
        }
    }

    func deleteDefinition(id: String, appState: AppState) {
        appState.sloDefinitions.removeAll { $0.id == id }
        appState.saveConfig()
    }

    func addFromTemplate(_ template: SLOTemplate, productId: String, serviceName: String, appState: AppState) {
        let query = template.metricQueryTemplate.replacingOccurrences(of: "{service}", with: serviceName)
        let def = SLODefinition(
            name: "\(template.name) — \(serviceName)",
            sloDescription: template.description,
            productId: productId,
            target: template.defaultTarget,
            windowDays: template.defaultWindowDays,
            metricQuery: query,
            category: template.category
        )
        addDefinition(def, appState: appState)
    }

    // MARK: - Editor

    func startNewDefinition(productId: String = "") {
        editingDefinition = SLODefinition(name: "", productId: productId)
        showEditor = true
    }

    func saveEditingDefinition(appState: AppState) {
        guard let def = editingDefinition else { return }
        if appState.sloDefinitions.contains(where: { $0.id == def.id }) {
            updateDefinition(def, appState: appState)
        } else {
            addDefinition(def, appState: appState)
        }
        showEditor = false
        editingDefinition = nil
    }

    // MARK: - AI Analysis

    func analyzeSLOHealth(appState: AppState) async {
        guard claudeService.isAIAvailable else {
            aiError = "No AI backend available."
            return
        }
        guard !statuses.isEmpty else { return }

        isAnalyzing = true
        aiError = nil

        let summary = statuses.map { s in
            let sliStr = s.currentSLI.map { String(format: "%.4f", $0) } ?? "no data"
            return "- \(s.definition.name) [\(s.definition.category.rawValue)]: SLI=\(sliStr), target=\(String(format: "%.3f", s.definition.target)), budget=\(String(format: "%.1f", s.errorBudgetRemainingPct))% remaining, health=\(s.health.label)"
        }.joined(separator: "\n")

        do {
            let result = try await claudeService.chat(
                messages: [(role: "user", content: "Analyze these SLO statuses and recommend actions:\n\(summary)")],
                systemPrompt: "You are an SRE advisor. Analyze SLO health, identify risks, and recommend specific actions. Be concise and actionable.",
                maxTokens: 1024
            )
            withAnimation(.none) { self.aiAnalysis = result }
        } catch {
            aiError = error.localizedDescription
        }
        isAnalyzing = false
    }

    // MARK: - Datasource Discovery

    func loadDatasources(appState: AppState) async {
        guard !appState.grafanaURL.isEmpty else { return }
        availableDatasources = (try? await grafanaService.listDatasources(
            baseURL: appState.grafanaURL, token: appState.grafanaToken)) ?? []
    }
}
