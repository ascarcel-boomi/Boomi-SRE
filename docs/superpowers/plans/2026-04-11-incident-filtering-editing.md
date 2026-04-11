# Incident Filtering + Inline Editing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional product element filtering toggle, editable triage fields (product element, priority, assignee, transitions), and AI-suggested field population to the Incident Command view.

**Architecture:** Three tasks in sequence. Task 1 adds the toggle + VM state + config persistence. Task 2 adds all editable fields and transitions to the right panel. Task 3 modifies AI prompts and adds suggestion parsing + apply logic. Each task is self-contained and commits independently.

**Tech Stack:** Swift 6.3, SwiftUI (@Observable), macOS 15+, Jira REST API v3

**Spec:** `docs/superpowers/specs/2026-04-11-incident-filtering-editing-design.md`

**Hard Rules:**
- ALL async property mutations wrapped in `withAnimation(.none) { }`
- `@ObservationIgnored` on service instances and non-UI state
- `ZscalerTrustURLSession.shared` for all HTTP
- Use `ViewStyles.swift` design tokens
- Do NOT touch auth/credential code

---

## Task 1: Product Element Toggle Filter

**Problem:** Users need to switch between "show all incidents" and "show only incidents matching my configured product elements."

**Files:**
- Modify: `BoomiSRE/Sources/Models/AppState.swift`
- Modify: `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift`

- [ ] **Step 1: Add `showAllIncidents` to AppState**

In `AppState.swift`, add the property alongside the existing incident config (near line 69):

```swift
@Published var showAllIncidents: Bool = true
```

In the `ConfigData` struct (near line 1239), add:

```swift
var showAllIncidents: Bool?
```

In `loadConfig()` (near line 507), add after the `useCustomIncidentJQL` load:

```swift
if let v = config.showAllIncidents { showAllIncidents = v }
```

In `saveConfig()` (near line 595), add to the `ConfigData` initializer:

```swift
showAllIncidents: showAllIncidents,
```

In `factoryReset()` (near line 1068), add:

```swift
showAllIncidents = true
```

- [ ] **Step 2: Rewrite `buildIncidentJQL` to use toggle**

In `IncidentViewModel.swift`, replace `buildIncidentJQL` (lines 116-151) with:

```swift
private func buildIncidentJQL(appState: AppState) -> String {
    if appState.useCustomIncidentJQL, !appState.customIncidentJQL.isEmpty {
        return appState.customIncidentJQL
    }

    var clauses = ["project = \"Boomi Incident Management\""]

    // Only filter by product elements when the user has toggled "My Products"
    if !appState.showAllIncidents {
        let effectiveElements: [String]
        if !appState.activeIncidentProductElements.isEmpty {
            effectiveElements = appState.activeIncidentProductElements
        } else if let p = appState.selectedProduct, !p.incidentProductElements.isEmpty {
            effectiveElements = p.incidentProductElements
        } else if !appState.favoriteProductElements.isEmpty {
            effectiveElements = appState.favoriteProductElements
        } else {
            effectiveElements = []
        }
        if !effectiveElements.isEmpty {
            let elements = effectiveElements
                .map { "\"\($0)\"" }
                .joined(separator: ", ")
            clauses.append("\"product element[select list (multiple choices)]\" IN (\(elements))")
        }
    }

    switch incidentFilter {
    case .active:
        clauses.append("statusCategory NOT IN (Done)")
    case .recent:
        clauses.append("created >= -30d")
    case .all:
        clauses.append("created >= -90d")
    }

    return clauses.joined(separator: " AND ") + " ORDER BY created DESC, priority DESC"
}
```

- [ ] **Step 3: Add toggle to the top bar in IncidentCommandView**

In `IncidentCommandView.swift`, in the `topBar` view (after the filter/search `HStack` at line 117-148), replace the product element pills section (lines 151-167) with:

```swift
HStack(spacing: 12) {
    // All / My Products toggle
    Picker("Scope", selection: Binding(
        get: { appState.showAllIncidents ? "all" : "filtered" },
        set: { val in
            appState.showAllIncidents = (val == "all")
            appState.saveConfig()
            Task { await vm.fetchIncidents(appState: appState) }
        }
    )) {
        Text("All Incidents").tag("all")
        Text("My Products").tag("filtered")
    }
    .pickerStyle(.segmented)
    .frame(width: 220)

    // Show active product element pills when filtering
    if !appState.showAllIncidents {
        let activeElements = appState.activeIncidentProductElements.isEmpty
            ? (appState.selectedProduct?.incidentProductElements ?? appState.favoriteProductElements)
            : appState.activeIncidentProductElements
        if !activeElements.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Image(systemName: "tag").font(.caption).foregroundStyle(.secondary)
                    ForEach(activeElements, id: \.self) { element in
                        Text(element)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(height: 28)
        } else {
            Label("No product elements configured", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    Spacer()
}
```

- [ ] **Step 4: Build and verify**

```bash
swift build -c release
```

- [ ] **Step 5: Commit**

```bash
git add BoomiSRE/Sources/Models/AppState.swift BoomiSRE/Sources/ViewModels/IncidentViewModel.swift BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift
git commit -m "feat: add All Incidents / My Products toggle to incident filter

Persisted toggle in AppState. 'All Incidents' (default) shows everything.
'My Products' filters by configured product element mappings.
Replaces the implicit product element filter.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Editable Triage Fields + Transitions

**Problem:** Users must open Jira to edit Product Element, Priority, Assignee, or transition incident status.

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift`

- [ ] **Step 1: Add field editing state to IncidentViewModel**

Add these properties and methods to `IncidentViewModel.swift` after the existing comment state (near line 30):

```swift
// Field editing state
var isUpdatingField = false
var fieldUpdateFeedback: String? = nil
var detailTransitions: [JiraTransition] = []
var isTransitioning = false
var transitionFeedback: String? = nil
var assigneeSearchResults: [JiraAssignableUser] = []
var isSearchingAssignees = false
```

- [ ] **Step 2: Add field update methods to IncidentViewModel**

Add after the `postComment` method (near line 471):

```swift
// MARK: - Field Editing

func updateProductElement(_ value: String, for key: String, appState: AppState) async {
    guard appState.isJiraConfigured, !appState.incidentProductElementFieldId.isEmpty else { return }
    withAnimation(.none) { isUpdatingField = true; fieldUpdateFeedback = nil }
    do {
        let fieldId = appState.incidentProductElementFieldId
        try await jiraService.updateIssueFields(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken, key: key,
            fields: [fieldId: ["value": value]]
        )
        // Optimistic update — add to affectedServices
        if let idx = incidents.firstIndex(where: { $0.jiraTicketKey == key }) {
            withAnimation(.none) {
                if !incidents[idx].affectedServices.contains(value) {
                    incidents[idx].affectedServices = [value]
                }
            }
        }
        if selectedIncident?.jiraTicketKey == key {
            withAnimation(.none) { selectedIncident?.affectedServices = [value] }
        }
        withAnimation(.none) { fieldUpdateFeedback = "Product Element set to \(value)" }
    } catch {
        withAnimation(.none) { fieldUpdateFeedback = "Failed: \(error.localizedDescription)" }
    }
    withAnimation(.none) { isUpdatingField = false }
}

func updatePriority(_ priorityName: String, for key: String, appState: AppState) async {
    guard appState.isJiraConfigured else { return }
    withAnimation(.none) { isUpdatingField = true; fieldUpdateFeedback = nil }
    do {
        try await jiraService.updateIssueFields(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken, key: key,
            fields: ["priority": ["name": priorityName]]
        )
        // Optimistic update
        let newSeverity: IncidentSeverity = {
            switch priorityName.lowercased() {
            case "highest", "blocker", "p1": return .p1
            case "high", "critical", "p2": return .p2
            case "medium", "p3": return .p3
            default: return .p4
            }
        }()
        if let idx = incidents.firstIndex(where: { $0.jiraTicketKey == key }) {
            withAnimation(.none) { incidents[idx].severity = newSeverity }
        }
        if selectedIncident?.jiraTicketKey == key {
            withAnimation(.none) { selectedIncident?.severity = newSeverity }
        }
        withAnimation(.none) { fieldUpdateFeedback = "Priority set to \(priorityName)" }
    } catch {
        withAnimation(.none) { fieldUpdateFeedback = "Failed: \(error.localizedDescription)" }
    }
    withAnimation(.none) { isUpdatingField = false }
}

func updateAssignee(_ user: JiraAssignableUser, for key: String, appState: AppState) async {
    guard appState.isJiraConfigured else { return }
    withAnimation(.none) { isUpdatingField = true; fieldUpdateFeedback = nil }
    do {
        try await jiraService.updateIssueFields(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken, key: key,
            fields: ["assignee": ["accountId": user.accountId]]
        )
        if let idx = incidents.firstIndex(where: { $0.jiraTicketKey == key }) {
            withAnimation(.none) { incidents[idx].assigneeName = user.displayName }
        }
        if selectedIncident?.jiraTicketKey == key {
            withAnimation(.none) { selectedIncident?.assigneeName = user.displayName }
        }
        withAnimation(.none) { fieldUpdateFeedback = "Assigned to \(user.displayName)" }
    } catch {
        withAnimation(.none) { fieldUpdateFeedback = "Failed: \(error.localizedDescription)" }
    }
    withAnimation(.none) { isUpdatingField = false }
}

func searchAssignableUsers(query: String, appState: AppState) async -> [JiraAssignableUser] {
    guard appState.isJiraConfigured, !query.isEmpty else { return [] }
    return (try? await jiraService.searchUsers(
        baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
        apiToken: appState.jiraAPIToken, query: query
    )) ?? []
}

func loadTransitions(for key: String, appState: AppState) async {
    guard appState.isJiraConfigured else { return }
    do {
        let transitions = try await jiraService.getTransitions(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken, key: key
        )
        withAnimation(.none) { detailTransitions = transitions }
    } catch {
        withAnimation(.none) { detailTransitions = [] }
    }
}

func applyTransition(_ transition: JiraTransition, for key: String, appState: AppState) async {
    withAnimation(.none) { isTransitioning = true; transitionFeedback = nil }
    do {
        try await jiraService.transitionIssue(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken, key: key, transitionId: transition.id
        )
        withAnimation(.none) { transitionFeedback = "Transitioned to \(transition.name)" }
        // Refresh transitions and detail
        await loadTransitions(for: key, appState: appState)
        if let incident = selectedIncident {
            await loadComments(for: incident, appState: appState)
        }
    } catch {
        withAnimation(.none) { transitionFeedback = "Failed: \(error.localizedDescription)" }
    }
    withAnimation(.none) { isTransitioning = false }
}
```

- [ ] **Step 3: Clear edit state on incident selection**

In the existing `selectedIncident` property, there's no `didSet`. Since we can't use `didSet` on `@Observable`, add a `selectIncident` method:

```swift
func selectIncident(_ incident: Incident, appState: AppState) {
    selectedIncident = incident
    selectedIncidentComments = []
    detailTransitions = []
    fieldUpdateFeedback = nil
    transitionFeedback = nil
    assigneeSearchResults = []
    isSearchingAssignees = false
    aiOutput = nil
    aiOutputLabel = ""
    aiError = nil
    Task {
        async let comments: () = loadComments(for: incident, appState: appState)
        async let transitions: () = loadTransitions(for: incident.jiraTicketKey ?? "", appState: appState)
        _ = await (comments, transitions)
    }
}
```

Update `IncidentCommandView.swift` line 301-305 to use this method:

```swift
.onTapGesture {
    vm.selectIncident(incident, appState: appState)
}
```

- [ ] **Step 4: Replace read-only metadataSection with editable version**

In `IncidentCommandView.swift`, replace the `metadataSection` function (lines 621-641) with an editable version. Add `@State` vars near the top of the struct (after line 11):

```swift
@State private var assigneeSearchText: String = ""
@State private var isEditingAssignee = false
```

Replace `metadataSection`:

```swift
private func metadataSection(_ incident: Incident) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            Text("Incident Details").font(.subheadline.bold())
            Spacer()
            if vm.isUpdatingField { ProgressView().scaleEffect(0.6) }
        }

        if let feedback = vm.fieldUpdateFeedback {
            Text(feedback)
                .font(.caption)
                .foregroundStyle(feedback.hasPrefix("Failed") ? .red : .green)
        }

        metaRow("Jira Key", incident.jiraTicketKey ?? "—")
        metaRow("Duration", incident.elapsedString)
        metaRow("Created", incident.createdAt.formatted(date: .abbreviated, time: .shortened))
        if !incident.reporterName.isEmpty {
            metaRow("Reporter", incident.reporterName)
        }

        Divider()

        // Editable: Product Element
        editableProductElementRow(incident)

        // Editable: Priority
        editablePriorityRow(incident)

        // Editable: Assignee
        editableAssigneeRow(incident)

        // Transitions
        if !vm.detailTransitions.isEmpty {
            Divider()
            transitionsSection(incident)
        }
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 12).fill(.background))
    .onChange(of: vm.selectedIncident?.jiraTicketKey) { _, _ in
        assigneeSearchText = ""
        isEditingAssignee = false
    }
}
```

- [ ] **Step 5: Add editable field sub-views**

Add these below the `metadataSection` function:

```swift
@ViewBuilder
private func editableProductElementRow(_ incident: Incident) -> some View {
    let current = incident.affectedServices.first ?? "Unset"
    HStack(alignment: .top) {
        Text("Product Element").font(.caption).foregroundStyle(.secondary)
            .frame(width: 110, alignment: .trailing)
        if appState.availableProductElements.isEmpty {
            Text(current).font(.caption)
            Text("(Discover in Settings)").font(.caption2).foregroundStyle(.tertiary)
        } else {
            Picker("", selection: Binding(
                get: { current },
                set: { newValue in
                    guard let key = incident.jiraTicketKey, newValue != current else { return }
                    Task { await vm.updateProductElement(newValue, for: key, appState: appState) }
                }
            )) {
                Text("Unset").tag("Unset")
                ForEach(appState.availableProductElements, id: \.self) { element in
                    Text(element).tag(element)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@ViewBuilder
private func editablePriorityRow(_ incident: Incident) -> some View {
    let priorities = ["Highest", "Critical", "High", "Medium", "Low", "Lowest"]
    let currentPriority: String = {
        switch incident.severity {
        case .p1: return "Highest"
        case .p2: return "High"
        case .p3: return "Medium"
        case .p4: return "Low"
        }
    }()
    HStack(alignment: .top) {
        Text("Priority").font(.caption).foregroundStyle(.secondary)
            .frame(width: 110, alignment: .trailing)
        Picker("", selection: Binding(
            get: { currentPriority },
            set: { newValue in
                guard let key = incident.jiraTicketKey, newValue != currentPriority else { return }
                Task { await vm.updatePriority(newValue, for: key, appState: appState) }
            }
        )) {
            ForEach(priorities, id: \.self) { p in Text(p).tag(p) }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@ViewBuilder
private func editableAssigneeRow(_ incident: Incident) -> some View {
    HStack(alignment: .top) {
        Text("Assignee").font(.caption).foregroundStyle(.secondary)
            .frame(width: 110, alignment: .trailing)
        VStack(alignment: .leading, spacing: 4) {
            if isEditingAssignee {
                TextField("Search user…", text: $assigneeSearchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        Task {
                            let results = await vm.searchAssignableUsers(
                                query: assigneeSearchText, appState: appState
                            )
                            withAnimation(.none) { vm.assigneeSearchResults = results }
                        }
                    }
                if !vm.assigneeSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(vm.assigneeSearchResults.prefix(5)) { user in
                            Button {
                                guard let key = incident.jiraTicketKey else { return }
                                Task { await vm.updateAssignee(user, for: key, appState: appState) }
                                isEditingAssignee = false
                                assigneeSearchText = ""
                                withAnimation(.none) { vm.assigneeSearchResults = [] }
                            } label: {
                                Text(user.displayName).font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2).padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                }
            } else {
                HStack {
                    Text(incident.assigneeName.isEmpty ? "Unassigned" : incident.assigneeName)
                        .font(.caption)
                    Button { isEditingAssignee = true } label: {
                        Image(systemName: "pencil").font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@ViewBuilder
private func transitionsSection(_ incident: Incident) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Transitions").font(.caption.bold()).foregroundStyle(.secondary)
        if vm.isTransitioning {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.6)
                Text("Transitioning…").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let feedback = vm.transitionFeedback {
            Text(feedback)
                .font(.caption)
                .foregroundStyle(feedback.hasPrefix("Failed") ? .red : .green)
        }
        FlowLayout(spacing: 6) {
            ForEach(vm.detailTransitions) { transition in
                Button {
                    guard let key = incident.jiraTicketKey else { return }
                    Task { await vm.applyTransition(transition, for: key, appState: appState) }
                } label: {
                    Text(transition.name).font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(vm.isTransitioning)
            }
        }
    }
}
```

- [ ] **Step 6: Build and verify**

```bash
swift build -c release
```

- [ ] **Step 7: Commit**

```bash
git add BoomiSRE/Sources/ViewModels/IncidentViewModel.swift BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift
git commit -m "feat: editable triage fields + transitions on incident detail

Product Element picker, Priority picker, Assignee search + assign,
and Jira workflow transition buttons in the incident right panel.
All updates are optimistic with error feedback.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: AI-Suggested Field Population

**Problem:** AI analysis output is text-only. Field suggestions aren't actionable.

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/IncidentViewModel.swift`
- Modify: `BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift`

- [ ] **Step 1: Add AI suggestion model and state**

In `IncidentViewModel.swift`, add near the other state properties (after `aiOutputLabel`):

```swift
struct SuggestedField: Identifiable {
    let id = UUID()
    let fieldName: String    // e.g. "Incident Category"
    let fieldValue: String   // e.g. "Infrastructure"
    var applied: Bool = false
}

var suggestedFields: [SuggestedField] = []
```

- [ ] **Step 2: Add prompt suffix to `analyzeIncident` and `suggestRemediation`**

Create a shared suffix constant:

```swift
private static let suggestedFieldsSuffix = """

If you can determine any of the following fields from the incident data, include them at the very end of your response under a heading `### Suggested Fields` with one `key: value` per line. Only include fields you are confident about. Omit any you cannot determine.

- Incident Category (e.g., Infrastructure, Application, Network, Security, Third-Party)
- Incident Type (e.g., Service Degradation, Full Outage, Data Issue, Latency, Configuration Error)
- Remediation Method (e.g., Restart, Rollback, Configuration Change, Scaling, Vendor Escalation)
"""
```

In `analyzeIncident()` (line 498), append the suffix to the user message before the closing `"""`:

```swift
\(Self.suggestedFieldsSuffix)
""")],
```

In `suggestRemediation()` (line 619), do the same:

```swift
\(Self.suggestedFieldsSuffix)
""")],
```

- [ ] **Step 3: Add parsing and apply methods**

```swift
// MARK: - AI Suggestion Parsing

func parseSuggestedFields(from output: String) {
    var fields: [SuggestedField] = []
    guard let range = output.range(of: "### Suggested Fields") else {
        withAnimation(.none) { suggestedFields = [] }
        return
    }
    let block = String(output[range.upperBound...])
    for line in block.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        guard trimmed.contains(":") else { continue }
        let parts = trimmed.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !value.isEmpty else { continue }
        // Stop parsing if we hit another markdown heading
        if name.hasPrefix("#") { break }
        fields.append(SuggestedField(fieldName: name, fieldValue: value))
    }
    withAnimation(.none) { suggestedFields = fields }
}

func applySuggestedField(_ field: SuggestedField, appState: AppState) async {
    guard let key = selectedIncident?.jiraTicketKey, appState.isJiraConfigured else { return }
    // Map field names to Jira custom field IDs via the cached fieldNameMap
    if fieldNameMap.isEmpty {
        if let fields = try? await jiraService.getCustomFields(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken
        ) {
            fieldNameMap = Dictionary(fields.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        }
    }
    // Find matching field ID by display name
    let targetName = field.fieldName.lowercased()
    guard let matchId = fieldNameMap.first(where: { $0.value.lowercased().contains(targetName) })?.key else {
        withAnimation(.none) { fieldUpdateFeedback = "Could not find Jira field for '\(field.fieldName)'" }
        return
    }
    withAnimation(.none) { isUpdatingField = true; fieldUpdateFeedback = nil }
    do {
        try await jiraService.updateIssueFields(
            baseURL: appState.jiraBaseURL, email: appState.jiraEmail,
            apiToken: appState.jiraAPIToken, key: key,
            fields: [matchId: ["value": field.fieldValue]]
        )
        if let idx = suggestedFields.firstIndex(where: { $0.id == field.id }) {
            withAnimation(.none) { suggestedFields[idx].applied = true }
        }
        withAnimation(.none) { fieldUpdateFeedback = "\(field.fieldName) set to \(field.fieldValue)" }
    } catch {
        withAnimation(.none) { fieldUpdateFeedback = "Failed: \(error.localizedDescription)" }
    }
    withAnimation(.none) { isUpdatingField = false }
}

func applyAllSuggestedFields(appState: AppState) async {
    for field in suggestedFields where !field.applied {
        await applySuggestedField(field, appState: appState)
    }
}
```

- [ ] **Step 4: Call parsing after AI output**

In `analyzeIncident()`, after `withAnimation(.none) { self.aiOutput = result }` (line 503), add:

```swift
parseSuggestedFields(from: result)
```

In `suggestRemediation()`, after the equivalent line (near line 624), add:

```swift
parseSuggestedFields(from: remResult)
```

Also clear suggestions at the start of each AI action — add to the `isAnalyzing = true; aiError = nil; aiOutput = nil` lines:

```swift
suggestedFields = []
```

- [ ] **Step 5: Add Suggested Fields card to the view**

In `IncidentCommandView.swift`, in the `aiActionsSection` function, after the AI output box closing brace (after the `.overlay(...)` line, near line 614), add:

```swift
if !vm.suggestedFields.isEmpty {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Label("Suggested Fields", systemImage: "wand.and.stars")
                .font(.caption.bold()).foregroundStyle(.purple)
            Spacer()
            if vm.suggestedFields.contains(where: { !$0.applied }) {
                Button {
                    Task { await vm.applyAllSuggestedFields(appState: appState) }
                } label: {
                    Label("Apply All", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
            }
        }
        ForEach(vm.suggestedFields) { field in
            HStack {
                Text(field.fieldName).font(.caption).foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .trailing)
                Text(field.fieldValue).font(.caption.bold())
                Spacer()
                if field.applied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                } else {
                    Button {
                        Task { await vm.applySuggestedField(field, appState: appState) }
                    } label: {
                        Text("Apply").font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.04)))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple.opacity(0.15)))
}
```

- [ ] **Step 6: Build and verify**

```bash
swift build -c release
```

- [ ] **Step 7: Commit**

```bash
git add BoomiSRE/Sources/ViewModels/IncidentViewModel.swift BoomiSRE/Sources/Views/Panels/IncidentCommandView.swift
git commit -m "feat: AI-suggested field population for incidents

Analyze Incident and Suggest Remediation now produce a Suggested Fields
block. Parsed into actionable cards with per-field and Apply All buttons.
Writes to Jira via updateIssueFields with field name resolution.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Final Step

After all tasks:

- [ ] **Full build and install**

```bash
swift build -c release && bash build_app.sh
```

- [ ] **Manual smoke test**

1. Toggle All Incidents / My Products — verify count changes
2. Select an incident, edit Product Element — verify Jira updates
3. Change Priority — verify badge updates
4. Assign a user — verify assignee updates
5. Click a transition button — verify status changes
6. Run Analyze Incident — verify Suggested Fields card appears
7. Click Apply on a suggestion — verify field written to Jira

- [ ] **Push**

```bash
git push origin main
```
