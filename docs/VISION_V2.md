# Boomi SRE v2 — Vision Document

## The Problem

Adam leads SRE across 5+ Boomi product lines with a team that's too small, growing responsibilities, and a mandate to achieve 50x productivity through AI adoption. The current app has grown organically into a feature-rich but complex tool. It needs to evolve from "a dashboard with many sections" into "an intelligent assistant that knows what you need before you ask."

---

## Three Problems to Solve

### 1. Horizontal Scalability — One SRE, Any Product

**Today:** Each SRE knows their product deeply but struggles when covering another product's on-call. They don't know the alerts, the runbooks, or the architecture. Context-switching between products is painful.

**V2:** The app becomes **product-aware**. An SRE selects their current product context and the entire experience adapts. The AI knows every product's architecture, alerts, and procedures. A CAM SRE covering MFT on-call can ask "what does this alert mean?" and get the right answer instantly.

### 2. AI Adoption — Invisible, Not Optional

**Today:** AI features exist but require the user to click "Analyze with AI" or open the Copilot. Junior engineers skip it. Senior engineers ignore it.

**V2:** AI is **woven into every interaction**, not a separate feature. When an alert appears, the AI has already analyzed it. When a PR is opened, the review is already started. The SRE doesn't "use AI" — they use the app, and the app uses AI on their behalf.

### 3. 50x Productivity — Measured and Visible

**Today:** No way to measure how much time the tool saves. No way to prove productivity gains. Some team members haven't adopted the tool at all.

**V2:** Every action the SRE takes (or doesn't take because the AI did it for them) is tracked. Time savings are estimated and displayed. Weekly reports show individual and team productivity trends. The data proves the ROI.

---

## The New Architecture

### Concept: The Intelligent Feed

Replace the widget grid with a **single intelligent feed** — like a curated news feed for your infrastructure. Every item in the feed is:

1. **Contextual** — filtered by the selected product
2. **Actionable** — the action buttons (ACK, Close, Merge, Approve) are right there inline
3. **AI-enriched** — the AI has already analyzed it and added context
4. **Prioritized** — most urgent at the top, auto-sorted in real-time
5. **Dismissible** — once handled, it fades away

```
┌─────────────────────────────────────────────────────────────┐
│  Boomi SRE                    [CAM SRE ▾]  [🔍]  [⚙️]      │
│                                                              │
│  Good afternoon, Adam         SRE Health: 72%  ⚠️            │
│  3 items need attention       You've saved 2.3 hours today   │
│                                                              │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ 🔴 P1 ALERT  New Relic: High Memory Usage     2 min ago │ │
│ │ Team: MCS SRE · Source: NewRelicV2                       │ │
│ │                                                          │ │
│ │ AI: Memory spike on Cloud-ataretail-ZVSD2P. This alert   │ │
│ │ has fired 3 times in the past 24h. Check the container   │ │
│ │ restart count and consider scaling the pod.               │ │
│ │                                                          │ │
│ │ 📖 Relevant: MCS Memory Troubleshooting Runbook          │ │
│ │                                                          │ │
│ │ [ACK]  [Close]  [Snooze 1h]  [View in JSM]              │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ 🟡 PR REVIEW NEEDED  #CAMSRE-23769        15 min ago     │ │
│ │ Convert Grafana dashboards to New Relic Terraform         │ │
│ │ by @jbeck-tibco · Mashery-Boomi/apim-sre-terraform-iac   │ │
│ │                                                          │ │
│ │ AI: This PR migrates 4 Grafana dashboards to New Relic   │ │
│ │ using the NR Terraform provider. Key risk: dashboard      │ │
│ │ IDs may differ between environments.                      │ │
│ │                                                          │ │
│ │ [Approve]  [Request Changes]  [View PR]                  │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ 🟢 ON-CALL  You're on primary for CAM SRE    Now        │ │
│ │ Secondary: Henry Wang · IC: James Beck                   │ │
│ │ Next rotation change: Tomorrow 9:00 AM ET                │ │
│ │                                                          │ │
│ │ [View Schedule]  [Swap Shift]                            │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ 📋 JIRA  5 tickets assigned · 1 overdue       Updated   │ │
│ │ ⚠️ CAMSRE-24001 "CVE remediation for ALB" — due today   │ │
│ │ • CAMSRE-23998 "Update AMIs for Q2"                      │ │
│ │ • CAMSRE-23995 "Terraform state migration"               │ │
│ │                                                          │ │
│ │ [Open My TODO]                                           │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ─── All clear below this line ─────────────────────────────  │
│                                                              │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ 🤖 AI DAILY BRIEF                          Generated 2h │ │
│ │ 2 P1 incidents are the immediate priority. 10 open       │ │
│ │ tickets, 8 PRs awaiting review...                        │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ ✅ Jenkins: All 5 monitored builds passing                │ │
│ │ ✅ Grafana: No alerts firing                              │ │
│ │ ✅ Services: All 7 connected                              │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ 🥷 "When we do our job well, no one knows we exist."        │
│    — Boomi SRE Spirit                                       │
└─────────────────────────────────────────────────────────────┘
```

### The Product Context Switcher

A dropdown at the top of the app: `[All Products ▾]`

Options:
- **All Products** — see everything across all product lines
- **CAM SRE** (Mashery) — only CAM alerts, CAM on-call, CAM tickets, CAM repos, CAM runbooks
- **MFT SRE** (Thru) — only MFT alerts, schedules, repos, runbooks
- **DI SRE** (Rivery) — only DI alerts, schedules, repos, runbooks
- **MCS SRE** — only MCS alerts, schedules, repos, runbooks
- **Boomi SRE** (Platform/Runtime) — only Platform alerts, schedules, repos, runbooks
- **Dedicated Clouds** — (future)

**How filtering works:**
- JSM Ops Alerts → filter by `responders` team ID (each product line has a JSM team)
- On-Call → filter by team's schedules
- Jira Tickets → filter by project key (CAMSRE, SRE, etc.)
- GitHub/Bitbucket → filter by repo org or naming convention
- Jenkins → filter by job name pattern
- Grafana → filter by dashboard tags or folder
- Knowledge Base → filter by product tag on SOPs/runbooks

The product context is stored in AppState and persists. When an SRE switches products (e.g., starting an MFT on-call shift), one click transforms the entire app.

### The Sidebar — Simplified

Instead of 8 expandable sections with 15+ items, the sidebar becomes:

```
🏠 Home (the intelligent feed)
───────────────────
🔔 Alerts (JSM + Grafana consolidated)
🚨 Incidents
📞 On-Call
📋 My Work (tickets, PRs, builds)
📚 Knowledge (SOPs, runbooks, docs)
💬 Communicate (Gmail, Calendar, Chat)
⚙️ Settings
```

**7 items.** That's it. Each one opens a focused view. The Home feed surfaces the most important items from ALL of these, so most SREs only ever look at Home.

### AI Copilot — Always Present

Instead of a separate "Copilot Chat" section, the AI is a **persistent bottom bar** on every screen:

```
┌─────────────────────────────────────────────────────────────┐
│ 🤖 Ask anything... (or ⌘/ for quick actions)               │
└─────────────────────────────────────────────────────────────┘
```

The SRE can type a question from anywhere:
- "What's causing the MCS memory alerts?"
- "Draft a PCR for CAMSRE-24001"
- "Who's on call for MFT tonight?"
- "Show me the MFT runbook for database failover"

The AI has full context: it knows which product the SRE is viewing, what alerts are active, what tickets are assigned, and what the recent incident history looks like.

### Productivity Tracker

A built-in analytics system that tracks:

**Per-SRE metrics (visible to the individual):**
- Time saved today / this week / this month (estimated from actions taken)
- Alerts acknowledged via app vs. via JSM web UI
- AI features used (analyses, PCR generation, copilot queries)
- Context switches avoided (how many tools they DIDN'T have to open)
- Response time trends (how quickly they act on alerts)

**Team metrics (visible to leads/managers):**
- Adoption rate — who's using the app and how often
- Feature usage heatmap — which features are most used
- MTTR trends — are incidents resolving faster since adoption
- Cross-product coverage — are SREs successfully covering other product on-call shifts
- Knowledge base usage — are SREs finding answers in the app

**Display:**
- A small "You've saved X hours today" badge in the header (motivating, not surveillance)
- A "Team Pulse" view in Settings or a dedicated section showing adoption trends
- Weekly email digest (optional) summarizing the SRE's productivity gains

**How time savings are estimated:**
- Alert ACK via app = 2 min saved (vs. logging into JSM, finding alert, clicking through)
- PR reviewed with AI summary = 10 min saved
- PCR generated with AI = 30 min saved
- Runbook lookup via KB = 5 min saved (vs. searching Confluence, asking a colleague)
- Incident analysis via AI = 15 min saved
- Each Copilot query = 3 min saved (vs. researching the answer manually)

These are rough estimates, configurable by the admin. The point isn't precision — it's showing the trend.

---

## Implementation Roadmap

### Phase A: Product Context System
1. Define product configurations (team IDs, project keys, repo patterns, Jenkins job patterns, Grafana tags)
2. Add product context switcher to the app header
3. Filter all data sources by the selected product
4. Persist product context per user

### Phase B: Intelligent Feed (Home Page v2)
1. Replace the widget grid with a single feed
2. Each feed item is a `FeedItem` with: source, priority, timestamp, AI analysis, actions
3. Feed items come from: JSM alerts, Grafana alerts, Jira tickets, GitHub PRs, Jenkins failures, On-Call changes, Notifications
4. Feed is sorted by urgency (same scoring system, applied to individual items not widgets)
5. Items are dismissible — once actioned, they fade/shrink
6. "All clear" divider separates urgent from informational items

### Phase C: Simplified Sidebar
1. Collapse 8 sections into 7 focused items
2. Home is the default and primary view
3. Each section is a deep-dive — only needed when the feed item says "View all"

### Phase D: Persistent AI Bar
1. Move Copilot from a sidebar section to a persistent bottom bar
2. Available on every screen
3. Context-aware — knows current product, current screen, current data
4. Quick actions via ⌘/ (like Spotlight)

### Phase E: Productivity Tracker
1. Log every user action with timestamp and estimated time saved
2. Build the individual dashboard ("You saved X hours")
3. Build the team dashboard (adoption, coverage, MTTR)
4. Optional weekly digest

### Phase F: Product Knowledge Integration
1. For each product, associate: architecture docs, common alerts, runbooks, escalation contacts
2. When an SRE switches to a product they're unfamiliar with, the AI proactively offers context
3. "You're now on MFT on-call. Here's what you need to know: [3 key runbooks] [current alert patterns] [escalation contacts]"

---

## What This Means for the Current App

The current app doesn't get thrown away — it evolves:

- **Keep:** All the service integrations (JSM, Grafana, Jira, GitHub, Bitbucket, Jenkins, Confluence, AWS, Google). These are the data sources. They work.
- **Keep:** The AI analysis capabilities (PR review, incident analysis, PCR generation, copilot). This is the intelligence layer.
- **Keep:** The Knowledge Base, On-Call, Alerts, and Incidents features. These are the core SRE workflows.
- **Restructure:** The home page becomes a feed. The sidebar shrinks. The product context filters everything.
- **Add:** Productivity tracking. Product-aware AI. Persistent copilot bar.

The transformation is about **how information is presented**, not about building new integrations. The data is already there — we just need to surface it smarter.

---

## Success Criteria

**For the SRE:**
- "I open the app and immediately know what needs my attention"
- "I can cover any product's on-call shift without feeling lost"
- "I don't need to open any other tool for 90% of my work"

**For the team lead (Adam):**
- "I can see who's using the tool and how much time it's saving"
- "New team members are productive within days, not weeks"
- "We're covering more products with the same team size"

**For the business:**
- "SRE productivity has measurably increased"
- "AI adoption in SRE is at 100%"
- "Incident response times have decreased"

---

## Next Steps

This document is the north star. Implementation should be incremental:
1. Start with Phase A (Product Context) — it's the foundation
2. Then Phase B (Intelligent Feed) — it's the most visible change
3. Then Phase E (Productivity Tracker) — it proves the ROI
4. Phases C, D, F can happen in parallel as polish

Each phase should be a standalone improvement that makes the app better immediately, not a "big bang" rewrite.
