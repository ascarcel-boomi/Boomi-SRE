# CLAUDE.md — Boomi SRE macOS App

## What This Is

A native macOS SwiftUI desktop app (~150 files, ~44K lines) for Boomi's APIM SRE team. It provides a unified dashboard for Jira, AWS, GitHub, Bitbucket, Jenkins, Grafana, Confluence, Gmail, and an AI Copilot — all behind a corporate Zscaler SSL proxy.

## Build Commands

```bash
swift build                    # Debug build (SPM, no Xcode required)
swift build -c release         # Release build
bash build_app.sh              # Build + package as .app bundle in /Applications
bash release.sh                # Build + DMG + GitHub release via `gh`
swift test                     # Run tests (requires Xcode CLT Testing framework)
```

- **Swift 5.9 tools-version**, targets **macOS 15.0**
- Swift Package Manager only — no `.xcodeproj` / `.xcworkspace`
- Package.swift is at the repo root; sources are in `BoomiSRE/Sources/`

## Architecture

**MVVM + actor services**, single-window NavigationSplitView-style layout:

```
BoomiSREApp (@main)
  └─ ContentView
       ├─ SidebarView (7 sections: Home, Alerts, Incidents, My Work, Infra, Knowledge, Communicate)
       ├─ BreadcrumbView
       └─ Detail pane (switch on selectedSidebarItem)
            ├─ DashboardView (Home — feed + widgets)
            ├─ AlertsOnCallPanel
            ├─ IncidentCommandView
            ├─ MyWorkPanel
            ├─ InfrastructurePanel
            ├─ KnowledgeToolsPanel
            └─ CommunicatePanel
```

### Layer responsibilities

| Layer | Path | Pattern |
|-------|------|---------|
| **App entry** | `BoomiSREApp.swift` | `@main`, creates `@StateObject` VMs, injects via `.environmentObject()` |
| **Models** | `Models/` | Plain structs, `Codable`, `Identifiable`. `AppState` is the central `ObservableObject` |
| **Services** | `Services/` | `actor` or `class` singletons. All HTTP via `ZscalerTrustURLSession.shared` |
| **ViewModels** | `ViewModels/` | `@MainActor ObservableObject` classes. Own loading/error/empty state |
| **Views** | `Views/Panels/` | SwiftUI views. Use `ViewStyles.swift` design tokens |
| **Extensions** | `Extensions/` | `ViewStyles`, `Formatters`, `AWSCLIRunner`, `AIAnalyzable`, `URLRequestExtensions` |
| **Bridge** | `Bridge/` | `PythonBridge` + `OutputParser` for legacy Python script integration |

### Key shared types

- **`AppState`** — Central `ObservableObject` with all navigation, config, auth status, product context. Injected as `@EnvironmentObject` everywhere.
- **`ProductContext`** — Multi-product filter system. `activeProductIds: Set<String>` (empty = all). Every service query filters by active products.
- **`ProductResourceMap`** — Maps products to their Jira projects, GitHub repos, Jenkins jobs, etc. AI-assisted discovery with confirm/reject workflow.
- **`ReportItem`** — Navigation target for deep-linking into panels/sub-tabs.
- **`ServiceError`** — Shared error enum for API failures.

### Navigation model

Flat 7-item sidebar (`selectedSidebarItem`). Each sidebar section is a "hub panel" that contains sub-tabs. Deep linking uses `appState.navigate(to: reportId)` which sets `pendingTabId` + `selectedSidebarItem`. Panels consume `pendingTabId` in `onAppear`.

## Key Patterns

### ZscalerTrustURLSession

**All HTTP calls MUST use `ZscalerTrustURLSession.shared`** — never `URLSession.shared`. The corporate Zscaler proxy does SSL inspection; this custom session trusts the Zscaler root CA. Defined in `Services/ZscalerTrustURLSession.swift`.

### Product-filter-first

Every data-fetching VM should filter by `appState.activeProductIds`. Use `appState.activeJiraProjectKeys`, `appState.activeGitHubRepos`, etc. to get the union of resources for active products.

### ViewStyles design system

All views should use the tokens from `Extensions/ViewStyles.swift`:
- `DesignTokens.cornerRadius`, `.cardPadding`, `.sectionPadding`, `.panelPadding`
- `.cardStyle()` modifier — rounded background + subtle border
- `.sectionCard()` modifier — fill-only, no border, for ScrollView sections
- `PillBadge` / `CompactBadge` — status pills
- `AIAnalysisBox` — purple-bordered AI analysis container
- `SectionHeaderLabel` — consistent section headers
- `PanelHeader` — top bar of detail panes
- `BrowserSidebarHeader` — sidebar pane headers for browser views

### BoomiTheme

`BoomiColors` provides brand colors. `AppState` extensions (`themeAccent`, `themeSuccess`, etc.) return themed or system colors based on `appTheme`.

### Actor services

Services that do network I/O are either `actor` types or classes with internal serial dispatch. They return Swift `Result` or throw. VMs catch errors and set `@Published var errorMessage: String?`.

### Auth status

`AppState` tracks auth for every service (`awsAuthStatus`, `jiraAuthStatus`, etc.) as `AuthStatus` enum: `.authenticated`, `.expired`, `.checking`, `.notConfigured`, `.error`, `.unknown`. `checkAllServices()` runs all checks on launch.

## Gotchas

### Jira API: GET not POST
Jira Cloud's search endpoint is `GET /rest/api/3/search/jql?jql=...` — NOT POST. The MCP tools may differ, but direct API calls in `JiraService` must use GET.

### AWS CLI absolute path
The `.app` bundle strips `PATH`. Always use `/usr/local/bin/aws` (via `AWSCLIRunner`). Never assume `aws` is in PATH.

### @StateObject in switch cases
SwiftUI destroys and recreates views in `switch` branches. If a view uses `@StateObject`, it will be re-initialized on every switch. VMs that need persistence across navigation are created in `BoomiSREApp` and injected as `@EnvironmentObject`.

### SourceKit false positives
SourceKit may report false errors in complex generic SwiftUI views. Always verify with `swift build` — if it compiles, SourceKit warnings can be ignored.

### Force unwraps
`Color(hex:)` in `BoomiTheme.swift` uses a known-safe pattern. Other force unwraps should be treated as bugs.

### Config persistence
`AppState.saveConfig()` writes to `~/.boomi_sre_config.json`. Call it after any user-facing config change. The file is loaded in `AppState.init()`.

## File Structure

```
BoomiSRE/
  Sources/
    BoomiSREApp.swift              # @main entry point
    ContentView.swift              # Root view with sidebar + detail
    Bridge/                        # Python bridge (legacy)
    Extensions/
      AIAnalyzable.swift           # Protocol for AI-analyzable content
      AWSCLIRunner.swift           # AWS CLI subprocess wrapper
      Formatters.swift             # Date/number formatters
      URLRequestExtensions.swift   # Request helpers
      ViewStyles.swift             # Design tokens + shared view modifiers
    Models/                        # 26 model files (AppState, Jira, Chat, Incident, SLO, etc.)
    Services/                      # 21 service files (Jira, AWS, GitHub, Jenkins, Grafana, etc.)
    ViewModels/                    # 25 VM files (one per panel/feature)
    Views/
      SidebarView.swift
      BreadcrumbView.swift
      DashboardView.swift
      FeedView.swift
      OnboardingWizardView.swift
      WelcomeView.swift
      AboutView.swift
      APIKeyGuideView.swift
      SettingsView.swift
      Charts/                      # ReportChartView
      Panels/                      # 42 panel views
      Settings/                    # 6 settings content views
      Shared/                      # AIBar, JiraIssueTableView, MarkdownView, MOTDView, etc.
      Widgets/                     # WidgetViews
    Resources/
      default_product_maps.json    # Bundled product-to-resource mappings
Package.swift                      # SPM manifest (swift-tools-version: 5.9, macOS 15)
build_app.sh                       # Build + .app bundle
release.sh                         # Build + DMG + GitHub release
```
