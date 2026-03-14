# Boomi SRE App — Phase 27: Fix On-Call View — Name Resolution, Alerts Message, Filter Layout

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — On-Call UI with three bugs
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — on-call data loading, participant name resolution
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — JSM Ops API client
- `BoomiSRE/Sources/Services/JiraService.swift` — Jira REST API (has user lookup or can be extended)

---

## Bugs to Fix

### 1. "Who's On-Call" cards show "Loading on-call..." forever and never resolve names

In `onCallCard()` (line ~143), the on-call participants are loaded via `.task { await vm.loadOnCall(for: team.id, appState: appState) }` — but the on-call API returns participants with only an `id` (Atlassian accountId like `712020:xxxx`) and `type`, NOT display names. The view tries to show `vm.displayNames[p.name]` but `p.name` is the accountId, not a name, and `displayNames` is probably never populated.

**Confirmed API response format:**
```json
{"onCallParticipants": [{"id": "712020:1c18606a-24ed-49f6-b7c4-75e40fa7b0fa", "type": "user"}]}
```

Note: the field is `id`, not `name`.

**Fix:**
1. Check that the `OnCallParticipant` model and the JSON parsing in `JSMOpsService.getOnCall()` correctly read the `id` field (not `name`). The participant's identifier is in the `id` field.
2. After `loadOnCall()` fetches participants, resolve each participant's accountId to a display name by calling the Jira user API: `GET {baseURL}/rest/api/3/user?accountId={accountId}` with Basic auth (email:token). This returns `{"displayName": "Adam Scarcella", ...}`.
3. Add a method to resolve names — either in `OnCallViewModel` or `JiraService`:
   ```swift
   func resolveUserName(baseURL: String, email: String, apiToken: String, accountId: String) async throws -> String
   ```
4. Cache resolved names in `vm.displayNames: [String: String]` (accountId → displayName) so they don't re-fetch on every render.
5. If name resolution fails for a participant, show the accountId as fallback text.
6. Make sure `loadOnCall()` actually completes and the participants array is populated — add error logging if the parse returns empty.

### 2. Alerts section shows broken link and misleading text

In `alertsSection` (line ~226-239), when alerts are empty it shows "Alerts require a JSM Ops API Integration key (separate from your Jira token)" with a button linking to `https://boomii.atlassian.net/jira/ops/integrations`. This URL doesn't work for the user.

**Fix:** Replace the entire empty-alerts block (lines 226-239) with a clean, non-misleading message:

```swift
if vm.alerts.isEmpty && !vm.isLoadingAlerts {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("No active alerts").font(.callout).foregroundStyle(.secondary)
        }
        Text("Alerts from JSM Operations will appear here when they are available.")
            .font(.caption).foregroundStyle(.tertiary)
    }
    .padding()
}
```

Remove the "Set Up JSM Ops Integration" button and the broken URL entirely.

### 3. The "Filter" label next to the segmented picker is squished/truncated

In `alertsSection` (line ~216-222), the `Picker("Filter", selection:)` with `.pickerStyle(.segmented)` has a visible "Filter" label that gets squished into a narrow vertical strip reading "Fil te r".

**Fix:** Hide the label and widen the picker slightly:

```swift
Picker("Filter", selection: $vm.alertFilter) {
    ForEach(OnCallViewModel.AlertFilter.allCases, id: \.self) { f in
        Text(f.rawValue).tag(f)
    }
}
.pickerStyle(.segmented)
.labelsHidden()
.frame(width: 280)
```

---

## General Guidelines

- Run `swift build` to verify.
- Commit with message: "Fix On-Call: resolve participant names, remove broken alerts link, fix squished filter label".
