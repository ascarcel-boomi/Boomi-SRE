import SwiftUI

/// Reusable table for displaying Jira issues.
struct JiraIssueTableView: View {
    let issues: [JiraIssue]
    let baseURL: String

    var body: some View {
        Table(issues) {
            TableColumn("Key") { issue in
                let url = URL(string: "\(baseURL.hasSuffix("/") ? baseURL : baseURL + "/")browse/\(issue.key)")
                if let url {
                    Link(issue.key, destination: url)
                        .font(.body.monospaced())
                } else {
                    Text(issue.key).font(.body.monospaced())
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("Summary") { issue in
                Text(issue.fields.summary ?? "")
                    .lineLimit(2)
            }
            .width(min: 200, ideal: 400)

            TableColumn("Status") { issue in
                let name = issue.fields.status?.name ?? "—"
                let catName = issue.fields.status?.statusCategory?.name ?? ""
                Text(name)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(statusColor(catName).opacity(0.15)))
                    .foregroundStyle(statusColor(catName))
            }
            .width(min: 80, ideal: 120)

            TableColumn("Priority") { issue in
                Text(issue.fields.priority?.name ?? "—")
                    .font(.caption)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Type") { issue in
                Text(issue.fields.issuetype?.name ?? "—")
                    .font(.caption)
            }
            .width(min: 70, ideal: 100)

            TableColumn("Due") { issue in
                Text(issue.fields.duedate ?? "—")
                    .font(.caption)
                    .foregroundStyle(isDueOverdue(issue.fields.duedate) ? .red : .secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .frame(minHeight: CGFloat(min(issues.count * 32 + 40, 500)))
    }

    private func statusColor(_ categoryName: String) -> Color {
        switch categoryName {
        case "In Progress": return .blue
        case "To Do": return .orange
        case "Done": return .green
        default: return .secondary
        }
    }

    private func isDueOverdue(_ dateStr: String?) -> Bool {
        guard let s = dateStr else { return false }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: s) else { return false }
        return d < Date()
    }
}
