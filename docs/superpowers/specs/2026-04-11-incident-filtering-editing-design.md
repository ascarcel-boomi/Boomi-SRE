# Incident Filtering + Inline Editing — Design Spec

**Date:** 2026-04-11
**Status:** Approved
**Scope:** IncidentCommandView, IncidentViewModel, JiraService (existing)

---

## Problem

1. The incident list was implicitly filtered by product elements from bundled resource maps, hiding newer incidents that had different or no product element set. Fixed by removing the implicit filter, but users still need the ability to optionally filter by their configured product elements.
2. Incident detail is read-only — users must open Jira to edit triage fields like Product Element, Priority, Assignee, or transition status.
3. AI analysis output is text-only — field suggestions aren't actionable.

## Requirements

### R1: Product Element Toggle Filter

- A toggle in the incident list top bar: **"All Incidents"** / **"My Products"**.
- **All Incidents** (default): No product element clause in JQL. Shows everything in "Boomi Incident Management."
- **My Products**: Collects incident product elements from the user's configured Products & Resource Mappings (`activeIncidentProductElements`) and adds them to the JQL filter. Also falls back to `selectedProduct.incidentProductElements` then `favoriteProductElements` if resource maps are empty.
- Toggle state persisted to `AppState` config (`showAllIncidents: Bool`, default `true`).
- Switching the toggle triggers a fresh `fetchIncidents` call.
- The existing Active/Recent/All filter continues to work alongside this toggle.

### R2: Editable Triage Fields

Four fields become editable in the incident detail right panel:

**R2.1 Product Element**
- Picker populated from `appState.availableProductElements`.
- Shows current value or "Unset".
- On change, calls `JiraService.updateIssueFields` with `appState.incidentProductElementFieldId`.
- Optimistic local update; revert on error.

**R2.2 Priority**
- Picker with values: Highest, Critical, High, Medium, Low, Lowest.
- Updates Jira `priority` field via `updateIssueFields`.
- Optimistic local update.

**R2.3 Assignee**
- Search text field with type-ahead.
- Queries `JiraService.searchAssignableUsers` (same pattern as TodoDashboardViewModel).
- Click result to assign. Updates Jira `assignee` field.
- Optimistic local update.

**R2.4 Status Transitions**
- Fetch available transitions via `GET /rest/api/3/transitions?issueIdOrKey={key}`.
- Render as action buttons in a `FlowLayout`.
- On tap, `POST /rest/api/3/transitions` with the transition ID.
- Show feedback toast ("Transitioned to Remediated").
- Refresh detail after transition.

All editable fields:
- Wrap async property mutations in `withAnimation(.none)`.
- Show `fieldUpdateFeedback` toast on success/error.
- Clear feedback and edit state on incident selection change.

### R3: AI-Suggested Field Population

- Modify AI analysis prompts (Analyze Incident, Suggest Remediation) to include an instruction: produce a `### Suggested Fields` block at the end with key-value pairs for: Incident Category, Incident Type, Remediation Method (only if determinable).
- After AI output renders, parse for the `### Suggested Fields` heading.
- Below the AI output box, render a **"Suggested Fields"** card showing each parsed suggestion as a row with an "Apply" button.
- Include an "Apply All" button if multiple suggestions are present.
- Clicking "Apply" or "Apply All" writes values to Jira via `updateIssueFields`, shows confirmation toast, and refreshes the extra fields on the detail.
- If the AI can't determine a field, it is simply omitted from the block.
- Parsing uses simple string matching on `key: value` lines under the heading — no complex JSON extraction.

## Architecture

### Files Modified

| File | Changes |
|------|---------|
| `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift` | Toggle state, field update methods, transition fetch/apply, assignee search, AI suggestion parsing |
| `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift` | Top bar toggle, editable metadata section, transition buttons, suggested fields card |
| `BoomiSRE/Sources/Models/AppState.swift` | `showAllIncidents: Bool` property + config persistence |

### No New Files

`JiraService.updateIssueFields` already exists. `FlowLayout` already exists in `ViewStyles.swift`. All patterns (optimistic update, assignee search, transitions) are proven in `TodoDashboardViewModel`/`TodoDashboardView`.

### Data Flow

```
Toggle "My Products" → buildIncidentJQL adds product element filter → fetchIncidents
Toggle "All Incidents" → buildIncidentJQL omits filter → fetchIncidents

Edit Product Element → updateIssueFields(key, {fieldId: value}) → optimistic local update
Edit Priority → updateIssueFields(key, {priority: {name: value}}) → optimistic local update
Search Assignee → searchAssignableUsers(query) → updateIssueFields(key, {assignee: {accountId}})
Tap Transition → POST /transitions → refresh detail

AI Analysis → output includes "### Suggested Fields" → parseSuggestedFields → render card
Apply suggestion → updateIssueFields(key, {fieldId: value}) → refresh extraFields
```

## Mandatory Patterns

- `@Observable` VM, `@State` in views.
- `withAnimation(.none)` on all async property mutations.
- `@ObservationIgnored` on service instances.
- `ZscalerTrustURLSession.shared` for all HTTP.
- `Text(LocalizedStringKey(desc))` for inline content — no MarkdownView (except the existing AI output box which already uses it).
- Design tokens from `ViewStyles.swift`.

## Out of Scope

- Direct editing of B fields (Incident Category, Type, Remediation Method) via manual pickers — these are AI-suggested only.
- Bulk editing of multiple incidents.
- New Jira API endpoints beyond what already exists (search, transitions, updateIssueFields, searchAssignableUsers).
- Changes to the Dashboard's `loadIncidents` method (already works correctly).

## Test Plan

1. **Toggle filter**: Switch between All/My Products — verify JQL changes in logs, incident count changes, newer tickets appear in "All" mode.
2. **Edit Product Element**: Select an incident with "Unset" product element, pick a value, verify it persists in Jira.
3. **Edit Priority**: Change priority on an incident, verify the badge updates and Jira reflects the change.
4. **Assign user**: Search for a user, click to assign, verify assignee updates locally and in Jira.
5. **Transition**: Click a transition button, verify status changes and button list refreshes.
6. **AI suggestions**: Run "Analyze Incident", verify suggested fields card appears, click "Apply", verify field written to Jira.
7. **Error handling**: Disconnect network, attempt an edit, verify error feedback and no data corruption.
