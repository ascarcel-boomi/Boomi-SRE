# Boomi SRE App — Phase 7: Preferences & Polish

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state object
- `BoomiSRE/Sources/Views/Panels/SettingsView.swift` — existing settings UI
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation
- `BoomiSRE/Sources/Services/JiraService.swift` — for fetching projects list
- `BoomiSRE/Sources/Services/ConfluenceService.swift` — for fetching spaces list
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry point

**Key constraints:**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Never macOS Keychain (unsigned app).
- Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path `/usr/local/bin/aws` (PATH stripped in .app bundle).
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira/Confluence Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.

---

## Implementation Plan

---

### Phase 7: Preferences & Polish

**Goal:** Let users customize which features are active and configure favorites.

#### 7A. Enhanced Preferences

Extend `SettingsView` with a new "Preferences" tab:

**Sections:**
- **Favorites:**
  - Favorite AWS Accounts (from ~/.aws/config profiles)
  - Favorite Jira Projects (fetched from API)
  - Favorite Confluence Spaces
  - Favorite GitHub Repos
  - Favorite Jenkins Jobs
  - Favorite Grafana Dashboards
- **AI Settings:**
  - Claude model selection (sonnet vs opus for analysis)
  - Max tokens for chat (default 4096)
  - Auto-context toggle (auto-inject relevant data in copilot)
  - Analysis depth (brief / standard / thorough)
- **Notifications:**
  - Enable/disable per notification type
  - macOS notification toggle
  - Background refresh interval
- **Executive Assistant:**
  - Enable/disable per briefing type
  - Schedule times (morning brief, EOD digest)
  - Auto-generate on app launch toggle

#### 7B. Onboarding Wizard

Create a first-launch onboarding flow that:
1. Welcomes the user
2. Runs credential auto-discovery
3. Tests each service connection
4. Lets user pick favorites
5. Configures notification preferences
6. Generates first morning brief
