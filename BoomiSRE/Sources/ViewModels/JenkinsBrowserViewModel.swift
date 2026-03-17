import Foundation
import SwiftUI

@MainActor
final class JenkinsBrowserViewModel: ObservableObject, AIAnalyzable {
    @Published var jobs: [JenkinsJob] = []
    @Published var views: [JenkinsView] = []
    @Published var selectedJob: JenkinsJob?
    @Published var builds: [JenkinsBuild] = []
    @Published var selectedBuild: JenkinsBuild?
    @Published var consoleOutput: String = ""
    @Published var isLoadingJobs = false
    @Published var isLoadingBuilds = false
    @Published var isLoadingConsole = false
    @Published var error: String?
    @Published var lastFetched: Date?
    // Track which server each job came from (for build fetching)
    var jobServerMap: [String: JenkinsServer] = [:]
    // AI
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?

    private let jenkinsService = JenkinsService()
    private let claudeService  = ClaudeService()
    private var depthHint: String = ""

    func loadJobs(appState: AppState) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint

        let servers: [JenkinsServer]
        if !appState.jenkinsServers.isEmpty {
            servers = appState.jenkinsServers
        } else if !appState.jenkinsToken.isEmpty {
            servers = [JenkinsServer(id: "legacy", name: "Jenkins",
                                    url: appState.jenkinsURL, username: appState.jenkinsUsername,
                                    token: appState.jenkinsToken)]
        } else {
            error = "Jenkins not configured. Add credentials in Settings."; return
        }

        isLoadingJobs = true; error = nil
        var allJobs: [JenkinsJob] = []
        var allViews: [JenkinsView] = []
        var serverMap: [String: JenkinsServer] = [:]

        for server in servers {
            do {
                let fetchedJobs = try await jenkinsService.listJobs(
                    baseURL: server.url, username: server.username, token: server.token)
                let fetchedViews = (try? await jenkinsService.listViews(
                    baseURL: server.url, username: server.username, token: server.token)) ?? []
                allViews += fetchedViews
                for job in fetchedJobs { serverMap[job.name] = server }
                allJobs += fetchedJobs
            } catch {
                self.error = (self.error ?? "") + "\(server.name): \(error.localizedDescription) "
            }
        }

        allJobs.sort { $0.name < $1.name }

        // Filter by active product mappings (jobs or views)
        let activeJobs = Set(appState.activeJenkinsJobs)
        let activeViews = Set(appState.activeJenkinsViews)
        if !activeJobs.isEmpty || !activeViews.isEmpty {
            // Build view membership lookup
            let viewJobNames: Set<String> = {
                var names = Set<String>()
                for v in allViews where activeViews.contains(v.name) {
                    names.formUnion(v.jobNames)
                }
                return names
            }()
            allJobs = allJobs.filter { activeJobs.contains($0.name) || viewJobNames.contains($0.name) }
        }

        jobs = allJobs
        views = allViews
        jobServerMap = serverMap
        isLoadingJobs = false
        lastFetched = Date()
    }

    func loadBuilds(job: JenkinsJob, appState: AppState) async {
        selectedJob = job; builds = []; selectedBuild = nil; consoleOutput = ""; aiAnalysis = nil
        isLoadingBuilds = true
        let server = jobServerMap[job.name]
        let baseURL = server?.url ?? appState.jenkinsURL
        let user = server?.username ?? appState.jenkinsUsername
        let tok = server?.token ?? appState.jenkinsToken
        do {
            builds = try await jenkinsService.getBuildHistory(
                baseURL: baseURL, jobName: job.name, username: user, token: tok)
        } catch { self.error = error.localizedDescription }
        isLoadingBuilds = false
    }

    func loadConsole(build: JenkinsBuild, appState: AppState) async {
        guard let job = selectedJob else { return }
        selectedBuild = build; consoleOutput = ""; aiAnalysis = nil
        isLoadingConsole = true
        let server = jobServerMap[job.name]
        let baseURL = server?.url ?? appState.jenkinsURL
        let user = server?.username ?? appState.jenkinsUsername
        let tok = server?.token ?? appState.jenkinsToken
        do {
            consoleOutput = try await jenkinsService.getConsoleOutput(
                baseURL: baseURL, jobName: job.name, buildNumber: build.number,
                username: user, token: tok)
        } catch { self.error = error.localizedDescription }
        isLoadingConsole = false
    }

    // MARK: - AI

    func explainFailure() async {
        guard let build = selectedBuild, let job = selectedJob,
              !consoleOutput.isEmpty else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        // Use tail of console (most relevant for failures) + head (for context)
        let head = String(consoleOutput.prefix(1500))
        let tail = String(consoleOutput.suffix(3000))
        let context = head == tail ? head : head + "\n\n[...]\n\n" + tail

        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Analyze this Jenkins build failure and explain what went wrong.

            Job: \(job.name)
            Build #\(build.number) | Result: \(build.displayResult) | Duration: \(build.formattedDuration)
            Date: \(build.date.formatted(date: .abbreviated, time: .shortened))

            CONSOLE OUTPUT (head + tail):
            \(context)

            Provide:
            1. **Root Cause** — what exactly failed and why
            2. **Error Message** — the key error line(s) from the log
            3. **Fix** — specific steps to resolve this (commands, config changes, etc.)
            4. **Prevention** — how to avoid this failure in the future

            Be specific: quote the actual error messages from the console output.
            """)],
            systemPrompt: "You are an SRE analyzing Jenkins build failures. Be specific, quote log lines, and give actionable fixes." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
            maxTokens: 1024
        )
    }

    func summarizeBuild() async {
        guard let build = selectedBuild, let job = selectedJob,
              !consoleOutput.isEmpty else { return }
        guard claudeService.isAIAvailable else {
            aiError = "No Anthropic API key configured."; return
        }
        let context = String(consoleOutput.prefix(4000))

        await runAIAnalysis(
            using: claudeService,
            messages: [("user", """
            Summarize what this Jenkins build did.

            Job: \(job.name) | Build #\(build.number) | Result: \(build.displayResult)

            CONSOLE OUTPUT:
            \(context)

            Provide a concise summary covering:
            - What stages/steps ran
            - Deployments or packages produced
            - Test results (pass/fail counts if present)
            - Any warnings or non-critical issues
            - Overall outcome
            """)],
            systemPrompt: "You are an SRE summarizing Jenkins build output. Be concise and focus on what matters." + (depthHint.isEmpty ? "" : "\n\n" + depthHint),
            maxTokens: 768
        )
    }

    // Badge count helper
    var failedJobCount: Int {
        jobs.filter { $0.color.hasPrefix("red") }.count
    }
}
