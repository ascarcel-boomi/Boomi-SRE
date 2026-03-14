# Boomi SRE App — Phase 17: SSO Authentication & Guided API Key Setup

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first to understand the current codebase:**
- `BoomiSRE/Sources/Models/AppState.swift` — all credential properties, auth statuses, config persistence
- `BoomiSRE/Sources/Services/KeychainHelper.swift` — secrets storage (`~/.boomi_sre_secrets.json`)
- `BoomiSRE/Sources/Services/CredentialDiscovery.swift` — auto-discovery from `~/.kiro/`, `~/.amazonq/`, etc.
- `BoomiSRE/Sources/Views/SettingsView.swift` — current settings tabs for all services
- `BoomiSRE/Sources/Views/OnboardingWizardView.swift` — first-run wizard (has 5 steps: welcome, discover, connect, profile, ready)
- `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift` — already has WebView+SSO for page rendering (but pages don't load — the issue is the WebView SSO login flow)
- `BoomiSRE/Sources/Views/Panels/GrafanaBrowserView.swift` — currently API-only panel outline view
- `BoomiSRE/Sources/Views/Panels/ChatView.swift` — WebView for Google Chat (reference for SSO pattern)
- `BoomiSRE/Sources/Views/Panels/GmailView.swift` — API-based Gmail (OAuth credentials)
- `BoomiSRE/Sources/Views/Panels/CalendarView.swift` — API-based Calendar (OAuth credentials)
- `BoomiSRE/Sources/Services/GoogleService.swift` — OAuth token management
- `BoomiSRE/Sources/Services/GrafanaService.swift` — Grafana API client
- `BoomiSRE/Sources/Services/ConfluenceService.swift` — Confluence API client

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`.
- The app is unsigned — WKWebView cookie sharing with Safari may not work without entitlements. Plan for in-WebView login as the primary flow.

**Auth landscape — what each service needs:**

| Service | API Token (required for) | SSO/WebView (works for) |
|---------|-------------------------|------------------------|
| Jira | All features (search, tickets, comments, creation) | N/A (no WebView features) |
| Confluence | Space listing, page listing, search, AI summaries | Page rendering (WebView+SSO already implemented) |
| GitHub | Repos, PRs, files, workflow runs, issue creation | N/A |
| Jenkins | Jobs, builds, console output | N/A |
| Grafana | Dashboard listing, alert listing, panel queries, AI analysis | Dashboard rendering (WebView+SSO possible) |
| Google (Gmail/Calendar) | Email listing, calendar events (for AI briefings, Copilot context) | N/A (OAuth, not simple API key) |
| Google Chat | N/A (no API features) | Full experience (WebView+SSO) |
| AWS | All features | SSO already works via `aws sso login` (Okta portal) |
| Bitbucket | Repos, PRs | N/A |
| JSM Ops | Teams, on-call, alerts | N/A |

---

## Implementation Plan

Work through these phases in order. Each phase should compile and run before moving to the next. After each phase, run `swift build` to verify. Commit after each phase.

---

### Phase 17A: Guided API Key Setup Wizard

**Goal:** For every service that requires an API token, provide a step-by-step guide with direct links to the exact settings page, required permissions, and copy-paste instructions. Make it so easy that a brand-new SRE can set up all their keys in under 5 minutes.

**Implementation:**

1. **Create `BoomiSRE/Sources/Views/APIKeyGuideView.swift`:**
   A reusable guided setup view that accepts a service name and shows step-by-step instructions.

2. **For each service in SettingsView, add a "Setup Guide" button** next to the API token field. Clicking it opens a sheet with the guided setup:

#### Jira & Confluence (same token):
```
Step 1: Open your Atlassian API token page
        [Open id.atlassian.com/manage-profile/security/api-tokens] ← clickable link button

Step 2: Click "Create API token"
        - Label: "Boomi SRE App" (or anything you'll remember)
        - Click "Create"

Step 3: Copy the token and paste it below
        [Token field]  [Paste & Save]

Note: This same token works for both Jira AND Confluence.
      You only need to create it once.

Required permissions: Your token inherits your Atlassian account permissions.
No special scopes needed — if you can access Jira/Confluence in your browser, the token will work.
```

#### GitHub:
```
Step 1: Open GitHub token settings
        [Open github.com/settings/tokens] ← clickable link button

Step 2: Click "Generate new token" → "Generate new token (classic)"
        - Note: "Boomi SRE App"
        - Expiration: 90 days (or "No expiration" for convenience)
        - Select scopes:
          ☑ repo (Full control of private repositories)
          ☑ read:org (Read org membership)
          ☑ workflow (Update GitHub Actions workflows)
          ☑ read:user (Read user profile)

Step 3: Click "Generate token", copy it, and paste below
        [Token field]  [Paste & Save]

Note: If your GitHub org requires SSO authorization, click "Configure SSO" next to the
token after creating it, and authorize your organization.
```

#### Jenkins:
```
Step 1: Open your Jenkins user settings
        [Open {jenkinsURL}/me/configure] ← clickable link button (uses configured Jenkins URL)

Step 2: Scroll to "API Token" section
        - Click "Add new Token"
        - Name: "Boomi SRE App"
        - Click "Generate"

Step 3: Copy the token and paste below
        [Token field]  [Paste & Save]

Also needed:
- Jenkins URL: {auto-filled if discovered, otherwise text field}
- Username: {auto-filled if discovered, otherwise text field}
```

#### Grafana:
```
Step 1: Open Grafana Service Account settings
        [Open {grafanaURL}/org/serviceaccounts] ← clickable link button

Step 2: Create a Service Account
        - Click "Add service account"
        - Display name: "Boomi SRE App"
        - Role: "Viewer" (sufficient for dashboards and alerts)
        - Click "Create"

Step 3: Add a token to the service account
        - Click "Add service account token"
        - Display name: "boomi-sre"
        - Click "Generate token"

Step 4: Copy the token and paste below
        [Token field]  [Paste & Save]

Also needed:
- Grafana URL: {auto-filled if discovered, otherwise text field}

Note: A "Viewer" role token can read dashboards, panels, and alerts.
If you also want to create annotations, use "Editor" role.
```

#### Bitbucket:
```
Step 1: Open Bitbucket App Passwords
        [Open bitbucket.org/account/settings/app-passwords/] ← clickable link button

Step 2: Click "Create app password"
        - Label: "Boomi SRE App"
        - Permissions:
          ☑ Repositories: Read
          ☑ Pull requests: Read
          ☑ Account: Read

Step 3: Copy the password and paste below
        [Token field]  [Paste & Save]
```

#### Google Workspace (Gmail & Calendar):
```
This service uses OAuth 2.0, which is more complex than a simple API key.

Option A: Auto-discover from existing MCP config
        If you've already set up google-workspace MCP credentials, click "Auto-discover"
        and they'll be imported automatically.
        [Auto-discover] ← button

Option B: Manual setup
        Step 1: Open Google Cloud Console
                [Open console.cloud.google.com/apis/credentials] ← link

        Step 2: Create OAuth 2.0 credentials
                - Click "Create Credentials" → "OAuth client ID"
                - Application type: "Desktop app"
                - Name: "Boomi SRE App"
                - Click "Create"

        Step 3: Download the credentials JSON
                - Click the download button next to your new credential
                - Save the file

        Step 4: Import the credentials file
                [Choose File...] ← file picker button
                [Import]

Note: Gmail and Calendar features (AI briefings, email triage, meeting context)
require these OAuth credentials. Google Chat works without them (uses browser login).
If you don't set up OAuth, Chat will still work but AI briefings won't include
email or calendar context.
```

3. **Visual design for the guide:**
   - Each step has a step number in a colored circle (accent color)
   - The link buttons are prominent (`.buttonStyle(.borderedProminent)`)
   - The required permissions are shown as a checklist with checkboxes (visual only, not interactive)
   - A "Need help?" link at the bottom that opens a generic troubleshooting page or the app's GitHub Issues
   - A green checkmark appears next to the token field when the token validates successfully

4. **Inline validation:** After the user pastes a token and clicks "Save":
   - Immediately call the service's `checkAuth()` method
   - Show a green checkmark + "Connected as {name}" on success
   - Show a red X + error message on failure (e.g., "Invalid token", "Expired", "Insufficient permissions")
   - This gives instant feedback so the user knows if their token works

---

### Phase 17B: Fix Confluence WebView SSO Login Flow

**Problem:** Confluence pages don't load in the WebView. The existing implementation uses `WKWebsiteDataStore.default()` hoping to share Safari cookies, but this doesn't reliably work for unsigned macOS apps. The user sees a blank page or a login page.

**Current state (from `ConfluenceBrowserView.swift`):**
- The WebView already exists (`ConfluenceWebView`) using `WKWebsiteDataStore.default()`
- There's a "Log In" button that opens `/login` in the system browser — but browser cookies don't automatically flow back to WKWebView
- The "Web View" / "Plain Text" segmented control already exists
- Space listing and page listing work (via API) — only the page content rendering is broken

**Fix:**

1. **Replace the "Log In" button approach** with an in-WebView login flow:
   - When the WebView loads a Confluence page URL and gets redirected to a login page (Okta SSO), let the user complete the login within the WebView itself
   - The WebView will store the session cookies in its persistent data store
   - On subsequent loads, the cookies will be reused (user stays logged in)
   - Add a `WKNavigationDelegate` that detects successful login (URL returns to the Confluence page) and shows a success indicator

2. **Use a persistent, named `WKWebsiteDataStore`** instead of `.default()`:
   ```swift
   let dataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "confluence-sso")!)
   // Or use .default() but explicitly — the key is persistence
   config.websiteDataStore = .default()
   ```
   The `.default()` store IS persistent across app launches. The issue is more likely that the WebView never completes the Okta SSO redirect chain.

3. **Handle the Okta redirect chain:**
   - Okta SSO typically redirects: Confluence → Okta login page → Okta MFA → back to Confluence
   - The `WKNavigationDelegate` must allow ALL redirects in this chain. The current delegate (if any) might be blocking cross-domain redirects.
   - Allow all domains in the navigation policy: `*.okta.com`, `*.atlassian.net`, `*.atlassian.com`, `*.google.com` (if Google SSO is involved), and any other identity provider domains.
   - Do NOT restrict navigation to only Atlassian domains during the login flow.

4. **Add a "Sign In" banner** at the top of the WebView when the page hasn't loaded:
   ```
   [ℹ️] Sign in to Confluence using your Okta SSO credentials below. You only need to do this once.
   ```
   After successful login (detected by the URL returning to `*.atlassian.net/wiki/*`), hide the banner and show "Signed in ✓".

5. **Add a "Sign Out" option** in the Confluence settings or context menu:
   - Clears the WKWebView cookies for Atlassian domains
   - Useful if the user needs to switch accounts

6. **Improve the Plain Text fallback:**
   - The Plain Text tab uses the API to fetch content (via `getPageContent()` which calls `body.export_view`)
   - This is the fallback that works with API tokens and is used for AI summarization
   - Make sure this still works even when the WebView SSO is the primary rendering method

---

### Phase 17C: Add WebView+SSO to Grafana Dashboard View

**Goal:** When viewing a Grafana dashboard, show the actual rendered dashboard via WebView with Okta SSO, not just the panel metadata outline.

**Current state:** `GrafanaBrowserView` shows dashboard list (via API) on the left, and a text-based panel outline on the right showing panel types, titles, descriptions, and PromQL/LogQL queries. No actual visualization.

**Implementation:**

1. **Add a view mode toggle** to the dashboard detail pane:
   - "Dashboard" (WebView — SSO rendered) | "Panels" (current text outline) | "Queries" (raw PromQL)
   - Default to "Dashboard"

2. **Dashboard WebView:**
   - Load `{grafanaURL}{dashboard.url}?kiosk` in a WKWebView
   - The `?kiosk` parameter hides Grafana's chrome (sidebar, header) for a clean embedded view
   - Match macOS appearance: add `&theme=light` or `&theme=dark` based on `NSApp.effectiveAppearance`
   - Use persistent `WKWebsiteDataStore.default()` for session cookies
   - Handle Okta SSO redirects the same way as Confluence (allow all auth-related domains)

3. **SSO login flow:**
   - Same pattern as Confluence: let the user log in within the WebView
   - "Sign In" banner when not authenticated
   - Detect successful login when URL returns to `{grafanaURL}/*`
   - Session persists across app launches and dashboard changes

4. **Keep API-based features alongside WebView:**
   - Dashboard list (left pane) still uses API (needs the service account token)
   - Alert listing still uses API
   - AI analysis ("Explain Dashboard", "Analyze Alerts") still uses API (sends panel metadata to Claude)
   - The WebView is ONLY for rendering the actual dashboard visualization
   - If the user hasn't logged in via SSO, show a message: "Log in to view the dashboard, or switch to 'Panels' view for a text summary."

5. **"Open in Grafana" button** should open the dashboard URL (without `?kiosk`) in the system browser as a fallback.

---

### Phase 17D: Okta SSO Profile Integration

**Goal:** Associate the user's Okta SSO identity with their profile. Since Okta is the single sign-on provider for most Boomi services, this is the user's primary corporate identity.

**Implementation:**

1. **Add Okta fields to UserProfile** (from Phase 13):
   ```swift
   var oktaEmail: String       // Corporate Okta email (usually same as Jira/Google email)
   var oktaDomain: String      // e.g., "boomi.okta.com"
   ```

2. **Auto-discover Okta domain:**
   - If the Jira base URL is `*.atlassian.net`, the Okta domain is likely discoverable from the login redirect chain
   - Or: infer from the user's email domain (e.g., `@boomi.com` → `boomi.okta.com`)
   - Or: let the user set it manually in Profile settings

3. **Profile view shows Okta info:**
   - "Corporate Identity" section showing Okta email
   - Explanation: "Your Okta SSO credentials are used to sign in to Confluence, Grafana, and Google Chat within the app. You sign in once per service and stay signed in."

4. **Settings UX improvement — shared identity callout:**
   At the top of the Settings view (above the service tabs), add a card:
   ```
   🔑 Your Corporate Identity
   Email: adam.scarcella@boomi.com
   SSO Provider: Okta

   This email is used across Jira, Confluence, GitHub, and other services.
   Services that embed web views (Confluence, Grafana, Google Chat) use your
   Okta SSO session — sign in once and stay signed in.
   Services that use APIs need a personal access token (see each tab for setup guides).
   ```

5. **Pre-fill email fields:**
   - When the user's Okta email is known (from profile), pre-fill the email field in Jira, Confluence, Bitbucket, and Google settings tabs
   - Show a note: "Using your corporate email from your profile"
   - The user can override if needed

---

### Phase 17E: Onboarding Wizard — API Key Setup Integration

**Goal:** The onboarding wizard should guide new users through API key setup for their most important services.

**Current state:** The onboarding wizard has 5 steps: Welcome → Auto-discover → Test Connections → Profile → Ready. The "Auto-discover" step finds credentials from existing config files, but if none exist, the user is stuck.

**Implementation:**

1. **Add a "Setup API Keys" step** between "Auto-discover" and "Test Connections" (now 6 steps total):
   - Show a checklist of services with their current status:
     ```
     ☑ Jira .................. Connected (auto-discovered)
     ☑ Confluence ............ Connected (same token as Jira)
     ☐ GitHub ................ Not configured  [Set Up →]
     ☐ Jenkins ............... Not configured  [Set Up →]
     ☐ Grafana ............... Not configured  [Set Up →]
     ☑ AWS ................... Connected (SSO)
     ☐ Google Workspace ...... Not configured  [Set Up →]  [Skip — Chat still works]
     ```
   - Each "Set Up →" button opens the guided setup (from Phase 17A) inline or as a sheet
   - Services that were auto-discovered show a green checkmark
   - Services that use SSO only (no API key needed for basic features) show a note
   - A "Skip for now" option for each service — don't force setup
   - A "Skip all — I'll set up later in Settings" button at the bottom

2. **Prioritize the setup order:**
   - Jira first (most critical — auto-discovered tokens often work)
   - GitHub second (needed for KB, PRs, feature requests)
   - Jenkins third (for build monitoring)
   - Grafana fourth (for dashboard monitoring)
   - Google Workspace last (optional — Chat works without it)

3. **After each key is saved, immediately test it:**
   - Call `checkAuth()` for the service
   - Show green checkmark on success, red X on failure
   - If it fails, show a "Troubleshoot" link with common issues:
     - "Token expired" → regenerate
     - "403 Forbidden" → check permissions/scopes
     - "SSO authorization required" → for GitHub, remind to authorize the org

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** All existing auth flows, auto-discovery, and service connections must continue to work.
- **Existing tokens should keep working.** Don't force users to re-enter tokens they've already configured.
- **Dark mode:** All views must support both light and dark macOS appearances.
- **Security:** Never log or display full API tokens. Show only the last 4 characters when displaying a saved token (e.g., "••••••••abcd").
- **Commit after each phase** (17A, 17B, 17C, 17D, 17E) with a descriptive commit message.
