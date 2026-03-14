# Boomi SRE App — Phase 26: Fix On-Call — Use Standard Atlassian API Token (Not GenieKey)

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files — they need to be fixed:**
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — currently uses `api.opsgenie.com` with `GenieKey` (WRONG)
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — currently uses `appState.jsmOpsAPIKey` (WRONG)
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — references "OpsGenie" in UI text
- `BoomiSRE/Sources/Views/Settings/JSMSettingsContent.swift` — setup wizard references "OpsGenie" and asks for a separate API key
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — data models
- `BoomiSRE/Sources/Models/AppState.swift` — has `jsmOpsAPIKey` (unnecessary — should use existing Jira creds)
- `BoomiSRE/Sources/Services/CredentialDiscovery.swift` — scans for OPSGENIE_API_KEY

---

## Root Cause — Previous Fix Was Wrong

Phase 25 incorrectly switched the JSM Ops API to use `api.opsgenie.com` with a `GenieKey` header. This was wrong.

**The CORRECT configuration, confirmed by live testing:**

- **Base URL:** `https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/`
- **Auth:** Standard Atlassian Basic auth — `email:apiToken` (the SAME token used for Jira and Confluence)
- **CloudId:** `2cd0c4d5-fb26-4e47-b128-dbf33f624fa2` (from `https://boomii.atlassian.net/_edge/tenant_info`)
- **NO separate API key needed** — the user's existing Jira API token works

**Confirmed working endpoints (tested live, returns real data):**
- `GET /v1/schedules` → returns 21 on-call schedules (200 OK)
- `GET /v1/schedules/{scheduleId}/on-calls` → returns current on-call participants (200 OK)
- `GET /v1/teams` → returns all JSM Ops teams (200 OK)
- `GET /v1/alerts` → returns 404 (alerts are NOT available through this API — they require the GenieKey Integration API)

**Response formats (confirmed):**
- Schedules: `{"values": [{"id": "...", "name": "CAMSRE_PrimarySchedule", "description": "...", "timezone": "Etc/UTC", "enabled": true, "teamId": "..."}], "links": {"next": null}}`
- On-call: `{"onCallParticipants": [{"id": "712020:...", "type": "user"}]}`
- Teams: plain array `[{"teamId": "...", "teamName": "CAM SRE (not used)"}]` (NOT wrapped in `values`)

**Relevant Atlassian docs:**
- Auth: https://developer.atlassian.com/cloud/jira/service-desk/rest/intro/#authentication (same as Jira)
- API Integration setup (for alerts only — NOT needed for schedules/on-call): https://support.atlassian.com/jira-service-management-cloud/docs/set-up-an-api-integration/
- Terraform provider (confirms email+token auth): https://support.atlassian.com/jira-service-management-cloud/docs/set-up-atlassian-operations-terraform-provider/

---

## Implementation Plan

### Phase 26A: Revert JSMOpsService to Use Atlassian API with Basic Auth

**Completely rewrite `JSMOpsService.swift`:**

```swift
actor JSMOpsService {
    private var cloudId: String?

    /// Discover the Atlassian Cloud ID.
    func getCloudId(baseURL: String) async throws -> String {
        if let cached = cloudId { return cached }
        // GET {baseURL}/_edge/tenant_info — no auth needed
        // Parse {"cloudId": "..."}
        let url = URL(string: "\(baseURL.trimmingSlash)/_edge/tenant_info")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw JSMError.cloudIdNotFound
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["cloudId"] as? String else {
            throw JSMError.cloudIdNotFound
        }
        cloudId = id
        return id
    }

    /// List all on-call schedules.
    func listSchedules(baseURL: String, email: String, apiToken: String) async throws -> [OpsSchedule] {
        let cid = try await getCloudId(baseURL: baseURL)
        // GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/schedules
        // Auth: Basic email:apiToken
        // Response: {"values": [...], "links": {"next": ...}}
    }

    /// Get who is currently on call for a schedule.
    func getOnCall(baseURL: String, email: String, apiToken: String, scheduleId: String) async throws -> [OnCallParticipant] {
        let cid = try await getCloudId(baseURL: baseURL)
        // GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/schedules/{scheduleId}/on-calls
        // Auth: Basic email:apiToken
        // Response: {"onCallParticipants": [{"id": "...", "type": "user"}]}
        // Note: participants only have "id" (accountId) and "type" — need to resolve names separately
    }

    /// List all teams.
    func listTeams(baseURL: String, email: String, apiToken: String) async throws -> [OpsTeam] {
        let cid = try await getCloudId(baseURL: baseURL)
        // GET https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/teams
        // Auth: Basic email:apiToken
        // Response: plain array [{"teamId": "...", "teamName": "..."}]
        // NOTE: response is a bare JSON array, NOT wrapped in {"values": [...]}
    }

    // MARK: - Private helpers

    private func get(path: String, cloudId: String, email: String, apiToken: String) async throws -> Data {
        let url = URL(string: "https://api.atlassian.com/jsm/ops/api/\(cloudId)/v1\(path)")!
        var req = URLRequest(url: url, timeoutInterval: 15)
        // Basic auth: email:apiToken base64 encoded
        if let authData = "\(email):\(apiToken)".data(using: .utf8) {
            req.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JSMError.httpError(status: code, body: body)
        }
        return data
    }
}
```

**Key points:**
- Base URL is `https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/`
- Auth is Basic auth with the user's Jira email + API token (same creds as Jira)
- CloudId is fetched from `{jiraBaseURL}/_edge/tenant_info` (no auth needed, cached)
- Teams response is a **bare JSON array**, not wrapped in `{"values": [...]}`
- On-call response has `onCallParticipants` with accountIds (not display names — may need to resolve via Jira user API)
- Alerts endpoint returns 404 on this API — do NOT implement alerts here. Show a note: "Alerts require a separate JSM Ops API Integration key. On-call and schedules work with your Jira credentials."

### Phase 26B: Update OnCallViewModel — Use Jira Credentials

Replace all `appState.jsmOpsAPIKey` references with the standard Jira credentials:

```swift
// Old:
try await service.listSchedules(apiKey: appState.jsmOpsAPIKey)
// New:
try await service.listSchedules(baseURL: appState.jiraBaseURL, email: appState.jiraEmail, apiToken: appState.jiraAPIToken)
```

Update the guard check:
```swift
// Old:
guard !appState.jsmOpsAPIKey.isEmpty else { error = "JSM Ops API key not configured..." }
// New:
guard appState.isJiraConfigured else { error = "Jira not configured — add credentials in Settings → Jira" }
```

### Phase 26C: Remove Separate JSM Ops API Key

1. **Remove `jsmOpsAPIKey`** from AppState (or deprecate it — only needed for alerts in the future).
2. **Remove `jsmOpsAuthStatus`** from AppState — on-call auth status is the same as Jira auth status.
3. **Remove `JSMSettingsContent.swift`** or simplify it — no separate API key setup wizard needed for on-call/schedules. The existing Jira credentials work.
4. **Remove OpsGenie credential discovery** from `CredentialDiscovery.swift`.

### Phase 26D: Remove All "OpsGenie" References

Search the ENTIRE `Sources/` directory for "OpsGenie", "opsgenie", "GenieKey" and replace:
- All user-facing text: use "JSM Operations" or "JSM Ops"
- Code comments: "JSM Operations API at api.atlassian.com"
- The `GenieKey` header: **remove entirely** — use Basic auth instead
- Error messages: reference "Jira credentials" not "OpsGenie API key"

### Phase 26E: Update OnCallView

1. **Remove the "API key setup" empty state.** Since on-call uses Jira credentials, if Jira is configured, on-call should just work. Replace the setup prompt with:
   - If Jira is not configured: "Configure Jira in Settings to view on-call schedules."
   - If Jira is configured but schedules fail: show the actual error from the API.

2. **Resolve on-call participant names.** The on-call endpoint returns accountIds (`712020:xxxx`), not display names. To show names:
   - Use the Jira user API: `GET /rest/api/3/user?accountId={id}` to resolve each accountId to a display name
   - Cache the results (accountId → displayName mapping) in the ViewModel
   - Or: show the accountId initially and resolve names in the background

3. **Settings for JSM Ops** should just be the favorites picker:
   - "Discover Teams" button (calls `listTeams()` using Jira credentials)
   - Team list with favorite toggles
   - "Discover Schedules" button (calls `listSchedules()`)
   - Schedule list with favorite toggles
   - No API key field needed

### Phase 26F: Handle Alerts Separately (Optional)

Alerts are NOT available through the standard API. For now:
- Show a note in the Alerts section: "Alerts require a JSM Ops API Integration key (separate from your Jira token). Set up an integration at your JSM Ops Integrations page."
- Provide a link to `https://boomii.atlassian.net/jira/ops/integrations`
- If the user provides a GenieKey (optional field in Settings), use it for alerts only — via the `api.opsgenie.com/v2/alerts` endpoint
- This is optional and should not block the on-call/schedules functionality

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- The critical fix is Phase 26A — reverting to the correct API that actually works.
- Do NOT break Jira, Confluence, or any other service — only JSMOpsService changes.
- Test that `getCloudId()` still works (it's a public endpoint, no auth needed).
