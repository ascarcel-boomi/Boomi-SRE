import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedReport) {
            // Home button at the top
            Button {
                appState.selectedReport = nil
            } label: {
                Label("Home", systemImage: "house")
                    .font(.body.bold())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Report sections (only sections that have reports)
            ForEach(ReportCatalog.activeSections, id: \.self) { section in
                let reports = ReportCatalog.reports(for: section)
                Section {
                    ForEach(reports) { report in
                        NavigationLink(value: report) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.title)
                                    .font(.body)
                                Text(report.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Label(section.rawValue, systemImage: section.icon)
                        .font(.headline)
                }
            }

            // Coming soon sections
            Section {
                Label("Jira analytics via API — coming soon", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Label("Coming Soon", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Boomi SRE")
    }
}
