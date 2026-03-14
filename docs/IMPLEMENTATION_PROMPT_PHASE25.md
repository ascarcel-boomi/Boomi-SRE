# Boomi SRE App — Phase 25: Fix On-Call — JSM Ops Uses OpsGenie API Key, Not Jira Token

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — current implementation uses Basic auth with Jira email:token (WRONG)
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — calls JSMOpsService with Jira credentials
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — On-Call UI, error display
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — OpsTeam, OnCallParticipant, OpsAlert, OpsSchedule
- `BoomiSRE/Sources/Models/AppState.swift` — `favoriteJSMTeams`, `jsmCloudId`, Jira credentials
- `BoomiSRE/Sources/Views/SettingsView.swift` — look for any JSM/OpsGenie settings tab
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — secrets storage

**Key constraints:**
- Pure SwiftUI. No third-party frameworks.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600).

---

## Root Cause

The On-Call section returns **401 Unauthorized** because the JSM Ops / OpsGenie API uses a **completely different authentication method** than Jira.

**Current (broken) auth:** Basic auth with `email:jiraApiToken`
**Required auth:** `Authorization: GenieKey {opsgenieApiKey}`

### OpsGenie API — Confirmed Details

**Authentication:**
- Header: `Authorization: GenieKey {api_key}`
- This is NOT the Jira API token. It is a separate credential.
- Jira Basic auth does NOT work on OpsGenie endpoints (confirmed: returns 401).

**Base URL:**
- Standard: `https://api.opsgenie.com/v2/`
- EU instances: `https://api.eu.opsgenie.com/v2/`
- The current code uses `https://api.atlassian.com/jsm/ops/api/{cloudId}/v1/` — this may also work but needs the GenieKey header regardless. Test both; prefer `api.opsgenie.com/v2/` as it's the documented endpoint.

**Key endpoints (confirmed from OpsGenie docs):**
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

**How to create the API key:**
1. In the OpsGenie / JSM Ops interface, go to **Settings → Integrations**
2. Search for and select **"API"**
3. Name it: "Boomi SRE App"
4. Optionally assign to a team (for team-scoped access)
5. Click **"Continue"** to save
6. Expand **"Steps to configure the integration"** and **copy the API key**
7. Click **"Turn on integration"** to activate it

**Important notes:**
- Users on Free, Essentials, or JSM Standard plans must add integrations from their **team dashboard** instead of Settings.
- The account owner must verify their email before API integrations work.
- Team-scoped API keys can only access that team's alerts/schedules. For full access, use a non-team-scoped integration.

---

## Implementation Plan

### Phase 25A: Add OpsGenie API Key to AppState & Settings

1. **Add new credential to AppState:**
   ```swift
   var opsgenieAPIKey: String {
       get { KeychainHelper.load(key: "opsgenie-api-key") ?? "" }
       set { try? KeychainHelper.save(key: "opsgenie-api-key", value: newValue); objectWillChange.send() }
   }
   ```

2. **Add a JSM Operations settings section** (new tab or section within an existing tab):

   **Settings → JSM Operations:**
   - **API Key field** (SecureField) for the OpsGenie API key
   - **Guided setup:**
     ```
     On-Call & Alerts use the OpsGenie API, which requires a separate API key
     from your Jira token.

     Step 1: Open JSM Ops Integrations
             [Open boomii.atlassian.net/jira/ops] ← clickable link button
             Then go to Settings → Integrations

     Step 2: Search for "API" and select it

     Step 3: Name it "Boomi SRE App"
             Optionally assign to your team for team-scoped access
             Click "Continue"

     Step 4: Expand "Steps to configure the integration" and copy the API key
             Click "Turn on integration" to activate

     Step 5: Paste the API key below
             [API Key field]  [Paste & Save]

     Note: If you don't see Settings → Integrations, you may need to create
     the integration from your team dashboard instead (JSM Standard plans).
     Ask your JSM admin if you need help.
     ```
   - **"Test Connection" button** that calls `listSchedules()` or `listTeams()` with the new key
   - Status indicator: green "Connected" / red with error
   - **Favorite teams section** (existing): discover teams button + team list with toggles

3. **Add to credential discovery** (`CredentialDiscovery.swift`): scan for `OPSGENIE_API_KEY`, `OPSGENIE_TOKEN`, `JSM_OPS_API_KEY` in MCP credential directories.

### Phase 25B: Rewrite JSMOpsService — Use OpsGenie v2 API

**Replace the entire implementation** to use the documented OpsGenie v2 API at `api.opsgenie.com`:

```swift
actor JSMOpsService {

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
}
```

**Key changes from current implementation:**
- Base URL: `https://api.opsgenie.com/v2/` (NOT `api.atlassian.com/jsm/ops/api/{cloudId}/v1/`)
- Auth: `Authorization: GenieKey {apiKey}` (NOT Basic auth)
- No `email` parameter needed
- No `baseURL` parameter needed (OpsGenie has a fixed base URL)
- No `cloudId` needed
- Remove the `getCloudId()` method entirely
- Response parsing: data is wrapped in `{"data": ...}` — always unwrap the `data` key first

**Error handling:**
- 401: "OpsGenie API key is invalid or not activated. Check Settings → JSM Operations."
- 403: "OpsGenie API key lacks access to this resource. If using a team-scoped key, the team must have access to the requested schedule/alert."
- 422: "Invalid request — check parameters."
- Rate limiting (429): "OpsGenie rate limit hit. Try again in a moment."

### Phase 25C: Update OnCallViewModel

1. **Replace all credential passing** from Jira credentials to OpsGenie API key:
   ```swift
   // Old:
   try await service.listTeams(baseURL: appState.jiraBaseURL, email: appState.jiraEmail, apiToken: appState.jiraAPIToken)
   // New:
   try await service.listTeams(apiKey: appState.opsgenieAPIKey)
   ```

2. **Update guard checks:**
   ```swift
   guard !appState.opsgenieAPIKey.isEmpty else {
       error = "OpsGenie API key not configured — set it up in Settings → JSM Operations"
       return
   }
   ```

3. **Update schedule/on-call loading:**
   - First load schedules (not teams) since on-call is per-schedule
   - For each schedule, load who is on call
   - Optionally also load teams for the favorites picker

### Phase 25D: Update OnCallView Error & Empty States

1. **When OpsGenie key is not configured:**
   ```
   📞  On-Call requires a JSM Operations API key
      (separate from your Jira token).

      [Set Up API Key]  → opens Settings → JSM Operations

      The On-Call section shows:
      • Who's currently on call for your schedules
      • Active alerts from OpsGenie
      • On-call schedule rotations
   ```

2. **When key is configured but returns 401:** "OpsGenie API key is invalid or integration is not turned on. Open Settings to check."

3. **When key works but no schedules found:** "No on-call schedules found. This may mean your API key is team-scoped and the team has no schedules."

4. **When schedules load but no favorites selected:** "Select your favorite schedules to see on-call information."

### Phase 25E: Add OpsGenie Auth Status

1. Add `@Published var opsgenieAuthStatus: AuthStatus = .unknown` to AppState.

2. Add OpsGenie to `checkAllServices()`:
   ```swift
   if !opsgenieAPIKey.isEmpty {
       opsgenieAuthStatus = .checking
       let jsmService = JSMOpsService()
       do {
           let schedules = try await jsmService.listSchedules(apiKey: opsgenieAPIKey)
           opsgenieAuthStatus = .authenticated(detail: "\(schedules.count) schedules")
       } catch {
           opsgenieAuthStatus = .error(error.localizedDescription)
       }
   }
   ```

3. Wire the On-Call sidebar item to show `opsgenieAuthStatus` as its status dot.

---

## General Guidelines

- Run `swift build` after each sub-phase. Commit after each.
- Don't break other features.
- Search the entire codebase for ALL references to `JSMOpsService` and update every call site.
- The `cloudId` and `getCloudId()` method are no longer needed — remove them.
- Test the OpsGenie API key format: it should be a long alphanumeric string, not an email:token pair.
