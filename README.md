# Boomi SRE

Native macOS SwiftUI application for Boomi's Production Engineering and Reliability team. Integrates Jira, AWS, Confluence, Bitbucket, GitHub, Jenkins, and Grafana into a single unified dashboard with AI-powered ticket analysis.

## Quick Start

```bash
# Clone
git clone https://github.com/ascarcel-boomi/Boomi-SRE.git
cd Boomi-SRE

# Build and install
bash build_app.sh

# Launch
open -a "Boomi SRE"
```

Requires: macOS 15+, Swift 6.2 (Xcode Command Line Tools), Python 3 with boto3 (for AWS reports).

## Features

### Jira Dashboards
- **My TODO** — personal task list from sprint work and unplanned kanban, with priority charts
- **Saved Filters** — run and visualize your favourite Jira filters with auto-generated charts
- **Boards** — browse scrum and kanban boards across all your projects

### Ticket Detail
- Full ticket view with 7 tabs: AI Analysis, Details, Actions, Description, Comments, Subtasks, PRs & Commits, History
- **Claude AI Analysis** — auto-analyzes each ticket and recommends next steps
- **Inline actions** — change status, add comments, assign tickets without leaving the app
- **Post AI analysis as comment** — with duplicate detection to prevent spam

### AWS Cost Reports
- CAM Production cost breakdown by service
- Top 10 services by spend
- AWS portal credential paste for quick account setup

### Settings & Connections
- 7 integrated services: AWS SSO, Jira, Confluence, Bitbucket, GitHub, Jenkins, Grafana
- Auto-discover credentials from ~/.kiro/, ~/.amazonq/, ~/.aws/, ~/.gitconfig
- One-click retry, disconnect, and re-configure for all services
- AWS SSO login opens the SSO start page in your browser

## Architecture

- **SwiftUI** with NavigationSplitView and Swift Charts
- **MVVM** with @MainActor ViewModels and actor-based services
- **Native API calls** via URLSession (Jira, Confluence, Bitbucket, GitHub, Grafana)
- **Python bridge** via Process for AWS Cost Explorer scripts
- **Claude AI** via Anthropic Messages API (auto-discovers API key)
- **Credentials**: ~/.boomi_sre_secrets.json (chmod 600)
- **Config**: ~/.boomi_sre_config.json

## For New Team Members

1. Run `bash build_app.sh` — installs to /Applications/
2. Launch the app — credentials are auto-discovered from your existing tool configs
3. If anything is missing, click "Auto-discover Credentials" in Settings
4. For AWS, paste portal credentials or use SSO Login

No manual credential setup needed if you already have Kiro or Amazon Q configured.
