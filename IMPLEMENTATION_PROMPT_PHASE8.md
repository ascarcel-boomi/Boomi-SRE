# Boomi SRE App — Phase 8: Home Page Redesign, Sidebar Polish & Bug Fixes

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, NavigationSplitView layout, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `Package.swift` — dependencies and targets
- `TODO.md` — existing roadmap
- `IMPLEMENTATION_PROMPT.md` — phases 1-7 that have already been implemented
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry point and CommandMenu
- `BoomiSRE/Sources/Views/ContentView.swift` — NavigationSplitView root
- `BoomiSRE/Sources/Models/AppState.swift` — central state object
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation
- `BoomiSRE/Sources/Views/WelcomeView.swift` — current home page
- `BoomiSRE/Sources/Views/Panels/GitHubBrowserView.swift` — GitHub browser
- `BoomiSRE/Sources/ViewModels/GitHubBrowserViewModel.swift` — GitHub view model
- `BoomiSRE/Sources/Services/GitHubService.swift` — GitHub API client
- `BoomiSRE/Sources/Views/Panels/GrafanaBrowserView.swift` — Grafana browser
- `BoomiSRE/Sources/ViewModels/GrafanaBrowserViewModel.swift` — Grafana view model
- `BoomiSRE/Sources/Services/GrafanaService.swift` — Grafana API client
- `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift` — Confluence browser
- `BoomiSRE/Sources/ViewModels/ConfluenceBrowserViewModel.swift` — Confluence view model
- `BoomiSRE/Sources/Services/ConfluenceService.swift` — Confluence API client
- `BoomiSRE/Sources/Views/Panels/ChatView.swift` — Google Chat (WebView)

**Key constraints (same as phases 1-7):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Never macOS Keychain (unsigned app).
- Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path `/usr/local/bin/aws` (PATH stripped in .app bundle).
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira/Confluence Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.
- Zscaler SSL proxy is active — some internal URLs may need certificate handling.

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 8A: Sidebar Visual Polish

**Problems to fix:**
1. When the sidebar collapses (via the macOS NavigationSplitView toggle), it shows a completely empty/blank strip — no icons visible at all.
2. Some sidebar icons are orange, some are grey — they should all be consistent.
3. The Settings menu item at the bottom is visually larger than all other menu items.

**Current sidebar structure** (in `SidebarView.swift`):
- Home button at top (plain button, not a NavigationLink)
- AI section (no status dot in header, items use `NavigationLink(value:)`)
- Jira section (section header via `sectionHeader()` helper with status dot)
- AWS section (same)
- Google section (same)
- Services section (items have inline status dots, header uses plain `Label`)
- Settings section (plain `Button` with `Label("Settings", systemImage: "gear")`)

**Requirements:**

1. **Collapsed sidebar icons:** SwiftUI's `NavigationSplitView` with `.sidebar` column visibility should automatically show icons in compact mode. The problem is that the sidebar items use custom layouts (`VStack` with title + description) inside `NavigationLink`. When collapsed, SwiftUI only shows the `label:` portion of `NavigationLink(value:) { ... } label: { ... }` — but the current code puts the content inside the value content closure, not a label closure. Ensure each `NavigationLink` has an appropriate `Label(report.title, systemImage: report.icon)` so the SF Symbol shows when the sidebar is narrow/collapsed. This means:
   - Add an `icon` property to `ReportItem` (the model in `ReportItem.swift`) — a String for the SF Symbol name. Map each report to an appropriate icon (e.g., "bubble.left.and.text.badge.plus" for Copilot Chat, "list.clipboard" for Executive Assistant, "exclamationmark.triangle" for Incidents, "bell" for Notifications, "checklist" for My TODO, "line.3.horizontal.decrease.circle" for Saved Filters, "kanban" or "rectangle.split.3x3" for Boards, "dollarsign.circle" for Cost Explorer, "envelope" for Gmail, "calendar" for Calendar, "bubble.left.and.bubble.right" for Chat, etc.)
   - Use the two-argument `NavigationLink(value:) { Label(...) }` form so SwiftUI can extract the icon for compact mode. Put the expanded content (title + description + badges) inside the label closure, using the `Label` initializer with a custom `title:` view and `icon:` view.

2. **Consistent icon colors:** All sidebar section header icons and item icons should use `.secondary` foreground color (the grey). Remove any `.foregroundStyle(.orange)` or accent-colored icon overrides. The only color accents in the sidebar should be:
   - Status dots (green/orange/red/grey) on section headers
   - Badge capsules (red for incidents, blue for notifications/briefings)
   - The selected/highlighted item (handled automatically by SwiftUI's list selection)

3. **Settings item sizing:** The Settings button is in its own `Section { }` block which adds section header spacing. Change it so Settings is styled identically to other navigation items — same font size (`.body` for title, `.caption` for description), same padding (`.vertical, 2`). The simplest fix: make Settings a `NavigationLink`-style button (or a real `NavigationLink` to a settings report item) with the same layout as other items, OR remove it from its own Section and put it as an item in the Services section, OR use `.listRowInsets` to match. The key requirement: Settings should be visually identical in size/spacing to every other sidebar item.

---

### Phase 8B: Home Page Redesign — Customizable Widget Dashboard

**Problem:** The current home page (`WelcomeView.swift`) shows a static "Boomi SRE Reports" title with a chart icon, two feature callouts, and a 3×3 grid of auth status cards. This is redundant (auth status is already visible in the sidebar status dots) and not useful for daily SRE work.

**New vision:** The home page should be a **customizable widget dashboard** — the most valuable real-time information for an SRE engineer, at a glance. Think of it like macOS Dashboard/Notification Center widgets, or Grafana's home dashboard concept.

**Requirements:**

#### 8B-1. Rename & Rebrand
- Change "Boomi SRE Reports" → "Boomi SRE" everywhere (window title, home page, about). This app has evolved far beyond reports.
- Change the home page icon from `chart.bar.doc.horizontal` to something more fitting like `shield.checkmark` or `gauge.with.dots.needle.33percent` (SRE/reliability themed).
- The home page greeting should be contextual: "Good morning, Adam" / "Good afternoon" / "Good evening" based on time of day, using the user's name from Jira auth or config.

#### 8B-2. Widget System Architecture

Create a widget framework with these components:

**Widget Model** (`BoomiSRE/Sources/Models/WidgetModels.swift`):
```
enum WidgetType: String, Codable, CaseIterable {
    case activeIncidents      // P1/P2 incidents currently open
    case myTickets            // Assigned Jira tickets (count + top 5)
    case recentPRs            // Open PRs across favorite repos
    case jenkinsBuilds        // Recent build status (last 5 jobs)
    case grafanaAlerts        // Currently firing alerts
    case awsCostTrend         // This month's cost vs last month
    case upcomingCalendar     // Next 3 calendar events
    case unreadEmails         // Unread email count + top 3 subjects
    case confluenceRecent     // Recently updated pages in favorite spaces
    case serviceHealth        // Auth status of all 7 services (compact)
    case quickActions         // Buttons: New Incident, Ask Copilot, Run Report
    case aiDailySummary       // AI-generated summary of the day's SRE state
}

struct DashboardWidget: Identifiable, Codable {
    let id: UUID
    var type: WidgetType
    var position: Int        // ordering on the dashboard
    var size: WidgetSize     // .small (1 col), .medium (2 col), .large (full width)
    var isEnabled: Bool
}

enum WidgetSize: String, Codable {
    case small, medium, large
}
```

**Widget Configuration** (persisted in `~/.boomi_sre_config.json` alongside existing config):
- `dashboardWidgets: [DashboardWidget]` — user's chosen widgets and order
- `dashboardMode: "custom" | "auto"` — whether the user manages widgets manually or lets AI choose

**Default widget set** (for new users or "auto" mode):
1. `serviceHealth` (small) — quick glance at what's connected
2. `activeIncidents` (medium) — any P1/P2 incidents
3. `myTickets` (medium) — assigned Jira tickets
4. `grafanaAlerts` (medium) — firing alerts
5. `jenkinsBuilds` (medium) — recent builds
6. `recentPRs` (medium) — open PRs
7. `quickActions` (small) — action buttons

#### 8B-3. Widget Views

Create `BoomiSRE/Sources/Views/Widgets/` directory with individual widget views. Each widget should:
- Have a consistent card appearance: rounded rectangle, subtle border, header with icon + title + optional badge
- Show a loading skeleton when data is being fetched
- Show a compact error state if the service isn't configured (not a blocking error — just "Configure in Settings" link)
- Be clickable to navigate to the full view (e.g., clicking the Jira tickets widget navigates to My TODO)

**Individual widget specifications:**

- **ServiceHealth**: Compact horizontal row of 7 service icons with colored dots. No text labels needed — just icons + status color. Clicking opens Settings.

- **ActiveIncidents**: Shows count of active P1/P2 incidents with severity badges. Lists top 3 by severity. Red background tint if any P1. Clicking navigates to Incident Command Center.

- **MyTickets**: Shows count of tickets assigned to user. Lists top 5 by priority with status icons. Shows a mini bar chart (Swift Charts) of tickets by status (To Do / In Progress / Done). Clicking navigates to My TODO.

- **RecentPRs**: Lists open PRs from favorite GitHub repos (or all if no favorites). Shows repo name, PR title, author, CI status badge. Clicking navigates to GitHub Browser with that PR selected.

- **JenkinsBuilds**: Shows last 5 builds across favorite jobs (or recent if no favorites). Color-coded: green (success), red (failure), yellow (in progress), grey (aborted). Clicking navigates to Jenkins Browser.

- **GrafanaAlerts**: Shows count of firing alerts with red badge. Lists currently firing alerts (title + duration). Green "All Clear" state when nothing is firing. Clicking navigates to Grafana Browser with alerts toggled on.

- **AWSCostTrend**: Shows current month-to-date cost with a sparkline chart (Swift Charts) of daily costs for the past 14 days. Shows delta vs. same period last month (e.g., "+12% vs. last month"). Clicking navigates to Cost Explorer.

- **UpcomingCalendar**: Shows next 3 calendar events with time, title, and meeting link (if available). Clicking an event opens the Google Calendar event URL.

- **UnreadEmails**: Shows unread count badge. Lists top 3 unread email subjects with sender name. Clicking navigates to Gmail view.

- **ConfluenceRecent**: Shows 5 most recently updated pages across favorite spaces. Shows page title, space key, last modified date. Clicking navigates to Confluence Browser with that page selected.

- **QuickActions**: 3-4 action buttons in a row:
  - "Ask Copilot" → navigates to Copilot Chat
  - "New Incident" → navigates to Incident Command Center with create sheet open
  - "Run Report" → opens a picker to select and run a report
  - "Check Services" → triggers `appState.checkAllServices()`

- **AIDailySummary**: AI-generated 3-5 sentence summary of the current SRE state. Generated on first load of the day (cached for 4 hours). Uses Claude to synthesize: active incidents, ticket counts, alert status, build failures, and any anomalies. Shows a "Regenerate" button. This widget should always be `large` size.

#### 8B-4. Dashboard Layout View

Replace `WelcomeView.swift` with a new `DashboardView.swift`:
- Top bar: greeting + date + "Customize" button (gear icon)
- Body: `LazyVGrid` with adaptive columns (responsive to window width)
  - Small widgets: 1 column span
  - Medium widgets: 2 column span
  - Large widgets: full width
- Each widget card is wrapped in a `WidgetCardView` that provides the consistent frame, background, and navigation action
- Pull-to-refresh or a refresh button to reload all widget data
- Widgets load data independently and in parallel (each widget view model fetches its own data)

#### 8B-5. Dashboard Customization

Add a "Customize Dashboard" sheet/popover accessible from the dashboard's "Customize" button:
- Toggle `dashboardMode` between "Auto (AI-managed)" and "Custom"
- In Custom mode:
  - List of all `WidgetType` cases with toggles to enable/disable
  - Drag-to-reorder enabled widgets
  - Size picker (small/medium/large) for each enabled widget
- In Auto mode:
  - AI determines which widgets to show based on what services are configured and what data is available
  - E.g., if GitHub isn't configured, don't show the PRs widget
  - If there are active incidents, promote the incidents widget to the top and make it large
  - Show a brief explanation: "AI is managing your dashboard based on your connected services and current activity."
- Save changes to `~/.boomi_sre_config.json`

#### 8B-6. Dashboard View Model

Create `BoomiSRE/Sources/ViewModels/DashboardViewModel.swift`:
- `@MainActor` ObservableObject
- Loads widget configuration from AppState
- Has a `refreshAll()` method that fetches data for all enabled widgets in parallel
- Each widget's data is stored as a published property (e.g., `jiraTicketCount: Int`, `activeAlertCount: Int`, `recentPRs: [GitHubPR]`)
- Auto-refreshes on appear and every 5 minutes (respecting the existing `appState.refreshInterval`)
- The AI daily summary is generated via ClaudeService, cached with a timestamp, and regenerated if > 4 hours old

---

### Phase 8C: Bug Fix — GitHub Browser Not Showing Personal Repos

**Problem:** The GitHub service browser doesn't list the user's actual repos. It only shows repos from the hardcoded `Mashery-Boomi` org.

**Root cause:** In `GitHubBrowserViewModel.swift`, `loadRepos()` calls `listOrgRepos(org: orgName)` where `orgName` defaults to `"Mashery-Boomi"`. If the token doesn't have access to that org, or the org has few repos, the user's personal repos may appear empty or get deduplicated incorrectly.

**Fix:**
1. The `orgName` should come from `appState` configuration, not be hardcoded. Add a `githubOrg` field to AppState (persisted in config). Default to `"Mashery-Boomi"` but allow the user to change it in Settings.
2. Make the org fetch optional — if `githubOrg` is empty, skip the org fetch entirely and just show personal repos.
3. If `listOrgRepos` fails (403/404 — user doesn't have access to the org), catch the error gracefully and continue with just personal repos. Currently the error propagates and aborts the entire load.
4. In the GitHub Browser view, add a UI element (text field or picker) at the top of the repo list to change/filter the org. Show "Personal" as a separate section from "Organization" repos.
5. Add pagination for personal repos — currently only fetches 1 page of 100. Add the same `while` pagination loop as `listOrgRepos`.
6. In `GitHubService.listUserRepos()`, change `affiliation=owner` to `affiliation=owner,collaborator,organization_member` to show all repos the user has access to (not just owned repos).
7. Add a search/filter field at the top of the repo list to filter by name.

---

### Phase 8D: Bug Fix — Grafana Dashboards Show Only Panel Outlines

**Problem:** Grafana dashboards show a list of dashboards correctly, but when you click one, it only shows a text outline of the panels (panel type badge, title, description, PromQL queries as text). There's no actual visualization — no charts, no graphs, no data.

**Root cause:** The Grafana API `/api/dashboards/uid/{uid}` only returns the dashboard JSON definition (panel layout, query expressions, thresholds). It does NOT return rendered images or query results. The current code correctly parses this and shows the metadata, but there's no attempt to actually execute the queries or render the panels.

**Fix — Two-pronged approach:**

1. **Embed Grafana via WebView (primary):** The best way to show actual Grafana dashboards is to embed them. Grafana supports iframe embedding and has a "kiosk mode" URL parameter (`?kiosk`) that hides the Grafana chrome.
   - When a dashboard is selected, show a `WKWebView` loading `{grafanaURL}{dashboard.url}?kiosk&theme=dark` (or light, matching the macOS appearance)
   - Use the Grafana API token as a Bearer token in the request headers (set via `WKWebView` custom request)
   - If the Grafana instance requires authentication, inject the API token via a cookie or Authorization header. For Grafana Cloud or instances with API key auth, add `?kiosk` and set `Authorization: Bearer {token}` header on the initial request using `WKWebView`'s `load(URLRequest)`.
   - **Important:** WKWebView doesn't easily support custom headers on subsequent requests. Two approaches:
     a. Use Grafana's "auth proxy" approach: if the Grafana instance supports cookie-based auth, navigate to the login first.
     b. For API-key-based access: use a `WKURLSchemeHandler` or inject a script that sets the auth header, OR use the Grafana `/render` API to get panel PNGs (see option 2).
   - Fall back to the current text-based panel outline if the WebView fails to load.

2. **Panel snapshot images (fallback):** Grafana has a render API (`/render/d-solo/{uid}/{slug}?panelId={id}&width=800&height=400`) that returns a PNG of a single panel. If the Grafana instance has the rendering plugin installed:
   - For each panel, attempt to load its rendered PNG via the render API
   - Display these images in a vertical scroll view, one per panel
   - This gives actual visualized data without needing a full WebView

3. **Keep the existing text outline as a third fallback** and also as an "Inspector" or "Query Inspector" tab — useful for SREs who want to see the raw PromQL/LogQL queries.

**Implementation:**
- Add a segmented control at the top of the dashboard detail pane: "Dashboard" (WebView) | "Panels" (rendered PNGs or text outline) | "Queries" (current text view)
- Default to "Dashboard" (WebView) when a dashboard is selected
- The WebView should show a loading indicator and handle errors gracefully

---

### Phase 8E: Bug Fix — Confluence Pages Show Blank White Window

**Problem:** Confluence spaces list correctly, and pages within a space list correctly, but when you click a page, it shows a very narrow blank white window with no content.

**Root cause analysis — likely issues:**

1. **Content not loading:** The `getPageContent()` method fetches `body.export_view` and strips HTML to plain text. If the page uses Atlassian Document Format (ADF) instead of storage format, `body.export_view` may be empty. Check if `body.storage` or `body.atlas_doc_format` should be used instead.

2. **Layout issue:** The `pageContentPane` is inside an `HSplitView` nested inside another `HSplitView` (space list → page list → content). Three-level HSplitView can cause layout collapse where the innermost pane gets squeezed to zero width. The page content pane has no `minWidth` constraint.

3. **Empty string display:** If `vm.pageContent` is empty (API returned no body), the view shows `Text("(No content loaded)")` — but this text may be invisible in a zero-width pane.

**Fix:**

1. **Fix the layout:** Add `.frame(minWidth: 400)` to the page content pane. Consider changing the three-pane layout from nested HSplitViews to a single `NavigationSplitView` with three columns, or use a flat HSplitView with all three panes at the same level.

2. **Fix content fetching:** In `ConfluenceService.getPageContent()`:
   - Try `body.export_view` first (current approach)
   - If empty, fall back to `body.storage` (HTML storage format)
   - If still empty, fall back to `body.atlas_doc_format` (ADF JSON → convert to readable text)
   - Change the expand parameter to `body.export_view,body.storage` to get both in one request

3. **Render HTML properly:** Instead of stripping HTML to plain text (which loses all formatting), render the Confluence HTML in a `WKWebView`. This preserves tables, code blocks, images, formatting, and macros:
   - Create a `ConfluencePageWebView` (NSViewRepresentable wrapping WKWebView)
   - Load the HTML content with a base URL of the Confluence instance (so relative image URLs resolve)
   - Wrap the HTML in a minimal `<html><head><style>...</style></head><body>...</body></html>` with CSS that matches macOS appearance (light/dark mode support)
   - Add basic Confluence-like styling: max-width content area, readable fonts, code block highlighting

4. **Add a toggle** between "Rendered" (WebView) and "Plain Text" (current stripped text) views, for users who prefer the text view or when WebView has issues.

---

### Phase 8F: Bug Fix — Google Chat Shows Default Gmail Login Page

**Problem:** The Google Chat view (`ChatView.swift`) loads `https://mail.google.com/mail/u/0/#chat/home` in a WKWebView, but it shows the default Gmail login page as if the user is not logged in. The user expects to see their actual Google Chat conversations.

**Root cause:** WKWebView has its own cookie/session storage that is separate from the system browser (Safari/Chrome). The user may be logged into Google in their browser, but the WKWebView has no Google session cookies. The custom User-Agent pretending to be Chrome doesn't help because authentication is cookie-based, not UA-based.

**Fix — Multiple approaches (implement in this priority order):**

1. **Use Google Chat's standalone URL:** Instead of the Gmail URL (`mail.google.com/mail/u/0/#chat/home`), use the standalone Google Chat URL: `https://chat.google.com/`. This is a dedicated Google Chat interface that may behave better in embedded WebViews.

2. **Persistent WKWebView data store:** Use a persistent `WKWebsiteDataStore` (not the default ephemeral one) so that once the user logs in to Google within the WebView, the session persists across app launches:
   ```swift
   let dataStore = WKWebsiteDataStore.default()  // persistent store
   config.websiteDataStore = dataStore
   ```
   Currently the code uses the default configuration which should already be persistent, but verify this is the case.

3. **Add a "Sign In" flow:** Since the WebView won't have existing browser cookies, the user needs to log in within the WebView itself. Add clear UX for this:
   - On first load, show a banner: "Sign in to your Google account to view Chat"
   - After the user signs in once, the persistent data store will remember the session
   - Add a "Sign Out" button that clears the WebView's cookies for Google domains
   - Add a "Reload" button to refresh the page

4. **Share cookies from system browser (advanced, optional):** If you want the WebView to automatically pick up the user's existing Google session:
   - This is intentionally blocked by macOS sandboxing and browser security — you cannot read Safari cookies from a WKWebView
   - Don't pursue this approach

5. **Alternative: Open in a dedicated browser window:** If WebView embedding proves too unreliable with Google's auth, provide a fallback that opens Google Chat in a dedicated minimal browser window (NSWindow with WKWebView, no address bar) that persists its session. This gives a better experience than the system browser while maintaining session state.

6. **User experience improvements regardless of auth approach:**
   - Add a toolbar with: Reload button, Back/Forward navigation, "Open in Browser" button
   - Show the current URL or a status indicator so the user knows what state they're in
   - If the page hasn't loaded after 10 seconds, show a "Having trouble? Try opening in browser" prompt

---

### Phase 8G: Update TODO.md & Navigation Title

1. Update `TODO.md` with the new features implemented in this phase.
2. Change the sidebar navigation title from `"Boomi SRE"` to just `"Boomi SRE"` (it's already correct, but verify `WelcomeView` title says "Boomi SRE" not "Boomi SRE Reports").
3. Update `ContentView.swift` routing to use `DashboardView` instead of `WelcomeView` as the default view.
4. If there's a `NavigationTitle` or window title that says "Reports", update it.

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** All existing sidebar navigation, service browsers, and AI features must continue to work.
- **Error handling:** All new network calls should handle errors gracefully — show inline error messages, not crashes or empty screens.
- **Dark mode:** All new views must support both light and dark macOS appearances.
- **Performance:** Widget data fetching should be parallel and non-blocking. Don't block the UI while loading dashboard data.
- **Persistence:** New config fields (dashboardWidgets, dashboardMode, githubOrg) should be added to AppState and persisted in `~/.boomi_sre_config.json` alongside existing fields.
- **Commit after each phase** (8A, 8B, 8C, 8D, 8E, 8F, 8G) with a descriptive commit message.
