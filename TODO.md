# Boomi SRE — TODO / Roadmap

## Current State (as of 2026-03-17)

### Recently Completed
- **Products & Resource Mapping** — AI-powered resource discovery, per-integration, team templates
- **Claude CLI Backend** — Enterprise license support (no API key needed)
- **Multi-Jenkins** — multiple servers, Jenkins Views, per-server routing
- **Skills Builder** — reusable AI prompt templates, 6 built-in, editor, runner, Copilot integration
- **SLO Dashboard** — SLI/SLO/SLA with Prometheus queries via Grafana, error budgets, AI analysis
- **P2P Team Presence** — Bonjour/mDNS zero-config LAN peer discovery
- **UI Overhaul** — deep tab linking, breadcrumbs, collapsible sections, alternating rows, MOTD bar
- **Navigation Fixes** — all widgets deep-link to correct panel + tab, single sidebar toggle
- **Confluence Fix** — removed unsupported `orderby` parameter, improved error messages
- **Removed Google Chat** — Google Chat API not available in Cloud project; feature removed entirely
- **Grafana Folders** — folder-based filtering, collapsible folder groups, UID matching, 5K limit
- **AWS IAM Identity Center** — SSO account discovery (238+ accounts with names)
- **Theming** — Boomi brand colors via .tint(), live preview, CAM icon fix (network)

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
- **P2P Team Presence**: Bonjour discovery, sidebar indicator, popover
- **AI Copilot**: tool-use chat, quick actions, skills, context injection
- **Executive Assistant**: morning brief, email triage, daily ticket brief
- **Home Dashboard**: 12+ widget types, customizable, health score bar, MOTD

---

## In Progress

### Bug Fixes Needed
- [ ] Confluence: verify page listing works end-to-end after `orderby` removal
- [ ] SLO Dashboard: test with real Prometheus queries
- [ ] Skills: test "Save as Skill" from Copilot conversation
- [ ] P2P Presence: test with a second Mac on the same network

---

## Next Up

### Polish & Integration
- [ ] SLO widget on home dashboard (summary card showing health counts)
- [ ] Skills quick-launch from keyboard shortcut
- [ ] P2P Presence: show incident context (if someone is in Incident Commander view)
- [ ] Confluence: add MCP-based page creation/editing (mcp-atlassian tools)

### macOS Menu Bar Integration
- [ ] Menu bar companion (quick-access mini app)
- [ ] Standard keyboard shortcuts: Cmd+1-6 for sidebar panels
- [ ] Cmd+R to refresh the current view
- [ ] Reports menu: quick access to common views

### Code Quality
- [ ] Code signing for easier distribution (no Gatekeeper warnings)
- [ ] Comprehensive unit tests for ViewModels
- [ ] Integration tests for service API calls
- [ ] Accessibility audit (VoiceOver, keyboard navigation)

---

## Future Features

### Incident Commander
- Structured incident response workflow
- Real-time timeline with automatic event logging
- Role assignment (IC, Communications, Operations)
- Auto-post updates to Slack
- Post-incident report generation (ties into Skills)

### PDF/Markdown Export
- Generate PDF reports for SLOs, incidents, weekly status
- Export post-mortems as markdown
- Share via email or Confluence

### GitHub PR Review
- Inline diff viewer within the app
- AI-powered code review suggestions
- Link PRs to Jira tickets automatically

### Slack Integration
- [ ] Slack channel messages (replace Google Chat)
- [ ] Incident channel auto-creation
- [ ] Alert notifications to Slack

### Advanced AWS
- Multi-account cost comparison charts
- Resource browser (EC2, RDS, S3, Lambda)
- Cost anomaly detection and alerts
- CloudWatch metric embedding

### AI Enhancements
- Batch ticket analysis (daily work plan)
- "Troubleshoot" mode: Claude reviews ticket + AWS + Grafana context together
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
