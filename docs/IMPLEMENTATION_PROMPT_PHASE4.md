# Boomi SRE App — Phase 4: Service Browsers

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first:**
- `BoomiSRE/Sources/Models/AppState.swift` — central state object
- `BoomiSRE/Sources/Services/ClaudeService.swift` — AI integration
- `BoomiSRE/Sources/Services/GitHubService.swift` — existing GitHub API client
- `BoomiSRE/Sources/Services/ConfluenceService.swift` — existing Confluence client
- `BoomiSRE/Sources/Views/SidebarView.swift` — sidebar navigation
- `BoomiSRE/Sources/Models/ReportItem.swift` — ReportItem, ReportCatalog, ReportSection

**Key constraints:**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.
- All HTTP via native URLSession. No Alamofire or similar.
- Credentials in `~/.boomi_sre_secrets.json` (chmod 600). Never macOS Keychain (unsigned app).
- Config in `~/.boomi_sre_config.json`.
- AWS CLI must use absolute path `/usr/local/bin/aws` (PATH stripped in .app bundle).
- Jira search uses GET `/rest/api/3/search/jql`, NOT POST. Use `NOT IN` not `!=` in JQL.
- All Jira/Confluence Codable models need explicit CodingKeys.
- Claude API: `claude-sonnet-4-6` model via Anthropic Messages API v1.
- Jenkins at `jenkins-master.mashspud.com` uses Basic auth. USW2 instance at `jenkins-master.usw2.mashspud.com` requires SSL bypass — set `URLSessionConfiguration` to bypass SSL for that host.

---

## Implementation Plan

---

### Phase 4: Service Browsers

**Goal:** Add browsable panels for GitHub, Jenkins, Grafana, and Confluence. Each browser should have an AI layer.

#### 4A. GitHub Browser

Create `BoomiSRE/Sources/ViewModels/GitHubBrowserViewModel.swift` and `BoomiSRE/Sources/Views/Panels/GitHubBrowserView.swift`:

**Features:**
- List repositories (from org `Mashery-Boomi` + personal repos)
- Browse open PRs per repo with status (checks passing/failing, review status)
- PR detail view: diff summary, review comments, CI status
- **AI features:**
  - "Summarize PR" — AI reads the PR diff and generates a summary
  - "Review PR" — AI does a code review focusing on SRE concerns (reliability, security, performance, observability)
  - "Draft Review Comment" — AI drafts review feedback

**GitHub API calls** (extend existing GitHubService):
- `GET /orgs/{org}/repos` — list org repos
- `GET /repos/{owner}/{repo}/pulls` — list PRs
- `GET /repos/{owner}/{repo}/pulls/{number}` — PR detail
- `GET /repos/{owner}/{repo}/pulls/{number}/files` — PR diff
- `GET /repos/{owner}/{repo}/actions/runs` — CI/CD status

#### 4B. Jenkins Browser

Create `BoomiSRE/Sources/Services/JenkinsService.swift` (actor), `BoomiSRE/Sources/ViewModels/JenkinsBrowserViewModel.swift`, and `BoomiSRE/Sources/Views/Panels/JenkinsBrowserView.swift`:

**Features:**
- List Jenkins jobs/pipelines (from configured Jenkins URL)
- Show build history per job with status (success/failure/unstable/running)
- View console output for any build
- **AI features:**
  - "Explain Failure" — AI reads console output of a failed build and explains what went wrong + how to fix it
  - "Summarize Build" — AI summarizes what a build did (deployments, test results)
  - "Compare Builds" — AI compares two builds and highlights differences

**Jenkins API calls:**
- `GET /api/json?tree=jobs[name,color,url]` — list jobs
- `GET /job/{name}/api/json?tree=builds[number,result,timestamp,duration]` — build history
- `GET /job/{name}/{number}/consoleText` — console output
- `GET /job/{name}/{number}/api/json` — build detail

**Important:** Jenkins at `jenkins-master.mashspud.com` uses Basic auth. The USW2 instance at `jenkins-master.usw2.mashspud.com` requires `-sk` (skip SSL verify) — set `URLSessionConfiguration` to bypass SSL for that specific host.

#### 4C. Grafana Browser

Create `BoomiSRE/Sources/Services/GrafanaService.swift` (actor), `BoomiSRE/Sources/ViewModels/GrafanaBrowserViewModel.swift`, and `BoomiSRE/Sources/Views/Panels/GrafanaBrowserView.swift`:

**Features:**
- List dashboards (search API)
- Show dashboard panels with their queries
- Run Prometheus/Loki queries and display results
- **AI features:**
  - "Explain Dashboard" — AI summarizes what a dashboard is monitoring and current state
  - "Analyze Alerts" — AI reviews active alerts and correlates them
  - "Explain Metric" — user pastes a PromQL query, AI explains what it measures and current value

**Grafana API calls:**
- `GET /api/search?type=dash-db` — search dashboards
- `GET /api/dashboards/uid/{uid}` — get dashboard JSON
- `POST /api/ds/query` — run datasource queries
- `GET /api/v1/provisioning/alert-rules` — list alert rules

#### 4D. Confluence Browser

Create `BoomiSRE/Sources/ViewModels/ConfluenceBrowserViewModel.swift` and `BoomiSRE/Sources/Views/Panels/ConfluenceBrowserView.swift`:

**Features:**
- List spaces (use existing ConfluenceService)
- Browse pages within a space (hierarchy)
- View page content (rendered HTML or converted to markdown)
- Search across Confluence
- **AI features:**
  - "Summarize Page" — AI reads a Confluence page and provides a TL;DR
  - "Draft Page" — AI generates a new Confluence page (runbook, postmortem, design doc) from a prompt
  - "Update Page" — AI suggests updates to an existing page based on recent changes

**Confluence API calls** (extend existing ConfluenceService):
- `GET /wiki/api/v2/spaces` — list spaces
- `GET /wiki/api/v2/spaces/{id}/pages` — pages in space
- `GET /wiki/api/v2/pages/{id}?body-format=storage` — page content
- `GET /wiki/rest/api/search?cql=...` — search

#### 4E. Sidebar Integration

Add a "Services" section in the sidebar with:
- GitHub (icon: branch)
- Jenkins (icon: hammer)
- Grafana (icon: chart)
- Confluence (icon: document)

Each shows a badge with relevant counts (open PRs, failed builds, active alerts, etc.).
