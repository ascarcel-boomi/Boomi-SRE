# Boomi SRE — TODO / Roadmap

## Mission

Reduce toil and context switching for SREs working across multiple teams and products.
Blur the lines between services so engineers flow between tasks without juggling browser tabs.

---

## Current State (as of 2026-03-17)

### Recently Completed
- **Zscaler SSL Trust** — shared URLSession across all 16 network callers, no more cert errors
- **UI Consistency** — shared ViewStyles (cards, badges, AI boxes, headers) across 22 views
- **Copilot Fix** — works with both API key and Claude CLI (Enterprise license)
- **Removed AIBar** — single full Copilot panel, no duplicate mini-bar
- **Removed Google Chat** — API not available; Slack Integration on roadmap
- **Confluence Fix** — fixed expand params in both listPages and recentlyModifiedPages
- **SLO Query Fix** — Prometheus queries now use SLO's windowDays (not hardcoded 5m), better error messages
- **Products & Resource Mapping** — AI-powered resource discovery, per-integration, team templates
- **Multi-Jenkins** — multiple servers, Jenkins Views, per-server routing
- **Skills Builder** — reusable AI prompt templates, 6 built-in, editor, runner, Copilot integration
- **SLO Dashboard** — SLI/SLO/SLA with Prometheus queries via Grafana, error budgets, AI analysis
- **Keyboard Shortcuts** — Cmd+1-6 sidebar panels, Cmd+R refresh, Cmd+/ Copilot, Cmd+F search

### Working Features
- Native SwiftUI macOS 15 app (Swift, SPM)
- **7+ service connections**: AWS SSO, Jira, Confluence, Bitbucket, GitHub, Jenkins (multi), Grafana, Google (Gmail, Calendar)
- Auto-discovery of credentials from ~/.kiro/, ~/.amazonq/, ~/.aws/, ~/.gitconfig
- **Products & Resource Mapping** with per-integration discovery, filter bar, bulk actions, team templates
- **Jira**: TODO dashboard, saved filters, boards, ticket detail (7 tabs), AI analysis
- **GitHub Browser**: org/personal repos, PRs, branches, commits, AI analysis
- **Bitbucket Browser**: workspace repos, PRs, branches, pipelines
- **Jenkins Browser**: multi-server, views, builds, console output, AI analysis
- **Grafana Browser**: folders + dashboards, WebView embed, alerts, AI explain
- **Confluence Browser**: spaces, pages, content (WebView + plain text), search, AI summarize
- **Google**: Gmail, Calendar via OAuth
- **AWS**: Health (multi-account EC2/RDS/ALB/ASG), Cost Explorer, SSO account discovery
- **SLO Dashboard**: define SLOs per product, live Prometheus data, error budget gauges
- **Skills Library**: 6 built-in + custom, variable templates, Copilot integration
- **AI Copilot**: tool-use + CLI fallback, quick actions, skills, context injection
- **Home Dashboard**: 12+ widget types, customizable, health score bar, MOTD

---

## Priority 1 — Verify & Stabilize

These must work reliably before adding anything new.

- [ ] SLO Dashboard: test with real Prometheus queries (query fix deployed, needs live validation)
- [ ] P2P Presence: test with a second Mac on the same network
- [ ] Code signing for easier distribution (blocks team adoption)

---

## Priority 2 — Cross-Service Integration

The browser views work individually but don't connect the dots. An SRE responding to an
alert needs alert details + recent deploys + change ticket + runbook + on-call — in one flow.

### Troubleshoot Mode (Copilot)
- [ ] "Troubleshoot" command: given an alert or ticket, auto-gather context from Grafana + Jenkins + Jira + Confluence
- [ ] Copilot context chips for Grafana alerts and Jenkins builds (not just Jira/Calendar/Email/AWS)
- [ ] Link Jira tickets ↔ Jenkins builds ↔ GitHub PRs automatically via commit messages and ticket keys

### Smart Feed (Home Dashboard)
- [ ] Feed items that cross-reference services (e.g. "CAMSRE-123 has a failing Jenkins build")
- [ ] SLO health summary widget on home dashboard
- [ ] Alert-to-ticket correlation: when a Grafana alert fires, show the related Jira ticket if one exists

### Incident Flow
- [ ] One-click "Start Incident" from a Grafana alert or Jira ticket
- [ ] Incident view auto-populates: alert details, affected product, on-call, recent deploys, runbook links

---

## Priority 3 — Team Adoption & Polish

- [ ] Slack Integration (channel messages, incident channels, alert notifications)
- [ ] Menu bar companion (quick-access mini app)
- [ ] Export: PDF/markdown reports for SLOs, incidents, weekly status
- [ ] Confluence: MCP-based page creation/editing

---

## Future Features

### Advanced AWS
- Multi-account cost comparison charts
- Resource browser (EC2, RDS, S3, Lambda)
- Cost anomaly detection and alerts

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
