import SwiftUI

/// Sheet for creating new SOPs using AI assistance and saving them to the Knowledge Base repo.
struct SOPCreatorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var product = ""
    @State private var content = ""
    @State private var showPreview = false

    @State private var isGenerating = false
    @State private var generationError: String?

    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var saveIsError = false

    private let claudeService = ClaudeService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.badge.plus").foregroundStyle(Color.accentColor)
                Text("New Standard Operating Procedure")
                    .font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Title
                    labeledField("SOP Title") {
                        TextField("e.g. Restarting Mashery API Gateway", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Description
                    labeledField("Brief Description") {
                        TextField("What does this SOP cover?", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Product/service
                    labeledField("Product / Service") {
                        TextField("e.g. Mashery, APIM, Redis…", text: $product)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // AI Generate button
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                Task { await generateWithAI() }
                            } label: {
                                Label(isGenerating ? "Generating…" : "Generate with AI", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isGenerating || title.isEmpty)
                            if isGenerating { ProgressView().scaleEffect(0.8) }
                        }
                        if let err = generationError {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.red)
                        }
                        Text("AI will generate a complete SOP based on the title and description. You can then edit the result.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Divider()

                    // Editor / Preview toggle
                    HStack {
                        Text("SOP Content").font(.headline)
                        Spacer()
                        Toggle("Preview", isOn: $showPreview)
                            .toggleStyle(.button)
                            .font(.caption)
                    }

                    if showPreview {
                        // Rendered markdown preview
                        MarkdownView(markdown: content)
                            .frame(minHeight: 200)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                                .fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                                .stroke(Color.secondary.opacity(0.2)))
                    } else {
                        TextEditor(text: $content)
                            .font(.body.monospaced())
                            .frame(minHeight: 300)
                            .border(Color.secondary.opacity(0.3))
                    }

                    Divider()

                    // Actions
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save Options").font(.headline)
                        Text("New SOPs should be reviewed by the team before use. Consider using 'Open PR' to get team review.")
                            .font(.caption).foregroundStyle(.orange)

                        HStack(spacing: 10) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(content, forType: .string)
                                saveMessage = "Copied to clipboard"
                                saveIsError = false
                            } label: {
                                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .disabled(content.isEmpty)

                            Button {
                                Task { await saveToKB(asPR: false) }
                            } label: {
                                Label(isSaving ? "Saving…" : "Save to Knowledge Base", systemImage: "arrow.up.doc")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSaving || content.isEmpty || title.isEmpty)

                            Button {
                                Task { await saveToKB(asPR: true) }
                            } label: {
                                Label(isSaving ? "Creating PR…" : "Open PR", systemImage: "arrow.triangle.branch")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || content.isEmpty || title.isEmpty)

                            if isSaving { ProgressView().scaleEffect(0.8) }
                        }

                        if let msg = saveMessage {
                            HStack {
                                Image(systemName: saveIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                Text(msg).textSelection(.enabled)
                            }
                            .font(.callout)
                            .foregroundStyle(saveIsError ? .red : .green)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill((saveIsError ? Color.red : Color.green).opacity(0.1)))
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 680, minHeight: 600)
    }

    // MARK: - Helpers

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - AI Generation

    private func generateWithAI() async {
        guard claudeService.isAIAvailable else {
            generationError = "No Anthropic API key configured."
            return
        }
        isGenerating = true
        generationError = nil
        let prompt = """
        Generate a Standard Operating Procedure (SOP) for an SRE team.

        Title: \(title)
        Description: \(description.isEmpty ? "(no description provided)" : description)
        Product / Service: \(product.isEmpty ? "(not specified)" : product)

        Use this structure:
        # \(title)

        ## Purpose
        (1-2 sentences on what this SOP covers and when to use it)

        ## Prerequisites
        (checklist of what must be in place before starting)

        ## Procedure
        (Numbered steps with specific commands/actions — include actual CLI commands where applicable)

        ## Verification Steps
        (How to confirm the procedure succeeded)

        ## Rollback Procedure
        (How to undo the changes if something goes wrong)

        ## References
        (Links to related documentation, dashboards, or tickets)

        Be specific and actionable. Include actual commands using code blocks where applicable. Assume the reader is a mid-level SRE.
        """

        do {
            content = try await claudeService.chat(
                messages: [("user", prompt)],
                systemPrompt: "You are an SRE writing a Standard Operating Procedure. Be specific, actionable, and include actual commands. Use Markdown formatting.",
                maxTokens: 2048
            )
        } catch {
            generationError = error.localizedDescription
        }
        isGenerating = false
    }

    // MARK: - Save to GitHub

    private func saveToKB(asPR: Bool) async {
        guard !appState.githubToken.isEmpty else {
            saveMessage = "GitHub token not configured — add it in Settings → GitHub"
            saveIsError = true
            return
        }
        isSaving = true
        saveMessage = nil

        let owner = appState.kbRepoOwner
        let repo  = appState.kbRepoName
        let token = appState.githubToken
        let filename = title
            .lowercased()
            .components(separatedBy: .whitespaces)
            .joined(separator: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let path = "sops/\(filename).md"

        do {
            if asPR {
                // Create branch, push file, create PR
                let branchName = "sop/\(filename)-\(Int(Date().timeIntervalSince1970))"
                try await createBranchAndPR(owner: owner, repo: repo, token: token,
                                             path: path, branchName: branchName)
                saveMessage = "PR created! Check GitHub to review and merge."
                saveIsError = false
            } else {
                // Commit directly to main
                try await commitFile(owner: owner, repo: repo, token: token,
                                      path: path, branch: "main")
                saveMessage = "SOP saved to \(path) on main branch"
                saveIsError = false
            }
        } catch {
            saveMessage = error.localizedDescription
            saveIsError = true
        }
        isSaving = false
    }

    private func commitFile(owner: String, repo: String, token: String,
                             path: String, branch: String) async throws {
        guard let contentData = content.data(using: .utf8) else { return }
        let encoded = contentData.base64EncodedString()

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "PUT"
        req.addBearerAuth(token: token)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "message": "Add SOP: \(title)",
            "content": encoded,
            "branch": branch
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await ZscalerTrustURLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw KBError.httpError(status: code, body: bodyStr)
        }
    }

    private func createBranchAndPR(owner: String, repo: String, token: String,
                                    path: String, branchName: String) async throws {
        // 1. Get HEAD SHA of main
        let refURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/refs/heads/main")!
        var refReq = URLRequest(url: refURL, timeoutInterval: 15)
        refReq.addBearerAuth(token: token)
        refReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (refData, _) = try await ZscalerTrustURLSession.shared.data(for: refReq)
        guard let refJSON = try? JSONSerialization.jsonObject(with: refData) as? [String: Any],
              let obj = refJSON["object"] as? [String: Any],
              let sha = obj["sha"] as? String else {
            throw KBError.invalidResponse
        }

        // 2. Create branch
        let createBranchURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/refs")!
        var branchReq = URLRequest(url: createBranchURL, timeoutInterval: 15)
        branchReq.httpMethod = "POST"
        branchReq.addBearerAuth(token: token)
        branchReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        branchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        branchReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "ref": "refs/heads/\(branchName)", "sha": sha
        ])
        let (_, branchResp) = try await ZscalerTrustURLSession.shared.data(for: branchReq)
        guard let bHttp = branchResp as? HTTPURLResponse, (200...299).contains(bHttp.statusCode) else {
            throw KBError.httpError(status: (branchResp as? HTTPURLResponse)?.statusCode ?? 0, body: "Branch creation failed")
        }

        // 3. Commit file on branch
        try await commitFile(owner: owner, repo: repo, token: token, path: path, branch: branchName)

        // 4. Create PR
        let prURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls")!
        var prReq = URLRequest(url: prURL, timeoutInterval: 15)
        prReq.httpMethod = "POST"
        prReq.addBearerAuth(token: token)
        prReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        prReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        prReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": "Add SOP: \(title)",
            "body": "Adds new SOP: **\(title)**\n\n\(description)\n\n*Generated by Boomi SRE*",
            "head": branchName,
            "base": "main"
        ])
        let (_, prResp) = try await ZscalerTrustURLSession.shared.data(for: prReq)
        guard let pHttp = prResp as? HTTPURLResponse, (200...299).contains(pHttp.statusCode) else {
            throw KBError.httpError(status: (prResp as? HTTPURLResponse)?.statusCode ?? 0, body: "PR creation failed")
        }
    }
}
