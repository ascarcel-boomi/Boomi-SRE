# Locked Team Template Mappings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate product resource maps into locked team defaults (bundled, Director-editable) and user additions (personal, additive-only), so curated mappings survive and SREs can only add on top.

**Architecture:** Replace the single `productResourceMaps` array with a two-tier system: `teamResourceMaps` (loaded from bundled JSON, read-only except for Directors) and `userResourceAdditions` (per-user local additions). A computed `productResourceMaps` merges both at runtime. The UI splits into "Team Defaults (locked)" and "My Additions" sections, with Director-only edit controls gated by `UserProfile.role`.

**Tech Stack:** SwiftUI, Swift 5.9, SPM, macOS 15

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `BoomiSRE/Sources/Models/AppState.swift` | Modify | Replace `productResourceMaps` with `teamResourceMaps` + `userResourceAdditions` + computed merged property |
| `BoomiSRE/Sources/Models/ProductResourceMap.swift` | Modify | Add `isTeamDefault` flag to `MappedResource` |
| `BoomiSRE/Sources/Models/UserProfile.swift` | Modify | Add `isDirector` computed property to `SRERole` |
| `BoomiSRE/Sources/Views/Settings/ProductSettingsContent.swift` | Modify | Split resource display into Team Defaults / My Additions sections, add Director edit controls |
| `BoomiSRE/Sources/ViewModels/ProductMappingViewModel.swift` | Modify | Route add/remove through user additions layer, add Director edit methods |

---

### Task 1: Backend — Add `isTeamDefault` flag and Director role check

**Files:**
- Modify: `BoomiSRE/Sources/Models/ProductResourceMap.swift:84-110` (MappedResource struct)
- Modify: `BoomiSRE/Sources/Models/UserProfile.swift:101-111` (SRERole enum)

- [ ] **Step 1: Add `isTeamDefault` to MappedResource**

In `BoomiSRE/Sources/Models/ProductResourceMap.swift`, add a new property to the `MappedResource` struct after line 100 (`var addedAt: Date`):

```swift
/// True if this resource came from the bundled team template (Director-managed).
/// Team default resources cannot be removed by non-Director users.
var isTeamDefault: Bool = false
```

Also update the `hash(into:)` and `==` implementations — no change needed since they only use `id` and `type`.

- [ ] **Step 2: Add `isDirector` to SRERole**

In `BoomiSRE/Sources/Models/UserProfile.swift`, add a computed property after line 110 (`case other = "Other"`), inside the `SRERole` enum:

```swift
/// True for roles that can edit the team template.
var canEditTeamTemplate: Bool {
    self == .director || self == .manager
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds — new properties have defaults so all existing code compiles.

- [ ] **Step 4: Commit**

```bash
git add BoomiSRE/Sources/Models/ProductResourceMap.swift BoomiSRE/Sources/Models/UserProfile.swift
git commit -m "feat: add isTeamDefault flag to MappedResource and canEditTeamTemplate to SRERole"
```

---

### Task 2: Backend — Split AppState into team maps + user additions

**Files:**
- Modify: `BoomiSRE/Sources/Models/AppState.swift`

This is the core data model change. `productResourceMaps` becomes a computed property merging `teamResourceMaps` and `userResourceAdditions`.

- [ ] **Step 1: Add new stored properties**

In `BoomiSRE/Sources/Models/AppState.swift`, replace line 91:

```swift
@Published var productResourceMaps: [ProductResourceMap] = []
```

with:

```swift
/// Team default resource maps — loaded from bundled JSON, read-only except for Directors.
@Published var teamResourceMaps: [ProductResourceMap] = []

/// User's personal additions on top of team defaults — persisted to local config.
@Published var userResourceAdditions: [ProductResourceMap] = []
```

- [ ] **Step 2: Add computed merged property**

Add this computed property immediately after the two new properties (replacing the old `productResourceMaps`):

```swift
/// Merged view: team defaults + user additions. All existing code reads this.
var productResourceMaps: [ProductResourceMap] {
    get {
        var merged: [String: ProductResourceMap] = [:]
        for map in teamResourceMaps {
            var copy = map
            // Mark all team resources as team defaults
            for i in copy.resources.indices {
                copy.resources[i].isTeamDefault = true
            }
            merged[map.id] = copy
        }
        for userMap in userResourceAdditions {
            if var existing = merged[userMap.id] {
                // Append user additions (skip duplicates by id+type)
                let existingKeys = Set(existing.resources.map { "\($0.id)|\($0.type.rawValue)" })
                for resource in userMap.resources {
                    let key = "\(resource.id)|\(resource.type.rawValue)"
                    if !existingKeys.contains(key) {
                        var userResource = resource
                        userResource.isTeamDefault = false
                        existing.resources.append(userResource)
                    }
                }
                merged[userMap.id] = existing
            } else {
                merged[userMap.id] = userMap
            }
        }
        return Array(merged.values).sorted { $0.id < $1.id }
    }
    set {
        // Backward compat: if something sets productResourceMaps directly,
        // route to teamResourceMaps (only happens during migration/factory reset)
        teamResourceMaps = newValue
    }
}
```

- [ ] **Step 3: Update `updateResourceMap` to route correctly**

Find the `updateResourceMap` method (around line 200) and update it to route team vs user changes:

```swift
func updateResourceMap(_ map: ProductResourceMap) {
    // Separate team defaults from user additions
    let teamResources = map.resources.filter { $0.isTeamDefault }
    let userResources = map.resources.filter { !$0.isTeamDefault }

    // Update team maps
    var teamMap = ProductResourceMap(id: map.id, resources: teamResources, lastDiscoveredAt: map.lastDiscoveredAt)
    if let idx = teamResourceMaps.firstIndex(where: { $0.id == map.id }) {
        teamMap.resources = teamResourceMaps[idx].resources // Preserve team resources as-is
        teamResourceMaps[idx] = teamMap
    }

    // Update user additions
    let userMap = ProductResourceMap(id: map.id, resources: userResources, lastDiscoveredAt: nil)
    if let idx = userResourceAdditions.firstIndex(where: { $0.id == map.id }) {
        userResourceAdditions[idx] = userMap
    } else if !userResources.isEmpty {
        userResourceAdditions.append(userMap)
    }

    saveConfig()
}
```

- [ ] **Step 4: Update `ensureResourceMapsExist` to load team maps**

Update the method (around line 211):

```swift
func ensureResourceMapsExist() {
    // Load team defaults from bundled template if not yet loaded
    if teamResourceMaps.isEmpty, let defaults = Self.loadBundledDefaultMaps() {
        teamResourceMaps = defaults
    }
    // Ensure every product has a team map entry
    for product in products where product.id != "all" {
        if !teamResourceMaps.contains(where: { $0.id == product.id }) {
            teamResourceMaps.append(.migrated(from: product))
        }
    }
}
```

- [ ] **Step 5: Update `factoryReset` to clear user additions and reload team maps**

Update the factory reset section (around line 948):

```swift
products = ProductContext.defaults
// Reload team defaults from bundled template
if let bundled = Self.loadBundledDefaultMaps() {
    teamResourceMaps = bundled
} else {
    teamResourceMaps = ProductContext.defaults
        .filter { $0.id != "all" }
        .map { .migrated(from: $0) }
}
// Clear user additions
userResourceAdditions = []
```

- [ ] **Step 6: Update `saveAsDefaultTemplate` to only save team maps**

Update the method (around line 239). Change:
```swift
for var map in productResourceMaps {
```
to:
```swift
for var map in teamResourceMaps {
```

- [ ] **Step 7: Update config persistence — save and load**

In the `saveConfig()` method, find where `productResourceMaps` is saved (around line 503) and update the `AppConfig` construction to save both:

Replace:
```swift
productResourceMaps: productResourceMaps.isEmpty ? nil : productResourceMaps,
```
with:
```swift
productResourceMaps: teamResourceMaps.isEmpty ? nil : teamResourceMaps,
userResourceAdditions: userResourceAdditions.isEmpty ? nil : userResourceAdditions,
```

In the `loadConfig()` method (around line 433), find where `productResourceMaps` is loaded and update:

Replace:
```swift
if let v = config.productResourceMaps { productResourceMaps = v }
```
with:
```swift
if let v = config.productResourceMaps { teamResourceMaps = v }
if let v = config.userResourceAdditions { userResourceAdditions = v }
```

- [ ] **Step 8: Add `userResourceAdditions` to AppConfig struct**

In the `AppConfig` struct (around line 1115), after `var productResourceMaps: [ProductResourceMap]?`, add:

```swift
var userResourceAdditions: [ProductResourceMap]?
```

- [ ] **Step 9: Build and verify**

Run: `swift build`
Expected: Build succeeds. The computed `productResourceMaps` property provides backward compatibility — all existing code that reads it gets the merged view.

- [ ] **Step 10: Commit**

```bash
git add BoomiSRE/Sources/Models/AppState.swift
git commit -m "feat: split resource maps into team defaults and user additions with merged computed property"
```

---

### Task 3: Backend — Update ProductMappingViewModel for two-tier routing

**Files:**
- Modify: `BoomiSRE/Sources/ViewModels/ProductMappingViewModel.swift`

- [ ] **Step 1: Read the current ProductMappingViewModel**

Read `BoomiSRE/Sources/ViewModels/ProductMappingViewModel.swift` to understand the current `addResource`, `removeResource`, `confirmAll`, and `dismissPending` methods.

- [ ] **Step 2: Add user-addition-aware add method**

Add a new method that routes additions to `userResourceAdditions`:

```swift
/// Add a resource as a user addition (not a team default).
func addUserResource(_ resource: MappedResource, to productId: String, appState: AppState) {
    var userResource = resource
    userResource.isTeamDefault = false
    userResource.isConfirmed = true
    userResource.addedAt = Date()

    if let idx = appState.userResourceAdditions.firstIndex(where: { $0.id == productId }) {
        appState.userResourceAdditions[idx].upsert(userResource)
    } else {
        var newMap = ProductResourceMap.empty(for: productId)
        newMap.upsert(userResource)
        appState.userResourceAdditions.append(newMap)
    }
    appState.saveConfig()
}
```

- [ ] **Step 3: Add user-addition-aware remove method**

```swift
/// Remove a user-added resource. Team defaults cannot be removed by non-Directors.
func removeUserResource(id: String, type: MappedResourceType, from productId: String, appState: AppState) {
    if let idx = appState.userResourceAdditions.firstIndex(where: { $0.id == productId }) {
        appState.userResourceAdditions[idx].remove(id: id, type: type)
        // Clean up empty maps
        if appState.userResourceAdditions[idx].resources.isEmpty {
            appState.userResourceAdditions.remove(at: idx)
        }
        appState.saveConfig()
    }
}
```

- [ ] **Step 4: Add Director-only team edit methods**

```swift
/// Add a resource to team defaults (Director only).
func addTeamResource(_ resource: MappedResource, to productId: String, appState: AppState) {
    var teamResource = resource
    teamResource.isTeamDefault = true
    teamResource.isConfirmed = true
    teamResource.addedAt = Date()

    if let idx = appState.teamResourceMaps.firstIndex(where: { $0.id == productId }) {
        appState.teamResourceMaps[idx].upsert(teamResource)
    } else {
        var newMap = ProductResourceMap.empty(for: productId)
        newMap.upsert(teamResource)
        appState.teamResourceMaps.append(newMap)
    }
    appState.saveConfig()
}

/// Remove a resource from team defaults (Director only).
func removeTeamResource(id: String, type: MappedResourceType, from productId: String, appState: AppState) {
    if let idx = appState.teamResourceMaps.firstIndex(where: { $0.id == productId }) {
        appState.teamResourceMaps[idx].remove(id: id, type: type)
        appState.saveConfig()
    }
}
```

- [ ] **Step 5: Update existing addResource to route through user additions**

Update the existing `addResource` method to call `addUserResource` instead of directly modifying `productResourceMaps`. Find the method and change its implementation body to:

```swift
addUserResource(resource, to: productId, appState: appState)
```

- [ ] **Step 6: Update existing removeResource to be user-addition-aware**

Update the existing `removeResource` method. It should only remove user additions unless the caller is a Director editing team defaults:

```swift
func removeResource(id: String, type: MappedResourceType, from productId: String, appState: AppState) {
    // Try removing from user additions first
    removeUserResource(id: id, type: type, from: productId, appState: appState)
}
```

- [ ] **Step 7: Build and verify**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 8: Commit**

```bash
git add BoomiSRE/Sources/ViewModels/ProductMappingViewModel.swift
git commit -m "feat: add two-tier resource routing with user addition and Director team edit methods"
```

---

### Task 4: Frontend — Split resource display into Team Defaults / My Additions

**Files:**
- Modify: `BoomiSRE/Sources/Views/Settings/ProductSettingsContent.swift`

This task modifies the `ResourceTypeSection` to show two sections and gates Director controls.

- [ ] **Step 1: Add Director state to ProductSettingsContent header**

In `ProductSettingsContent`, update the header area (around lines 28-52). Wrap the "Save as Team Template" button in a Director check and add an "Edit Team Template" toggle:

Replace the existing `Button { ... } label: { Label("Save as Team Template"...` block with:

```swift
if appState.userProfile.role.canEditTeamTemplate {
    HStack(spacing: 8) {
        Toggle("Edit Mode", isOn: $isDirectorEditMode)
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Enable to edit team default mappings")

        if isDirectorEditMode {
            Button {
                templateSaved = appState.saveAsDefaultTemplate()
                showTemplateSaved = true
            } label: {
                Label("Save Team Template", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .help("Save confirmed mappings as the default template for all users")
            .popover(isPresented: $showTemplateSaved) {
                VStack(spacing: 8) {
                    Image(systemName: templateSaved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(templateSaved ? .green : .red)
                    if templateSaved {
                        Text("Template saved! It will be bundled with the next build.")
                            .font(.caption)
                    } else if let err = appState.lastTemplateError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    } else {
                        Text("Failed to save template.").font(.caption)
                    }
                }
                .padding()
            }
        }
    }
}
```

Add the state variable near the other `@State` declarations:

```swift
@State private var isDirectorEditMode = false
```

- [ ] **Step 2: Pass `isDirectorEditMode` down to child views**

Add an `isDirectorEditMode` parameter to `ProductMappingDetail`, `IntegrationResourcePanel`, and `ResourceTypeSection`. Thread it through from `ProductSettingsContent`:

In `ProductMappingDetail` call site:
```swift
ProductMappingDetail(
    product: product,
    vm: vm,
    isDirectorEditMode: isDirectorEditMode
)
```

Add the property to each struct:
```swift
var isDirectorEditMode: Bool = false
```

Thread it through to `IntegrationResourcePanel` and then to `ResourceTypeSection`.

- [ ] **Step 3: Split ResourceTypeSection into Team Defaults / My Additions**

In `ResourceTypeSection.body`, replace the confirmed resources display (around lines 450-468) with two sections:

```swift
// Team Defaults (locked)
let teamConfirmed = confirmed.filter { $0.isTeamDefault }.filter { matches($0) }
if !teamConfirmed.isEmpty {
    HStack {
        Label("Team Defaults (\(teamConfirmed.count))", systemImage: "lock.fill")
            .font(.caption.bold())
            .foregroundStyle(.blue)
        Spacer()
        if isDirectorEditMode {
            Button("Remove All") {
                for r in teamConfirmed {
                    vm.removeTeamResource(id: r.id, type: r.type, from: productId, appState: appState)
                }
            }
            .font(.caption).buttonStyle(.bordered)
        }
    }
    ForEach(Array(teamConfirmed.enumerated()), id: \.element.id) { idx, resource in
        if isDirectorEditMode {
            ConfirmedResourceRow(resource: resource, productId: productId, vm: vm, isEven: idx.isMultiple(of: 2), isTeamEdit: true)
        } else {
            LockedResourceRow(resource: resource, isEven: idx.isMultiple(of: 2))
        }
    }
}

// My Additions
let userConfirmed = confirmed.filter { !$0.isTeamDefault }.filter { matches($0) }
if !userConfirmed.isEmpty {
    HStack {
        Label("My Additions (\(userConfirmed.count))", systemImage: "person.fill")
            .font(.caption.bold())
            .foregroundStyle(.green)
        Spacer()
        Button("Remove All") {
            for r in userConfirmed {
                vm.removeUserResource(id: r.id, type: r.type, from: productId, appState: appState)
            }
        }
        .font(.caption).buttonStyle(.bordered)
    }
    ForEach(Array(userConfirmed.enumerated()), id: \.element.id) { idx, resource in
        ConfirmedResourceRow(resource: resource, productId: productId, vm: vm, isEven: idx.isMultiple(of: 2))
    }
}
```

- [ ] **Step 4: Add LockedResourceRow view**

Add a new private struct after `ConfirmedResourceRow`:

```swift
private struct LockedResourceRow: View {
    let resource: MappedResource
    var isEven: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.blue.opacity(0.5))
                .font(.caption2)
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.name).font(.callout)
                if let desc = resource.description, !desc.isEmpty {
                    Text(desc).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
            Text(resource.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isEven ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}
```

- [ ] **Step 5: Update ManualAddRow to route through user additions**

In `ManualAddRow`, update the add action to call `vm.addUserResource` instead of `vm.addResource` when in normal mode, and `vm.addTeamResource` when in Director edit mode. Pass `isDirectorEditMode` through.

- [ ] **Step 6: Build and verify**

Run: `swift build`
Expected: Build succeeds. The UI now shows locked team defaults and editable user additions.

- [ ] **Step 7: Commit**

```bash
git add BoomiSRE/Sources/Views/Settings/ProductSettingsContent.swift
git commit -m "feat: split resource UI into locked Team Defaults and editable My Additions sections"
```

---

### Task 5: QA — Build, verify, and release

**Files:**
- All modified files from Tasks 1-4

- [ ] **Step 1: Full clean build**

```bash
swift build 2>&1
```

Expected: `Build complete!` with no errors.

- [ ] **Step 2: Verify team defaults load from bundled JSON**

Verify by reading the code path: `ensureResourceMapsExist()` loads from `default_product_maps.json` into `teamResourceMaps`. The computed `productResourceMaps` merges team + user and marks team resources with `isTeamDefault = true`.

- [ ] **Step 3: Verify factory reset preserves team defaults**

Read `factoryReset()` and confirm it reloads `teamResourceMaps` from bundled template and clears `userResourceAdditions`.

- [ ] **Step 4: Verify Director gating**

Confirm that `isDirectorEditMode` toggle only appears when `appState.userProfile.role.canEditTeamTemplate` is true (Director or Manager roles).

- [ ] **Step 5: Verify save template only saves team maps**

Read `saveAsDefaultTemplate()` and confirm it iterates `teamResourceMaps`, not `productResourceMaps`.

- [ ] **Step 6: Push and release**

```bash
git push origin main
bash release.sh
```

- [ ] **Step 7: Final commit with all files**

```bash
git add -A
git commit -m "feat: locked team template mappings with Director edit mode and user additions"
git push origin main
bash release.sh
```
