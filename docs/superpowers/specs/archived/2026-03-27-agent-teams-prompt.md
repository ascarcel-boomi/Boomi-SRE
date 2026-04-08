# Agent Teams Prompt — Production Readiness Audit

**Usage:** Open a tmux session, start `claude` in `~/github/Boomi-SRE/`, and paste the prompt below.

---

## Prompt

```
I need you to run a full production-readiness audit of this Boomi SRE macOS SwiftUI app (147 files, 44K lines). Read the spec at docs/superpowers/specs/2026-03-27-production-readiness-audit-design.md for the full plan.

Here's what I need you to do as team lead:

**Phase 1 — Pre-work (you, before spawning anyone):**
1. Read the entire codebase structure and the existing CLAUDE.md (if any)
2. Create or update CLAUDE.md in this repo root with: architecture overview, build commands (`swift build`, `bash build_app.sh`, `bash release.sh`), key patterns (MVVM, actor services, ZscalerTrustURLSession, product-filter-first, ViewStyles), gotchas (Jira GET not POST, AWS CLI absolute path, @StateObject in switch cases, SourceKit false positives), and file structure
3. Commit the CLAUDE.md

**Phase 2 — Spawn 4 teammates using Agent Teams:**

Teammate 1 — "services-auditor":
- Audit all files in BoomiSRE/Sources/Services/ and BoomiSRE/Sources/Extensions/
- Check: error handling (no silent failures), auth expiry handling (401/403), retry logic (no infinite loops), consistent use of ZscalerTrustURLSession.shared, dead code, proper actor isolation, missing timeouts
- Fix everything you find. Run `swift build` after changes. If build fails, fix it.
- Commit with descriptive messages grouped by logical change.
- Message other teammates if you find cross-layer issues (e.g., a service that returns nil where a VM expects non-nil).

Teammate 2 — "models-auditor":
- Audit all files in BoomiSRE/Sources/Models/
- Check: Codable correctness (missing CodingKeys, strict decoding, defaults for optional API fields), the 3 BPOPData TODOs, type safety (no Any types, no force casts), missing Equatable/Hashable conformances, unused models/properties, naming consistency
- Fix everything you find. Run `swift build` after changes. If build fails, fix it.
- Commit with descriptive messages grouped by logical change.
- Message other teammates if you find cross-layer issues.

Teammate 3 — "viewmodels-auditor":
- Audit all files in BoomiSRE/Sources/ViewModels/
- Check: @MainActor correctness, unnecessary @Published re-renders, error state exposure (every VM must expose errors to views), consistent loading/loaded/error/empty pattern, strong reference cycles ([weak self] in closures), Task cancellation on deinit/disappear, empty data handling
- Fix everything you find. Run `swift build` after changes. If build fails, fix it.
- Commit with descriptive messages grouped by logical change.
- Message other teammates if you find cross-layer issues.

Teammate 4 — "views-auditor":
- Audit all files in BoomiSRE/Sources/Views/ (Panels/, Shared/, Settings/, Widgets/)
- Check: empty states (no blank screens), loading states (spinner/skeleton), error state display, accessibility (VoiceOver labels, contrast, keyboard nav), layout edge cases (long text, 0 items, 100+ items), consistent use of ViewStyles.swift patterns (.cardStyle(), .sectionCard()), dead/unreachable views
- Fix everything you find. Run `swift build` after changes. If build fails, fix it.
- Commit with descriptive messages grouped by logical change.
- Message other teammates if you find cross-layer issues.

**Phase 3 — After all teammates complete:**
1. Merge all teammate branches
2. Resolve any conflicts
3. Run final `swift build` — must pass with zero warnings
4. Write a summary report to docs/audit-report-2026-03-27.md listing: issues found per category, fixes applied, any items that need my design decision
5. Commit the report

**Important rules for all agents:**
- Always run `swift build` after making changes — never leave the build broken
- The app uses Swift 6.2, macOS 15, Swift Package Manager (no Xcode)
- All HTTP calls must use `ZscalerTrustURLSession.shared` (Zscaler SSL proxy)
- AWS CLI is at `/usr/local/bin/aws` (PATH is stripped in .app bundle)
- Jira API uses GET `/rest/api/3/search/jql` (NOT POST)
- Do not add new features. This is audit and fix only.
- Do not refactor architecture. Fix bugs, add missing error handling, remove dead code, improve consistency.
```

---

## How to Run

```bash
# 1. Start tmux
tmux new -s boomi-audit

# 2. Navigate to repo
cd ~/github/Boomi-SRE

# 3. Start Claude Code
claude

# 4. Paste the prompt above (or reference this file)
#    You can also type: @docs/superpowers/specs/2026-03-27-agent-teams-prompt.md
```

Watch the tmux panes as teammates spawn. Use `Alt+Arrow` to switch between panes and monitor progress.
