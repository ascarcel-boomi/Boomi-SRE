import SwiftUI

struct JenkinsBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var vm = JenkinsBrowserViewModel()
    @State private var collapsedSections: Set<String> = []

    var body: some View {
        HSplitView {
            // Left: job list
            VStack(spacing: 0) {
                BrowserSidebarHeader(title: "Jenkins", isLoading: vm.isLoadingJobs, lastRefreshed: vm.lastFetched) {
                    Task { await vm.loadJobs(appState: appState) }
                }

                IntegrationHealthBadge(serviceName: "Jenkins", status: appState.jenkinsAuthStatus)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                Divider()

                if vm.jobs.isEmpty && !vm.isLoadingJobs {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "hammer").font(.title).foregroundStyle(.secondary)
                        Text("No jobs found").font(.callout).foregroundStyle(.secondary)
                        Text("Click ↻ to load Jenkins jobs").font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                    }.padding()
                } else {
                    List(selection: $vm.selectedJob) {
                        // Build view membership lookup
                        let viewJobSets = Dictionary(uniqueKeysWithValues:
                            vm.views.map { ($0.name, Set($0.jobNames)) })
                        let allViewedJobs = viewJobSets.values.reduce(into: Set<String>()) { $0.formUnion($1) }
                        let ungrouped = vm.jobs.filter { !allViewedJobs.contains($0.name) }

                        // Views (collapsible sections)
                        ForEach(vm.views.sorted(by: { $0.name < $1.name })) { view in
                            let viewJobs = vm.jobs.filter { viewJobSets[view.name]?.contains($0.name) == true }
                            if !viewJobs.isEmpty {
                                Section(isExpanded: sectionBinding(view.name)) {
                                    ForEach(Array(viewJobs.enumerated()), id: \.element.name) { idx, job in
                                        jobRow(job)
                                            .tag(job)
                                            .listRowBackground(idx.isMultiple(of: 2)
                                                ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                                : Color.clear)
                                    }
                                } header: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder").foregroundStyle(.secondary)
                                        Text(view.name).font(.caption.bold())
                                        Spacer()
                                        Text("\(viewJobs.count)").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { toggleSection(view.name) }
                                }
                            }
                        }

                        // Ungrouped jobs (not in any view)
                        if !ungrouped.isEmpty {
                            Section(isExpanded: sectionBinding("__ungrouped__")) {
                                ForEach(Array(ungrouped.enumerated()), id: \.element.name) { idx, job in
                                    jobRow(job)
                                        .tag(job)
                                        .listRowBackground(idx.isMultiple(of: 2)
                                            ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                            : Color.clear)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "tray").foregroundStyle(.secondary)
                                    Text("Other Jobs").font(.caption.bold())
                                    Spacer()
                                    Text("\(ungrouped.count)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { toggleSection("__ungrouped__") }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            .splitGrip()

            // Right: build history + detail
            VStack(spacing: 0) {
                if let job = vm.selectedJob {
                    // Header
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: job.statusIcon).foregroundStyle(jobColor(job))
                            Text(job.name).font(.title2.bold())
                        }
                        Spacer()
                        if vm.isLoadingBuilds { ProgressView().scaleEffect(0.8) }
                        Text("\(vm.builds.count) builds").font(.callout).foregroundStyle(.secondary)
                        if let url = URL(string: job.url) {
                            Link(destination: url) { Label("Jenkins", systemImage: "safari") }
                        }
                    }
                    .padding(16)
                    Divider()

                    HSplitView {
                        // Build list
                        List(vm.builds, id: \.number, selection: $vm.selectedBuild) { build in
                            buildRow(build).tag(build)
                        }
                        .listStyle(.plain)
                        .frame(minWidth: 180, maxWidth: 260)
                        .splitGrip()

                        // Console / AI panel
                        if let build = vm.selectedBuild {
                            buildDetailPane(build: build, job: job)
                        } else {
                            VStack { Spacer(); Text("Select a build").foregroundStyle(.secondary); Spacer() }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "hammer").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("Select a job").font(.headline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            let stale = vm.lastFetched.map { Date().timeIntervalSince($0) > 60 } ?? true
            if vm.jobs.isEmpty || stale { Task { await vm.loadJobs(appState: appState) } }
        }
        .onChange(of: vm.selectedJob) {
            if let job = vm.selectedJob { Task { await vm.loadBuilds(job: job, appState: appState) } }
        }
        .onChange(of: vm.selectedBuild) {
            if let build = vm.selectedBuild { Task { await vm.loadConsole(build: build, appState: appState) } }
        }
    }

    private func buildRow(_ build: JenkinsBuild) -> some View {
        HStack(spacing: 8) {
            Image(systemName: buildIcon(build)).foregroundStyle(buildColor(build)).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text("#\(build.number)").font(.callout.monospaced())
                Text(build.isRunning ? "Running" : (build.result ?? "?"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(build.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                Text(build.formattedDuration).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func buildDetailPane(build: JenkinsBuild, job: JenkinsJob) -> some View {
        VStack(spacing: 0) {
            // Build header + AI buttons
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: buildIcon(build)).foregroundStyle(buildColor(build))
                    Text("Build #\(build.number)").font(.headline)
                    Text(build.isRunning ? "RUNNING" : (build.result ?? "?"))
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(buildColor(build).opacity(0.15)).clipShape(Capsule())
                }
                Spacer()
                Text(build.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: build.url) {
                    Link(destination: url) { Image(systemName: "safari") }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            HStack(spacing: 10) {
                if build.result == "FAILURE" || build.result == "UNSTABLE" {
                    Button { Task { await vm.explainFailure() } } label: {
                        Label(vm.isAnalyzing ? "…" : "Explain Failure", systemImage: "exclamationmark.magnifyingglass")
                    }
                    .buttonStyle(.bordered).tint(.red).disabled(vm.isAnalyzing || vm.consoleOutput.isEmpty)
                }
                Button { Task { await vm.summarizeBuild() } } label: {
                    Label(vm.isAnalyzing ? "…" : "Summarize", systemImage: "text.magnifyingglass")
                }
                .buttonStyle(.bordered).disabled(vm.isAnalyzing || vm.consoleOutput.isEmpty)
                if vm.isAnalyzing { ProgressView().scaleEffect(0.8) }
                if vm.aiAnalysis != nil {
                    Button { vm.aiAnalysis = nil } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)

            if let err = vm.aiError {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }
            if let analysis = vm.aiAnalysis {
                AIAnalysisBox(text: analysis, tintColor: build.result == "FAILURE" ? .red : .orange)
                    .frame(maxHeight: 220)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }

            Divider()

            // Console output
            if vm.isLoadingConsole {
                VStack { Spacer(); ProgressView("Loading console…"); Spacer() }
            } else {
                ScrollView {
                    Text(vm.consoleOutput.isEmpty ? "(No console output)" : vm.consoleOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func jobRow(_ job: JenkinsJob) -> some View {
        HStack(spacing: 8) {
            Image(systemName: job.statusIcon)
                .foregroundStyle(jobColor(job)).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name).font(.callout).lineLimit(1)
                Text(job.statusLabel).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func sectionBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(key) },
            set: { if $0 { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
        )
    }

    private func toggleSection(_ key: String) {
        withAnimation { if collapsedSections.contains(key) { collapsedSections.remove(key) } else { collapsedSections.insert(key) } }
    }

    private func jobColor(_ job: JenkinsJob) -> Color {
        if job.color.hasSuffix("_anime") { return .orange }
        switch job.color {
        case "blue": return .green; case "red": return .red; case "yellow": return .orange
        default: return .secondary
        }
    }
    private func buildIcon(_ build: JenkinsBuild) -> String {
        if build.isRunning { return "arrow.triangle.2.circlepath" }
        switch build.result {
        case "SUCCESS": return "checkmark.circle.fill"
        case "FAILURE": return "xmark.circle.fill"
        case "UNSTABLE": return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }
    private func buildColor(_ build: JenkinsBuild) -> Color {
        if build.isRunning { return .orange }
        switch build.result {
        case "SUCCESS": return .green; case "FAILURE": return .red; case "UNSTABLE": return .orange
        default: return .secondary
        }
    }
}
