# Bug-Fix & Stabilization Pass — Design Spec

**Date:** 2026-04-02
**Goal:** Fix all known bugs, UX issues, and structural problems before adding new features. Stabilize the foundation.

**Hard Rule:** DO NOT touch integration auth/configuration code — tokens, API keys, MCP servers, credential discovery, auth flows, ZscalerTrustURLSession, or Settings integration forms. All integration fixes are display-layer only.

**Fix Approach Tags:**
- **Code fix** — logic/navigation/data bugs fixed via `/review` and `/simplify`
- **`/frontend-design`** — UI/UX improvements fixed via the frontend-design skill
- **Unit tests required** — every fix must have a passing unit test before moving on

---

## 1. HOME — Navigation Restructure

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 1.1 | Rework | App restores last sidebar item on launch — should always open Home > Dashboard | Code fix |
| 1.2 | Rework | Swap Home structure: Dashboard = default first tab, AI Copilot = second tab (reverses 03/28 copilot-as-home design) | Code fix |

**Context:** The 2026-03-28 design made AI Copilot the Home page and moved Dashboard under My Work. This reversal puts Dashboard back as the landing page (at-a-glance status) with AI Copilot as a secondary tab for deeper interaction.

---

## 2. HOME > DASHBOARD

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 2.1 | Bug | Dashboard reloads from scratch every visit — no caching in any mode (Feed, Auto, Custom) | Code fix |
| 2.2 | Tweak | Rename "AI Daily Summary" widget to "AI Executive Assistant" | Code fix |
| 2.3 | Remove | Quick Actions widget — entirely redundant (Ask Copilot, Settings, New Incident all accessible elsewhere; New Incident is dangerous as a quick action) | Code fix |
| 2.4 | Bug+Rework | Service Health widget not clickable; should navigate to new Settings > Integrations landing page | Code fix + `/frontend-design` |

---

## 3. HOME > AI COPILOT

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 3.1 | Bug | "See all Skills" link navigates to Knowledge Base instead of Skills | Code fix |
| 3.2 | Tweak | Show AI Preferences summary on Copilot screen with link to edit in Settings | `/frontend-design` |
| 3.3 | Rework | Integrate skill invocation directly into Copilot screen (Skills removed as separate sidebar item) | Code fix + `/frontend-design` |

---

## 4. ALERTS & ON-CALL

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 4.1 | Tweak | Grafana: default to collapsed state; add expand all / collapse all controls; remember user's expanded items on return | Code fix + `/frontend-design` |
| 4.2 | Tweak | Notifications: expanded items too shallow — show full ticket description + comments inline, adaptable per notification source type | `/frontend-design` |
| 4.3 | Bug | "View Full Ticket" from Notifications breaks sidebar navigation — all sidebar items stop working | Code fix (systemic — see 17.2) |
| 4.4 | Bug | Back button under breadcrumbs navigates to Home > AI Copilot instead of previous screen | Code fix (systemic — see 17.3) |
| 4.5 | Bug | Top-level back button (between Toggle Sidebar and Manage Teams) is permanently greyed out / non-functional | Code fix |
| 4.6 | Bug | Only Jira notifications populate — Jenkins, Grafana, GitHub, Confluence, and Briefings notification types don't generate or display | Code fix |

---

## 5. INCIDENTS

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 5.1 | Bug | Changing team/product dropdown doesn't refresh the incidents list | Code fix (systemic — see 17.1) |
| 5.2 | Bug | Incident detail shows plain unformatted text — Jira wiki markup / ADF content not rendered | Code fix + `/frontend-design` (systemic — see 17.4) |
| 5.3 | Bug | "View Full Ticket" has same broken navigation as Notifications | Code fix (systemic — see 17.2) |

---

## 6. MY WORK > TICKETS

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 6.1 | Rework | Almost nothing is clickable — only ticket numbers link, and they go to broken full ticket view | `/frontend-design` |
| 6.2 | Rework | Needs rich inline detail view: formatted description, comments (viewable + addable), status transitions, editable fields | `/frontend-design` + code fix |
| 6.3 | Tweak | Add more filtering options: status, priority, sprint, assignee, etc. | `/frontend-design` |
| 6.4 | Rework | Integrate story point lens: SP completed vs committed, planned vs unplanned breakdown, velocity context — so users see their work through the productivity metric | `/frontend-design` + code fix |

**Vision:** Tickets should be rich and interactive enough that the user basically never has to open Jira.

---

## 7. MY WORK — SUB-TAB CLEANUP

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 7.1 | Rework | Move Jenkins from My Work to Infrastructure > Automation/CI-CD | Code fix |

**Note:** Filters and Boards stay under My Work. Dashboard moves to Home (see 1.2).

---

## 8. INFRASTRUCTURE

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 8.1 | Rework | Reorganize sub-tabs from flat tool list into categories: Cloud Providers (AWS Health, AWS Costs), Source Control (GitHub, Bitbucket), Automation/CI-CD (Jenkins) | Code fix + `/frontend-design` |
| 8.2 | Tweak | AWS Health: account selection should filter by active product context (match AWS Costs behavior) | Code fix |
| 8.3 | Bug | GitHub shows green/connected in Settings but fails to load org repos — health check passes but API calls fail. Display-layer fix only. | Code fix (display layer only) |
| 8.4 | Bug | Bitbucket shows HTTP 401 in browser but Settings reports healthy — display-layer disconnect. Do NOT change auth code. | Code fix (display layer only) |
| 8.5 | Tweak | Bitbucket 401 error message is bare — needs actionable user guidance | `/frontend-design` |

---

## 9. CROSS-CUTTING: INTEGRATION HEALTH

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 9.1 | Tweak | Show red/green health indicator at top of each integration's screen (GitHub page shows GitHub status, etc.) | `/frontend-design` |
| 9.2 | Rework | New Settings > Integrations landing page: high-level health for all integrations, add/edit/remove integrations (affects sidebar) | `/frontend-design` + code fix |
| 9.3 | Rework | Health checks should verify actual API access (e.g., try listing repos), not just "token exists" | Code fix (display layer only — verify without changing auth) |

---

## 10. KNOWLEDGE & TOOLS

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 10.1 | Bug | Knowledge Base shows "No results for ''" — content not loading at all | Code fix |
| 10.2 | Rework | KB default view should render the repo's README as a landing page instead of empty "Select an article" | `/frontend-design` |
| 10.3 | Bug | Confluence spaces don't reflect active product context — shows static/wrong list of spaces | Code fix |
| 10.4 | Bug | Changing team/product dropdown doesn't update Confluence spaces | Code fix (systemic — see 17.1) |
| 10.5 | Tweak | Confluence space abbreviations are cryptic — show full names or add tooltips | `/frontend-design` |

---

## 11. EXEC ASSISTANT

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 11.1 | Bug | Report modal scroll area takes half the modal — bottom half is blank dead space | Code fix |
| 11.2 | Tweak | Report cards not obviously clickable — unclear how to view a generated report | `/frontend-design` |
| 11.3 | Bug | Background automation (standalone `boomi-exec-assistant` repo) stopped working March 16th | Separate investigation (not in-app fix) |

---

## 12. SKILLS — REMOVE FROM SIDEBAR

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 12.1 | Remove | Skills as separate sidebar item — skill invocation integrates into AI Copilot | Code fix |
| 12.2 | Rework | Skill configuration moves to Settings > Skills: auto-discovery, enable/disable, show/hide | `/frontend-design` + code fix |
| 12.3 | Rework | Add skill-to-product/team mapping in Products & Resources section | Code fix |

---

## 13. COMMUNICATE

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 13.1 | Bug | Calendar detail pane has dead space — scrollbar cuts off halfway, content doesn't fill remaining area | Code fix |

---

## 14. SETTINGS

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 14.1 | Rework | Move AI Preferences out of Profile into its own Settings section | Code fix |
| 14.2 | Rework | Move Exec Assistant settings out of Profile into their own section | Code fix |
| 14.3 | Remove/Fix | Appearance > Dashboard section: either sync bidirectionally with Home Dashboard settings or remove as dead code | Code fix |
| 14.4 | Tweak | Boomi theme colors underutilized throughout app — `/frontend-design` pass to apply the 5 brand colors more prominently | `/frontend-design` |
| 14.5 | Tweak | Notification settings need better descriptions explaining what each setting controls and its effect | `/frontend-design` |
| 14.6 | Bug | BPOP auto-populated metrics showing blank — data pipeline not working | Code fix |
| 14.7 | Rework | Credential management: app should exclusively use `~/.boomi-sre/credentials/`; auto-discover = discover + copy to local dir; never read external credential sources at runtime | Code fix |
| 14.8 | Tweak | Move Feedback from Advanced section to About section | Code fix |
| 14.9 | Tweak | About section icon should match the actual app icon, not shield/lightning bolt | `/frontend-design` |

---

## 15. GLOBAL UI

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 15.1 | Rework | Global Search is a navigator, not a search — rename or add real content search capability | Code fix |
| 15.2 | Bug | Global Refresh button doesn't appear to do anything | Code fix |
| 15.3 | Bug | AI Copilot toolbar button navigates to Knowledge Base instead of AI Copilot | Code fix |
| 15.4 | Tweak | Notification badge always shows 99 — show actual count or "99+" cap | Code fix |
| 15.5 | Bug | Collapsed sidebar clips notification count badge — widen collapsed sidebar or reposition badge | `/frontend-design` |
| 15.6 | Tweak | Collapsed sidebar icons confusing — Alerts & On-Call looks like Notifications due to badge. Add tooltips or improve iconography | `/frontend-design` |
| 15.7 | Bug | Team section at sidebar bottom disappears when sidebar is collapsed — should show compact icon | Code fix |

---

## 16. MENU BAR

| # | Type | Issue | Fix Approach |
|---|------|-------|-------------|
| 16.1 | Bug | Show Tab Bar creates duplicate tabs that all show the same screen — fix or remove | Code fix |
| 16.2 | Bug | Help menu Search field doesn't search anything | Code fix |
| 16.3 | Bug | "Boomi SRE Help" not built — disable or remove until content exists | Code fix |
| 16.4 | Bug | "SOPs" navigates to Knowledge Base without activating the SOP filter | Code fix |
| 16.5 | Remove | Factory Reset from Help menu — too dangerous here; keep only in Settings > Advanced | Code fix |

---

## 17. SYSTEMIC (Cross-Cutting Patterns)

These are root-cause fixes that resolve multiple items above:

| # | Type | Issue | Resolves |
|---|------|-------|----------|
| 17.1 | Bug | Product context changes (team/product dropdown) don't trigger screen refreshes | 5.1, 10.4, and any screen that ignores product changes |
| 17.2 | Bug | "View Full Ticket" navigation clobbers sidebar state — sidebar items stop working, only escape is broken back button | 4.3, 5.3, and all ticket detail navigation |
| 17.3 | Bug | Back button navigation logic broken — breadcrumb back goes to wrong destination, top-level back always greyed out | 4.4, 4.5 |
| 17.4 | Bug | Rich text rendering missing — Jira wiki markup / ADF content displays as plain text in all detail views | 5.2, and all inline ticket/incident detail views |

**Recommendation:** Fix systemic issues (17.x) first — they unblock and resolve the most downstream bugs.

---

## Summary

| Category | Count |
|----------|-------|
| Bugs | 27 |
| Tweaks | 15 |
| Removes | 4 |
| Reworks | 8 |
| **Total** | **54** |

## Fix Strategy Per Item Type

- **UI/UX fixes** → `/frontend-design` skill
- **Code bugs / logic fixes** → `/review` and `/simplify` skills
- **Every fix** → must have a passing unit test before moving on

## Sidebar After Fixes

1. **Home** — Dashboard (default), AI Copilot (with skills integrated)
2. **Alerts & On-Call** — On-Call, Grafana, SLOs, Notifications
3. **Incidents** — Active, filters
4. **My Work** — Tickets (with SP lens), Filters, Boards
5. **Infrastructure** — Cloud Providers (AWS Health, AWS Costs), Source Control (GitHub, Bitbucket), Automation/CI-CD (Jenkins)
6. **Knowledge & Tools** — Knowledge Base, Confluence, Exec Assistant
7. **Communicate** — Gmail, Calendar

Skills removed as sidebar item; configuration in Settings. Total: 7 sidebar items (down from 8).

## Out of Scope (Parked for Feature Phase)

- AWS Cost Optimization recommendations + Jira story creation
- Multiple Knowledge Bases per team/product + "Build a KB" feature
- Slack integration in Communicate
- Exec Assistant background automation redesign
- GCP / Azure / Harness integrations
- Gmail web-view approach with Okta SSO
- Harness and New Relic integrations
