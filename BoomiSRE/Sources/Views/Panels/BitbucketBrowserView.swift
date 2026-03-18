import SwiftUI

struct BitbucketBrowserView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vm: BitbucketBrowserViewModel
    @State private var commentText = ""

    var body: some View {
        HSplitView {
            // Left: repo list
            repoListPane
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Right: repo detail
            VStack(spacing: 0) {
                if let repo = vm.selectedRepo {
                    repoDetailPane(repo: repo)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            let stale = vm.lastFetched.map { Date().timeIntervalSince($0) > 300 } ?? true
            if vm.repos.isEmpty || stale { Task { await vm.loadRepos(appState: appState) } }
        }
        .alert("Confirm Action", isPresented: Binding(
            get: { vm.showConfirmAction != nil },
            set: { if !$0 { vm.showConfirmAction = nil } }
        )) {
            Button(vm.showConfirmAction?.title ?? "Confirm",
                   role: vm.showConfirmAction?.isDestructive == true ? .destructive : nil) {
                if let action = vm.showConfirmAction {
                    vm.showConfirmAction = nil
                    Task { await vm.executeAction(action, appState: appState) }
                }
            }
            Button("Cancel", role: .cancel) { vm.showConfirmAction = nil }
        } message: {
            Text("Are you sure you want to \(vm.showConfirmAction?.title.lowercased() ?? "proceed")?")
        }
    }

    // MARK: - Repo list
    private var repoListPane: some View {
        VStack(spacing: 0) {
            BrowserSidebarHeader(title: "Bitbucket", isLoading: vm.isLoadingRepos) {
                Task { await vm.loadRepos(appState: appState) }
            }

            HStack(spacing: 6) {
                Text("Workspace:").font(.caption).foregroundStyle(.secondary)
                Text(appState.bitbucketWorkspace).font(.caption.bold())
                Spacer()
                Button { Task { await vm.loadRepos(appState: appState) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Force reload repos")
            }
            .padding(.horizontal, 12).padding(.bottom, 4)

            TextField("Filter repos…", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12).padding(.bottom, 8)

            Divider()

            if let error = vm.error {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).font(.title2)
                    Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Settings") {
                        appState.showSettings = true
                        appState.selectedSettingsTab = "bitbucket"
                    }.buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                }.padding()
            } else if vm.filteredRepos.isEmpty && !vm.isLoadingRepos {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.triangle.branch").font(.title).foregroundStyle(.secondary)
                    Text("No repositories").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }.padding()
            } else {
                List(selection: $vm.selectedRepo) {
                    ForEach(Array(vm.filteredRepos.enumerated()), id: \.element.id) { idx, repo in
                        repoRow(repo).tag(repo)
                            .listRowBackground(idx.isMultiple(of: 2)
                                ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                : Color.clear)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onChange(of: vm.selectedRepo) {
            if let repo = vm.selectedRepo {
                vm.repoTab = 0
                Task { await vm.loadPRs(repo: repo, appState: appState) }
            }
        }
    }

    private func repoRow(_ repo: BBRepo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock" : "globe").foregroundStyle(.secondary).frame(width: 14)
                Text(repo.name).font(.callout).lineLimit(1)
            }
            if !repo.description.isEmpty {
                Text(repo.description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                if !repo.language.isEmpty {
                    Text(repo.language)
                        .font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Text(repo.updatedOn).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Repo detail
    private func repoDetailPane(repo: BBRepo) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: repo.isPrivate ? "lock" : "globe")
                        Text(repo.name).font(.title2.bold())
                        if !repo.language.isEmpty {
                            Text(repo.language).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                    }
                    Text(repo.fullName).font(.caption).foregroundStyle(.secondary)
                    if !repo.description.isEmpty {
                        Text(repo.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                if let url = URL(string: repo.htmlURL) {
                    Link(destination: url) { Label("Bitbucket", systemImage: "safari") }
                        .font(.caption)
                }
            }
            .padding(14)
            Divider()

            // Tab picker
            Picker("", selection: $vm.repoTab) {
                Text("Pull Requests").tag(0)
                Text("Branches").tag(1)
                Text("Pipelines").tag(2)
                Text("Commits").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            // Action result banner
            if let result = vm.actionResult {
                HStack {
                    Image(systemName: result.hasPrefix("Error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(result.hasPrefix("Error") ? .red : .green)
                    Text(result).font(.callout)
                    Spacer()
                    Button { vm.actionResult = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(result.hasPrefix("Error") ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
                Divider()
            }

            switch vm.repoTab {
            case 0: prPane(repo: repo)
            case 1: branchesPane(repo: repo)
            case 2: pipelinesPane(repo: repo)
            case 3: commitsPane(repo: repo)
            default: EmptyView()
            }
        }
    }

    // MARK: - PR pane
    private func prPane(repo: BBRepo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("State", selection: $vm.prStateFilter) {
                    Text("Open").tag("OPEN")
                    Text("Merged").tag("MERGED")
                    Text("Declined").tag("DECLINED")
                }
                .pickerStyle(.segmented).frame(width: 260)
                Spacer()
                if vm.isLoadingPRs { ProgressView().scaleEffect(0.7) }
                Text("\(vm.prs.count) PRs").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if vm.prs.isEmpty && !vm.isLoadingPRs {
                VStack { Spacer(); Text("No \(vm.prStateFilter.lowercased()) pull requests").foregroundStyle(.secondary); Spacer() }
            } else {
                HSplitView {
                    List(vm.prs, id: \.id, selection: $vm.selectedPR) { pr in
                        prRow(pr).tag(pr)
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 240, maxWidth: 360)

                    if let pr = vm.selectedPR {
                        prDetailPane(pr: pr, repo: repo)
                    } else {
                        VStack { Spacer(); Text("Select a pull request").foregroundStyle(.secondary); Spacer() }
                    }
                }
            }
        }
        .onChange(of: vm.prStateFilter) {
            Task { await vm.loadPRs(repo: repo, appState: appState) }
        }
        .onChange(of: vm.selectedPR) {
            if let pr = vm.selectedPR {
                Task { await vm.loadPRDetail(pr: pr, appState: appState) }
            }
        }
    }

    private func prRow(_ pr: BBPR) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("#\(pr.id): \(pr.title)").font(.callout).lineLimit(2)
            HStack(spacing: 8) {
                Label(pr.authorDisplayName, systemImage: "person").font(.caption2).foregroundStyle(.secondary)
                Text("\(pr.sourceBranch) → \(pr.destinationBranch)").font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Text(pr.updatedOn).font(.caption2).foregroundStyle(.tertiary)
                if pr.commentCount > 0 {
                    Label("\(pr.commentCount)", systemImage: "bubble.left").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func prDetailPane(pr: BBPR, repo: BBRepo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("#\(pr.id): \(pr.title)").font(.headline)
                    HStack(spacing: 12) {
                        Label(pr.authorDisplayName, systemImage: "person")
                        Label("\(pr.sourceBranch) → \(pr.destinationBranch)", systemImage: "arrow.right")
                        Label(pr.updatedOn, systemImage: "clock")
                        prStateBadge(pr.state)
                        if let url = URL(string: pr.htmlURL) {
                            Link(destination: url) { Label("Open", systemImage: "safari") }
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .cardStyle()

                // Actions
                HStack(spacing: 8) {
                    if pr.state == "OPEN" {
                        Button("Approve") { vm.showConfirmAction = .approvePR(pr) }
                            .buttonStyle(.bordered)
                        Button("Decline") { vm.showConfirmAction = .declinePR(pr) }
                            .buttonStyle(.bordered).tint(.red)
                        Button("Merge") { vm.showConfirmAction = .mergePR(pr) }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Button { Task { await vm.summarizePR(appState: appState) } } label: {
                        Label(vm.isAnalyzing ? "…" : "Summarize", systemImage: "text.magnifyingglass")
                    }.buttonStyle(.bordered).disabled(vm.isAnalyzing)
                    Button { Task { await vm.reviewPR(appState: appState) } } label: {
                        Label("SRE Review", systemImage: "checkmark.shield")
                    }.buttonStyle(.bordered).disabled(vm.isAnalyzing)
                    if vm.isAnalyzing { ProgressView().scaleEffect(0.8) }
                }

                if let err = vm.aiError {
                    Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                }
                if let analysis = vm.aiAnalysis {
                    AIAnalysisBox(text: analysis)
                }

                // Description
                if !pr.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.subheadline.bold())
                        Text(pr.description).font(.callout).textSelection(.enabled)
                    }
                    .cardStyle()
                }

                // Diff
                if vm.isLoadingDetail {
                    HStack { ProgressView().scaleEffect(0.8); Text("Loading diff…").font(.caption) }
                } else if !vm.prDiff.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Diff").font(.subheadline.bold())
                        ScrollView(.horizontal) {
                            Text(String(vm.prDiff.prefix(8000)))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color(nsColor: .textBackgroundColor)))
                        .frame(maxHeight: 300)
                    }
                    .cardStyle()
                }

                // Comments
                if !vm.prComments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Comments (\(vm.prComments.count))").font(.subheadline.bold())
                        ForEach(vm.prComments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(comment.authorDisplayName).font(.caption.bold())
                                    Text(comment.createdOn).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Text(comment.content).font(.callout).textSelection(.enabled)
                            }
                            .padding(8).background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.secondary.opacity(0.05)))
                        }
                    }
                    .cardStyle()
                }

                // Post comment
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add Comment").font(.subheadline.bold())
                    TextEditor(text: $commentText)
                        .font(.callout)
                        .frame(minHeight: 60, maxHeight: 120)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    HStack {
                        Spacer()
                        Button("Post Comment") {
                            let text = commentText
                            commentText = ""
                            Task { await vm.postComment(pr: pr, text: text, appState: appState) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .cardStyle()
            }
            .padding(14)
        }
    }

    // MARK: - Branches pane
    private func branchesPane(repo: BBRepo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(vm.branches.count) branches").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await vm.loadBranches(repo: repo, appState: appState) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if vm.branches.isEmpty {
                VStack { Spacer(); ProgressView("Loading branches…"); Spacer() }
                    .onAppear { Task { await vm.loadBranches(repo: repo, appState: appState) } }
            } else {
                List(vm.branches) { branch in
                    HStack(spacing: 10) {
                        Image(systemName: branch.name == repo.mainBranch ? "star.fill" : "arrow.triangle.branch")
                            .foregroundStyle(branch.name == repo.mainBranch ? .yellow : .secondary)
                            .frame(width: 16)
                        Text(branch.name).font(.callout)
                        Spacer()
                        Text(branch.target).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Button { vm.showConfirmAction = .triggerPipeline(branch.name) } label: {
                            Image(systemName: "play.circle").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                        .help("Trigger pipeline on \(branch.name)")
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Pipelines pane
    private func pipelinesPane(repo: BBRepo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Pipelines").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await vm.loadPipelines(repo: repo, appState: appState) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if vm.pipelines.isEmpty {
                VStack { Spacer(); ProgressView("Loading pipelines…"); Spacer() }
                    .onAppear { Task { await vm.loadPipelines(repo: repo, appState: appState) } }
            } else {
                List(vm.pipelines) { pipeline in
                    HStack(spacing: 10) {
                        Image(systemName: pipelineIcon(pipeline)).foregroundStyle(pipelineColor(pipeline)).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(pipeline.buildNumber) · \(pipeline.targetBranch)").font(.callout)
                            HStack(spacing: 8) {
                                Text(pipeline.triggerName).font(.caption2).foregroundStyle(.secondary)
                                Text(pipeline.createdOn).font(.caption2).foregroundStyle(.tertiary)
                                if let dur = pipeline.durationSeconds {
                                    Text("\(dur)s").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        pipelineStateBadge(pipeline)
                        if let url = URL(string: pipeline.htmlURL) {
                            Link(destination: url) { Image(systemName: "safari").font(.caption2) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Commits pane
    private func commitsPane(repo: BBRepo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Commits").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if vm.commits.isEmpty {
                VStack { Spacer(); ProgressView("Loading commits…"); Spacer() }
                    .onAppear { Task { await vm.loadCommits(repo: repo, appState: appState) } }
            } else {
                List(vm.commits) { commit in
                    HStack(spacing: 10) {
                        Text(commit.shortHash).font(.caption.monospaced())
                            .foregroundStyle(Color.accentColor).frame(width: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.message).font(.callout).lineLimit(2)
                            Text("\(commit.authorName) · \(commit.date)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Select a repository").font(.headline).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Helpers
    private func prStateBadge(_ state: String) -> some View {
        let color: Color = state == "OPEN" ? .green : state == "MERGED" ? .purple : .red
        return Text(state)
            .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15))).foregroundStyle(color)
    }

    private func pipelineIcon(_ p: BBPipeline) -> String {
        if p.state == "RUNNING" { return "arrow.triangle.2.circlepath" }
        switch p.result {
        case "SUCCESSFUL": return "checkmark.circle.fill"
        case "FAILED": return "xmark.circle.fill"
        case "STOPPED": return "stop.circle.fill"
        default: return "circle"
        }
    }

    private func pipelineColor(_ p: BBPipeline) -> Color {
        if p.state == "RUNNING" { return .orange }
        switch p.result {
        case "SUCCESSFUL": return .green
        case "FAILED": return .red
        default: return .secondary
        }
    }

    private func pipelineStateBadge(_ p: BBPipeline) -> some View {
        let label = p.result ?? p.state
        let color: Color = pipelineColor(p)
        return Text(label).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15))).foregroundStyle(color)
    }
}
