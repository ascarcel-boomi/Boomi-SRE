# Boomi SRE App — Phase 32: Revert Alerts to Native View & Add More Filters

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — current On-Call view (Phase 31 replaced alerts with a WebView — THIS MUST BE REVERTED)
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — alerts properties were removed by Phase 31 — MUST BE RESTORED
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — the `listAlerts()` method (check if it still exists)
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — OpsAlert model

---

## Problem

Phase 31 replaced the native alerts section with an embedded WebView. This was wrong — the user wants native macOS UI, not HTML pages. The alerts section needs to be reverted to a native SwiftUI view with alert data pulled from the API.

The alerts API at `api.atlassian.com/jsm/ops/api/{cloudId}/v1/alerts` returns 404 with Basic auth. However, if the user has a JSM Ops Integration API key (GenieKey), alerts CAN be fetched from `api.opsgenie.com/v2/alerts`. The key may or may not be configured.

## What to Do

### Phase 32A: Remove the WebView From OnCallView

1. **Remove the entire `alertsWebSection`** view and the `AlertsWebView` struct from `OnCallView.swift`.
2. **Remove the `WebKit` import** from OnCallView.swift.
3. **Remove** `AlertWebFilter` enum, `alertFilter`, `alertWebLoading`, `showAlertSSO`, `resolvedAccountId` state variables.
4. **Remove** `fetchAccountIdIfNeeded()` method.
5. **Remove** `alertURL(for:)` method.
6. **Revert the layout** from `VSplitView` back to a `ScrollView` containing both sections vertically:
   ```swift
   ScrollView {
       VStack(alignment: .leading, spacing: 24) {
           onCallSection
           alertsSection
       }
       .padding(20)
   }
   ```

### Phase 32B: Restore Alert Properties in OnCallViewModel

Add back to `OnCallViewModel`:

```swift
@Published var alerts: [OpsAlert] = []
@Published var isLoadingAlerts = false
@Published var alertFilter: AlertFilter = .open

enum AlertFilter: String, CaseIterable {
    case all             = "All"
    case open            = "Open"
    case unacknowledged  = "Unacknowledged"
    case assignedToMe    = "Assigned to Me"
    case closed          = "Closed"
}

var filteredAlerts: [OpsAlert] {
    switch alertFilter {
    case .all:            return alerts
    case .open:           return alerts.filter { $0.status.lowercased() == "open" }
    case .unacknowledged: return alerts.filter { $0.status.lowercased() == "open" && !($0.acknowledged ?? false) }
    case .assignedToMe:   return alerts.filter { $0.owner == currentUserAccountId }
    case .closed:         return alerts.filter { $0.status.lowercased() == "closed" }
    }
}
```

### Phase 32C: Add Alert Fetching (Optional — Graceful Degradation)

Alerts require a GenieKey (JSM Ops Integration API key). Check if `appState.jsmOpsAPIKey` exists (it may have been added in Phase 25). If the key exists, fetch alerts from `api.opsgenie.com/v2/alerts`. If it doesn't exist, show a helpful empty state — don't break the page.

In `OnCallViewModel`, add:

```swift
func loadAlerts(appState: AppState) async {
    // Try the GenieKey API first (if configured)
    let gk = appState.jsmOpsAPIKey  // may be empty
    guard !gk.isEmpty else {
        // No GenieKey — show helpful message, not an error
        alerts = []
        return
    }
    isLoadingAlerts = true
    do {
        alerts = try await service.listAlertsViaGenieKey(apiKey: gk, limit: 100)
    } catch {
        // Silently fail — alerts are supplementary
        alerts = []
    }
    isLoadingAlerts = false
}
```

Add `listAlertsViaGenieKey()` to `JSMOpsService`:
```swift
func listAlertsViaGenieKey(apiKey: String, limit: Int = 100, query: String? = nil) async throws -> [OpsAlert] {
    // GET https://api.opsgenie.com/v2/alerts?limit={limit}
    // Optional: &query={query}
    // Header: Authorization: GenieKey {apiKey}
    // Response: {"data": [...], "took": 0.3, "requestId": "..."}
}
```

Also add `acknowledged` and `owner` fields to the `OpsAlert` model if they don't exist:
```swift
struct OpsAlert: ... {
    // ... existing fields ...
    let acknowledged: Bool?
    let owner: String?        // accountId of the alert owner
}
```

In `load()`, add the alert loading back:
```swift
func load(appState: AppState) async {
    // ... existing guard ...
    error = nil
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.loadTeams(appState: appState) }
        group.addTask { await self.loadAlerts(appState: appState) }
    }
    lastFetched = Date()
}
```

### Phase 32D: Build the Native Alerts Section

Add back `alertsSection` to `OnCallView.swift` as a native SwiftUI view:

```swift
private var alertsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        // Header with filter picker
        HStack {
            Image(systemName: "bell.badge").foregroundStyle(.orange)
            Text("Alerts").font(.headline)
            Spacer()
            if vm.isLoadingAlerts { ProgressView().scaleEffect(0.7) }
            Picker("Filter", selection: $vm.alertFilter) {
                ForEach(OnCallViewModel.AlertFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 380)
        }

        // Alert list
        if vm.alerts.isEmpty && !vm.isLoadingAlerts {
            if appState.jsmOpsAPIKey.isEmpty {
                // No GenieKey configured — show setup prompt
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Alerts require a JSM Ops API Integration key.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("On-call schedules work with your Jira credentials, but alerts need an additional API Integration key created in your JSM Operations settings.")
                        .font(.caption).foregroundStyle(.tertiary)
                    Button {
                        appState.showSettings = true
                        appState.selectedSettingsTab = "jsm"
                    } label: {
                        Label("Configure in Settings", systemImage: "gear")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding()
            } else {
                // GenieKey configured but no alerts matching filter
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("No \(vm.alertFilter == .all ? "" : vm.alertFilter.rawValue.lowercased() + " ")alerts")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding()
            }
        } else {
            // Render alert rows
            VStack(spacing: 4) {
                ForEach(vm.filteredAlerts) { alert in
                    alertRow(alert)
                }
            }
        }
    }
    .padding()
    .background(RoundedRectangle(cornerRadius: 12).fill(.background))
}
```

And the alert row (same native style as before Phase 31):
```swift
private func alertRow(_ alert: OpsAlert) -> some View {
    HStack(alignment: .top, spacing: 10) {
        // Priority badge
        Text(alert.priority)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(priorityColor(alert.priority).opacity(0.15)))
            .foregroundStyle(priorityColor(alert.priority))
            .frame(width: 36)

        VStack(alignment: .leading, spacing: 3) {
            Text(alert.message).font(.callout).lineLimit(2)
            HStack(spacing: 8) {
                Text(alert.status.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(statusColor(alert.status).opacity(0.15)))
                    .foregroundStyle(statusColor(alert.status))
                if let source = alert.source, !source.isEmpty {
                    Text(source).font(.caption2).foregroundStyle(.secondary)
                }
                if !alert.createdAt.isEmpty {
                    Text(relativeTime(alert.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if let tags = alert.tags, !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                }
            }
        }
        Spacer()
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 8))
}
```

Add the helper functions back too (priorityColor, statusColor, relativeTime) if they were removed.

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- The on-call cards section must NOT be affected — only the alerts section changes.
- If `appState.jsmOpsAPIKey` doesn't exist as a property, add it back (it was added in Phase 25 — check if it survived Phase 26's cleanup).
- If `listAlertsViaGenieKey` or similar method already exists in JSMOpsService, reuse it. If not, add it.
