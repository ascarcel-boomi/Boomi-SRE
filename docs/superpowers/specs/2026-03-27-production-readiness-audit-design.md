# Boomi SRE App — Production Readiness Audit

**Date:** 2026-03-27
**Goal:** Full production-readiness review of the 44K-line SwiftUI macOS app, executed by an Agent Team splitting work by architectural layer.
**Approach:** Audit by Layer (Approach B) — each agent owns non-overlapping files, fixes issues autonomously, compiles after changes.
**Timeline:** No hard deadline. Do it right.
**Fix policy:** Fix everything. No ticket-for-later unless it requires a design decision.

---

## Pre-Work (Team Lead, before spawning agents)

### 1. Update repo CLAUDE.md
Create/update `~/github/Boomi-SRE/CLAUDE.md` with architecture, build commands, patterns, and gotchas. Every agent reads this on startup.

### 2. Shared audit checklist
Every agent applies this to their layer:

| Category | What to check |
|----------|--------------|
| **Bugs** | Force unwraps, dead code, unreachable branches, build warnings |
| **Resilience** | Missing error handling, no empty state UI, no loading state, unhandled optionals |
| **Performance** | Unnecessary `@Published` triggers, missing `Equatable`, large closures capturing `self`, unbounded arrays |
| **Edge cases** | No network, expired tokens, empty API responses, 0 results, very long strings |
| **Consistency** | Inconsistent naming, mixed patterns, style drift |
| **Accessibility** | Missing labels, low contrast, no keyboard nav, hardcoded sizes |
| **Dead weight** | Unused imports, commented-out code, unused parameters, unreferenced files |

---

## Agent Assignments

### Team Lead (main Opus session)
- **Scope:** Shared/cross-cutting files + coordination + CLAUDE.md
- **Files:** `AppState.swift`, `ContentView.swift`, `SidebarView.swift`, `ViewStyles.swift`, `BoomiTheme.swift`, `Package.swift`, `BoomiSREApp.swift`, `OnboardingWizardView.swift`, `WelcomeView.swift`, `BreadcrumbView.swift`
- **Responsibilities:**
  - Write the repo CLAUDE.md first (before spawning agents)
  - Audit shared files for consistency issues that ripple everywhere
  - Review each agent's results at completion
  - Resolve any merge conflicts
  - Final `swift build` verification
  - Write summary report of all changes

### Agent 1 — Services (21 files)
- **Scope:** `BoomiSRE/Sources/Services/` + `BoomiSRE/Sources/Extensions/`
- **Key files:** JiraService, AWSAuthService, ClaudeService, GitHubService, BitbucketService, JenkinsService, GrafanaService, GoogleService, ConfluenceService, ZscalerTrustURLSession, CredentialDiscovery, KeychainHelper, JSMOpsService, KnowledgeBaseService, PeerPresenceService, ProductivityTracker, ResourceDiscoveryService, UpdateService, ServiceError
- **Focus areas:**
  - Error handling: are all API failures caught and surfaced? No silent failures
  - Token/auth expiry: does every service handle 401/403 gracefully?
  - Retry logic: any infinite retry loops? Missing timeouts?
  - Consistent patterns: do all services use `ZscalerTrustURLSession.shared`?
  - Dead code: unused methods, commented-out endpoints
  - Concurrency: proper `actor` isolation, no data races
- **After changes:** Run `swift build` and fix any compilation errors

### Agent 2 — Models (26 files)
- **Scope:** `BoomiSRE/Sources/Models/`
- **Key files:** AppState, JiraModels, ChatModels, IncidentModels, SLOModels, ProductContext, ProductResourceMap, FeedItem, NotificationModels, BPOPData, BPOPModels, BriefingModels, MOTDData, MOTDModels, WidgetModels, SkillModels, ToolCallModels, UserProfile, Peer, ProductivityModels, ReportItem, ReportResult, NotificationDetailModels
- **Focus areas:**
  - Codable correctness: missing `CodingKeys`, strict vs lenient decoding, default values for optional API fields
  - The 3 BPOPData TODOs (auto-populate from Jira)
  - Type safety: any `Any` types, stringly-typed enums, or force casts
  - Equatable/Hashable: missing conformances causing unnecessary SwiftUI re-renders
  - Unused models or properties
  - Consistency: naming conventions across all model files
- **After changes:** Run `swift build` and fix any compilation errors

### Agent 3 — ViewModels (20+ files)
- **Scope:** `BoomiSRE/Sources/ViewModels/`
- **Key files:** DashboardViewModel, ChatViewModel, IncidentViewModel, CostExplorerViewModel, OnCallViewModel, AWSHealthViewModel, BitbucketBrowserViewModel, BoardsViewModel, ConfluenceBrowserViewModel, ExecAssistantViewModel, GitHubBrowserViewModel, GrafanaBrowserViewModel, JenkinsBrowserViewModel, KnowledgeBaseViewModel, NotificationViewModel, NotificationDetailViewModel, ProductMappingViewModel, SavedFiltersViewModel, SkillsViewModel, SLOViewModel, TodoDashboardViewModel, TeamPresenceViewModel
- **Focus areas:**
  - `@MainActor` correctness: are all VMs properly annotated?
  - Published property hygiene: any that trigger re-renders unnecessarily?
  - Error states: does every VM expose error state to the view? Or do errors silently disappear?
  - Loading states: is there a consistent pattern for loading/loaded/error/empty?
  - Memory: any strong reference cycles (closures capturing `self` without `[weak self]`)?
  - Cancellation: are `Task` instances cancelled on deinit/disappear?
  - Empty data: what happens when the API returns 0 results?
- **After changes:** Run `swift build` and fix any compilation errors

### Agent 4 — Views (42 panels + shared)
- **Scope:** `BoomiSRE/Sources/Views/` (Panels/, Shared/, Settings/, Widgets/)
- **Key files:** All 42 panel views, SharedComponents, AIBar, MarkdownView, JiraIssueTableView, ProductBriefingCard, MOTDView, all Settings content views, WidgetViews
- **Focus areas:**
  - Empty states: does every view show something useful when data is empty? (not blank screen)
  - Loading states: spinner or skeleton while data loads?
  - Error states: does the view show the error from the VM, or swallow it?
  - Accessibility: VoiceOver labels on icons/buttons, sufficient contrast, keyboard navigation
  - Layout edge cases: very long text, 0 items, 100+ items, narrow window
  - Consistency: all views using `ViewStyles.swift` patterns (`.cardStyle()`, `.sectionCard()`, etc.)
  - Dead views: any panel that's defined but not reachable from sidebar/navigation
- **After changes:** Run `swift build` and fix any compilation errors

---

## Coordination Protocol

1. Team lead writes CLAUDE.md, then spawns all 4 agents
2. Each agent works in its own git worktree
3. Agents communicate findings via mailbox — especially cross-layer issues (e.g., "Service X returns nil where VM Y expects non-nil")
4. Each agent commits after every logical group of fixes with descriptive messages
5. Team lead merges each agent's branch, resolves conflicts
6. Final `swift build` by team lead
7. Team lead writes summary report: what was found, what was fixed, what needs design decisions

## Success Criteria

- `swift build` passes with zero warnings
- Every view has empty, loading, and error states
- Every service handles auth expiry and network failure
- No force unwraps outside of known-safe contexts (e.g., `Color(hex:)`)
- No dead code or unused files
- Consistent patterns across all layers
- CLAUDE.md accurately reflects the codebase
