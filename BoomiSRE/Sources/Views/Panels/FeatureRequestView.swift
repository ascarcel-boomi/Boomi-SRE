import SwiftUI

/// Sheet for submitting feature requests and bug reports as GitHub Issues.
struct FeatureRequestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum RequestType: String, CaseIterable {
        case feature    = "Feature Request"
        case bug        = "Bug Report"
        case improvement = "Improvement"

        var labels: [String] {
            switch self {
            case .feature:     return ["feature-request", "submitted-from-app"]
            case .bug:         return ["bug", "submitted-from-app"]
            case .improvement: return ["enhancement", "submitted-from-app"]
            }
        }

        var icon: String {
            switch self {
            case .feature:     return "star"
            case .bug:         return "ant"
            case .improvement: return "arrow.up.circle"
            }
        }
    }

    @State private var requestType: RequestType = .feature
    @State private var title = ""
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var submittedIssueURL: String?
    @State private var errorMessage: String?

    private let githubService = GitHubService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Label("Submit Feedback", systemImage: "questionmark.bubble.fill")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
            }

            if let url = submittedIssueURL {
                successView(url: url)
            } else {
                formView
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 400)
    }

    // MARK: - Form

    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Type picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Type").font(.subheadline.bold())
                Picker("Type", selection: $requestType) {
                    ForEach(RequestType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.subheadline.bold())
                TextField("Brief summary of your request", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Description
            VStack(alignment: .leading, spacing: 6) {
                Text("Description").font(.subheadline.bold())
                TextEditor(text: $description)
                    .font(.body)
                    .frame(minHeight: 120)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )
            }

            // GitHub token status note
            if appState.githubToken.isEmpty {
                Label("GitHub token not configured — will open in browser instead.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Error
            if let err = errorMessage {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Actions
            HStack {
                Spacer()
                Button("Submit") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .overlay {
                    if isSubmitting { ProgressView().scaleEffect(0.8) }
                }
            }
        }
    }

    // MARK: - Success

    private func successView(url: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Submitted!").font(.title2.bold())
            if let issueURL = URL(string: url) {
                Link("View on GitHub →", destination: issueURL)
                    .font(.callout)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Submit

    private func submit() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil

        let token = appState.githubToken

        if token.isEmpty {
            // Open in browser with title pre-filled
            let encodedTitle = trimmedTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedTitle
            if let url = URL(string: "https://github.com/ascarcel-boomi/Boomi-SRE/issues/new?title=\(encodedTitle)") {
                NSWorkspace.shared.open(url)
            }
            await MainActor.run {
                submittedIssueURL = "https://github.com/ascarcel-boomi/Boomi-SRE/issues"
                isSubmitting = false
            }
            return
        }

        let fullBody = buildBody()

        do {
            let result = try await githubService.createIssue(
                owner: "ascarcel-boomi",
                repo: "Boomi-SRE",
                title: trimmedTitle,
                body: fullBody,
                labels: requestType.labels,
                token: token
            )
            await MainActor.run {
                submittedIssueURL = result.htmlURL
                isSubmitting = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to submit: \(error.localizedDescription)"
                isSubmitting = false
            }
        }
    }

    private func buildBody() -> String {
        var parts: [String] = []
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(description)
        }
        parts.append("---")
        parts.append("**Submitted from Boomi SRE App**")

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        parts.append("- App Version: \(version)")
        parts.append("- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        let connected = [
            ("AWS", appState.awsAuthStatus),
            ("Jira", appState.jiraAuthStatus),
            ("GitHub", appState.githubAuthStatus),
            ("Jenkins", appState.jenkinsAuthStatus),
            ("Grafana", appState.grafanaAuthStatus),
            ("Confluence", appState.confluenceAuthStatus),
            ("Google", appState.googleAuthStatus),
            ("Bitbucket", appState.bitbucketAuthStatus),
        ].filter { if case .authenticated = $0.1 { return true }; return false }
         .map { $0.0 }

        if !connected.isEmpty {
            parts.append("- Connected Services: \(connected.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }
}
