# Boomi SRE App — Phase 24: Sidebar Reorganization — Intuitive SRE Categories

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2).

**Read these files first:**
- `BoomiSRE/Sources/Models/ReportItem.swift` — `ReportSection` enum, `ReportCatalog` with all items, `ReportItem` model
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar rendering, section headers, status dots, auth logic
- `BoomiSRE/Sources/Views/ContentView.swift` — detail pane routing
- `BoomiSRE/Sources/Models/AppState.swift` — auth statuses for all services
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — CommandMenu structure (AI menu, Jira menu, AWS menu, Google menu)

**Key constraints:**
- Pure SwiftUI. No third-party frameworks.
- Don't break any existing functionality — this is purely a reorganization of navigation, not features.

---

## The Vision

The current sidebar is organized by **vendor** (Jira, AWS, Google, "Services"). This doesn't match how an SRE thinks about their work. An SRE thinks in terms of **what they're doing**, not which vendor they're clicking on.

The new sidebar should be organized by **SRE workflow domain** — when an SRE opens the app, they should immediately see categories that map to their job responsibilities. The groupings should feel so natural that a new SRE joining the team on day one would know exactly where to find everything.

---

## New Sidebar Structure

Here is the complete reorganization. **Every existing item must be accounted for** — nothing is removed, only moved.

```
🏠 Home (Dashboard)

⚡ COMMAND CENTER                    ← The SRE nerve center
   🔔 Notifications                  ← What needs attention right now
   🚨 Incidents                      ← Active and recent incidents
   📞 On-Call                        ← Who's on call, alerts from JSM
   🤖 AI Copilot                     ← Ask anything
   📋 Executive Assistant            ← AI briefings

📋 WORK                              ← Where the tickets live
   ✅ My TODO                         ← Personal Jira task list
   🔍 Saved Filters                  ← Jira filter results
   📊 Boards                         ← Scrum/kanban boards

🏗️ INFRASTRUCTURE                    ← The systems we keep running
   ❤️ AWS Health                      ← EC2, ALB, RDS, Lambda health
   💰 AWS Costs                       ← Cost Explorer
   (🔷 Azure — future)
   (☁️ GCP — future)

👁️ OBSERVABILITY                     ← How we see what's happening
   📈 Grafana                         ← Dashboards, panels, alerts
   (📊 New Relic — future)
   (⏰ CloudWatch — future)

💻 SOURCE CONTROL                    ← The code
   🐙 GitHub                          ← Repos, PRs, Actions, reviews
   🔀 Bitbucket                       ← Repos, PRs, pipelines

⚙️ AUTOMATION                        ← How we build and deploy
   🔨 Jenkins                         ← Jobs, builds, console output
   (🚀 Harness — future)

📚 KNOWLEDGE                         ← What we know
   📖 Knowledge Base                  ← SOPs, runbooks, guides
   📄 Confluence                      ← Wiki spaces and pages

💬 COMMUNICATION                     ← How we talk
   📧 Gmail                           ← Email inbox
   📅 Calendar                        ← Google Calendar
   💬 Chat                            ← Google Chat

──────────
⚙️ Settings (pinned footer)
```

---

## Implementation Plan

### Phase 24A: Redefine ReportSection Enum

**Replace the current `ReportSection` enum** in `ReportItem.swift`:

```swift
enum ReportSection: String, CaseIterable {
    case commandCenter = "Command Center"
    case work = "Work"
    case infrastructure = "Infrastructure"
    case observability = "Observability"
    case sourceControl = "Source Control"
    case automation = "Automation"
    case knowledge = "Knowledge"
    case communication = "Communication"

    var icon: String {
        switch self {
        case .commandCenter:  return "bolt.shield.fill"
        case .work:           return "checklist.checked"
        case .infrastructure: return "server.rack"
        case .observability:  return "eye"
        case .sourceControl:  return "chevron.left.forwardslash.chevron.right"
        case .automation:     return "gearshape.2"
        case .knowledge:      return "books.vertical"
        case .communication:  return "bubble.left.and.bubble.right"
        }
    }
}
```

### Phase 24B: Reassign Every ReportItem to New Sections

**Update every item in `ReportCatalog.all`** with its new section. Here is the complete mapping:

| Item | Old Section | New Section |
|------|------------|-------------|
| `notifications` | `.ai` | `.commandCenter` |
| `incidents` | `.ai` | `.commandCenter` |
| `oncall` | `.ai` | `.commandCenter` |
| `copilot_chat` | `.ai` | `.commandCenter` |
| `exec_assistant` | `.ai` | `.commandCenter` |
| `jira_todo` | `.jira` | `.work` |
| `jira_filters` | `.jira` | `.work` |
| `jira_boards` | `.jira` | `.work` |
| `aws_health` | `.aws` | `.infrastructure` |
| `aws_cost_explorer` | `.aws` | `.infrastructure` |
| `grafana_browser` | `.services` | `.observability` |
| `github_browser` | `.services` | `.sourceControl` |
| `bitbucket_browser` | `.services` | `.sourceControl` |
| `jenkins_browser` | `.services` | `.automation` |
| `knowledge_base` | `.ai` | `.knowledge` |
| `confluence_browser` | `.services` | `.knowledge` |
| `google_gmail` | `.google` | `.communication` |
| `google_calendar` | `.google` | `.communication` |
| `google_chat` | `.google` | `.communication` |

Also reorder the items within `ReportCatalog.all` to match the sidebar order above (Command Center items first, then Work, then Infrastructure, etc.).

### Phase 24C: Update SidebarView — New Section Rendering

**Rewrite the section rendering in `SidebarView.swift`:**

1. **Replace the old section blocks** (AI, Jira, AWS, Google, Services) with the new 8 sections.

2. **Each section gets a `sectionHeader()` with the appropriate auth status.** Map the auth status to the "most important" service in each section:
   - Command Center: no status dot (it's a meta-section, not a service)
   - Work: `appState.jiraAuthStatus`
   - Infrastructure: `appState.awsAuthStatus`
   - Observability: `appState.grafanaAuthStatus`
   - Source Control: composite — show green only if ALL configured source control services are authenticated. Show the worst status (red > orange > grey > green).
   - Automation: `appState.jenkinsAuthStatus`
   - Knowledge: composite of Confluence + GitHub (KB comes from GitHub)
   - Communication: `appState.googleAuthStatus`

3. **For composite status sections** (Source Control, Knowledge), create a helper:
   ```swift
   private func compositeStatus(_ statuses: [AuthStatus]) -> AuthStatus {
       // If any are .error, return .error
       // If any are .expired, return .expired
       // If any are .checking, return .checking
       // If all are .authenticated, return .authenticated
       // If all are .notConfigured, return .notConfigured
       // Otherwise return .unknown
   }
   ```

4. **Section order in the sidebar** must match the order in the structure above. The Command Center should feel like the "home base" — the most prominent section.

5. **Future items** (Azure, GCP, New Relic, CloudWatch, Harness, Salesforce, Slack): Do NOT add placeholder items to the sidebar. They don't exist yet and would confuse users. Only show items that have actual views. The sections are designed to accommodate them when they're built.

### Phase 24D: Update CommandMenu Structure

**Reorganize the top menu bar** to match the new sidebar groupings:

Replace the old menus (AI, Jira, AWS, Google) with:

```swift
// Keep "Command Center" as the primary menu
CommandMenu("Command Center") {
    Button("Notifications") { navigateTo("notifications") }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    Button("Incidents") { navigateTo("incidents") }
        .keyboardShortcut("i", modifiers: .command)
    Button("On-Call") { navigateTo("oncall") }
    Button("AI Copilot") { navigateTo("copilot_chat") }
        .keyboardShortcut("/", modifiers: .command)
    Button("Executive Assistant") { navigateTo("exec_assistant") }
        .keyboardShortcut("e", modifiers: .command)
    Divider()
    Button("Refresh Notifications Now") {
        Task { await notificationVM.pollAllServices(appState: appState) }
    }
    .keyboardShortcut("n", modifiers: [.command, .option])
}

CommandMenu("Work") {
    Button("My TODO") { navigateTo("jira_todo") }
        .keyboardShortcut("1", modifiers: .command)
    Button("Saved Filters") { navigateTo("jira_filters") }
        .keyboardShortcut("2", modifiers: .command)
    Button("Boards") { navigateTo("jira_boards") }
        .keyboardShortcut("3", modifiers: .command)
}

CommandMenu("Infrastructure") {
    Button("AWS Health") { navigateTo("aws_health") }
    Button("AWS Costs") { navigateTo("aws_cost_explorer") }
        .keyboardShortcut("4", modifiers: .command)
    Divider()
    Button("Status: \(statusText(appState.awsAuthStatus))") { }.disabled(true)
}

// Combine smaller sections into a "Services" menu to avoid too many top-level menus
CommandMenu("Browse") {
    Section("Observability") {
        Button("Grafana") { navigateTo("grafana_browser") }
    }
    Section("Source Control") {
        Button("GitHub") { navigateTo("github_browser") }
        Button("Bitbucket") { navigateTo("bitbucket_browser") }
    }
    Section("Automation") {
        Button("Jenkins") { navigateTo("jenkins_browser") }
    }
    Section("Knowledge") {
        Button("Knowledge Base") { navigateTo("knowledge_base") }
            .keyboardShortcut("k", modifiers: .command)
        Button("Confluence") { navigateTo("confluence_browser") }
    }
    Section("Communication") {
        Button("Gmail") { navigateTo("google_gmail") }
            .keyboardShortcut("5", modifiers: .command)
        Button("Calendar") { navigateTo("google_calendar") }
            .keyboardShortcut("6", modifiers: .command)
        Button("Chat") { navigateTo("google_chat") }
            .keyboardShortcut("7", modifiers: .command)
    }
}
```

Keep the Favorites menu and Help menu unchanged.

### Phase 24E: Update Breadcrumbs

If `BreadcrumbView` exists (from Phase 9D), update it to use the new section names. The breadcrumb should show: `Home > Infrastructure > AWS Health` instead of `Home > AWS > Infrastructure Health`.

### Phase 24F: Update Item Descriptions

With the new groupings, some item descriptions can be simplified since the section name provides context. Update these:

| Item | Old Description | New Description |
|------|----------------|-----------------|
| `aws_health` | "EC2, ALB, RDS, Lambda, CloudWatch — account health at a glance" | "EC2, ALB, RDS, Lambda — account health at a glance" |
| `aws_cost_explorer` | "Query AWS Cost Explorer for the active profile — costs by service, region, or account" | "Costs by service, region, or account" |
| `grafana_browser` | "Browse dashboards, panels, and alert rules with AI insights" | "Dashboards, alerts, and panels with AI insights" |
| `github_browser` | "Browse repos, open PRs, and CI runs with AI code review" | "Repos, PRs, Actions, and AI code review" |
| `bitbucket_browser` | "Browse repos, PRs, branches, and pipelines with AI review" | "Repos, PRs, branches, and pipelines" |
| `jenkins_browser` | "Browse jobs, build history, and console output with AI failure analysis" | "Jobs, builds, and AI failure analysis" |
| `knowledge_base` | "SOPs, runbooks, guides, and Boomi documentation from the team KB" | "SOPs, runbooks, and Boomi documentation" |
| `confluence_browser` | "Browse spaces, pages, and search with AI summaries and page drafting" | "Wiki spaces, pages, and AI summaries" |
| `google_gmail` | "Recent emails from your Boomi Google inbox" | "Your Boomi inbox" |
| `google_calendar` | "Upcoming events from your Google Calendar" | "Upcoming meetings and events" |
| `google_chat` | "Google Chat spaces and recent messages" | "Team chat and messages" |

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break any features.** This is a navigation reorganization only. All views, view models, services, and routing remain unchanged. Only the section assignments and sidebar rendering change.
- **Search for all references** to the old `ReportSection` cases (`.ai`, `.jira`, `.aws`, `.services`, `.google`). Every reference must be updated — in SidebarView, SettingsView, NotificationViewModel, DashboardView, BreadcrumbView, and anywhere else they appear.
- **The sidebar should feel like a map of an SRE's brain.** Command Center = what's happening now. Work = what I need to do. Infrastructure = what I'm responsible for. Observability = how I watch it. Source Control = the code. Automation = how it deploys. Knowledge = how I learn. Communication = how I talk. If a new SRE joins tomorrow, this sidebar should make them feel like they already know how to use the tool.
- **Commit after each phase** (24A, 24B, 24C, 24D, 24E, 24F) with a descriptive commit message.
