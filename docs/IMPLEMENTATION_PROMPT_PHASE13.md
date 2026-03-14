# Boomi SRE App — Phase 13: User Profile

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state, config persistence, credential properties, `importDiscoveredCredentials()`, `checkAllServices()`
- `BoomiSRE/Sources/Services/CredentialDiscovery.swift` — auto-discovers credentials from `~/.kiro/`, `~/.amazonq/`, `~/.aws/`, `~/.gitconfig`
- `BoomiSRE/Sources/Services/JiraService.swift` — `checkAuth()` returns display name
- `BoomiSRE/Sources/Services/GitHubService.swift` — `checkAuth()` returns "Name (@login)"
- `BoomiSRE/Sources/Services/ClaudeService.swift` — system prompts used for AI (to understand where profile data would be injected)
- `BoomiSRE/Sources/ViewModels/ChatViewModel.swift` — AI Copilot context gathering and system prompt construction
- `BoomiSRE/Sources/Views/SettingsView.swift` — existing settings tabs
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar (for profile icon placement)
- `BoomiSRE/Sources/Views/Panels/NotificationCenterView.swift` — notification filtering (to understand where profile filters would apply)

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 13A: User Profile Model

**Goal:** Define a profile model that captures who the user is, auto-discovered from configured services.

**Create `BoomiSRE/Sources/Models/UserProfile.swift`:**

```swift
struct UserProfile: Codable {
    // Auto-discovered (populated from service auth checks)
    var displayName: String          // from Jira, GitHub, or Git config
    var email: String                // from Jira auth or Git config
    var avatarURL: String?           // from Jira or GitHub profile picture
    var githubHandle: String?        // from GitHub auth (/user → login)
    var jiraAccountId: String?       // from Jira /myself
    var timeZone: String             // from system TimeZone.current.identifier

    // User-editable
    var role: SRERole                // dropdown selection
    var experienceLevel: ExperienceLevel  // affects AI tone and feature visibility
    var team: String                 // free text (e.g., "CAM SRE", "Platform Engineering")
    var onCallInfo: String           // free text (e.g., PagerDuty link, Grafana OnCall schedule)
    var notes: String                // free text for anything else

    // Computed
    var firstName: String {
        displayName.components(separatedBy: " ").first ?? displayName
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return "\(timeOfDay), \(firstName)"
    }
}

enum SRERole: String, Codable, CaseIterable {
    case sre = "SRE"
    case seniorSRE = "Senior SRE"
    case devops = "DevOps Engineer"
    case platformEngineer = "Platform Engineer"
    case manager = "Engineering Manager"
    case director = "Director"
    case other = "Other"

    var displayName: String { rawValue }
}

enum ExperienceLevel: String, Codable, CaseIterable {
    case junior = "Junior"
    case mid = "Mid-Level"
    case senior = "Senior"
    case lead = "Lead / Staff"

    var displayName: String { rawValue }

    /// Controls AI response depth
    var analysisDepthHint: String {
        switch self {
        case .junior: return "Explain concepts clearly, avoid jargon, be encouraging and educational. The reader is still learning."
        case .mid: return "Be practical and specific. Assume working knowledge of SRE fundamentals."
        case .senior: return "Be concise and technical. Skip basics, focus on root cause and tradeoffs."
        case .lead: return "Be strategic. Include blast radius, business impact, and cross-team coordination needs."
        }
    }
}
```

**Defaults for new users:** `displayName = ""`, `email = ""`, `role = .sre`, `experienceLevel = .mid`, `team = ""`, `timeZone = TimeZone.current.identifier`

---

### Phase 13B: Profile Auto-Discovery

**Goal:** Populate the profile automatically from configured service auth responses.

**Implementation:**

1. Add `@Published var userProfile: UserProfile` to `AppState`, persisted in `~/.boomi_sre_config.json` alongside existing config fields.

2. Add a `discoverProfile()` method to `AppState` that runs after `checkAllServices()` completes:
   ```swift
   func discoverProfile() async {
       var profile = userProfile

       // From Git config (~/.gitconfig)
       if let gitName = readGitConfig("user.name"), profile.displayName.isEmpty {
           profile.displayName = gitName
       }
       if let gitEmail = readGitConfig("user.email"), profile.email.isEmpty {
           profile.email = gitEmail
       }

       // From Jira auth (if authenticated)
       if case .authenticated(let detail) = jiraAuthStatus {
           // detail is the display name returned by checkAuth
           if profile.displayName.isEmpty { profile.displayName = detail }
       }
       if !jiraEmail.isEmpty && profile.email.isEmpty {
           profile.email = jiraEmail
       }

       // From GitHub auth (if authenticated)
       if case .authenticated(let detail) = githubAuthStatus {
           // detail is "Name (@login)" — parse the handle
           if let match = detail.range(of: #"\(@([^)]+)\)"#, options: .regularExpression) {
               let handle = String(detail[match]).dropFirst(2).dropLast()
               profile.githubHandle = String(handle)
           }
           if profile.displayName.isEmpty {
               profile.displayName = detail.components(separatedBy: " (").first ?? detail
           }
       }

       // Avatar: try GitHub first (public, no auth needed for avatar URL)
       if let handle = profile.githubHandle, profile.avatarURL == nil {
           profile.avatarURL = "https://github.com/\(handle).png?size=128"
       }

       // Time zone: always from system
       profile.timeZone = TimeZone.current.identifier

       userProfile = profile
       saveConfig()
   }
   ```

3. Add a helper to read `~/.gitconfig`:
   ```swift
   private func readGitConfig(_ key: String) -> String? {
       // Parse [user] section from ~/.gitconfig
       let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gitconfig")
       guard let content = try? String(contentsOf: path, encoding: .utf8) else { return nil }
       // Simple INI parser — find the key under [user]
       ...
   }
   ```

4. Call `discoverProfile()` after `checkAllServices()` completes in `BoomiSREApp.swift` onAppear. Only overwrite empty fields — never clobber user-edited values.

---

### Phase 13C: Profile View

**Goal:** A view where the user can see and edit their profile.

**Create `BoomiSRE/Sources/Views/Panels/ProfileView.swift`:**

**Layout:**

1. **Header section:**
   - Avatar image (loaded from `avatarURL` via `AsyncImage`, with a person.circle fallback)
   - Display name (large, bold)
   - Email (secondary)
   - Role badge + Experience level badge (colored capsules)

2. **Auto-discovered info (read-only, with refresh button):**
   - GitHub: `@handle` with link to profile
   - Jira: account status
   - Time zone: e.g., "America/New_York (EDT)"
   - A "Re-discover" button that re-runs `discoverProfile()`

3. **Editable fields:**
   - Display Name: text field (overrides auto-discovered)
   - Email: text field
   - Role: picker (SRERole cases)
   - Experience Level: picker (ExperienceLevel cases) with a description below explaining what each level means for AI interactions:
     - Junior: "AI will explain concepts and be educational"
     - Mid: "AI will be practical and specific"
     - Senior: "AI will be concise and technical"
     - Lead: "AI will include strategic and cross-team context"
   - Team: text field
   - On-Call Info: text field (placeholder: "PagerDuty link, Grafana OnCall schedule, etc.")
   - Notes: text editor (3-4 lines)

4. **Save button** at the bottom that calls `appState.saveConfig()`.

**Access points:**
- Sidebar: Add a small avatar/profile button next to the "Boomi SRE" navigation title at the top of the sidebar. Clicking it navigates to ProfileView.
- Settings: Add a "Profile" tab as the first tab in SettingsView (before Preferences).
- The profile should also be accessible from a user icon in the toolbar (if customizable toolbar from Phase 12C is implemented).

---

### Phase 13D: Profile Integration — AI System Prompts

**Goal:** Inject the user's profile into AI system prompts so Claude tailors responses to the user's experience level and role.

**Implementation:**

1. **Update `ChatViewModel`'s system prompt** (in `send()` or wherever the system prompt is built) to include profile context:
   ```
   You are an SRE copilot for {profile.displayName}, a {profile.role.displayName}
   on the {profile.team} team ({profile.experienceLevel.displayName} level).
   {profile.experienceLevel.analysisDepthHint}
   ```

2. **Update `IncidentViewModel`'s `incidentSystemPrompt`** to include:
   ```
   The user is {profile.displayName}, a {profile.experienceLevel.displayName}
   {profile.role.displayName}.
   {profile.experienceLevel.analysisDepthHint}
   ```

3. **Update ALL AI analysis methods** across ViewModels (GitHubBrowserViewModel, GrafanaBrowserViewModel, ConfluenceBrowserViewModel, JenkinsBrowserViewModel, CostExplorerViewModel, TicketDetailViewModel) to include the experience level hint in their system prompts. This is a simple string injection — find each `systemPrompt:` parameter and append the `analysisDepthHint`.

4. **Pass `appState` (or just the profile)** to view models that don't currently have access to it. The simplest approach: pass `appState.userProfile.experienceLevel.analysisDepthHint` as a parameter to the AI analysis methods.

---

### Phase 13E: Profile Integration — Dashboard Greeting & Contextual UI

**Goal:** Use the profile throughout the app for personalization.

**Implementation:**

1. **Dashboard greeting:** If `DashboardView` exists (from Phase 8B), replace the static "Good morning" with `appState.userProfile.greeting`. If no dashboard yet, update `WelcomeView` to use it.

2. **"Explain this to me" button visibility:**
   - For `.junior` experience level: always show "Explain" buttons prominently on every section header (AWS Health, Grafana dashboards, Jenkins builds, etc.)
   - For `.mid` level: show "Explain" buttons but smaller/secondary
   - For `.senior` and `.lead` levels: hide "Explain" buttons by default, but make them available in context menus (right-click → "Explain this to me")
   - Add a computed property: `appState.userProfile.experienceLevel.showExplainProminently: Bool`

3. **Notification filtering hint:** In the Notification Center, if the user has `favoriteJiraProjects` set, show a subtle note: "Showing notifications for your projects: CAMSRE, SRE. Change in Profile."

4. **Onboarding Wizard update:** Add a "Profile" step to the onboarding wizard (between "Test Connections" and "Ready") where the user sets their role and experience level. Pre-populate name and email from auto-discovery.

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** All existing AI analysis, notifications, and service connections must continue to work.
- **Default profile:** If the user never sets up a profile, everything should still work — use sensible defaults (displayName = "", experienceLevel = .mid, role = .sre). AI prompts should gracefully handle empty profile fields (don't inject "You are , a SRE").
- **Dark mode:** All views must support both light and dark macOS appearances.
- **Commit after each phase** (13A, 13B, 13C, 13D, 13E) with a descriptive commit message.
