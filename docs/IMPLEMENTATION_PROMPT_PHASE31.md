# Boomi SRE App — Phase 31: Add Alert Filters to On-Call via WebView

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — current On-Call view with alerts section
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — on-call data loading

---

## Background

The JSM Operations alerts are NOT available through the `api.atlassian.com` REST API with Basic auth (returns 404). However, they ARE accessible via the web UI at `boomii.atlassian.net/jira/ops/alerts`. The user wants to see filtered alert views directly in the app.

The user provided these exact URLs for the alert filters they want:

- **All Alerts:** `https://boomii.atlassian.net/jira/ops/alerts`
- **Assigned to me:** `https://boomii.atlassian.net/jira/ops/alerts?view=list&query=owner:%20%22712020:4475fc4e-ff9e-40ca-8c70-707c079f682e%22`
- **Closed:** `https://boomii.atlassian.net/jira/ops/alerts?view=list&query=status:%20%22closed%22`
- **Unacknowledged:** `https://boomii.atlassian.net/jira/ops/alerts?view=list&query=status:%20%22open%22%20AND%20acknowledged:%20false`

Since the API doesn't support alerts, we'll embed the web UI using a WKWebView with Okta SSO (same pattern used for Confluence pages and Grafana dashboards).

---

## Implementation

### Phase 31A: Replace Alerts Section with WebView

**Rewrite the `alertsSection` in `OnCallView.swift`:**

1. **Remove the old alerts code** — the current implementation tries to fetch alerts via the API (which returns nothing) and shows "No active alerts". Replace it entirely.

2. **Add an alert filter picker** at the top of the alerts section:
   ```swift
   enum AlertFilter: String, CaseIterable {
       case all = "All Alerts"
       case assignedToMe = "Assigned to Me"
       case unacknowledged = "Unacknowledged"
       case closed = "Closed"
   }
   ```

3. **Build the URL** based on the selected filter. The base URL uses `appState.jiraBaseURL`:
   ```swift
   private func alertURL(for filter: AlertFilter) -> URL {
       let base = appState.jiraBaseURL.trimmingSlash
       switch filter {
       case .all:
           return URL(string: "\(base)/jira/ops/alerts")!
       case .assignedToMe:
           // The accountId for "Assigned to me" should come from the user's Jira profile
           // Use appState.userProfile.jiraAccountId if available
           // Fall back to a generic "owner: currentUser" query
           let accountId = appState.userProfile?.jiraAccountId ?? ""
           if accountId.isEmpty {
               return URL(string: "\(base)/jira/ops/alerts")!
           }
           let query = "owner: \"\(accountId)\"".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
           return URL(string: "\(base)/jira/ops/alerts?view=list&query=\(query)")!
       case .unacknowledged:
           let query = "status: \"open\" AND acknowledged: false".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
           return URL(string: "\(base)/jira/ops/alerts?view=list&query=\(query)")!
       case .closed:
           let query = "status: \"closed\"".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
           return URL(string: "\(base)/jira/ops/alerts?view=list&query=\(query)")!
       }
   }
   ```

4. **Render the alerts section** as:
   ```
   ┌─────────────────────────────────────────────────┐
   │ 🔔 Alerts                                       │
   │                                                  │
   │ [All Alerts] [Assigned to Me] [Unacknowledged] [Closed]  │
   │                                                  │
   │ ┌─────────────────────────────────────────────┐ │
   │ │                                             │ │
   │ │   (Embedded WebView showing JSM Ops Alerts) │ │
   │ │                                             │ │
   │ └─────────────────────────────────────────────┘ │
   │                                                  │
   │         [Open in Browser ↗]                     │
   └─────────────────────────────────────────────────┘
   ```

5. **The WebView** should:
   - Use `WKWebsiteDataStore.default()` for persistent Okta SSO session (same as Confluence)
   - Allow all navigation for Atlassian/Okta domains during the SSO login flow
   - Show a loading indicator while the page loads
   - Have a reasonable minimum height (~400pt) so the alerts list is usable
   - Reload when the filter changes

6. **"Open in Browser" button** at the bottom that opens the current alert URL in the system browser as a fallback.

7. **"Sign in" hint:** If the WebView shows a login page (first time), show a subtle banner: "Sign in with your Okta credentials. You only need to do this once."

### Phase 31B: Discover User's Account ID for "Assigned to Me"

The "Assigned to me" filter needs the user's Jira account ID. This is the `712020:xxxx` format ID.

1. **Check if `appState.userProfile.jiraAccountId` is already populated** (from Phase 13 profile auto-discovery). If so, use it directly.

2. **If not available**, fetch it on demand via `GET {jiraBaseURL}/rest/api/3/myself` with Basic auth. This returns:
   ```json
   {"accountId": "712020:4475fc4e-ff9e-40ca-8c70-707c079f682e", "displayName": "Adam Scarcella", ...}
   ```
   Cache it in AppState or the ViewModel.

3. **If Jira isn't configured**, the "Assigned to Me" filter should show a message: "Configure Jira in Settings to use this filter" and fall back to the "All Alerts" URL.

### Phase 31C: Remove Alert API Code from OnCallViewModel

1. **Remove** `alerts: [OpsAlert]`, `isLoadingAlerts`, `alertFilter`, `filteredAlerts`, `loadAlerts()` from `OnCallViewModel` — all of this is replaced by the WebView.

2. **Remove** `alertsSection` alert row rendering code, `alertRow()`, priority/status color helpers, and relative time formatter if they're only used for alerts.

3. **Remove** the alert-related code from `load()` in `OnCallViewModel` (the `loadAlerts` task group entry).

4. **Keep the `AlertFilter` enum** but move it to `OnCallView` as local state since it just drives which URL the WebView loads.

### Phase 31D: Layout Adjustment

The On-Call view should now have two clear sections:
1. **Who's On-Call** (top) — the team cards with schedule participants (existing, working)
2. **Alerts** (bottom) — the WebView with filter tabs (new)

Use a `VStack` or `ScrollView` with both sections. The Who's On-Call section should take its natural height (cards). The Alerts WebView section should expand to fill remaining space (`.frame(maxHeight: .infinity)`).

Consider making this an `HSplitView` or `VSplitView` so the user can resize the split between on-call cards and the alerts WebView. Or keep it as a vertical scroll with the WebView having a fixed height of ~500pt.

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- The WebView pattern (SSO, persistent cookies, Okta redirect handling) should match the existing Confluence WebView implementation in `ConfluenceBrowserView.swift`.
- Don't break the existing on-call schedules functionality — only the alerts section changes.
