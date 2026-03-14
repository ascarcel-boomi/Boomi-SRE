# Boomi SRE App — Phase 34: Alert Actions — ACK, Close, Snooze, Add Note + Bulk Operations

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — add alert action methods here
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — add action functions here
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — add action buttons to alert rows and toolbar
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — OpsAlert model

---

## Confirmed Working Alert Actions (Tested Live)

All actions use the same Atlassian API with Basic auth (Jira email:token). All action endpoints return **202 Accepted** (async processing) except Add Note which returns **200** with the created note.

| Action | Method | Endpoint | Body | HTTP |
|--------|--------|----------|------|------|
| **Acknowledge** | POST | `/v1/alerts/{alertId}/acknowledge` | `{"note": "optional note"}` | 202 |
| **Close** | POST | `/v1/alerts/{alertId}/close` | `{"note": "optional note"}` | 202 |
| **Unacknowledge** | POST | `/v1/alerts/{alertId}/unacknowledge` | `{}` | 202 |
| **Add Note** | POST | `/v1/alerts/{alertId}/notes` | `{"note": "the note text"}` | 200 |
| **Snooze** | POST | `/v1/alerts/{alertId}/snooze` | `{"endTime": "2026-03-15T08:00:00.000Z"}` | 202 |

Base URL: `https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/alerts/{alertId}/{action}`
Auth: `Authorization: Basic {email:apiToken base64}` (same as schedules/teams/alert listing)

---

## Implementation

### Phase 34A: Add Alert Action Methods to JSMOpsService

Add these methods to `JSMOpsService`:

```swift
/// Acknowledge an alert.
func acknowledgeAlert(baseURL: String, email: String, apiToken: String,
                      alertId: String, note: String? = nil) async throws {
    let cid = try await getCloudId(baseURL: baseURL)
    var body: [String: Any] = [:]
    if let n = note, !n.isEmpty { body["note"] = n }
    try await post(path: "/alerts/\(alertId)/acknowledge", cloudId: cid,
                   email: email, apiToken: apiToken, body: body)
}

/// Close an alert.
func closeAlert(baseURL: String, email: String, apiToken: String,
                alertId: String, note: String? = nil) async throws {
    let cid = try await getCloudId(baseURL: baseURL)
    var body: [String: Any] = [:]
    if let n = note, !n.isEmpty { body["note"] = n }
    try await post(path: "/alerts/\(alertId)/close", cloudId: cid,
                   email: email, apiToken: apiToken, body: body)
}

/// Unacknowledge an alert.
func unacknowledgeAlert(baseURL: String, email: String, apiToken: String,
                        alertId: String) async throws {
    let cid = try await getCloudId(baseURL: baseURL)
    try await post(path: "/alerts/\(alertId)/unacknowledge", cloudId: cid,
                   email: email, apiToken: apiToken, body: [:])
}

/// Add a note to an alert.
func addAlertNote(baseURL: String, email: String, apiToken: String,
                  alertId: String, note: String) async throws {
    let cid = try await getCloudId(baseURL: baseURL)
    try await post(path: "/alerts/\(alertId)/notes", cloudId: cid,
                   email: email, apiToken: apiToken, body: ["note": note])
}

/// Snooze an alert until a given time.
func snoozeAlert(baseURL: String, email: String, apiToken: String,
                 alertId: String, endTime: Date) async throws {
    let cid = try await getCloudId(baseURL: baseURL)
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    try await post(path: "/alerts/\(alertId)/snooze", cloudId: cid,
                   email: email, apiToken: apiToken,
                   body: ["endTime": fmt.string(from: endTime)])
}
```

Also add a `post()` helper to JSMOpsService (alongside the existing `get()` helper):
```swift
private func post(path: String, cloudId: String, email: String,
                  apiToken: String, body: [String: Any]) async throws {
    let url = URL(string: "https://api.atlassian.com/jsm/ops/api/\(cloudId)/v1\(path)")!
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.httpMethod = "POST"
    if let authData = "\(email):\(apiToken)".data(using: .utf8) {
        req.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
    }
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if !body.isEmpty {
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let respBody = String(data: data, encoding: .utf8) ?? ""
        throw JSMError.httpError(status: code, body: respBody)
    }
}
```

### Phase 34B: Add Action Methods to OnCallViewModel

```swift
// MARK: - Alert Actions

@Published var actionInProgress: Set<String> = []  // alert IDs currently being actioned
@Published var actionError: String?
@Published var actionSuccess: String?

func acknowledgeAlert(_ alert: OpsAlert, note: String? = nil, appState: AppState) async {
    await performAction(alertId: alert.id, appState: appState, successMessage: "Alert acknowledged") {
        try await service.acknowledgeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                           apiToken: appState.jiraAPIToken, alertId: alert.id, note: note)
    }
}

func closeAlert(_ alert: OpsAlert, note: String? = nil, appState: AppState) async {
    await performAction(alertId: alert.id, appState: appState, successMessage: "Alert closed") {
        try await service.closeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                     apiToken: appState.jiraAPIToken, alertId: alert.id, note: note)
    }
}

func unacknowledgeAlert(_ alert: OpsAlert, appState: AppState) async {
    await performAction(alertId: alert.id, appState: appState, successMessage: "Alert unacknowledged") {
        try await service.unacknowledgeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                              apiToken: appState.jiraAPIToken, alertId: alert.id)
    }
}

func addNoteToAlert(_ alert: OpsAlert, note: String, appState: AppState) async {
    await performAction(alertId: alert.id, appState: appState, successMessage: "Note added") {
        try await service.addAlertNote(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                       apiToken: appState.jiraAPIToken, alertId: alert.id, note: note)
    }
}

func snoozeAlert(_ alert: OpsAlert, until endTime: Date, appState: AppState) async {
    await performAction(alertId: alert.id, appState: appState, successMessage: "Alert snoozed") {
        try await service.snoozeAlert(baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
                                      apiToken: appState.jiraAPIToken, alertId: alert.id, endTime: endTime)
    }
}

// Bulk actions
func bulkAcknowledge(alerts: [OpsAlert], appState: AppState) async {
    for alert in alerts {
        await acknowledgeAlert(alert, appState: appState)
    }
}

func bulkClose(alerts: [OpsAlert], appState: AppState) async {
    for alert in alerts {
        await closeAlert(alert, appState: appState)
    }
}

private func performAction(alertId: String, appState: AppState, successMessage: String,
                           action: () async throws -> Void) async {
    actionInProgress.insert(alertId)
    actionError = nil
    do {
        try await action()
        actionSuccess = successMessage
        // Refresh alerts after action (short delay for async processing)
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        await loadAlerts(appState: appState)
    } catch {
        actionError = error.localizedDescription
    }
    actionInProgress.remove(alertId)
    // Auto-clear success message after 3 seconds
    if actionSuccess != nil {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            actionSuccess = nil
        }
    }
}
```

### Phase 34C: Add Action Buttons to Individual Alert Rows

Update `alertRow()` in `OnCallView.swift` to include action buttons:

For each alert row, add a button bar at the right side or below the alert content:

```swift
// Inside alertRow(), after the existing content:
HStack(spacing: 6) {
    // ACK / UNACK toggle
    if alert.status == "open" && !alert.acknowledged {
        Button {
            Task { await vm.acknowledgeAlert(alert, appState: appState) }
        } label: {
            Label("ACK", systemImage: "checkmark.circle")
                .font(.caption2)
        }
        .buttonStyle(.bordered).controlSize(.mini)
        .disabled(vm.actionInProgress.contains(alert.id))
    } else if alert.acknowledged && alert.status != "closed" {
        Button {
            Task { await vm.unacknowledgeAlert(alert, appState: appState) }
        } label: {
            Label("Un-ACK", systemImage: "arrow.uturn.backward.circle")
                .font(.caption2)
        }
        .buttonStyle(.bordered).controlSize(.mini)
        .disabled(vm.actionInProgress.contains(alert.id))
    }

    // CLOSE
    if alert.status != "closed" {
        Button {
            Task { await vm.closeAlert(alert, appState: appState) }
        } label: {
            Label("Close", systemImage: "xmark.circle")
                .font(.caption2)
        }
        .buttonStyle(.bordered).controlSize(.mini).tint(.red)
        .disabled(vm.actionInProgress.contains(alert.id))
    }

    // SNOOZE (show a menu with preset durations)
    if alert.status != "closed" {
        Menu {
            Button("30 minutes") { snooze(alert, minutes: 30) }
            Button("1 hour") { snooze(alert, minutes: 60) }
            Button("4 hours") { snooze(alert, minutes: 240) }
            Button("Until tomorrow 9 AM") { snoozeUntilTomorrow9AM(alert) }
        } label: {
            Label("Snooze", systemImage: "moon.zzz")
                .font(.caption2)
        }
        .menuStyle(.borderlessButton)
        .disabled(vm.actionInProgress.contains(alert.id))
    }

    // ADD NOTE
    Button {
        selectedAlertForNote = alert
        showNoteSheet = true
    } label: {
        Label("Note", systemImage: "note.text.badge.plus")
            .font(.caption2)
    }
    .buttonStyle(.bordered).controlSize(.mini)

    // Loading indicator for this specific alert
    if vm.actionInProgress.contains(alert.id) {
        ProgressView().scaleEffect(0.5)
    }
}
```

Add snooze helper methods to the view:
```swift
private func snooze(_ alert: OpsAlert, minutes: Int) {
    let endTime = Date().addingTimeInterval(TimeInterval(minutes * 60))
    Task { await vm.snoozeAlert(alert, until: endTime, appState: appState) }
}

private func snoozeUntilTomorrow9AM(_ alert: OpsAlert) {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    components.day! += 1
    components.hour = 9
    components.minute = 0
    if let endTime = Calendar.current.date(from: components) {
        Task { await vm.snoozeAlert(alert, until: endTime, appState: appState) }
    }
}
```

### Phase 34D: Add Note Sheet

Add a sheet for adding notes to alerts:

```swift
@State private var selectedAlertForNote: OpsAlert?
@State private var showNoteSheet = false
@State private var noteText = ""
```

The sheet:
```swift
.sheet(isPresented: $showNoteSheet) {
    VStack(spacing: 16) {
        Text("Add Note to Alert").font(.headline)
        if let alert = selectedAlertForNote {
            Text(alert.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        TextEditor(text: $noteText)
            .frame(height: 100)
            .border(Color.secondary.opacity(0.2))
        HStack {
            Button("Cancel") { showNoteSheet = false; noteText = "" }
                .buttonStyle(.bordered)
            Spacer()
            Button("Add Note") {
                if let alert = selectedAlertForNote {
                    Task {
                        await vm.addNoteToAlert(alert, note: noteText, appState: appState)
                        showNoteSheet = false
                        noteText = ""
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    .padding(20)
    .frame(width: 400)
}
```

### Phase 34E: Bulk Actions Toolbar

Add a selection mechanism and bulk action toolbar to the alerts section:

1. **Add multi-select state:**
   ```swift
   @State private var selectedAlertIds: Set<String> = []
   @State private var isSelectMode = false
   ```

2. **Add a "Select" toggle button** in the alerts section header:
   ```swift
   Button(isSelectMode ? "Done" : "Select") {
       isSelectMode.toggle()
       if !isSelectMode { selectedAlertIds.removeAll() }
   }
   .buttonStyle(.bordered).controlSize(.small)
   ```

3. **When in select mode**, show checkboxes on each alert row:
   ```swift
   if isSelectMode {
       Image(systemName: selectedAlertIds.contains(alert.id) ? "checkmark.circle.fill" : "circle")
           .foregroundStyle(selectedAlertIds.contains(alert.id) ? Color.accentColor : .secondary)
           .onTapGesture { toggleSelection(alert.id) }
   }
   ```

4. **Show a bulk action bar** when alerts are selected:
   ```swift
   if isSelectMode && !selectedAlertIds.isEmpty {
       HStack(spacing: 12) {
           Text("\(selectedAlertIds.count) selected").font(.callout.bold())
           Spacer()
           Button("Select All") {
               selectedAlertIds = Set(vm.filteredAlerts.map(\.id))
           }
           .buttonStyle(.bordered).controlSize(.small)

           Button {
               let selected = vm.filteredAlerts.filter { selectedAlertIds.contains($0.id) }
               Task { await vm.bulkAcknowledge(alerts: selected, appState: appState) }
               selectedAlertIds.removeAll()
           } label: {
               Label("ACK All", systemImage: "checkmark.circle")
           }
           .buttonStyle(.bordered).controlSize(.small)

           Button {
               let selected = vm.filteredAlerts.filter { selectedAlertIds.contains($0.id) }
               Task { await vm.bulkClose(alerts: selected, appState: appState) }
               selectedAlertIds.removeAll()
           } label: {
               Label("Close All", systemImage: "xmark.circle")
           }
           .buttonStyle(.bordered).controlSize(.small).tint(.red)
       }
       .padding(.horizontal, 16).padding(.vertical, 8)
       .background(Color.accentColor.opacity(0.08))
       .clipShape(RoundedRectangle(cornerRadius: 8))
   }
   ```

### Phase 34F: Success/Error Feedback

Show action feedback at the top of the alerts section:

```swift
if let success = vm.actionSuccess {
    HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Text(success).font(.caption).foregroundStyle(.green)
        Spacer()
    }
    .padding(.horizontal, 16).padding(.vertical, 6)
    .background(Color.green.opacity(0.08))
    .transition(.move(edge: .top).combined(with: .opacity))
}

if let error = vm.actionError {
    HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
        Text(error).font(.caption).foregroundStyle(.red)
        Spacer()
        Button("Dismiss") { vm.actionError = nil }
            .font(.caption).buttonStyle(.plain)
    }
    .padding(.horizontal, 16).padding(.vertical, 6)
    .background(Color.red.opacity(0.08))
}
```

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- All actions should show a confirmation for destructive operations (Close) — use a simple alert dialog.
- After any action, automatically refresh the alerts list (with a 1-second delay for async processing).
- The bulk action bar should only appear when in select mode with at least one alert selected.
- Don't break the on-call schedules section or any other feature.
