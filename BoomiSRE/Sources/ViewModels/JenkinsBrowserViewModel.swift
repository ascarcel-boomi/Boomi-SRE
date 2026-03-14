import Foundation
import SwiftUI

@MainActor
final class JenkinsBrowserViewModel: ObservableObject, AIAnalyzable {
    @Published var jobs: [JenkinsJob] = []
    @Published var selectedJob: JenkinsJob?
    @Published var builds: [JenkinsBuild] = []
    @Published var selectedBuild: JenkinsBuild?
    @Published var consoleOutput: String = ""
    @Published var isLoadingJobs = false
    @Published var isLoadingBuilds = false
    @Published var isLoadingConsole = false
    @Published var error: String?
    // AI
    @Published var aiAnalysis: String?
    @Published var isAnalyzing = false
    @Published var aiError: String?

    private let jenkinsService = JenkinsService()
    private let claudeService  = ClaudeService()
    private var depthHint: String = ""

    func loadJobs(appState: AppState) async {
        depthHint = appState.userProfile.experienceLevel.analysisDepthHint
        guard !appState.jenkinsToken.isEmpty else {
            error = "Jenkins not configured. Add credentials in Settings."; return
        }
        isLoadingJobs = true; error = nil
        do {
            jobs = try await jenkinsService.listJobs(
                baseURL: appState.jenkinsURL,
                username: appState.jenkinsUsername,
                token: appState.jenkinsToken
            )
            .sorted { $0.name < $1.name }
        } catch { self.error = error.localizedDescription }
        isLoadingJobs = false
    }

    func loadBuilds(job: JenkinsJob, appState: AppState) async {
        selectedJob = job; builds = []; selectedBuild = nil; consoleOutput = ""; aiAnalysis = nil
        isLoadingBuilds = true
        do {
            builds = try await jenkinsService.getBuildHistory(
                baseURL: appState.jenkinsURL,
                jobName: job.name,
                username: appState.jenkinsUsername,
                token: appState.jenkinsToken
            )
        } catch { self.error = error.localizedDescription }
        isLoadingBuilds = false
    }

    func loadConsole(build: JenkinsBuild, appState: AppState) async {
        guard let job = selectedJob else { return }
        selectedBuild = build; consoleOutput = ""; aiAnalysis = nil
        isLoadingConsole = true
        do {
            consoleOutput = try await jenkinsService.getConsoleOutput(
                baseURL: appState.jenkinsURL,
                jobName: job.name,
                buildNumber: build.number,
                username: appState.jenkinsUsername,
                token: appState.jenkinsToken
            )
        } catch { self.error = error.localizedDescription }
        isLoadingConsole = false
    }

    // MARK: - AI

    func explainFailure() async {
        guard let build = selectedBuild, let job = selectedJob,
              !consoleOutput.isEmpty else { return }
        guard claudeService.discoverAPIKey() != nil else {
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
        guard claudeService.discoverAPIKey() != nil else {
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
