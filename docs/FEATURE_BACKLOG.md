# Boomi SRE App — Feature Backlog

This is the prioritized backlog of feature ideas. Each item is fleshed out enough to be turned into an `IMPLEMENTATION_PROMPT_PHASE*.md` when ready to build.

Items are grouped by effort size and priority. Pick items from the top of each group first.

---

## Small — Can be done in a single phase

### 1. Factory Reset (Phase 12A)
**Priority: HIGH** (needed for development/testing)

Add a "Factory Reset" button in Settings that resets the app to first-launch state. This allows testing the Onboarding Wizard and simulating a fresh install.

**What it resets (deletes/clears):**
- `~/.boomi_sre_config.json` — all persisted AppState config
- `~/.boomi_sre_secrets.json` — discovered credentials cache
- `~/.boomi_sre_notifications.json` — notification history
- `~/.boomi_sre_incidents.json` — local incidents
- `~/.boomi_sre_chat_history.json` — AI chat history
- `appState.hasCompletedOnboarding = false` — triggers onboarding wizard

**What it does NOT touch (safety):**
- `~/.aws/config` and `~/.aws/credentials` — these are system-level AWS configs
- `~/.kiro/` — MCP credentials
- `~/.amazonq/` — Amazon Q credentials
- `~/.gitconfig` — Git config
- Any files outside `~/.boomi_sre_*`

**UX:**
- Button in Settings → General tab (or a new "Advanced" tab)
- Confirmation dialog: "This will reset all app settings, clear notifications, incidents, and chat history. Your AWS, Jira, and other service credentials on disk are NOT affected. The app will restart with the Onboarding Wizard. Are you sure?"
- After reset: set `hasCompletedOnboarding = false`, clear all in-memory state, and trigger the onboarding sheet

---

### 2. Settings at Bottom of Sidebar (Phase 12B)
**Priority: HIGH** (visual polish)

Move the Settings item out of the scrollable sidebar list and pin it to the bottom of the sidebar as a fixed footer. This is the standard macOS app pattern (like Finder, Mail, System Settings).

**Implementation:**
- Remove Settings from the `List` in `SidebarView`
- Add it as a fixed `HStack` pinned below the List using a `VStack { List { ... } Divider() settingsButton }` layout
- In collapsed sidebar mode, show just the gear icon pinned to the bottom
- Style it with a subtle top divider to separate it from the scrollable content

---

### 3. Customizable Toolbar (Phase 12C)
**Priority: MEDIUM**

Let users add/remove/reorder toolbar buttons at the top of the window.

**Default toolbar items:**
- Sidebar toggle (already exists)
- Back/Forward navigation
- Refresh (Cmd+R)
- Account picker (AWS profile switcher)
- Search (global search across all services)
- AI Copilot quick-launch

**Customization:**
- Right-click toolbar → "Customize Toolbar..." (standard macOS `NSToolbar` customization)
- Users can drag items in/out and reorder
- SwiftUI `.toolbar` with `.customizable` modifier (macOS 13+)
- Save toolbar configuration to AppState

---

### 4. In-App Feature Requests (Phase 12D)
**Priority: MEDIUM**

Add a "Submit Feature Request" option accessible from:
- Help menu → "Submit Feature Request"
- Settings → "Feedback" section
- A small "?" button in the toolbar

**Implementation:**
- Opens a sheet with: Title (text field), Description (text area), Type picker (Bug / Feature / Improvement), optional screenshot attachment
- Submits as a GitHub Issue to `ascarcel-boomi/Boomi-SRE` repo using the GitHub API (token already configured in AppState)
- Auto-tags with labels: `feature-request`, `submitted-from-app`
- Auto-includes: app version, macOS version, configured services list (no credentials)
- Shows confirmation with link to the created issue
- If GitHub token isn't configured, fall back to opening the GitHub Issues page in the browser

---

### 5. Recent Incidents (Not Just Active) (Phase 12E)
**Priority: HIGH**

The Incidents section currently only shows active/open incidents. Add a "Recent" tab or filter.

**Implementation:**
- Add a segmented control at the top of IncidentCommandView: "Active" | "Recent" | "All"
- "Active" = current behavior (open incidents only)
- "Recent" = incidents resolved in the last 30 days
- "All" = everything, with search and date range filter
- Add a timeline/history view showing incidents over time (Swift Charts bar chart, grouped by week, colored by severity)
- Sort recent incidents by resolution time (most recent first)

---

### 6. Service Credential Explanation UX (Phase 12F)
**Priority: MEDIUM**

Users are confused about why they need API tokens AND sometimes web logins. Improve the Settings credential entry UX.

**For each service in Settings, add:**
- A brief explanation box: "Boomi SRE connects to {service} in two ways: (1) API calls use your personal access token to fetch data programmatically, and (2) some views embed the web UI directly and need your browser session."
- For services with web views (Grafana, Confluence, Google): add optional "Web Username" and "Web Password" fields, stored in `~/.boomi_sre_secrets.json`
- For Grafana specifically: "Your API token (Service Account Token) is used to fetch dashboards, alerts, and metrics via the Grafana API. The embedded dashboard view uses a web session — if you see a login page, enter your Grafana web credentials."
- Visual indicator showing which connection method each feature uses: icon badge "API" or "Web" next to each sidebar item

---

## Medium — Needs 2-3 phases each

### 7. User Profile (Phase 13)
**Priority: HIGH**

Add a Profile feature so the app knows who the user is, enabling personalization across all services.

**Auto-discovered fields:**
- Name: from Jira auth (`/rest/api/3/myself`), Git config (`~/.gitconfig` user.name), or GitHub auth
- Email: from Jira auth, Git config, or AppState.jiraEmail
- GitHub handle: from GitHub auth (`/user` → login)
- Jira username: from Jira auth
- Team: could be inferred from Jira project membership
- Avatar: from Jira or GitHub profile picture URL

**User-editable fields:**
- Display name (override auto-discovered)
- Role: dropdown (SRE, DevOps, Platform Engineer, Manager, Other)
- Experience level: Junior / Mid / Senior / Lead (this can adjust AI analysis depth and "Explain this" visibility)
- Time zone: auto-detected from system, editable
- Preferred AWS accounts: (already exists as favorites)
- Preferred Jira projects: (already exists)
- On-call schedule: free-text or link to PagerDuty/Grafana OnCall
- Notes: free-text field for anything else

**Where profile is used:**
- Home page greeting: "Good morning, Adam"
- AI Copilot system prompt: includes role + experience level for tailored responses
- Notification filtering: only notify for projects/repos the user cares about
- "Explain this to me" button visibility: always shown for Junior, hidden (but available in menu) for Senior

**Storage:** New section in `~/.boomi_sre_config.json`

---

### 8. Jira-Based Incidents (Phase 14)
**Priority: HIGH**

Currently incidents are local-only. They should also pull from Jira.

**Approach:**
- Incidents in Jira are typically tracked as issue type "Incident" or "Bug" with a priority of P1/P2, or with specific labels like "incident", "production-incident", or in a dedicated project.
- Add a config field `incidentJQL` in Settings → Incidents tab where the user can define their incident query. Default: `issuetype = Bug AND priority IN (Highest, High) AND project IN ({user's preferred projects}) AND created >= -90d ORDER BY created DESC`
- Poll Jira for matching tickets on the Incidents view load (not background polling — on-demand when the user opens Incidents)
- Show Jira-sourced incidents alongside local incidents, with a badge indicating source ("Jira" vs "Local")
- Allow linking a local incident to a Jira ticket (already exists) and vice versa (clicking a Jira incident opens it in TicketDetailView)
- The user should be able to customize the JQL to match their team's incident tracking pattern

**Settings → Incidents tab:**
- "Incident JQL Query" text field with the default query
- "Test Query" button to preview results
- "Incident Jira Projects" multi-select (from user's configured projects)
- Toggle: "Include local incidents" (default: on)
- Toggle: "Include Jira incidents" (default: on)

---

### 9. GitHub & Bitbucket Multiple Workspaces (Phase 15)
**Priority: MEDIUM**

Currently GitHub is hardcoded to `Mashery-Boomi` org and Bitbucket to `boomii` workspace. Allow multiple.

**GitHub:**
- Replace single `githubOrg` string with `githubOrgs: [String]` array in AppState
- Settings → GitHub tab: list of orgs with add/remove
- Auto-discover orgs the user belongs to: `GET /user/orgs` → list all orgs the token has access to
- In GitHub Browser, show a picker/tabs for orgs + "Personal" repos
- Repos from all configured orgs are searchable together

**Bitbucket:**
- Replace single workspace with `bitbucketWorkspaces: [String]` array
- Auto-discover workspaces: `GET /2.0/workspaces` → list all accessible workspaces
- In Bitbucket Browser (when built), show workspace picker

---

## Large — Significant new integrations

### 10. Slack Integration (Phase 16)
**Priority: MEDIUM**

Slack is critical for SRE communication — incident channels, alerts, team coordination.

**Approach options:**
1. **WebView embed** (like Google Chat): Load `https://app.slack.com` in a WKWebView with persistent session. Simplest but limited.
2. **Slack API integration**: Use Slack Web API with a user token or bot token. Richer but requires Slack app setup.
3. **Slack MCP server**: Use the existing MCP pattern if a Slack MCP server is available.

**Recommended: Start with WebView (quick win), then add API features:**

**Phase 16A — WebView embed:**
- New sidebar item under a "Communication" section (or replace Google section)
- Persistent WKWebView loading Slack, same pattern as Google Chat
- "Open in Browser" fallback

**Phase 16B — API integration (if user configures a Slack token):**
- List channels the user is in
- Show recent messages in incident channels (channels matching pattern: `#incident-*`, `#sre-*`)
- Post messages to channels from within the app
- Notification integration: surface Slack mentions as app notifications
- Settings: Slack workspace URL, Slack API token (user or bot), watched channel patterns

**Sidebar placement:** Create a new "Communication" section with: Slack, Google Chat, Gmail. Or add Slack to the existing Google section renamed to "Communication".

---

### 11. New Relic Integration (Phase 17)
**Priority: MEDIUM**

New Relic provides APM, infrastructure monitoring, and alerting.

**API:** New Relic has a REST API v2 and GraphQL (NerdGraph) API.

**Phase 17A — Service + Models:**
- `NewRelicService` actor using REST API v2 or NerdGraph
- Auth: New Relic API key (User key or Ingest key)
- Settings: New Relic API key, Account ID, base URL (US: `api.newrelic.com`, EU: `api.eu.newrelic.com`)

**Phase 17B — Key features:**
- **APM Dashboard**: List applications, show health status (green/yellow/red/grey), response time, throughput, error rate
- **Alerts**: List open alert conditions and incidents (New Relic Alerts → `GET /v2/alerts_violations.json`)
- **Infrastructure**: Host health, CPU, memory, disk across monitored hosts
- **Synthetics**: Monitor status (pass/fail) for synthetic checks
- **NRQL Query**: Free-form NRQL query field for power users

**Phase 17C — AI Integration:**
- "Analyze Application Health" — send APM metrics to Claude
- "Correlate with AWS" — cross-reference New Relic alerts with AWS CloudWatch alarms

**Sidebar:** Add to Services section alongside GitHub, Jenkins, Grafana, Confluence.

---

### 12. Azure Services Integration (Phase 18)
**Priority: LOW** (team is primarily AWS, but Azure is growing)

**Approach:** Use Azure CLI (`az`) same pattern as AWS CLI wrapper.

**Phase 18A — Azure Auth Service:**
- `AzureAuthService` actor
- Auth: `az login` (interactive), `az account show` (status check)
- Subscription picker: `az account list` → list subscriptions
- Profile management similar to AWS

**Phase 18B — Azure Health Dashboard:**
- Similar structure to AWS Health view but for Azure resources:
  - VMs: `az vm list` + `az vm get-instance-view`
  - App Services: `az webapp list` + `az webapp show`
  - Azure SQL: `az sql server list` + `az sql db list`
  - Load Balancers: `az network lb list`
  - AKS Clusters: `az aks list` + `az aks show`
  - Azure Monitor Alerts: `az monitor alert list`
- Same green/yellow/red health card pattern as AWS

**Phase 18C — Sidebar:**
- New "Azure" section in sidebar (between AWS and Google)
- Items: Infrastructure Health, Cost Analysis (using `az consumption` CLI)

**Sidebar restructure consideration:** With AWS, Azure, and potentially GCP in the future, consider grouping under a "Cloud" parent section with sub-sections per provider.

---

## Backlog Summary

| # | Feature | Size | Priority | Phase |
|---|---------|------|----------|-------|
| 1 | Factory Reset | S | HIGH | 12A |
| 2 | Settings pinned to sidebar bottom | S | HIGH | 12B |
| 3 | Customizable toolbar | S | MED | 12C |
| 4 | In-app feature requests | S | MED | 12D |
| 5 | Recent incidents view | S | HIGH | 12E |
| 6 | Credential explanation UX | S | MED | 12F |
| 7 | User Profile | M | HIGH | 13 |
| 8 | Jira-based incidents | M | HIGH | 14 |
| 9 | Multi-workspace GitHub/Bitbucket | M | MED | 15 |
| 10 | Slack integration | L | MED | 16 |
| 11 | New Relic integration | L | MED | 17 |
| 12 | Azure services | L | LOW | 18 |
