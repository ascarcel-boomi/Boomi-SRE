import SwiftUI

struct GitHubBrowserView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vm: GitHubBrowserViewModel
    @State private var collapsedSections: Set<String> = []

    var body: some View {
        HSplitView {
            // Left: repo list
            VStack(spacing: 0) {
                BrowserSidebarHeader(title: "GitHub", isLoading: vm.isLoadingRepos) {
                    Task { await vm.loadRepos(appState: appState) }
                }

                TextField("Filter repos...", text: $vm.repoFilter)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12).padding(.bottom, 8)

                Divider()

                // Prominent SSO error card per org
                ForEach(vm.orgErrors.sorted(by: { $0.key < $1.key }), id: \.key) { org, errMsg in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("Cannot load \(org)").font(.callout.bold())
                        }
                        Text(errMsg).font(.caption).foregroundStyle(.secondary)
                        if errMsg.contains("SSO") || errMsg.contains("403") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("To fix:").font(.caption.bold())
                                Text("1. Open github.com/settings/tokens\n2. Find your token\n3. Click \"Configure SSO\" → Authorize \"\(org)\"")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            Button("Open Token Settings") {
                                NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens")!)
                            }.buttonStyle(.bordered).controlSize(.small)
                            Button("Refresh") {
                                Task { await vm.loadRepos(appState: appState) }
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(Color.orange.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).stroke(Color.orange.opacity(0.2)))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                }

                if vm.filteredRepos.isEmpty && !vm.isLoadingRepos {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.title).foregroundStyle(.secondary)
                        Text("No repositories").font(.callout).foregroundStyle(.secondary)
                        Text("Click ↻ to load repos from \(appState.githubOrgs.joined(separator: ", ")) + personal")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                        Spacer()
                    }.padding()
                } else {
                    List(selection: $vm.selectedRepo) {
                        if !vm.orgRepos.isEmpty {
                            let filteredOrg = vm.repoFilter.isEmpty ? vm.orgRepos : vm.orgRepos.filter { $0.name.localizedCaseInsensitiveContains(vm.repoFilter) }
                            let orgKey = appState.githubOrgs.first ?? "Org"
                            Section(isExpanded: sectionBinding(orgKey)) {
                                ForEach(Array(filteredOrg.enumerated()), id: \.element.id) { idx, repo in
                                    repoRow(repo).tag(repo)
                                        .listRowBackground(idx.isMultiple(of: 2)
                                            ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                            : Color.clear)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "building.2").foregroundStyle(.secondary)
                                    Text(orgKey).font(.caption.bold())
                                    Spacer()
                                    Text("\(filteredOrg.count)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleSection(orgKey) }
                            }
                        }
                        if !vm.personalRepos.isEmpty {
                            let filteredPersonal = vm.repoFilter.isEmpty ? vm.personalRepos : vm.personalRepos.filter { $0.name.localizedCaseInsensitiveContains(vm.repoFilter) }
                            Section(isExpanded: sectionBinding("personal")) {
                                ForEach(Array(filteredPersonal.enumerated()), id: \.element.id) { idx, repo in
                                    repoRow(repo).tag(repo)
                                        .listRowBackground(idx.isMultiple(of: 2)
                                            ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                            : Color.clear)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person").foregroundStyle(.secondary)
                                    Text("Personal").font(.caption.bold())
                                    Spacer()
                                    Text("\(filteredPersonal.count)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleSection("personal") }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Right: repo detail with tabs
            VStack(spacing: 0) {
                if let repo = vm.selectedRepo {
                    repoDetailPane(repo: repo)
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
                Task { await vm.loadRepos(appState: appState) }
            }
        }
        .onChange(of: appState.activeProductIds) {
            Task { await vm.loadRepos(appState: appState) }
        }
        .onChange(of: vm.selectedRepo) {
            if let repo = vm.selectedRepo {
                vm.repoTab = 0
                Task {
                    await vm.loadOverview(repo: repo, token: appState.githubToken)
                    await vm.loadPRs(repo: repo, token: appState.githubToken)
                }
            }
        }
        .onChange(of: vm.selectedPR) {
            if let pr = vm.selectedPR {
                Task { await vm.loadPRFiles(pr: pr, token: appState.githubToken) }
            }
        }
    }

    // MARK: - Repo detail (tabbed)
    @ViewBuilder
    private func repoDetailPane(repo: GitHubRepo) -> some View {
        VStack(spacing: 0) {
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
                if let url = URL(string: repo.htmlURL) {
                    Link(destination: url) { Label("GitHub", systemImage: "safari") }
                }
            }
            .padding(16)
            Divider()

            // Tab picker
            Picker("", selection: $vm.repoTab) {
                Text("Overview").tag(0)
                Text("PRs").tag(1)
                Text("Branches").tag(2)
                Text("Commits").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            switch vm.repoTab {
            case 0: overviewTabPane(repo: repo)
            case 1: prTabPane(repo: repo)
            case 2: branchesTabPane(repo: repo)
            case 3: commitsTabPane(repo: repo)
            default: EmptyView()
            }
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private func overviewTabPane(repo: GitHubRepo) -> some View {
        if vm.isLoadingOverview {
            VStack { Spacer(); ProgressView("Loading overview…"); Spacer() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Health metrics row
                    if let detail = vm.repoDetail {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                            GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            healthCard("Stars", value: "\(detail.stargazersCount)", color: .yellow, icon: "star.fill")
                            healthCard("Forks", value: "\(detail.forksCount)", color: .blue, icon: "tuningfork")
                            healthCard("Issues", value: "\(detail.openIssuesCount)",
                                       color: detail.openIssuesCount > 10 ? .red : detail.openIssuesCount > 3 ? .orange : .green,
                                       icon: "exclamationmark.circle")
                            healthCard("PRs", value: "\(vm.prs.count)",
                                       color: vm.prs.count > 15 ? .red : vm.prs.count > 5 ? .orange : .green,
                                       icon: "arrow.triangle.pull")
                        }

                        // Metadata
                        VStack(alignment: .leading, spacing: 6) {
                            if !detail.language.isEmpty {
                                Label(detail.language, systemImage: "chevron.left.forwardslash.chevron.right").font(.callout)
                            }
                            if !detail.license.isEmpty && detail.license != "NOASSERTION" {
                                Label(detail.license, systemImage: "doc.badge.gearshape").font(.callout)
                            }
                            Label("Last push: \(detail.pushedAt)", systemImage: "clock").font(.callout)
                            if !detail.topics.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(detail.topics, id: \.self) { topic in
                                            Text(topic).font(.caption2)
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                        .cardStyle()
                    }

                    // README
                    if !vm.readme.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("README").font(.subheadline.bold())
                            let preview = String(vm.readme.prefix(3000))
                            MarkdownView(markdown: preview)
                                .frame(minHeight: 200)
                        }
                        .cardStyle()
                    } else if !vm.isLoadingOverview {
                        Text("No README").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
        }
    }

    private func healthCard(_ label: String, value: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius).fill(color.opacity(0.07)))
    }

    @ViewBuilder
    private func prTabPane(repo: GitHubRepo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("State", selection: $vm.prStateFilter) {
                    Text("Open").tag("open")
                    Text("Merged").tag("merged")
                    Text("Closed").tag("closed")
                    Text("All").tag("all")
                }
                .pickerStyle(.segmented).frame(width: 280)
                Spacer()
                Text("\(vm.displayedPRs.count) PRs").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if vm.displayedPRs.isEmpty && !vm.isLoadingPRs {
                VStack { Spacer(); Text("No \(vm.prStateFilter) pull requests").foregroundStyle(.secondary); Spacer() }
            } else {
                HSplitView {
                    List(vm.displayedPRs, id: \.id, selection: $vm.selectedPR) { pr in
                        prRow(pr).tag(pr)
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 260, maxWidth: 380)

                    if let pr = vm.selectedPR {
                        prDetailPane(pr: pr, repo: repo)
                    } else {
                        VStack { Spacer(); Text("Select a PR").foregroundStyle(.secondary); Spacer() }
                    }
                }
            }
        }
        .onChange(of: vm.prStateFilter) {
            Task { await vm.loadPRs(repo: repo, token: appState.githubToken) }
        }
    }

    @ViewBuilder
    private func branchesTabPane(repo: GitHubRepo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(vm.branches.count) branches").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await vm.loadBranches(repo: repo, token: appState.githubToken) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if vm.branches.isEmpty {
                VStack { Spacer(); ProgressView("Loading branches…"); Spacer() }
                    .onAppear { Task { await vm.loadBranches(repo: repo, token: appState.githubToken) } }
            } else {
                List(vm.branches) { branch in
                    HStack(spacing: 10) {
                        Image(systemName: branch.name == repo.defaultBranch ? "star.fill" : "arrow.triangle.branch")
                            .foregroundStyle(branch.name == repo.defaultBranch ? .yellow : .secondary)
                            .frame(width: 16)
                        Text(branch.name).font(.callout)
                        if branch.isProtected {
                            Image(systemName: "lock.shield").font(.caption2).foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(branch.sha).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func commitsTabPane(repo: GitHubRepo) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Commits").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await vm.loadCommits(repo: repo, token: appState.githubToken) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()

            if vm.commits.isEmpty {
                VStack { Spacer(); ProgressView("Loading commits…"); Spacer() }
                    .onAppear { Task { await vm.loadCommits(repo: repo, token: appState.githubToken) } }
            } else {
                List(vm.commits) { commit in
                    HStack(spacing: 10) {
                        Text(commit.shortSha).font(.caption.monospaced())
                            .foregroundStyle(Color.accentColor).frame(width: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.message).font(.callout).lineLimit(2)
                            HStack(spacing: 6) {
                                Text(commit.authorName).font(.caption2).foregroundStyle(.secondary)
                                Text(commit.date).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if let url = URL(string: commit.htmlURL) {
                            Link(destination: url) { Image(systemName: "safari").font(.caption2) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Repo Row

    private func sectionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(key) },
            set: { if $0 { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
        )
    }

    private func toggleSection(_ key: String) {
        withAnimation { if collapsedSections.contains(key) { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
    }

    private func repoRow(_ repo: GitHubRepo) -> some View {
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
                if pr.mergedAt != nil {
                    Image(systemName: "arrow.triangle.merge").font(.caption2).foregroundStyle(.purple)
                }
                Text("#\(pr.number)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(pr.title).font(.callout).lineLimit(2)
            }
            HStack(spacing: 8) {
                Label(pr.authorLogin, systemImage: "person").font(.caption2).foregroundStyle(.secondary)
                Text(pr.headBranch).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                Text(pr.updatedAt).font(.caption2).foregroundStyle(.tertiary)
                if let rd = pr.reviewDecision {
                    reviewBadge(rd)
                }
            }
            if !pr.labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(pr.labels, id: \.self) { label in
                            Text(label).font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func reviewBadge(_ decision: String) -> some View {
        let (label, color): (String, Color) = {
            switch decision {
            case "APPROVED": return ("Approved", .green)
            case "CHANGES_REQUESTED": return ("Changes", .red)
            default: return ("Review", .orange)
            }
        }()
        return Text(label).font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
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
                    if !pr.labels.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(pr.labels, id: \.self) { label in
                                Text(label).font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    if let mergeable = pr.mergeable {
                        Label(mergeable ? "This PR can be merged" : "Merge conflicts exist",
                              systemImage: mergeable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(mergeable ? .green : .red)
                    }
                }
                .cardStyle()

                // PR Actions
                HStack(spacing: 8) {
                    if pr.state == "open" {
                        Button {
                            Task { await vm.executeApprove(token: appState.githubToken) }
                        } label: { Label("Approve", systemImage: "checkmark.circle.fill") }
                        .buttonStyle(.borderedProminent).tint(.green)

                        Button { vm.showRequestChangesSheet = true } label: {
                            Label("Request Changes", systemImage: "pencil.circle")
                        }
                        .buttonStyle(.bordered).tint(.orange)

                        Button { vm.showMergeDialog = true } label: {
                            Label("Merge", systemImage: "arrow.triangle.merge")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await vm.executeClose(token: appState.githubToken) }
                        } label: { Label("Close", systemImage: "xmark.circle") }
                        .buttonStyle(.bordered).tint(.red)
                    }
                }

                // Action result banner
                if let result = vm.actionResult {
                    HStack {
                        Image(systemName: result.hasPrefix("Failed") || result.hasPrefix("Merge failed") ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(result.contains("failed") || result.contains("Failed") ? Color.red : Color.green)
                        Text(result).font(.callout)
                        Spacer()
                        Button { vm.actionResult = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                        .fill(result.contains("failed") || result.contains("Failed") ? Color.red.opacity(0.08) : Color.green.opacity(0.08)))
                }

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
                    AIAnalysisBox(text: analysis)
                }

                // PR description
                if !pr.body.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.subheadline.bold())
                        Text(pr.body).font(.callout).textSelection(.enabled)
                    }
                    .cardStyle()
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
                    .cardStyle()
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
                    .cardStyle()
                }

                // Post comment
                VStack(alignment: .leading, spacing: 6) {
                    Text("Post Comment").font(.subheadline.bold())
                    HStack(spacing: 8) {
                        TextField("Write a comment…", text: $vm.commentText)
                            .textFieldStyle(.roundedBorder)
                        Button("Post") {
                            Task { await vm.executeComment(token: appState.githubToken) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .cardStyle()
            }
            .padding(16)
        }
        .alert("Merge PR #\(vm.selectedPR?.number ?? 0)", isPresented: $vm.showMergeDialog) {
            Picker("Method", selection: $vm.mergeMethod) {
                Text("Create a merge commit").tag("merge")
                Text("Squash and merge").tag("squash")
                Text("Rebase and merge").tag("rebase")
            }
            Button("Merge", role: .destructive) { Task { await vm.executeMerge(token: appState.githubToken) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Merge using: \(vm.mergeMethod)")
        }
        .sheet(isPresented: $vm.showRequestChangesSheet) {
            VStack(spacing: 16) {
                Text("Request Changes").font(.headline)
                TextEditor(text: $vm.requestChangesText)
                    .font(.callout)
                    .frame(minHeight: 100)
                    .border(Color.secondary.opacity(0.3))
                HStack {
                    Button("Cancel") { vm.showRequestChangesSheet = false }.buttonStyle(.bordered)
                    Button("Submit") {
                        vm.showRequestChangesSheet = false
                        Task { await vm.executeRequestChanges(token: appState.githubToken) }
                    }.buttonStyle(.borderedProminent)
                    .disabled(vm.requestChangesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 400, minHeight: 240)
        }
    }

    private var prFiles: [GitHubPRFile] { vm.prFiles }

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
