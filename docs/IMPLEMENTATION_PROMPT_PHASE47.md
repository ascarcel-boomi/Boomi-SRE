# Boomi SRE App — Phase 47: Simplified Sidebar

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. This is Phase C of the v2 evolution (see `docs/VISION_V2.md`).

**Read these files first:**
- `docs/VISION_V2.md` — the simplified sidebar section
- `BoomiSRE/Sources/Models/ReportItem.swift` — `ReportSection` enum (8 sections), `ReportCatalog` (19 items)
- `BoomiSRE/Sources/Views/SidebarView.swift` — current sidebar rendering
- `BoomiSRE/Sources/Views/ContentView.swift` — detail pane routing
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — CommandMenu structure

---

## Goal

The sidebar currently has **8 collapsible sections with 19 items**. This is overwhelming. An SRE opening the app for the first time doesn't know where to look. The feed (Phase 46) is now the primary view — the sidebar should be a **flat, compact fallback** for when the SRE needs to deep-dive into a specific area.

**New sidebar structure — 7 flat items plus Settings:**

```
🏠 Home
🔔 Alerts & On-Call
🚨 Incidents
📋 My Work
🏗️ Infrastructure
📚 Knowledge & Tools
💬 Communicate
──────────
⚙️ Settings
```

Each item opens a **combined view** that consolidates what used to be separate sections. This cuts 19 clicks down to 7.

---

## Implementation

### Phase 47A: Redefine Sidebar Sections

**Replace the 8-section `ReportSection` enum** with a new simplified enum:

```swift
enum ReportSection: String, CaseIterable {
    case home              = "Home"
    case alertsOnCall      = "Alerts & On-Call"
    case incidents         = "Incidents"
    case myWork            = "My Work"
    case infrastructure    = "Infrastructure & DevOps"
    case knowledge         = "Knowledge & Tools"
    case communicate       = "Communicate"

    var icon: String {
        switch self {
        case .home:            return "house"
        case .alertsOnCall:    return "bell.badge"
        case .incidents:       return "exclamationmark.shield"
        case .myWork:          return "checklist.checked"
        case .infrastructure:  return "server.rack"
        case .knowledge:       return "books.vertical"
        case .communicate:     return "bubble.left.and.bubble.right"
        }
    }
}
```

### Phase 47B: Create Combined Views for Each Section

Each sidebar item opens a **combined view** with tabs for the sub-features that used to be separate sidebar items.

#### "Alerts & On-Call" — combines: On-Call, JSM Ops Alerts, Grafana Alerts, Notifications

Create `BoomiSRE/Sources/Views/Panels/AlertsOnCallView.swift`:

```swift
struct AlertsOnCallView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("", selection: $selectedTab) {
                Text("On-Call").tag(0)
                Text("JSM Alerts").tag(1)
                Text("Grafana").tag(2)
                Text("Notifications").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            // Content
            switch selectedTab {
            case 0: OnCallView()
            case 1: // JSM Alerts content — reuse the alerts section from OnCallView
                    OnCallView()  // Or extract the alerts portion into its own view
            case 2: GrafanaBrowserView()
            case 3: NotificationCenterView()
            default: EmptyView()
            }
        }
    }
}
```

#### "My Work" — combines: My TODO, Saved Filters, Boards, GitHub PRs, Jenkins Builds

Create `BoomiSRE/Sources/Views/Panels/MyWorkView.swift`:

```swift
struct MyWorkView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Tickets").tag(0)
                Text("Filters").tag(1)
                Text("Boards").tag(2)
                Text("PRs").tag(3)
                Text("Builds").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case 0: TodoDashboardView()
            case 1: SavedFiltersView()
            case 2: BoardsView()
            case 3: GitHubBrowserView()
            case 4: JenkinsBrowserView()
            default: EmptyView()
            }
        }
    }
}
```

#### "Infrastructure & DevOps" — combines: AWS Health, AWS Costs, Bitbucket

Create `BoomiSRE/Sources/Views/Panels/InfrastructureView.swift`:

```swift
struct InfrastructureView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("AWS Health").tag(0)
                Text("AWS Costs").tag(1)
                Text("Bitbucket").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case 0: AWSHealthView()
            case 1: CostExplorerView()
            case 2: BitbucketBrowserView()
            default: EmptyView()
            }
        }
    }
}
```

#### "Knowledge & Tools" — combines: Knowledge Base, Confluence, AI Copilot, Executive Assistant

Create `BoomiSRE/Sources/Views/Panels/KnowledgeToolsView.swift`:

```swift
struct KnowledgeToolsView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Knowledge Base").tag(0)
                Text("Confluence").tag(1)
                Text("AI Copilot").tag(2)
                Text("Exec Assistant").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case 0: KnowledgeBaseView()
            case 1: ConfluenceBrowserView()
            case 2: CopilotChatView()
            case 3: ExecAssistantView()
            default: EmptyView()
            }
        }
    }
}
```

#### "Communicate" — combines: Gmail, Calendar, Chat

Create `BoomiSRE/Sources/Views/Panels/CommunicateView.swift`:

```swift
struct CommunicateView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Gmail").tag(0)
                Text("Calendar").tag(1)
                Text("Chat").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case 0: GmailView()
            case 1: CalendarView()
            case 2: ChatView()
            default: EmptyView()
            }
        }
    }
}
```

### Phase 47C: Rewrite the Sidebar

Replace the current multi-section sidebar with a **flat list** of 7 items:

```swift
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel

    enum SidebarItem: String, CaseIterable, Identifiable {
        case home            = "Home"
        case alertsOnCall    = "Alerts & On-Call"
        case incidents       = "Incidents"
        case myWork          = "My Work"
        case infrastructure  = "Infrastructure"
        case knowledge       = "Knowledge & Tools"
        case communicate     = "Communicate"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home:           return "house"
            case .alertsOnCall:   return "bell.badge"
            case .incidents:      return "exclamationmark.shield"
            case .myWork:         return "checklist.checked"
            case .infrastructure: return "server.rack"
            case .knowledge:      return "books.vertical"
            case .communicate:    return "bubble.left.and.bubble.right"
            }
        }

        var description: String {
            switch self {
            case .home:           return "Your intelligent feed"
            case .alertsOnCall:   return "Alerts, on-call, notifications"
            case .incidents:      return "Active and recent incidents"
            case .myWork:         return "Tickets, PRs, builds, boards"
            case .infrastructure: return "AWS, Bitbucket, deployments"
            case .knowledge:      return "SOPs, Confluence, AI Copilot"
            case .communicate:    return "Gmail, Calendar, Chat"
            }
        }
    }

    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedItem) {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.rawValue).font(.body)
                                    Spacer()
                                    // Badge for alerts/notifications
                                    if item == .alertsOnCall {
                                        let count = notificationVM.unreadCount
                                        if count > 0 {
                                            Text("\(count)")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(Color.red).clipShape(Capsule())
                                        }
                                    }
                                    if item == .incidents && appState.activeIncidentCount > 0 {
                                        Text("\(appState.activeIncidentCount)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.red).clipShape(Capsule())
                                    }
                                }
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: item.icon)
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Boomi SRE")

            Divider()

            // Settings footer (pinned)
            Button {
                appState.selectedReport = nil
                appState.showSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

### Phase 47D: Update ContentView Routing

Replace the existing detail pane routing in `ContentView.swift`. Instead of routing by `ReportItem.id` (19 cases), route by `SidebarItem` (7 cases):

```swift
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationVM: NotificationViewModel
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedItem)
        } detail: {
            VStack(spacing: 0) {
                // Breadcrumb (if exists)
                // BreadcrumbView()

                // Detail content
                switch selectedItem {
                case .home, nil:
                    DashboardView()
                case .alertsOnCall:
                    AlertsOnCallView()
                case .incidents:
                    IncidentCommandView()
                case .myWork:
                    MyWorkView()
                case .infrastructure:
                    InfrastructureView()
                case .knowledge:
                    KnowledgeToolsView()
                case .communicate:
                    CommunicateView()
                }
            }
        }
    }
}
```

**Important:** The old routing by `appState.selectedReport` (ReportItem) still needs to work for:
- Feed item navigation ("View All" buttons navigate to specific sections)
- Keyboard shortcuts (⌘1 for My TODO, etc.)
- Deep links from notifications

Add a bridge: when `appState.selectedReport` is set (from a feed action or notification), map it to the correct `SidebarItem` and tab:
```swift
.onChange(of: appState.selectedReport) {
    if let report = appState.selectedReport {
        switch report.id {
        case "oncall", "notifications":
            selectedItem = .alertsOnCall
        case "incidents":
            selectedItem = .incidents
        case "jira_todo", "jira_filters", "jira_boards", "github_browser", "jenkins_browser":
            selectedItem = .myWork
        case "aws_health", "aws_cost_explorer", "bitbucket_browser":
            selectedItem = .infrastructure
        case "knowledge_base", "confluence_browser", "copilot_chat", "exec_assistant":
            selectedItem = .knowledge
        case "google_gmail", "google_calendar", "google_chat":
            selectedItem = .communicate
        default:
            break
        }
    }
}
```

Also pass the specific tab to each combined view so it opens on the right sub-tab. Add `@State` or `@Binding` for the initial tab based on `appState.selectedReport`.

### Phase 47E: Update CommandMenu Keyboard Shortcuts

Simplify the menu bar to match the new sidebar:

```swift
// Replace the multiple menus (AI, Jira, AWS, Google, Browse) with simpler structure
CommandMenu("Navigate") {
    Button("Home") { selectedItem = .home }
        .keyboardShortcut("0", modifiers: .command)
    Button("Alerts & On-Call") { selectedItem = .alertsOnCall }
        .keyboardShortcut("1", modifiers: .command)
    Button("Incidents") { selectedItem = .incidents }
        .keyboardShortcut("2", modifiers: .command)
    Button("My Work") { selectedItem = .myWork }
        .keyboardShortcut("3", modifiers: .command)
    Button("Infrastructure") { selectedItem = .infrastructure }
        .keyboardShortcut("4", modifiers: .command)
    Button("Knowledge & Tools") { selectedItem = .knowledge }
        .keyboardShortcut("5", modifiers: .command)
    Button("Communicate") { selectedItem = .communicate }
        .keyboardShortcut("6", modifiers: .command)
    Divider()
    Button("AI Copilot") {
        selectedItem = .knowledge
        // set tab to AI Copilot
    }
    .keyboardShortcut("/", modifiers: .command)
    Button("Settings") { appState.showSettings = true }
        .keyboardShortcut(",", modifiers: .command)
}
```

Keep the Favorites menu if it exists. Remove the individual AI, Jira, AWS, Google, Browse menus — they're now consolidated.

### Phase 47F: Preserve the Product Context Switcher

The product context dropdown (from Phase 45) should remain in the toolbar area, above the sidebar or in the window toolbar. It works independently of the sidebar structure.

Also add the product badge to each combined view's header — so the SRE always knows which product context they're in.

---

## Important: Backward Compatibility

The old `ReportItem` and `ReportCatalog` still exist and are used by:
- Feed item `navigateTo` strings (e.g., "oncall", "jira_todo")
- Notification deep links
- The `appState.selectedReport` mechanism

**Don't delete `ReportItem` or `ReportCatalog`** — they become an internal routing mechanism. The sidebar no longer directly displays them, but they're used for programmatic navigation from the feed, notifications, and keyboard shortcuts.

The `ReportSection` enum can be simplified or kept for internal categorization — it's no longer directly rendered in the sidebar.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Simplify sidebar — 7 items with tabbed combined views"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.
