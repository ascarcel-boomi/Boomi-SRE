# Boomi SRE

Native macOS SwiftUI application for Boomi's Production Engineering and Reliability team. Integrates Jira, AWS, Confluence, Bitbucket, GitHub, Jenkins, Grafana, and Google Workspace into a unified SRE command center with AI-powered analysis powered by Claude.

---

## Installation

### From DMG (recommended)
1. Download the latest `Boomi-SRE-*.dmg` from [Releases](https://github.com/ascarcel-boomi/Boomi-SRE/releases)
2. Open the DMG and drag **Boomi SRE** to the Applications folder
3. On first launch, macOS may warn about an unidentified developer — right-click → Open to bypass
4. Credentials are auto-discovered from existing tool configs (Kiro, Amazon Q, `~/.aws/`, `~/.gitconfig`)

### From Source
```bash
git clone https://github.com/ascarcel-boomi/Boomi-SRE.git
cd Boomi-SRE
bash build_app.sh
open -a "Boomi SRE"
```

**Requirements:** macOS 15+, Swift 6.2 (Xcode Command Line Tools)

---

## Features

### AI

| Feature | Description |
|---------|-------------|
| **AI Copilot** | Context-aware chat with Claude. Aware of your Jira tickets, incidents, AWS health, and recent PRs. Supports tool calls to fetch live data. |
| **Executive Assistant** | Daily briefing, standup notes, email triage, incident summaries, and on-demand reports for leadership. |
| **Incident Command** | Jira-backed incident dashboard. AI-powered root cause analysis, status updates, postmortems, and remediation suggestions. |
| **Notifications** | Background polling for Jira assignments, Jenkins failures, Grafana alerts, GitHub PR reviews, Confluence updates, AWS cost anomalies, and app updates. |

### Jira

| Feature | Description |
|---------|-------------|
| **My TODO** | Personal task list filtered from sprint/kanban work. Priority charts, due date tracking. |
| **Saved Filters** | Run and visualize your favorite Jira JQL filters with auto-generated charts. |
| **Boards** | Browse scrum and kanban boards across all projects. |
| **Ticket Detail** | Full 7-tab view: AI Analysis, Details, Actions, Description, Comments, Subtasks, PRs & Commits. Inline status changes, comments, and assignments. AI can post its analysis as a ticket comment with duplicate detection. |

### AWS

| Feature | Description |
|---------|-------------|
| **Infrastructure Health** | EC2, RDS, ALB, Auto Scaling, CloudFront, ElastiCache, OpenSearch, SQS/SNS, Route53, WAF health across all configured profiles. AI-powered incident diagnosis. |
| **Cost Explorer** | Monthly/weekly AWS cost breakdowns by service and account. Anomaly detection, trend analysis, and CSV export. |

### Services

| Feature | Description |
|---------|-------------|
| **GitHub Browser** | Browse org/personal repos, open PRs, workflow runs. AI summarizes PRs and performs SRE-focused code review. |
| **Jenkins Browser** | Browse jobs and build history, stream console output, diff log between runs. AI explains failures and summarizes builds. |
| **Grafana Browser** | Dashboard list with folder/tag filters, embedded WebView for live dashboards (Okta SSO via shared Safari cookies), panel/query inspector. AI explains dashboards and analyzes alert rules. |
| **Confluence Browser** | Space and page browser, embedded WebView for native Confluence rendering (Okta SSO), plain-text view for AI summarization. AI summarizes pages and drafts new ones. |

### Google Workspace

| Feature | Description |
|---------|-------------|
| **Gmail** | Inbox with unread count, thread view, HTML rendering. |
| **Calendar** | Upcoming events with meeting details. |
| **Google Chat** | Space/message browser (requires Google Workspace MCP). |

### Dashboard & Settings

- **Customizable Dashboard** — widgets for my tickets, firing alerts, recent PRs, Jenkins builds, upcoming meetings, unread emails, and active incidents. AI generates a daily status summary.
- **Onboarding Wizard** — guided first-run setup across all services.
- **Auto-discovery** — finds credentials from `~/.kiro/`, `~/.amazonq/`, `~/.aws/`, `~/.gitconfig`, `~/.npmrc`.
- **User Profile** — experience level (Junior → Principal) adjusts AI response depth.
- **Auto-Updates** — checks GitHub Releases on launch, shows update banner, one-click download and install.

---

## Configuration

All credentials are stored in `~/.boomi_sre_secrets.json` (chmod 600). Config in `~/.boomi_sre_config.json`. Neither file is ever committed to git.

### Supported Services

| Service | Auth Method | Notes |
|---------|-------------|-------|
| Jira | Email + API token | `boomii.atlassian.net` |
| Confluence | Email + API token | Same credentials as Jira |
| Bitbucket | Email + app password | `boomii` workspace |
| GitHub | Personal access token | Classic or fine-grained |
| Jenkins | Username + API token | `jenkins-master.mashspud.com` |
| Grafana | Service account token | Bearer auth for API, SSO cookie for WebView |
| AWS | SSO profile or access keys | CLI must be installed at `/usr/local/bin/aws` or `/opt/homebrew/bin/aws` |
| Google | OAuth2 via Google Workspace MCP | Requires credentials JSON |
| Claude (AI) | API key | Auto-discovered from env vars, Kiro, or Amazon Q config |

### Auto-Discovery
On first launch, click **Auto-discover Credentials** in Settings. The app scans:
- `~/.kiro/mcp_credentials/` — GitHub, Grafana, Jenkins tokens
- `~/.amazonq/mcp_credentials/` — same
- `~/.aws/credentials` and `~/.aws/config` — AWS profiles
- `~/.gitconfig` — Jira base URL, user email
- Environment variables — `ANTHROPIC_API_KEY`, `GITHUB_TOKEN`

---

## Architecture

```
BoomiSRE/Sources/
├── BoomiSREApp.swift         # App entry point, launch hooks, menu bar commands
├── ContentView.swift         # Main layout: sidebar + detail + update banner
├── Models/
│   ├── AppState.swift        # Central @Observable state, config persistence
│   ├── JiraModels.swift      # Codable models for Jira API
│   ├── IncidentModels.swift  # Incident, IncidentSeverity, IncidentStatus
│   ├── NotificationModels.swift  # SRENotification, NotificationType
│   └── UserProfile.swift     # Experience level, AI depth hints
├── Services/                 # Actor-based API clients (URLSession)
│   ├── JiraService.swift     # Jira REST API v3 (GET /search/jql)
│   ├── GrafanaService.swift  # Grafana REST API
│   ├── ConfluenceService.swift
│   ├── GitHubService.swift   # GitHub REST API v3
│   ├── JenkinsService.swift  # Jenkins JSON API
│   ├── BitbucketService.swift
│   ├── AWSAuthService.swift  # AWS SSO/profile management via CLI
│   ├── AWSCostService.swift  # AWS Cost Explorer via CLI
│   ├── AWSInfraService.swift # EC2/RDS/ALB/etc health via CLI
│   ├── ClaudeService.swift   # Anthropic Messages API
│   ├── GoogleService.swift   # Gmail/Calendar via OAuth2
│   ├── UpdateService.swift   # GitHub Releases auto-update
│   └── CredentialDiscovery.swift
├── ViewModels/               # @MainActor ObservableObject ViewModels
├── Views/
│   ├── Panels/               # Main content panels (one per sidebar item)
│   ├── Settings/             # Settings tab content views
│   ├── Shared/               # Shared components (LoadingView, EmptyStateView, etc.)
│   └── Widgets/              # Dashboard widget views
└── Extensions/
    ├── URLRequestExtensions.swift  # addBasicAuth, addBearerAuth, trimSlash
    ├── AIAnalyzable.swift    # Protocol + runAIAnalysis() default impl
    ├── AWSCLIRunner.swift    # Shared AWS CLI subprocess runner
    └── Formatters.swift      # Static DateFormatter/RelativeDate instances
```

**Key patterns:**
- All services are `actor` (thread-safe, no data races)
- All ViewModels are `@MainActor final class: ObservableObject`
- Shared auth helpers: `URLRequest.addBasicAuth()`, `URLRequest.addBearerAuth()`
- Shared AI boilerplate: `AIAnalyzable` protocol with `runAIAnalysis()`
- Credentials: never in code, loaded from `~/.boomi_sre_secrets.json` at runtime
- AWS CLI: absolute path via `AWSAuthService.resolvedAWSPath`, pipes read before `waitUntilExit()` to prevent deadlock

---

## Development

### Build
```bash
swift build              # debug build
swift build -c release   # release build
bash build_app.sh        # release + .app bundle + .dmg in dist/
```

### Test
```bash
swift test
```

### Release
```bash
bash release.sh              # auto-version (YY.MM.DD)
bash release.sh 26.03.14     # explicit version
```

Requires `gh` CLI authenticated. Creates a tagged GitHub release with the DMG attached.

### Prerequisites
- macOS 15+
- Swift 6.2 (via Xcode or `xcode-select --install`)
- AWS CLI (for infrastructure and cost features)
- `gh` CLI (for `release.sh` only)

---

## Contributing

Submit feature requests from within the app (Help → Submit Feedback) or via [GitHub Issues](https://github.com/ascarcel-boomi/Boomi-SRE/issues).
