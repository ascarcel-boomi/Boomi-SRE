# Boomi SRE App — Phase 33: Fix Alerts — Use Atlassian API (Same Auth as Schedules)

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — check if there's a `listAlerts` method and what URL/auth it uses
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — check `loadAlerts()` method
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — the alerts section UI
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — OpsAlert model

---

## Root Cause

Alerts DO work with the same Atlassian API and Basic auth used for schedules and teams. No GenieKey is needed.

**Confirmed working endpoint (tested live, returns 105,516 alerts):**
```
GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/alerts?limit=20
Authorization: Basic {email:apiToken base64}
```

**Response format (confirmed):**
```json
{
  "values": [
    {
      "id": "bf415f36-...",
      "tinyId": "148783",
      "createdAt": "2026-03-14T23:11:11.485Z",
      "updatedAt": "2026-03-14T23:12:15.275Z",
      "message": "[Coralogix] SQS: prod-rivery-feeders-v2, Approximate Age Of Oldest Message...",
      "entity": "",
      "source": "Coralogix",
      "status": "closed",
      "alias": "7785315d...",
      "tags": [],
      "acknowledged": false,
      "closeTime": "2026-03-14T23:12:15.275Z",
      "count": 1,
      "owner": "",
      "snoozed": false,
      "lastOccuredAt": "2026-03-14T23:11:11.485Z",
      "integrationType": "Coralogix",
      "integrationName": "Data Integration Devops - Coralogix",
      "priority": "P3",
      "responders": [{"id": "c8007b3c-...", "type": "team"}],
      "actions": [],
      "seen": true
    }
  ],
  "links": {"next": "/v1/alerts?offset=20&size=20&sort=insertedAt&order=desc"},
  "count": 105516
}
```

Key fields: `message`, `status` (open/closed/acked), `priority` (P1-P5), `acknowledged` (bool), `owner` (email string), `source`, `createdAt`, `updatedAt`, `tags`, `responders`, `integrationType`, `integrationName`, `tinyId`, `snoozed`.

---

## Fix

### Phase 33A: Add/Fix `listAlerts` in JSMOpsService

Add (or fix) a `listAlerts` method that uses the same Atlassian API and auth as `listSchedules` and `listTeams`:

```swift
func listAlerts(baseURL: String, email: String, apiToken: String,
                limit: Int = 50, query: String? = nil) async throws -> [OpsAlert] {
    let cid = try await getCloudId(baseURL: baseURL)
    var path = "/alerts?limit=\(limit)&sort=createdAt&order=desc"
    if let q = query, !q.isEmpty {
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        path += "&query=\(encoded)"
    }
    let data = try await get(path: path, cloudId: cid, email: email, apiToken: apiToken)

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let values = json["values"] as? [[String: Any]] else { return [] }
    return values.compactMap { parseAlert($0) }
}
```

**Important:** The response wraps alerts in `{"values": [...]}` — NOT `{"data": [...]}` like the OpsGenie v2 API. This is the Atlassian v1 API format (same as schedules).

### Phase 33B: Update OpsAlert Model

Update `OpsAlert` in `JSMOpsModels.swift` to include all useful fields from the confirmed response:

```swift
struct OpsAlert: Identifiable, Sendable {
    let id: String
    let tinyId: String         // short numeric ID (e.g., "148783")
    let message: String
    let status: String         // "open", "closed", "acked"
    let priority: String       // "P1", "P2", "P3", "P4", "P5"
    let acknowledged: Bool
    let owner: String          // email of the owner (may be empty)
    let source: String         // e.g., "Coralogix", "New Relic"
    let integrationType: String // e.g., "Coralogix", "NewRelicV2"
    let integrationName: String // e.g., "Data Integration Devops - Coralogix"
    let createdAt: String
    let updatedAt: String
    let tags: [String]
    let snoozed: Bool
    let count: Int             // number of occurrences
    let responders: [AlertResponder]
}

struct AlertResponder: Sendable {
    let id: String
    let type: String  // "team", "user"
}
```

### Phase 33C: Fix Alert Parsing

Add a `parseAlert()` method to `JSMOpsService` (or update the existing one) that handles the confirmed response format:

```swift
private func parseAlert(_ d: [String: Any]) -> OpsAlert? {
    guard let id = d["id"] as? String,
          let message = d["message"] as? String else { return nil }
    let responders = (d["responders"] as? [[String: Any]] ?? []).compactMap { r -> AlertResponder? in
        guard let rid = r["id"] as? String, let rtype = r["type"] as? String else { return nil }
        return AlertResponder(id: rid, type: rtype)
    }
    return OpsAlert(
        id: id,
        tinyId: d["tinyId"] as? String ?? "",
        message: message,
        status: d["status"] as? String ?? "open",
        priority: d["priority"] as? String ?? "P3",
        acknowledged: d["acknowledged"] as? Bool ?? false,
        owner: d["owner"] as? String ?? "",
        source: d["source"] as? String ?? "",
        integrationType: d["integrationType"] as? String ?? "",
        integrationName: d["integrationName"] as? String ?? "",
        createdAt: d["createdAt"] as? String ?? "",
        updatedAt: d["updatedAt"] as? String ?? "",
        tags: d["tags"] as? [String] ?? [],
        snoozed: d["snoozed"] as? Bool ?? false,
        count: d["count"] as? Int ?? 1,
        responders: responders
    )
}
```

### Phase 33D: Fix `loadAlerts()` in OnCallViewModel

Remove any GenieKey/OpsGenie logic. Use the same Jira credentials:

```swift
func loadAlerts(appState: AppState) async {
    guard appState.isJiraConfigured else { return }
    isLoadingAlerts = true
    do {
        alerts = try await service.listAlerts(
            baseURL: appState.jiraBaseURL,
            email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken,
            limit: 100
        )
    } catch {
        // Alert loading failure shouldn't block the rest of the page
        alerts = []
    }
    isLoadingAlerts = false
}
```

Add `loadAlerts` back to the `load()` task group:
```swift
func load(appState: AppState) async {
    guard appState.isJiraConfigured else { ... }
    error = nil
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.loadTeams(appState: appState) }
        group.addTask { await self.loadAlerts(appState: appState) }
    }
    lastFetched = Date()
}
```

### Phase 33E: Update Alerts Section UI

Remove the "Alerts require a JSM Ops API Integration key" message. Since alerts use the same Jira credentials, if Jira is configured, alerts should just load.

Update the empty state for each filter:
- **All / Open / Unacknowledged:** "No matching alerts" with green checkmark
- **Assigned to Me:** "No alerts assigned to you" (needs the user's email — use `appState.jiraEmail` to match against `alert.owner`)
- **Closed:** Show closed alerts (there will be many — the API returned 105,516 total)

For the "Assigned to Me" filter, match `alert.owner` against `appState.jiraEmail`:
```swift
case .assignedToMe: return alerts.filter { $0.owner.lowercased() == appState.jiraEmail.lowercased() }
```

**Note:** The `owner` field is an email string (e.g., "john.yocum@boomi.com"), NOT an accountId. So we can match directly against `appState.jiraEmail`.

### Phase 33F: Remove GenieKey References from Alerts

Search the entire codebase for any remaining references to GenieKey or `jsmOpsAPIKey` related to alerts and remove them. The alerts section should use the same auth path as schedules and teams — no separate key needed.

If `appState.jsmOpsAPIKey` still exists, it's fine to keep it (it might be used for future features), but the alerts loading should NOT depend on it.

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- Don't break the on-call schedules section — only alerts changes.
- The default alert filter should be "Open" (not "All") since there are 105K+ total alerts — loading all of them would be slow. The API `limit` parameter controls this.
