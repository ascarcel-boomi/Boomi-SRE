import SwiftUI

struct ReportDetailView: View {
    let report: ReportItem
    @EnvironmentObject var appState: AppState
    @State private var errorMessage: String?

    private let bridge = PythonBridge()

    private var result: ReportResult? {
        appState.results[report.id]
    }

    private var isRunning: Bool {
        appState.runningReports.contains(report.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()

            // Content
            if isRunning {
                loadingView
            } else if let result = result {
                resultView(result)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.title)
                    .font(.title2.bold())
                Text(report.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if result != nil {
                // View mode toggle
                Picker("View", selection: $appState.viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode == .table ? "tablecells" : "chart.bar.fill")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Divider().frame(height: 24)

                // Export buttons
                Button {
                    exportMarkdown()
                } label: {
                    Label("Export .md", systemImage: "square.and.arrow.up")
                }

                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            Divider().frame(height: 24)

            Button {
                runReport()
            } label: {
                Label(isRunning ? "Running..." : "Run Report", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Running \(report.scriptName)...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This may take a few seconds")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "play.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Click \"Run Report\" to generate this report")
                .font(.headline)
                .foregroundStyle(.secondary)

            // CSV status
            if !report.csvKeys.isEmpty {
                csvStatusView
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var csvStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Required CSV files:")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(report.csvKeys, id: \.self) { csv in
                let exists = FileManager.default.fileExists(
                    atPath: (appState.csvFolder as NSString).appendingPathComponent(csv)
                )
                HStack(spacing: 6) {
                    Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(exists ? .green : .red)
                    Text(csv)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Report Failed")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 600)
                .textSelection(.enabled)
            Button("Retry") { runReport() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result

    private func resultView(_ result: ReportResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Timestamp
                HStack {
                    Text("Generated: \(result.generatedAt, format: .dateTime)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                switch appState.viewMode {
                case .chart:
                    chartContent(result)
                case .table:
                    tableContent(result)
                }
            }
            .padding(20)
        }
    }

    private func chartContent(_ result: ReportResult) -> some View {
        ForEach(result.sections) { section in
            if !section.rows.isEmpty && section.rows.contains(where: { $0.value > 0 }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.headline)
                    ReportChartView(section: section)
                        .frame(minHeight: 300)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            }
        }
    }

    private func tableContent(_ result: ReportResult) -> some View {
        ForEach(result.sections) { section in
            if !section.rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.headline)
                    ReportTableView(rows: section.rows)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(.background))
            }
        }
    }

    // MARK: - Actions

    private func runReport() {
        errorMessage = nil
        appState.runningReports.insert(report.id)

        Task {
            do {
                let output = try await bridge.run(script: report.scriptName)
                let parsed = OutputParser.parse(output: output, report: report)
                await MainActor.run {
                    appState.results[report.id] = parsed
                    appState.runningReports.remove(report.id)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    appState.runningReports.remove(report.id)
                }
            }
        }
    }

    private func exportMarkdown() {
        guard let result = result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(report.id)_\(Date().formatted(.iso8601)).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? result.rawOutput.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func copyToClipboard() {
        guard let result = result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.rawOutput, forType: .string)
    }
}
