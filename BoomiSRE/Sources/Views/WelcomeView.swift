import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Boomi SRE Reports")
                .font(.largeTitle.bold())

            Text("Select a report from the sidebar to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "dollarsign.circle", color: .green,
                           text: "AWS Cost Reports — multi-account cost analysis and trends")
                FeatureRow(icon: "chart.bar.xaxis", color: .blue,
                           text: "Jira / SRE Analytics — epics, incidents, alerts, and YIR reports")
                FeatureRow(icon: "checkmark.seal", color: .purple,
                           text: "FY26 Self-Evaluation — BPOP mapping and bulk updater")
                FeatureRow(icon: "clock.arrow.2.circlepath", color: .orange,
                           text: "Automation — cron scheduling and status management")
            }
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
