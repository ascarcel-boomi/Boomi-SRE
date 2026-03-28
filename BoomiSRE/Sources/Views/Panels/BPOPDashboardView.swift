import SwiftUI

// MARK: - Local view mode (do NOT use ViewMode — it already exists in AppState)
enum BPOPViewMode: String, CaseIterable {
    case combined = "All Teams"
    case perTeam  = "Per Team"
}

// MARK: - BPOPDashboardView

struct BPOPDashboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var metrics: [BPOPMetric] = BPOPMetric.allMetrics
    @State private var viewMode: BPOPViewMode = .combined
    @State private var selectedPillar: BPOPPillar? = nil
    @State private var isEditing = false

    private var visibleMetrics: [BPOPMetric] {
        if let pillar = selectedPillar {
            return metrics.filter { $0.pillar == pillar }
        }
        return metrics
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                pillarFilterRow
                pillarsOverviewRow
                metricsListSection
            }
            .padding(20)
        }
        .onAppear { loadSavedValues() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("BPOP Dashboard").font(.title2.bold())
                Text("FY27 Boomi Plan on a Page — \(appState.userProfile.team.isEmpty ? "SRE" : appState.userProfile.team)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("View", selection: $viewMode) {
                ForEach(BPOPViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button {
                isEditing.toggle()
            } label: {
                Label(isEditing ? "Done" : "Edit Values", systemImage: isEditing ? "checkmark" : "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Pillar Filter

    private var pillarFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pillarChip(nil, label: "All")
                ForEach(BPOPPillar.allCases, id: \.self) { pillar in
                    pillarChip(pillar, label: pillar.rawValue)
                }
            }
        }
    }

    @ViewBuilder
    private func pillarChip(_ pillar: BPOPPillar?, label: String) -> some View {
        let isSelected = selectedPillar == pillar
        let color: Color = pillar?.color ?? .accentColor
        Button {
            selectedPillar = pillar
        } label: {
            HStack(spacing: 4) {
                if let p = pillar {
                    Image(systemName: p.icon).font(.caption)
                }
                Text(label).font(.caption.bold())
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.08))
            .foregroundStyle(isSelected ? color : Color.primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? color : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pillars Overview

    private var pillarsOverviewRow: some View {
        HStack(spacing: 12) {
            ForEach(BPOPPillar.allCases, id: \.self) { pillar in
                pillarCard(pillar)
            }
        }
    }

    private func pillarCard(_ pillar: BPOPPillar) -> some View {
        let pillarMetrics = metrics.filter { $0.pillar == pillar }
        let onTrack = pillarMetrics.filter { $0.status == .onTrack }.count
        let atRisk  = pillarMetrics.filter { $0.status == .atRisk }.count
        let total   = pillarMetrics.count
        let pct     = total > 0 ? Double(onTrack) / Double(total) : 0

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(pillar.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                Image(systemName: pillar.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(pillar.color)
            }
            Text(pillar.rawValue)
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 3) {
                Text("\(onTrack)/\(total)").font(.caption2).foregroundStyle(.secondary)
                if atRisk > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8)).foregroundStyle(.yellow)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(pillar.color.opacity(0.06)))
        .onTapGesture { selectedPillar = (selectedPillar == pillar) ? nil : pillar }
    }

    // MARK: - Metrics List

    private var metricsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedPillar.map { $0.rawValue } ?? "All Metrics")
                .font(.headline)
            ForEach(visibleMetrics) { metric in
                metricRow(metric)
            }
        }
    }

    private func metricRow(_ metric: BPOPMetric) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: metric.status.icon)
                .foregroundStyle(metric.status.color)
                .frame(width: 20)

            // Name + source
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name).font(.callout.bold()).lineLimit(1)
                Text(metric.dataSource.rawValue).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            // Value + progress (or inline text field when editing)
            if isEditing {
                // Inline edit field — no sheet needed
                HStack(spacing: 4) {
                    TextField("Value", text: Binding(
                        get: { metric.currentValue.map { String(format: "%g", $0) } ?? "" },
                        set: { newText in
                            if let i = metrics.firstIndex(where: { $0.id == metric.id }) {
                                metrics[i].currentValue = Double(newText)
                                metrics[i].lastUpdated = Date()
                                saveValues()
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    Text("/ \(metric.formattedTarget)").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(metric.formattedCurrent).font(.callout.bold())
                            .foregroundStyle(metric.status.color)
                        Text("/ \(metric.formattedTarget)").font(.caption2).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(metric.status.color)
                                .frame(width: geo.size.width * metric.progressPercent, height: 6)
                        }
                    }
                    .frame(width: 100, height: 6)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color(nsColor: .controlBackgroundColor)))
        .id(metric.id)
    }

    // MARK: - Persistence

    private func loadSavedValues() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".boomi_sre_bpop.json")
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        for i in metrics.indices {
            if let val = saved[metrics[i].id] {
                metrics[i].currentValue = val
            }
        }
    }

    private func saveValues() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".boomi_sre_bpop.json")
        let dict = Dictionary(uniqueKeysWithValues: metrics.compactMap { m -> (String, Double)? in
            guard let v = m.currentValue else { return nil }
            return (m.id, v)
        })
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: url)
        }
    }
}
