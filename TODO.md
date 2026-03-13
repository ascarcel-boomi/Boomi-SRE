# Boomi SRE — TODO / Roadmap

## Phase 8 (Complete)
- 8A: Sidebar icons in collapsed mode, consistent icon colors, Settings item sizing fix
- 8B: Home page redesign — customizable widget dashboard (12 widget types, AI daily summary)
- 8C: GitHub browser — graceful org error handling, pagination, broadened affiliation, repo filter
- 8D: Grafana browser — WKWebView embed with Bearer auth, Dashboard/Queries tab
- 8E: Confluence browser — layout fix, improved content fetching, WKWebView HTML renderer
- 8F: Google Chat — chat.google.com URL, persistent session, back/forward/reload toolbar
- 8G: DashboardView replaces WelcomeView, "Boomi SRE" branding throughout

## Next Session: Preferences & Menu Bar

### 1. macOS Menu Bar Integration
- Add a proper `CommandMenu` to the SwiftUI app with all sidebar items
- **Reports menu**: My TODO, Saved Filters, Boards, AWS Cost Reports
- **Services menu**: list all 7 services with status indicators, click to re-check or disconnect
- **Favorites menu**: quick-switch between favorite AWS accounts, Jira projects, etc.
- Standard keyboard shortcuts: Cmd+1 for TODO, Cmd+2 for Filters, etc.
- Cmd+R to refresh the current view

### 2. Preferences / Favorites in Settings
Add a new "Preferences" tab in Settings with:

#### Favorite AWS Accounts
- Show all discovered profiles from ~/.aws/config and ~/.aws/credentials
- Checkboxes to mark favorites
- Favorites appear in the menu bar for quick switching
- When running a report, picker only shows favorites (with "Show All" toggle)

#### Favorite Jira Projects
- Fetch all accessible projects via GET /rest/api/3/project/search
- Checkboxes to mark favorites (default: CAMSRE, SRE from saved config)
- Favorites filter the Boards view and TODO dashboard
- Quick-switch in menu bar

#### Favorite Confluence Spaces
- Fetch spaces via GET /wiki/rest/api/space
- Checkboxes to mark favorites
- Future: browse Confluence pages within the app

#### GitHub Repos
- Fetch repos via GET /api.github.com/user/repos and /orgs/Mashery-Boomi/repos
- Show as a browsable list with star/favorite toggle
- Future: view PRs, issues, actions within the app

#### Bitbucket Repos
- Fetch repos via GET /2.0/repositories/boomii (paginated, ~2000 repos)
- Filter/search by name
- Show as a browsable list with favorite toggle
- Future: view PRs within the app

#### Jenkins Pipelines
- Fetch jobs via GET /api/json?tree=jobs[name,url,color]
- Show pipeline list with status colors (blue=success, red=failed, etc.)
- Favorite specific pipelines for the menu bar
- Future: trigger builds, view console output

#### Grafana Dashboards
- Fetch dashboards via GET /api/search?type=dash-db
- Show as a browsable list with favorite toggle
- Click to open in browser or render key panels inline
- Future: embed Grafana panels via iframe or API

### 3. Service Browsers (new sidebar sections)
Each service gets a browsable panel (like the Jira Boards view):

- **GitHub Browser**: repos → PRs → files (read-only)
- **Bitbucket Browser**: repos → PRs → branches
- **Jenkins Browser**: pipelines → builds → console output
- **Grafana Browser**: dashboards → panels with data
- **Confluence Browser**: spaces → pages (read-only)

### 4. Persistence
- Store favorites in ~/.boomi_sre_config.json
- Favorites persist across app restarts
- Auto-discover should not overwrite user's favorites

---

## Future Features

### Claude AI Enhancements
- **Chat interface**: free-form chat with ticket context
- **"Draft a comment"**: Claude writes a response based on ticket history
- **"Troubleshoot"**: Claude reviews ticket + AWS infrastructure context
- **Batch analysis**: analyze all TODO tickets and generate a daily work plan
- **Kiro integration**: "Open in Kiro" button to launch IDE with relevant repo

### Jira Enhancements
- **Drag-and-drop kanban**: rearrange tickets on a kanban board view
- **Time tracking**: log work directly from the app
- **Bulk operations**: transition/assign multiple tickets at once
- **Custom JQL builder**: visual JQL query builder with autocomplete
- **Sprint planning**: view sprint burndown/velocity charts

### AWS Enhancements
- **Multi-account cost comparison**: side-by-side cost charts across accounts
- **Resource browser**: EC2 instances, RDS, S3 buckets with status
- **Cost anomaly alerts**: highlight unusual spending
- **Infrastructure health**: pull CloudWatch metrics

### App Polish
- **Notifications**: macOS notifications for ticket updates, cost alerts
- **Keyboard shortcuts**: full keyboard navigation
- **Dark/light mode**: follow system or manual toggle
- **Export**: PDF report generation, email sharing
- **Onboarding wizard**: first-run setup flow for new users
- **Code signing**: sign the app for easier distribution (no Gatekeeper warnings)

---

## Current State (as of 2026-03-12)

### Working Features
- Native SwiftUI macOS app (Swift 6.2, macOS 15)
- Boomi logo icon (Apple HIG compliant)
- **7 service connections**: AWS SSO, Jira, Confluence, Bitbucket, GitHub, Jenkins, Grafana
- Auto-discovery of credentials from ~/.kiro/, ~/.amazonq/, ~/.aws/, ~/.gitconfig
- Startup health checks for all services
- Clickable status cards (retry/disconnect/configure)
- Right-click context menus on all service indicators
- **Jira TODO Dashboard**: real-time ticket list with categories, charts, issue type icons
- **Jira Saved Filters**: browse and visualize favourite filters with auto-charts
- **Jira Boards**: auto-discover projects and boards, browse with "My tickets" toggle
- **Ticket Detail View**: 7 tabs (AI Analysis, Details, Actions, Description, Comments, Subtasks/Parent, PRs & Commits, History)
- **Claude AI Analysis**: auto-analyzes tickets with recommended next steps, post as comment with duplicate detection
- **Linked PRs & Commits**: fetched from Jira dev-status API
- **AWS Cost Reports**: CAM Production costs, Top 10 services (Python bridge)
- **Settings**: inline panel with 7 service tabs, auto-discover button, AWS portal credential paste
- **AWS profile management**: SSO profiles + portal paste, account name resolution

### Architecture
- SwiftUI + NavigationSplitView
- Swift Charts for visualization
- MVVM with @MainActor ViewModels
- Actor-based services (JiraService, AWSAuthService, ClaudeService, etc.)
- Credentials in ~/.boomi_sre_secrets.json (chmod 600)
- Config in ~/.boomi_sre_config.json
- Python bridge for AWS cost scripts (~/github/home-config/)
- Jira API calls native Swift (URLSession)
- Claude API calls native Swift (Anthropic Messages API)

### Repo
- https://github.com/ascarcel-boomi/Boomi-SRE
- Build: `swift build` or `bash build_app.sh`
- Install: `/Applications/Boomi SRE.app`
- Tests: `swift run_tests.swift`
