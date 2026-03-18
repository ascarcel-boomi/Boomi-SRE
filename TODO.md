# Boomi SRE — TODO / Roadmap

## Mission

Reduce toil and context switching for SREs working across multiple teams and products.
Blur the lines between services so engineers flow between tasks without juggling browser tabs.

---

## Current State (as of 2026-03-17)

### Recently Completed
- **Cross-service Copilot** — 5 tools (Jira, Grafana, Jenkins, Confluence, comments), 6 context chips, "Troubleshoot" action
- **Smart Feed** — bidirectional cross-service correlation, SLO health summary, one-click "Investigate" → Copilot
- **Zscaler SSL Trust** — shared URLSession across all 16 network callers
- **UI Consistency** — shared ViewStyles across 22 views
- **Copilot Enterprise Fix** — works with both API key and Claude CLI
- **SLO Query Fix** — Prometheus queries use SLO windowDays, better error messages
- **Keyboard Shortcuts** — Cmd+1-6 sidebar panels, Cmd+R refresh, Cmd+/ Copilot

### Working Features
- Native SwiftUI macOS 15 app (Swift, SPM)
- **7+ service connections**: AWS SSO, Jira, Confluence, Bitbucket, GitHub, Jenkins (multi), Grafana, Google (Gmail, Calendar)
- **AI Copilot**: 5-service tool-use, cross-service troubleshooting, "Investigate" from feed
- **Home Dashboard**: cross-service feed with correlation, SLO health, AI enrichment
- **Products & Resource Mapping**: per-integration discovery, product context filter across all views
- Full browser panels for Jira, GitHub, Bitbucket, Jenkins, Grafana, Confluence
- **SLO Dashboard**, **Skills Library**, **Incident Command**, **AWS Health/Cost**

---

## Priority 1 — Fix What's Broken

These bugs make existing features feel unfinished or unusable. Fix before adding anything new.

### Fixed
- [x] **Copilot: response formatting** — switched to MarkdownView (WKWebView) for assistant messages
- [x] **AWS Health: product filter** — now filters to activeAWSAccounts, auto-refreshes on product switch
- [x] **Confluence: layout + caching** — left-aligned, 3-layer caching (spaces/pages/content, 5-min TTL)
- [x] **Knowledge Base: caching** — ViewModel lifted to parent, survives tab switches
- [x] **Gmail: full-height layout** — email body fills available space
- [x] **Calendar: HTML rendering** — event descriptions render via CalendarHTMLView
- [x] **Skills: UX overhaul** — intro banner, "Try one" CTAs, "Run in Copilot" buttons

### Remaining
- [x] **AWS Costs: product filter** — account picker filters to product-relevant accounts, auto-selects on product switch
- [x] **AWS SSO: auto-config** — "Bootstrap AWS Config" button creates sso-session + profiles for all accounts/roles

---

## Priority 2 — Deepen Cross-Service Integration

### Done
- [x] Copilot cross-service tools (Grafana, Jenkins, Confluence)
- [x] Copilot context chips (Alerts, Builds)
- [x] "Troubleshoot" quick action
- [x] Smart Feed correlation (ticket keys across services)
- [x] SLO health in feed
- [x] One-click "Investigate" from feed → Copilot

### Remaining
- [ ] Alert-to-ticket correlation: Grafana alert → matching Jira ticket
- [ ] Incident view auto-populates: alert details, product, on-call, deploys, runbooks

---

## Priority 3 — Team Adoption & Polish

- [ ] Code signing (blocks team adoption — Gatekeeper warnings)
- [ ] SLO Dashboard: validate with real Prometheus queries
- [ ] Slack Integration (channel messages, incident channels, alert notifications)
- [ ] Menu bar companion (quick-access mini app)
- [ ] Export: PDF/markdown reports for SLOs, incidents, weekly status

---

## Future Features

### Executive Assistant (Background Intelligence)
The vision: a background service that proactively surfaces useful info throughout the day
without the user asking. Requires architecture change (launchd daemon or background agent).
- [ ] Automatic morning brief (on app launch or schedule)
- [ ] Background ticket monitoring (new comments on my tickets)
- [ ] Proactive alert correlation (new alert → check recent deploys → notify)
- [ ] Meeting prep (upcoming meeting → relevant tickets/docs auto-gathered)

### Harness Integration (CI/CD — used by most of Boomi outside CAM SRE)
- [ ] Harness pipeline browser (deployments, rollbacks, approvals)
- [ ] Harness context chip for Copilot (recent deployments)
- [ ] Copilot tool: `get_harness_deployments` for cross-service troubleshooting
- [ ] Product resource mapping: Harness projects/pipelines per product
- [ ] Feed integration: failed Harness deployments alongside Jenkins failures

### New Relic Integration (Observability — used by most of Boomi outside CAM SRE)
- [ ] New Relic alert browser (open violations, conditions)
- [ ] New Relic context chip for Copilot (active alerts)
- [ ] Copilot tool: `get_newrelic_alerts` for cross-service troubleshooting
- [ ] SLO Dashboard: support New Relic NRQL queries alongside Prometheus
- [ ] Product resource mapping: New Relic accounts/entities per product
- [ ] Feed integration: New Relic alerts alongside Grafana alerts

### Advanced AWS
- Multi-account cost comparison charts
- Resource browser (EC2, RDS, S3, Lambda)
- Cost anomaly detection and alerts

### Issue Triage Dashboard (Director's View)
In-app panel to review GitHub issues submitted by team members via Settings > Feedback.
- [ ] List open issues from ascarcel-boomi/Boomi-SRE (filtered by `submitted-from-app` label)
- [ ] Show issue details, labels, submitter metadata (app version, OS, connected services)
- [ ] Triage actions: label, prioritize, assign, close — all from within the app
- [ ] "Fix with Claude Code" button: generates a context-rich prompt (issue + relevant source files) and launches `claude -p` or copies to clipboard
- [ ] Status tracking: see which issues have associated commits/PRs
- [ ] Notification when new feedback arrives

### AI Enhancements
- Batch ticket analysis (daily work plan)
- Auto-generate runbooks from incident patterns
- Skills marketplace (share skills across teams)

---

## Architecture

- **SwiftUI** + macOS 15 (NavigationSplitView, Charts)
- **MVVM**: `@MainActor final class` ViewModels, `actor` Services
- **Swift Package Manager** (no Xcode project)
- Credentials in macOS Keychain via `KeychainHelper`
- Config in `~/.boomi_sre_config.json`
- Skills in `~/.boomi_sre_skills.json`
- Build: `swift build` or `bash build_app.sh`
- Release: `bash release.sh` (builds DMG, publishes GitHub release)
- Repo: https://github.com/ascarcel-boomi/Boomi-SRE
