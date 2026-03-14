# Boomi SRE App — Phase 26: Remove All OpsGenie References & Fix On-Call Setup Wizard

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files — they contain "OpsGenie" text that needs to be replaced:**
- `BoomiSRE/Sources/Views/Settings/JSMSettingsContent.swift` — has "OpsGenie API Key" as section header and "Paste your OpsGenie API key…" as placeholder
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — has "OpsGenie API key not configured" error messages
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — has "OpsGenie key not configured" and "OpsGenie Setup Prompt"
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — has "OpsGenie" in comments
- `BoomiSRE/Sources/Services/CredentialDiscovery.swift` — has "OpsGenie key from" in a source string
- `BoomiSRE/Sources/Models/AppState.swift` — has "OpsGenie / JSM Operations" in comments

**Also read for context:**
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app entry
- `BoomiSRE/Sources/Models/AppState.swift` — `jsmOpsAPIKey` property

---

## Problem

The On-Call section and its setup wizard reference "OpsGenie" throughout the user-facing UI. The user does not interact with "OpsGenie" — they interact with **JSM Operations** within their Jira Service Management instance. All user-facing text should say "JSM Operations" or "JSM Ops", never "OpsGenie".

Additionally, the setup wizard instructions need to accurately guide the user through creating an API integration in their JSM instance.

---

## Implementation

### Phase 26A: Replace All User-Facing "OpsGenie" Text

Search the ENTIRE codebase for every occurrence of "OpsGenie", "opsgenie", "Opsgenie", and "GenieKey" in user-facing strings (error messages, labels, placeholders, section headers, help text, comments that appear in UI). Replace them:

**Specific replacements:**

1. **`JSMSettingsContent.swift`:**
   - Section header: `"OpsGenie API Key"` → `"JSM Operations API Key"`
   - Placeholder: `"Paste your OpsGenie API key…"` → `"Paste your JSM Ops API key…"`
   - Any setup instructions referencing OpsGenie → reference "JSM Operations"

2. **`OnCallViewModel.swift`:**
   - `"OpsGenie API key not configured — add it in Settings → JSM Operations"` → `"JSM Ops API key not configured — add it in Settings → JSM Operations"`
   - Any other OpsGenie error messages → use "JSM Ops"

3. **`OnCallView.swift`:**
   - `"OpsGenie key not configured"` → `"JSM Ops key not configured"`
   - `"OpsGenie Setup Prompt"` → `"JSM Ops Setup"`
   - Any user-visible text mentioning OpsGenie → "JSM Operations" or "JSM Ops"

4. **`CredentialDiscovery.swift`:**
   - `"OpsGenie key from \(v.source)"` → `"JSM Ops key from \(v.source)"`

5. **Code comments** (in JSMOpsService.swift, AppState.swift): Replace "OpsGenie" with "JSM Operations" in comments. The API base URL `api.opsgenie.com` stays as-is in code since that's the actual endpoint — but comments should say "JSM Operations API (hosted at api.opsgenie.com)".

6. **The `GenieKey` header value in code stays unchanged** — that's the actual HTTP header the API requires. But any user-facing reference to "GenieKey" should not appear in the UI.

### Phase 26B: Fix the Setup Wizard Instructions

Rewrite the setup wizard in `JSMSettingsContent.swift` to be clear and accurate. The wizard should guide the user through the JSM Operations interface they actually see in their browser.

**Replace the current setup guide with:**

```
JSM Operations API Key

On-Call schedules and alerts are accessed through the JSM Operations API,
which uses a separate API key from your Jira token.

How to create your API key:

Step 1: Open your JSM Operations page
        [Open boomii.atlassian.net/jira/ops/overview] ← clickable button

Step 2: Go to Settings → Integrations
        (In the JSM Ops sidebar, click Settings, then Integrations)

Step 3: Click "Add integration", search for "API", and select it

Step 4: Name it "Boomi SRE App" and click "Continue"

Step 5: Expand "Steps to configure the integration" and copy the API key
        Important: The key is only shown once!

Step 6: Click "Turn on integration" to activate it

Step 7: Paste the API key below

[API Key field]  [Save & Test]

If you don't see Settings → Integrations, try:
Teams → [Your Team] → Integrations → Add integration

Learn more: https://support.atlassian.com/opsgenie/docs/create-a-default-api-integration/
```

**Note:** The "Learn more" link points to Atlassian's docs which still use the OpsGenie domain — that's fine, it's Atlassian's URL and we can't change it. But our own UI text should say "JSM Operations" everywhere.

### Phase 26C: Verify the API Is Actually Working

After the text changes, the underlying API code should already be correct (using `api.opsgenie.com/v2` with `GenieKey` header). But verify:

1. The `JSMOpsService` base URL is `https://api.opsgenie.com/v2` (correct — don't change)
2. The auth header is `Authorization: GenieKey {apiKey}` (correct — don't change)
3. The `jsmOpsAPIKey` property in AppState reads from KeychainHelper correctly
4. The "Save & Test" button in Settings actually calls the API and shows a success/failure message
5. If the test returns 401, show: "API key is invalid or the integration is not turned on. Go back to JSM Ops → Settings → Integrations and make sure the integration is active."
6. If the test returns 403, show: "API key doesn't have access. If you used a team-scoped integration, make sure your team has schedules and alerts configured."

Run `swift build` to verify. Commit with message: "Remove OpsGenie branding, use JSM Operations throughout UI".

---

## General Guidelines

- This is primarily a text/branding change, not a logic change.
- The API calls, base URL, and `GenieKey` header in code stay as-is — only user-facing strings change.
- Search the ENTIRE `Sources/` directory for "OpsGenie" (case-insensitive) to ensure nothing is missed.
