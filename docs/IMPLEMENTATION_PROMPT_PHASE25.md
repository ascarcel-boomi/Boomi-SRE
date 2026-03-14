# Boomi SRE App — Phase 25: Fix On-Call — JSM Ops Requires a Separate API Integration Key

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — current implementation uses Basic auth with Jira email:token (WRONG)
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — calls JSMOpsService with Jira credentials
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — On-Call UI, error display
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — OpsTeam, OnCallParticipant, OpsAlert, OpsSchedule
- `BoomiSRE/Sources/Models/AppState.swift` — `favoriteJSMTeams`, `jsmCloudId`, Jira credentials
- `BoomiSRE/Sources/Views/SettingsView.swift` — look for any JSM settings tab
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — secrets storage

**Key constraints:**
- Pure SwiftUI. No third-party frameworks.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600).

---

## Root Cause

The On-Call section returns **401 Unauthorized** because the JSM Operations API (on-call, alerts, schedules) uses a **completely different authentication method** than the standard Jira REST API.

**Current (broken) auth:** Basic auth with `email:jiraApiToken`
**Required auth:** `Authorization: GenieKey {jsmOpsApiKey}`

The standard Jira API token (from `id.atlassian.com/manage-profile/security/api-tokens`) does NOT work for JSM Operations endpoints. JSM Ops requires an **API Integration key** created within the JSM Ops interface itself.

### JSM Ops API — Confirmed Details

**Authentication:**
- Header: `Authorization: GenieKey {api_key}`
- This is NOT the Jira API token. It is a separate credential created as an API Integration.
- Jira Basic auth does NOT work on these endpoints (confirmed: returns 401).

**Base URL:**
- `https://api.opsgenie.com/v2/`
- (EU instances: `https://api.eu.opsgenie.com/v2/`)

**Key endpoints:**
- Schedules: `GET /v2/schedules`
- Who is on call: `GET /v2/schedules/{scheduleId}/on-calls?flat=true`
- Next on call: `GET /v2/schedules/{scheduleId}/next-on-calls`
- Teams: `GET /v2/teams`
- Alerts: `GET /v2/alerts`
- Alert count: `GET /v2/alerts/count`

**Response format:**
- All responses wrap data in `{"data": {...}, "took": 0.3, "requestId": "..."}`
- Schedules list: `{"data": [...], "totalCount": N}`
- On-call (with `flat=true`): `{"data": {"_parent": {...}, "onCallRecipients": ["user@email.com"]}}`
- On-call (without flat): `{"data": {"_parent": {...}, "onCallParticipants": [{...}]}}`

**How to create the API Integration key:**
1. Go to `https://boomii.atlassian.net/jira/ops/integrations`
2. Click **"Add integration"**
3. Search for **"API"** and select it
4. Name it: "Boomi SRE App"
5. Optionally assign to a team (for team-scoped access)
6. Click **"Continue"**
7. Expand **"Steps to configure the integration"** and **copy the API key**
8. Click **"Turn on integration"** to activate it

**Important notes:**
- If you don't see the Integrations page, navigate from your team dashboard: **Teams → [Your Team] → Integrations → Add integration**
- The account owner must verify their email before API integrations work.
- Team-scoped keys can only access that team's alerts/schedules.

---

## Implementation Plan

### Phase 25A: Add JSM Ops API Key to AppState & Settings

1. **Add new credential to AppState:**
   ```swift
   var jsmOpsAPIKey: String {
       get { KeychainHelper.load(key: "jsm-ops-api-key") ?? "" }
       set { try? KeychainHelper.save(key: "jsm-ops-api-key", value: newValue); objectWillChange.send() }
   }
   ```

2. **Add a JSM Operations settings section** (new tab or section within an existing tab):

   **Settings → JSM Operations:**
   - **API Key field** (SecureField) for the JSM Ops API key
   - **Guided setup:**
     ```
     On-Call & Alerts use the JSM Operations API, which requires a separate
     API Integration key from your Jira token.

     Step 1: Open JSM Ops Integrations in your browser
             [Open boomii.atlassian.net/jira/ops/integrations] ← clickable link button

     Step 2: Click "Add integration"
             Search for "API" and select it

     Step 3: Name it "Boomi SRE App"
             Optionally assign to your team for team-scoped access
             Click "Continue"

     Step 4: Expand "Steps to configure the integration" and copy the API key
             Click "Turn on integration" to activate

     Step 5: Paste the API key below
             [API Key field]  [Paste & Save]

     Note: If you don't see the Integrations page, navigate from your team
     dashboard: Teams → [Your Team] → Integrations → Add integration.
     Ask your JSM admin if you need help.

     Learn more: https://support.atlassian.com/opsgenie/docs/create-a-default-api-integration/
     ```
   - **"Test Connection" button** that calls `listSchedules()` with the new key
   - Status indicator: green "Connected — found N schedules" / red with error message
   - **Favorite teams section** (existing): discover teams button + team list with toggles

3. **Add to credential discovery** (`CredentialDiscovery.swift`): scan for `OPSGENIE_API_KEY`, `JSM_OPS_API_KEY`, `GENIEKEY` in MCP credential directories.

### Phase 25B: Rewrite JSMOpsService — Correct Auth & Base URL

**Replace the entire implementation** to use the correct API at `api.opsgenie.com` with `GenieKey` auth:

```swift
actor JSMOpsService {
    private let baseURL = "https://api.opsgenie.com/v2"

    /// List all schedules.
    func listSchedules(apiKey: String) async throws -> [OpsSchedule] {
        // GET https://api.opsgenie.com/v2/schedules
        // Header: Authorization: GenieKey {apiKey}
        // Response: {"data": [...schedules...], "totalCount": N}
    }

    /// Get who is currently on call for a schedule.
    func getOnCall(apiKey: String, scheduleId: String) async throws -> [OnCallParticipant] {
        // GET https://api.opsgenie.com/v2/schedules/{scheduleId}/on-calls?flat=true
        // Header: Authorization: GenieKey {apiKey}
        // Response (flat): {"data": {"_parent": {...}, "onCallRecipients": ["email@example.com"]}}
        // Also try without flat=true for more detail:
        //   {"data": {"onCallParticipants": [{"name": "...", "type": "user"}]}}
    }

    /// List all teams.
    func listTeams(apiKey: String) async throws -> [OpsTeam] {
        // GET https://api.opsgenie.com/v2/teams
        // Header: Authorization: GenieKey {apiKey}
    }

    /// List alerts.
    func listAlerts(apiKey: String, query: String? = nil) async throws -> [OpsAlert] {
        // GET https://api.opsgenie.com/v2/alerts?limit=50
        // Optional: &query={query}
        // Header: Authorization: GenieKey {apiKey}
    }

    /// Get alert count.
    func getAlertCount(apiKey: String, query: String? = nil) async throws -> Int {
        // GET https://api.opsgenie.com/v2/alerts/count
        // Header: Authorization: GenieKey {apiKey}
    }

    // MARK: - Private

    private func request(path: String, apiKey: String, queryItems: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(string: "\(baseURL)\(path)")!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var req = URLRequest(url: components.url!, timeoutInterval: 15)
        req.setValue("GenieKey \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw JSMError.httpError(status: 0, body: "No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw JSMError.httpError(status: http.statusCode, body: body)
        }
        return (data, http)
    }
}
```

**Key changes from current implementation:**
- Base URL: `https://api.opsgenie.com/v2` (NOT `api.atlassian.com/jsm/ops/api/{cloudId}/v1/`)
- Auth: `Authorization: GenieKey {apiKey}` (NOT Basic auth)
- No `email` parameter needed — the key authenticates on its own
- No `baseURL` parameter needed — the API has a fixed base URL
- No `cloudId` needed — remove `getCloudId()` entirely
- Response parsing: data is always wrapped in `{"data": ...}` — unwrap the `data` key first

**Error handling:**
- 401: "JSM Ops API key is invalid or the integration is not turned on. Check Settings → JSM Operations."
- 403: "JSM Ops API key lacks access. If using a team-scoped key, the team must have access to the requested schedule/alert."
- 422: "Invalid request — check parameters."
- 429: "Rate limit hit. Try again in a moment."

### Phase 25C: Update OnCallViewModel

1. **Replace all credential passing:**
   ```swift
   // Old:
   try await service.listTeams(baseURL: appState.jiraBaseURL, email: appState.jiraEmail, apiToken: appState.jiraAPIToken)
   // New:
   try await service.listTeams(apiKey: appState.jsmOpsAPIKey)
   ```

2. **Update guard checks:**
   ```swift
   guard !appState.jsmOpsAPIKey.isEmpty else {
       error = "JSM Ops API key not configured — set it up in Settings → JSM Operations"
       return
   }
   ```

3. **Update schedule/on-call loading:**
   - First load schedules (not teams) since on-call is per-schedule
   - For each schedule, load who is on call
   - Optionally also load teams for the favorites picker

### Phase 25D: Update OnCallView Error & Empty States

1. **When JSM Ops key is not configured:**
   ```
   📞  On-Call requires a JSM Operations API key
      (separate from your Jira token).

      [Set Up API Key]  → opens Settings → JSM Operations

      The On-Call section shows:
      • Who's currently on call for your schedules
      • Active alerts
      • On-call schedule rotations
   ```

2. **When key is configured but returns 401:** "JSM Ops API key is invalid or the integration is not turned on. Check Settings → JSM Operations."

3. **When key works but no schedules found:** "No on-call schedules found. Your API key may be team-scoped — check that the team has schedules configured."

4. **When schedules load but no favorites selected:** "Select your favorite schedules to see on-call information."

### Phase 25E: Add JSM Ops Auth Status

1. Add `@Published var jsmOpsAuthStatus: AuthStatus = .unknown` to AppState.

2. Add to `checkAllServices()`:
   ```swift
   if !jsmOpsAPIKey.isEmpty {
       jsmOpsAuthStatus = .checking
       let jsmService = JSMOpsService()
       do {
           let schedules = try await jsmService.listSchedules(apiKey: jsmOpsAPIKey)
           jsmOpsAuthStatus = .authenticated(detail: "\(schedules.count) schedules")
       } catch {
           jsmOpsAuthStatus = .error(error.localizedDescription)
       }
   }
   ```

3. Wire the On-Call sidebar item to show `jsmOpsAuthStatus` as its status dot.

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- Don't break other features.
- Search the entire codebase for ALL references to `JSMOpsService` and update every call site.
- The `cloudId` and `getCloudId()` method are no longer needed — remove them.
- Rename `opsgenieAPIKey` to `jsmOpsAPIKey` if it already exists in AppState/KeychainHelper.
- Rename `opsgenieAuthStatus` to `jsmOpsAuthStatus` if it already exists.
