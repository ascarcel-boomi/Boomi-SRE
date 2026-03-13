import SwiftUI

struct GitHubBrowserView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = GitHubBrowserViewModel()

    var body: some View {
        HSplitView {
            // Left: repo list
            VStack(spacing: 0) {
                HStack {
                    Text("GitHub").font(.headline)
                    Spacer()
                    if vm.isLoadingRepos { ProgressView().scaleEffect(0.7) }
                    Button { Task { await vm.loadRepos(token: appState.githubToken) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain)
                }
                .padding(12)
                Divider()

                if vm.repos.isEmpty && !vm.isLoadingRepos {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.title).foregroundStyle(.secondary)
                        Text("No repositories").font(.callout).foregroundStyle(.secondary)
                        Text("Click ↻ to load repos from \(vm.orgName) + personal")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                        Spacer()
                    }.padding()
                } else {
                    List(vm.repos, id: \.id, selection: $vm.selectedRepo) { repo in
                        HStack(spacing: 8) {
                            Image(systemName: repo.isPrivate ? "lock" : "globe")
                                .foregroundStyle(.secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name).font(.callout)
                                Text(repo.fullName).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if repo.openIssuesCount > 0 {
                                Text("\(repo.openIssuesCount)")
                                    .font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.accentColor).clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(repo)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Right: PR list + detail
            VStack(spacing: 0) {
                if let repo = vm.selectedRepo {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: repo.isPrivate ? "lock" : "globe")
                                Text(repo.name).font(.title2.bold())
                            }
                            Text(repo.fullName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if vm.isLoadingPRs { ProgressView().scaleEffect(0.8) }
                        Text("\(vm.prs.count) open PRs").font(.callout).foregroundStyle(.secondary)
                        if let url = URL(string: repo.htmlURL) {
                            Link(destination: url) { Label("GitHub", systemImage: "safari") }
                        }
                    }
                    .padding(16)
                    Divider()

                    if vm.prs.isEmpty && !vm.isLoadingPRs {
                        VStack { Spacer(); Text("No open pull requests").foregroundStyle(.secondary); Spacer() }
                    } else {
                        HSplitView {
                            // PR list
                            List(vm.prs, id: \.id, selection: $vm.selectedPR) { pr in
                                prRow(pr).tag(pr)
                            }
                            .listStyle(.plain)
                            .frame(minWidth: 260, maxWidth: 380)

                            // PR detail
                            if let pr = vm.selectedPR {
                                prDetailPane(pr: pr, repo: repo)
                            } else {
                                VStack { Spacer(); Text("Select a PR").foregroundStyle(.secondary); Spacer() }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "arrow.triangle.pull")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("Select a repository").font(.headline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if vm.repos.isEmpty && !appState.githubToken.isEmpty {
                Task { await vm.loadRepos(token: appState.githubToken) }
            }
        }
        .onChange(of: vm.selectedRepo) {
            if let repo = vm.selectedRepo {
                Task { await vm.loadPRs(repo: repo, token: appState.githubToken) }
            }
        }
        .onChange(of: vm.selectedPR) {
            if let pr = vm.selectedPR {
                Task { await vm.loadPRFiles(pr: pr, token: appState.githubToken) }
            }
        }
    }

    // MARK: - PR Row

    private func prRow(_ pr: GitHubPR) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if pr.isDraft {
                    Text("DRAFT").font(.caption2.bold())
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2)).clipShape(Capsule())
                }
                Text("#\(pr.number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(pr.title).font(.callout).lineLimit(2)
            }
            HStack(spacing: 8) {
                Label(pr.authorLogin, systemImage: "person").font(.caption2).foregroundStyle(.secondary)
                Text(pr.headBranch).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Text(pr.updatedAt).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - PR Detail

    @ViewBuilder
    private func prDetailPane(pr: GitHubPR, repo: GitHubRepo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("#\(pr.number): \(pr.title)").font(.headline)
                    HStack(spacing: 12) {
                        Label(pr.authorLogin, systemImage: "person")
                        Label("\(pr.headBranch) → \(pr.baseBranch)", systemImage: "arrow.right")
                        Label(pr.updatedAt, systemImage: "clock")
                        if let url = URL(string: pr.htmlURL) {
                            Link(destination: url) { Label("Open", systemImage: "safari") }
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if !pr.requestedReviewers.isEmpty {
                        Label("Reviewers: " + pr.requestedReviewers.joined(separator: ", "),
                              systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background))

                // AI buttons
                HStack(spacing: 10) {
                    Button { Task { await vm.summarizePR() } } label: {
                        Label(vm.isAnalyzing ? "…" : "Summarize PR", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.bordered).disabled(vm.isAnalyzing)

                    Button { Task { await vm.reviewPR() } } label: {
                        Label("SRE Review", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.bordered).disabled(vm.isAnalyzing || prFiles.isEmpty)

                    if vm.isAnalyzing { ProgressView().scaleEffect(0.8) }
                    if vm.aiAnalysis != nil {
                        Button { vm.aiAnalysis = nil } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }

                if let err = vm.aiError {
                    Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                }
                if let analysis = vm.aiAnalysis {
                    aiBox(analysis)
                }

                // PR description
                if !pr.body.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.subheadline.bold())
                        Text(pr.body).font(.callout).textSelection(.enabled)
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(.background))
                }

                // Changed files
                if vm.isLoadingFiles {
                    HStack { ProgressView().scaleEffect(0.8); Text("Loading files…").font(.caption) }
                } else if !prFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Changed Files (\(prFiles.count))")
                            .font(.subheadline.bold())
                        ForEach(prFiles) { file in
                            HStack(spacing: 8) {
                                Image(systemName: fileIcon(file.status))
                                    .foregroundStyle(fileColor(file.status)).frame(width: 14)
                                Text(file.filename).font(.caption.monospaced()).lineLimit(1)
                                Spacer()
                                Text("+\(file.additions)").font(.caption2).foregroundStyle(.green)
                                Text("-\(file.deletions)").font(.caption2).foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(.background))
                }

                // CI runs
                if !vm.workflowRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent CI Runs").font(.subheadline.bold())
                        ForEach(vm.workflowRuns.prefix(6)) { run in
                            HStack(spacing: 8) {
                                Image(systemName: runIcon(run))
                                    .foregroundStyle(runColor(run)).frame(width: 14)
                                Text(run.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text(run.createdAt).font(.caption2).foregroundStyle(.secondary)
                                if let url = URL(string: run.htmlURL) {
                                    Link(destination: url) { Image(systemName: "safari").font(.caption2) }
                                }
                            }
                        }
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(.background))
                }
            }
            .padding(16)
        }
    }

    private var prFiles: [GitHubPRFile] { vm.prFiles }

    private func aiBox(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text,
              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.2)))
    }

    private func fileIcon(_ status: String) -> String {
        switch status {
        case "added": return "plus.circle"; case "removed": return "minus.circle"
        case "renamed": return "arrow.right.circle"; default: return "pencil.circle"
        }
    }
    private func fileColor(_ status: String) -> Color {
        switch status {
        case "added": return .green; case "removed": return .red; default: return .orange
        }
    }
    private func runIcon(_ run: GitHubWorkflowRun) -> String {
        if run.status == "in_progress" { return "arrow.triangle.2.circlepath" }
        switch run.conclusion {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        default: return "circle"
        }
    }
    private func runColor(_ run: GitHubWorkflowRun) -> Color {
        if run.status == "in_progress" { return .orange }
        switch run.conclusion {
        case "success": return .green; case "failure": return .red; default: return .secondary
        }
    }
}
