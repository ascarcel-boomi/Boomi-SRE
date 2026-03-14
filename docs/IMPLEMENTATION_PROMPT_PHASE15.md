# Boomi SRE App — Phase 15: Code Quality, Distribution & Auto-Update

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services. The codebase is ~27,000 lines of Swift across Sources/ViewModels/, Sources/Services/, Sources/Views/, Sources/Models/, and Tests/.

**Read these files first:**
- `Package.swift` — SPM manifest (no external dependencies currently)
- `build_app.sh` — current build script (builds release binary, creates .app bundle at /Applications)
- `README.md` — current documentation
- `BoomiSRE/Sources/Models/AppState.swift` — central state, config persistence
- `BoomiSRE/Sources/Models/ReportItem.swift` — report catalog
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry point
- `BoomiSRE/Sources/Views/ContentView.swift` — navigation routing
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — secrets storage
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI integration
- Then skim ALL other files in Sources/ to understand the full codebase before making changes.

**Key constraints:**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path from `AWSAuthService.resolvedAWSPath`.
- The app is unsigned (no Apple Developer certificate). Distribution is direct .dmg, not App Store.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

**Important: This is an optimization and infrastructure pass.** Do not add new user-facing features. Do not change functionality. The app should behave identically before and after, just faster, cleaner, and distributable.

---

### Phase 15A: Code Audit & DRY Refactoring

**Goal:** Scan the entire codebase for repeated patterns, duplicated code, and opportunities to consolidate. Make the code DRY without changing behavior.

**Audit checklist — read every file and look for:**

1. **Duplicated HTTP request patterns:**
   - Multiple services (JiraService, GitHubService, ConfluenceService, GrafanaService, JenkinsService, BitbucketService) likely have similar boilerplate: URL construction, auth header injection, response validation, JSON parsing.
   - If 3+ services share the same pattern, extract a shared helper. For example:
     ```swift
     enum HTTPHelper {
         static func get(url: URL, headers: [String: String], timeout: TimeInterval = 20) async throws -> (Data, HTTPURLResponse)
         static func post(url: URL, headers: [String: String], body: Data?, timeout: TimeInterval = 20) async throws -> (Data, HTTPURLResponse)
         static func validateResponse(_ response: HTTPURLResponse, data: Data, service: String) throws
     }
     ```
   - Each service still owns its own auth logic (Basic vs Bearer vs API key), but the HTTP plumbing is shared.

2. **Duplicated auth header construction:**
   - Basic auth (`email:token` → base64) appears in JiraService, ConfluenceService, BitbucketService.
   - Bearer token auth appears in GitHubService, GrafanaService, GoogleService.
   - Extract `URLRequest` extensions:
     ```swift
     extension URLRequest {
         mutating func addBasicAuth(email: String, token: String)
         mutating func addBearerAuth(token: String)
     }
     ```
   - Check if `addBasicAuth` already exists (it was in ConfluenceService as a private extension). If so, move it to a shared location.

3. **Duplicated AI analysis patterns:**
   - Multiple ViewModels (GitHubBrowserViewModel, GrafanaBrowserViewModel, ConfluenceBrowserViewModel, JenkinsBrowserViewModel, CostExplorerViewModel, TicketDetailViewModel, IncidentViewModel) all have the same pattern:
     ```swift
     isAnalyzing = true; aiError = nil; aiOutput = nil
     do { aiOutput = try await claudeService.chat(...) }
     catch { aiError = error.localizedDescription }
     isAnalyzing = false
     ```
   - If the pattern is identical in 4+ places, extract a helper method or protocol:
     ```swift
     protocol AIAnalyzable: ObservableObject {
         var aiAnalysis: String? { get set }
         var isAnalyzing: Bool { get set }
         var aiError: String? { get set }
     }
     extension AIAnalyzable {
         @MainActor
         func runAIAnalysis(using claude: ClaudeService, messages: [(String, String)], systemPrompt: String, maxTokens: Int) async { ... }
     }
     ```

4. **Duplicated view patterns:**
   - HSplitView list+detail pattern appears in GitHubBrowserView, GrafanaBrowserView, ConfluenceBrowserView, JenkinsBrowserView, IncidentCommandView. If the structure is identical (left list, right detail, loading/empty/error states), extract shared components.
   - Loading state views: "Loading..." with ProgressView appears in many places. If identical, extract `LoadingView(message:)`.
   - Empty state views: icon + message + optional action button appears in many places. Extract `EmptyStateView(icon:message:action:)`.
   - Error banners: `Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)` appears repeatedly. Extract `ErrorBanner(message:)`.

5. **Duplicated date formatting:**
   - Multiple places create `DateFormatter` instances inline. Extract shared formatters as static constants (DateFormatter is expensive to create):
     ```swift
     enum Formatters {
         static let shortDate: DateFormatter = { let f = DateFormatter(); f.dateStyle = .short; return f }()
         static let relativeDate: RelativeDateTimeFormatter = { let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f }()
     }
     ```

6. **Duplicated AWS CLI Process construction:**
   - `AWSCostService` and `AWSAuthService` both construct `Process` objects with PATH augmentation, pipe setup, etc. If the pattern is the same, extract:
     ```swift
     enum AWSCLIRunner {
         static func run(arguments: [String], profile: String?, timeout: TimeInterval = 30) async throws -> Data
     }
     ```

7. **Large files that should be split:**
   - If any single file is >500 lines, consider splitting it. Common candidates: AppState.swift (model + persistence + health checks), SettingsView.swift (one tab per section could be separate files).

8. **Unused code:**
   - Search for functions/methods that are never called. Remove dead code.
   - Search for imports that are unused. Remove them.
   - Search for commented-out code blocks. Remove them.

**Rules for this phase:**
- Do NOT change any public API or behavior.
- Do NOT rename files that other code imports.
- Run `swift build` after each refactoring step to ensure nothing broke.
- Commit logical groups of changes separately (e.g., "Extract shared HTTP helper", "Consolidate date formatters", "Remove dead code").

---

### Phase 15B: Performance Optimization

**Goal:** Make the app faster and more memory-efficient.

**Audit and optimize:**

1. **View body recomputation:**
   - Look for views that pass `@EnvironmentObject` or `@ObservedObject` where they only need one or two properties. This causes the entire view to recompute when any property changes.
   - Where practical, pass specific values instead of entire objects, or use `@ObservedObject` with a focused ViewModel instead of a monolithic AppState.

2. **Lazy loading:**
   - Verify all lists use `LazyVStack` or `LazyVGrid` instead of `VStack`/`VGrid` for large datasets.
   - Verify `ForEach` in `List` doesn't have expensive computed properties in the row view.

3. **Image caching:**
   - If `AsyncImage` is used (for avatars, etc.), verify it has a cache policy. SwiftUI's `AsyncImage` caches by default, but verify.

4. **Reduce redundant API calls:**
   - Check if views call their fetch methods on every `.onAppear`. If the data hasn't changed (e.g., sidebar nav back and forth), the view shouldn't re-fetch. Add staleness checks: only re-fetch if data is older than N seconds.
   - Pattern:
     ```swift
     .onAppear {
         if vm.data.isEmpty || vm.lastFetched.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
             Task { await vm.fetch() }
         }
     }
     ```

5. **JSON parsing efficiency:**
   - The codebase uses `JSONSerialization` (manual dictionary parsing) in many services. This is fine for flexibility but verify there are no `try!` force-unwraps or redundant re-parsing of the same data.
   - If any model is parsed from JSON in more than one place, consolidate to a single parse function.

6. **Process/CLI efficiency:**
   - AWS CLI calls spawn a new Process each time. Verify that processes are properly cleaned up (no zombie processes). Check that `waitUntilExit()` is always called after `run()`.
   - Verify pipes are read BEFORE `waitUntilExit()` to prevent deadlocks on large output (the existing code should already do this — verify it's consistent everywhere).

7. **Concurrency:**
   - Verify `TaskGroup` is used where multiple independent fetches happen (e.g., dashboard widgets, health checks).
   - Verify no `Task { }` blocks are leaked without cancellation support.

---

### Phase 15C: Security Hardening

**Goal:** Ensure no secrets can leak and the app follows security best practices.

**Audit:**

1. **Secrets in source code:**
   - Grep the entire codebase for patterns: hardcoded tokens, API keys, passwords, URLs with credentials.
   - Patterns to search: `sk-ant-`, `ghp_`, `glpat-`, `xoxb-`, `xoxp-`, `AKIA`, `password`, `secret`, any base64-encoded strings that look like credentials.
   - If anything is found, remove it and ensure it's loaded from `~/.boomi_sre_secrets.json` or environment variables at runtime.

2. **Secrets in git history:**
   - Run `git log --all --oneline -20` to check recent commits. If any commit message suggests credentials were committed, flag it (don't rewrite history — just flag for the user).

3. **`.gitignore` completeness:**
   - Verify `.gitignore` includes: `*.json` (for config/secrets), `.build/`, `.swiftpm/`, `*.app`, `*.dmg`, `.DS_Store`, `*.xcodeproj`, `xcuserdata/`.
   - Verify `~/.boomi_sre_secrets.json` would never be committed (it's in the home directory, not the repo, so it shouldn't be — but verify no copies exist in the repo).

4. **File permissions:**
   - Verify `KeychainHelper.save()` always sets chmod 600 on `~/.boomi_sre_secrets.json`. It does — just verify.
   - Verify config file (`~/.boomi_sre_config.json`) doesn't contain secrets. It shouldn't — API tokens are in secrets.json. Verify no token/password fields leaked into the config persistence.

5. **Network security:**
   - Verify all HTTP calls use HTTPS (no plain HTTP URLs).
   - Verify no SSL certificate validation is disabled (no `URLSessionDelegate` that accepts all certs).

6. **AI prompt injection:**
   - Verify that user-supplied data sent to Claude (ticket summaries, PR descriptions, page content) is framed as "user content" not injected into the system prompt. The existing pattern (sending user data as the `user` message, not interpolated into the `system` prompt) should be correct — verify.

---

### Phase 15D: DMG Distribution

**Goal:** Create a `.dmg` installer so the app can be distributed as a standard macOS download.

**Implementation:**

1. **Update `build_app.sh`** to add a DMG creation step at the end:
   ```bash
   # After building the .app bundle...

   DMG_NAME="Boomi-SRE-${VERSION}.dmg"
   DMG_PATH="$(pwd)/dist/${DMG_NAME}"
   STAGING_DIR=$(mktemp -d)

   mkdir -p dist

   # Copy app to staging
   cp -R "/Applications/Boomi SRE.app" "${STAGING_DIR}/"

   # Create symlink to /Applications for drag-and-drop install
   ln -s /Applications "${STAGING_DIR}/Applications"

   # Create DMG
   hdiutil create -volname "Boomi SRE" \
       -srcfolder "${STAGING_DIR}" \
       -ov -format UDZO \
       "${DMG_PATH}"

   # Clean up
   rm -rf "${STAGING_DIR}"

   echo "DMG created at: ${DMG_PATH}"
   ```

2. **Create a `dist/` directory** for build artifacts. Add `dist/` to `.gitignore`.

3. **Add a background image for the DMG** (optional but professional):
   - Create a simple 600×400 PNG with the app name and an arrow pointing from the app icon to the Applications folder.
   - Or skip the background and just use the default DMG layout — the symlink to /Applications is the key part.

4. **Update README.md** with installation instructions:
   ```markdown
   ## Installation

   ### From DMG (recommended)
   1. Download the latest `Boomi-SRE-*.dmg` from [Releases](https://github.com/ascarcel-boomi/Boomi-SRE/releases)
   2. Open the DMG
   3. Drag "Boomi SRE" to the Applications folder
   4. Open "Boomi SRE" from Applications
   5. On first launch, macOS may warn about an unidentified developer — right-click → Open to bypass

   ### From Source
   ```bash
   git clone https://github.com/ascarcel-boomi/Boomi-SRE.git
   cd Boomi-SRE
   bash build_app.sh
   open -a "Boomi SRE"
   ```
   ```

5. **Create a GitHub Release workflow** (optional — a simple script):
   ```bash
   # release.sh
   #!/bin/bash
   set -e
   VERSION=$(date +"%y.%m.%d")
   bash build_app.sh
   gh release create "v${VERSION}" "dist/Boomi-SRE-${VERSION}.dmg" \
       --title "Boomi SRE v${VERSION}" \
       --notes "Release v${VERSION}"
   echo "Release v${VERSION} published."
   ```

---

### Phase 15E: Auto-Update System

**Goal:** The app should check for new versions on GitHub Releases and prompt the user to update.

**Implementation:**

1. **Create `BoomiSRE/Sources/Services/UpdateService.swift`:**
   ```swift
   actor UpdateService {
       struct Release: Sendable {
           let version: String      // tag name, e.g., "v26.03.14"
           let name: String         // release title
           let body: String         // release notes (markdown)
           let dmgURL: String       // download URL for the .dmg asset
           let publishedAt: String
       }

       /// Check GitHub Releases for a newer version.
       func checkForUpdate(currentVersion: String) async throws -> Release? {
           // GET https://api.github.com/repos/ascarcel-boomi/Boomi-SRE/releases/latest
           // No auth needed — public repo (or use GitHub token if private)
           // Compare tag version with currentVersion
           // Return Release if newer, nil if current
       }

       /// Download the DMG to a temporary location.
       func downloadUpdate(dmgURL: String) async throws -> URL {
           // Download to NSTemporaryDirectory()
           // Show progress via a callback or @Published property
           // Return the local file URL
       }

       /// Mount the DMG, copy the .app to /Applications, and restart.
       func applyUpdate(dmgPath: URL) async throws {
           // 1. Mount DMG: hdiutil attach {path} -nobrowse -quiet
           // 2. Find .app in mounted volume: /Volumes/Boomi SRE/Boomi SRE.app
           // 3. Copy to /Applications: cp -R (replace existing)
           // 4. Unmount: hdiutil detach /Volumes/Boomi\ SRE
           // 5. Relaunch: NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Boomi SRE.app"))
           // 6. Exit current process: exit(0)
           // Note: Step 3 may fail if the app is running from /Applications.
           //   Workaround: copy to a temp location, then use a shell script to
           //   wait for the app to exit, replace the .app, and relaunch.
       }
   }
   ```

2. **Version comparison:**
   - The current version is embedded in `Info.plist` as `CFBundleShortVersionString` (format: `YY.MM.DD-HHMMSS`).
   - Read it at runtime: `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"`
   - Compare with the GitHub release tag (strip the "v" prefix). Simple string comparison works if the format is consistent (`YY.MM.DD` sorts lexicographically).

3. **Create `BoomiSRE/Sources/ViewModels/UpdateViewModel.swift`:**
   ```swift
   @MainActor
   final class UpdateViewModel: ObservableObject {
       @Published var availableUpdate: UpdateService.Release?
       @Published var isChecking = false
       @Published var isDownloading = false
       @Published var downloadProgress: Double = 0  // 0.0 to 1.0
       @Published var isApplying = false
       @Published var error: String?
       @Published var lastChecked: Date?

       func checkForUpdate() async { ... }
       func downloadAndApply() async { ... }
   }
   ```

4. **Auto-check on launch:**
   - In `BoomiSREApp.swift`, check for updates 10 seconds after launch (don't block startup).
   - Check again every 24 hours while the app is running.
   - Store `lastUpdateCheck: Date` in AppState to avoid checking too frequently.

5. **Update UI — Settings:**
   - In Settings → "Advanced" tab (or "About" section):
     - Current version display
     - "Check for Updates" button
     - If update available: show version, release notes, "Download & Install" button with progress bar
     - "Check automatically on launch" toggle (default: on)

6. **Update UI — Notification:**
   - When an update is found, create an in-app notification:
     - Type: new `NotificationType.appUpdate` case
     - Title: "Boomi SRE v{version} available"
     - Body: first line of release notes
     - High priority: NO
     - Action: navigates to Settings → About or shows the update sheet
   - Add `appUpdate` to `NotificationModels.swift` with icon `arrow.down.circle.fill`, color `.accentColor`.

7. **Update banner:**
   - When an update is available, show a subtle banner at the top of the main window (above the breadcrumbs, below the toolbar):
     ```
     [↓] Boomi SRE v26.03.15 is available.  [Release Notes]  [Update Now]  [Dismiss]
     ```
   - Accent-colored background, dismissable. Reappears on next app launch if dismissed.

8. **The update-and-restart flow:**
   The tricky part is replacing the running app. The safest approach:
   ```bash
   # Write a tiny shell script to /tmp/boomi_sre_update.sh:
   #!/bin/bash
   sleep 2  # Wait for app to exit
   cp -R "$1" "/Applications/Boomi SRE.app"
   open -a "Boomi SRE"
   rm "$0"  # Self-delete
   ```
   - The app writes this script, makes it executable, launches it as a background Process, then calls `NSApp.terminate(nil)`.
   - The script waits 2 seconds, copies the new .app from the mounted DMG (or temp location), and relaunches.

---

### Phase 15F: Update README.md

**Goal:** Bring the README up to date with all features implemented through Phase 15.

**The README should include:**

1. **Header:** App name, one-line description, screenshot (if available)

2. **Features list** (organized by section, matching the sidebar):
   - AI: Copilot Chat, Executive Assistant, Incident Command, Notifications
   - Jira: My TODO, Saved Filters, Boards, Ticket Detail with AI Analysis
   - AWS: Infrastructure Health, Cost Explorer
   - Google: Gmail, Calendar, Chat
   - Services: GitHub Browser, Jenkins Browser, Grafana Browser, Confluence Browser
   - Other: Customizable Dashboard, User Profile, Auto-Updates

3. **Installation:**
   - From DMG (recommended)
   - From source (`git clone` + `build_app.sh`)

4. **Configuration:**
   - First-run onboarding wizard
   - Auto-discovery of credentials
   - Supported services and how to configure each

5. **Architecture:**
   - SwiftUI MVVM + actor-based services
   - No third-party dependencies
   - File-based credential storage (chmod 600)
   - AWS CLI integration via Process

6. **Development:**
   - Prerequisites: macOS 15+, Swift 6.2
   - Build: `swift build`
   - Test: `swift test`
   - Release: `bash build_app.sh` + `bash release.sh`

7. **Contributing:**
   - Submit feature requests from within the app or via GitHub Issues

8. **License** (if applicable)

**Important:** Only document features that actually exist in the codebase. Read the current source to verify what's been implemented before writing the README. Do not document planned/future features as if they exist.

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Do NOT change functionality.** The app should behave identically after optimization. No new features (except the update system in 15E).
- **Do NOT remove features.** Only remove dead/unreachable code.
- **Test before committing.** After refactoring, verify the app still builds and the major code paths are intact.
- **Commit after each phase** (15A, 15B, 15C, 15D, 15E, 15F) with a descriptive commit message.
- **Take your time on 15A.** Read every single file before making changes. Understand the codebase holistically before refactoring. Bad refactoring is worse than duplication.
