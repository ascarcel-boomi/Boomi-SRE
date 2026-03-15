# Boomi SRE App — Phase 39: Fix Auto-Update Nesting Bug, Add Tests & Optimize

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Services/UpdateService.swift` — `applyUpdate()` method with the cp -R bug (line ~121)
- `build_app.sh` — build script that creates the .app bundle and DMG
- `Tests/BoomiSRETests.swift` — empty placeholder
- `run_tests.swift` — existing CLI test runner (tests OutputParser and ReportCatalog only)
- `Package.swift` — test target configuration

---

## CRITICAL BUG: Auto-Update Creates Recursive Nested App Bundles

### The Bug

Every time the auto-update runs, it creates a nested copy of the app inside itself. After 32 updates, the app is **731MB** (32 × 24MB). The actual app is only **24MB**.

**Root cause** in `UpdateService.swift`, line ~121:
```bash
cp -R "/Volumes/BoomiSRE_Update/Boomi SRE.app" "/Applications/Boomi SRE.app"
```

This `cp -R` copies the source `.app` **INTO** the destination directory as a subdirectory, because `/Applications/Boomi SRE.app` already exists as a directory. The result:
```
/Applications/Boomi SRE.app/                    ← the real app
/Applications/Boomi SRE.app/Boomi SRE.app/     ← copy from update #1
/Applications/Boomi SRE.app/Boomi SRE.app/Boomi SRE.app/  ← copy from update #2
... 32 levels deep
```

### The Fix

Replace the `cp -R` with an `rm -rf` + `cp -R` sequence. The update script must **delete the existing app first**, then copy the new one:

```bash
#!/bin/bash
sleep 2
rm -rf "/Applications/Boomi SRE.app"
cp -R "/Volumes/BoomiSRE_Update/Boomi SRE.app" "/Applications/Boomi SRE.app"
hdiutil detach "/Volumes/BoomiSRE_Update" -quiet 2>/dev/null || true
open -a "Boomi SRE"
rm "$0"
```

The `rm -rf` is safe because:
- The app has already quit (the script waits 2 seconds)
- The new copy immediately replaces it
- If the copy fails, the app won't be there — but neither would it be there with the old broken approach

**Alternative (safer):** Move the old app to Trash instead of deleting:
```bash
sleep 2
mv "/Applications/Boomi SRE.app" "$HOME/.Trash/Boomi SRE.app.old.$$"
cp -R "/Volumes/BoomiSRE_Update/Boomi SRE.app" "/Applications/Boomi SRE.app"
```

---

## Implementation

### Phase 39A: Fix the Update Script in UpdateService.swift

1. **Fix the script in `applyUpdate()`** to delete the existing app before copying:
   ```swift
   let scriptContent = """
   #!/bin/bash
   sleep 2
   rm -rf "/Applications/Boomi SRE.app"
   cp -R "\(newAppPath)" "/Applications/Boomi SRE.app"
   hdiutil detach "/Volumes/BoomiSRE_Update" -quiet 2>/dev/null || true
   open -a "Boomi SRE"
   rm "$0"
   """
   ```

2. **Also clean up the current user's nested bundles.** Add a one-time cleanup that runs on app launch. In `BoomiSREApp.swift` or `AppState`, add:
   ```swift
   /// Remove nested app bundles created by the old buggy updater.
   private func cleanNestedAppBundles() {
       let appPath = "/Applications/Boomi SRE.app"
       let nestedPath = appPath + "/Boomi SRE.app"
       if FileManager.default.fileExists(atPath: nestedPath) {
           try? FileManager.default.removeItem(atPath: nestedPath)
           print("[Cleanup] Removed nested app bundle at \(nestedPath)")
       }
   }
   ```
   Call this on `onAppear` (once per launch). It only needs to remove the immediate child — removing one level is enough since the next update will use the fixed script.

### Phase 39B: Optimize Build — Strip Debug Symbols

1. **In `build_app.sh`**, after building in release mode, strip the binary:
   ```bash
   # Strip debug symbols from the release binary
   strip -x ".build/release/BoomiSRE"
   ```
   This can reduce binary size by 30-50%.

2. **Check if the `.build/` directory is being accidentally included** in the DMG. The DMG should only contain the `.app` bundle, not build artifacts. Verify the DMG creation step in `build_app.sh` only copies the `.app`.

### Phase 39C: Add Comprehensive Tests

The existing `run_tests.swift` only tests `OutputParser`. Create a proper test suite that covers the critical code paths.

**Create/update `Tests/BoomiSRETests.swift`** with XCTest tests. If XCTest isn't available (no Xcode), keep using the `run_tests.swift` pattern but expand it significantly.

**Tests to add:**

#### 1. URL/INI Parsing Tests
```swift
// Test AWSAuthService.addPortalCredentials parsing
// - Verify profile name extraction from [header] line
// - Verify \r\n handling (Windows line endings)
// - Verify duplicate profile removal (removeINIBlock)
// - Verify config file gets correct [profile name] entry
```

#### 2. JSM Ops API Response Parsing Tests
```swift
// Test JSMOpsService response parsing
// - Parse schedules response: {"values": [...]}
// - Parse teams response: [{teamId, teamName}]
// - Parse on-call response: {"onCallParticipants": [{"id": "...", "type": "user"}]}
// - Parse alerts response: {"values": [...]} with all fields
// - Handle empty responses gracefully
// - Handle malformed JSON gracefully
```

#### 3. Widget Model Tests
```swift
// - Verify all WidgetType cases have icons and titles
// - Verify DashboardWidget.defaults covers all expected widget types
// - Verify WidgetSize encoding/decoding
// - Verify urgency scoring returns 0-100 range
```

#### 4. MOTD Tests
```swift
// - Verify MOTDLibrary has 40+ messages
// - Verify messageOfTheMoment() returns a valid message
// - Verify nextRandom(excluding:) returns a different message
// - Verify all categories have messages
```

#### 5. Credential/Config Persistence Tests
```swift
// - Verify KeychainHelper.save/load roundtrip
// - Verify config JSON encoding/decoding roundtrip
// - Verify factory reset clears all expected files
```

#### 6. Update Version Comparison Tests
```swift
// - "26.03.14-120000" > "26.03.13-120000" (newer date)
// - "26.03.14-120001" > "26.03.14-120000" (newer time)
// - "26.03.14-120000" == "26.03.14-120000" (same version — no update)
// - "dev" < any version (dev build always gets updates)
```

#### 7. Health Score Tests
```swift
// - Perfect score (100) when no issues
// - Deduction for P1 incidents
// - Deduction for unacked alerts
// - Deduction for firing Grafana alerts
// - Score never goes below 0 or above 100
```

### Phase 39D: Run Tests and Verify

1. Run `swift test` (if XCTest tests exist) or `swift run_tests.swift`
2. Run `swift build -c release` and verify the binary size
3. Verify the DMG creation produces a clean `.dmg` without nested artifacts
4. Run the nested bundle cleanup and verify the app size drops from ~731MB to ~24MB

---

## General Guidelines

- The update script fix (Phase 39A) is the **highest priority** — it's causing the app to grow 24MB with every update.
- The cleanup code should be safe and non-destructive — only remove the nested `Boomi SRE.app/Boomi SRE.app` path, nothing else.
- Tests should be runnable without Xcode (use the `run_tests.swift` CLI pattern if needed).
- Commit after each phase with descriptive messages.
