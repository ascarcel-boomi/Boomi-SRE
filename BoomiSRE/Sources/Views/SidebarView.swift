import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: $appState.selectedReport) {
            ForEach(ReportSection.allCases, id: \.self) { section in
                let reports = ReportCatalog.reports(for: section)
                if !reports.isEmpty {
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
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Reports")
    }
}
