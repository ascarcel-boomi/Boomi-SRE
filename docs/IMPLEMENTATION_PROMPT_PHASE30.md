# Boomi SRE App — Phase 30: Fix AWS Credentials Duplicate Profiles & Config Cleanup

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read this file:**
- `BoomiSRE/Sources/Services/AWSAuthService.swift` — `addPortalCredentials()` and `removeINIBlock()` methods

---

## The Bug

After pasting AWS portal credentials, the `~/.aws/credentials` file ends up with **duplicate profile blocks**:

```ini
[554825952155_ReadOnlyAccess]
aws_access_key_id=ASIAYCLRUFON...
aws_secret_access_key=...
aws_session_token=...

[554825952155_ReadOnlyAccess]    ← DUPLICATE — causes AWS CLI parse error
aws_access_key_id=ASIAYCLRUFON...
aws_secret_access_key=...
aws_session_token=...
```

The AWS CLI fails with: `Unable to parse config file: /Users/adamscarcella/.aws/credentials`

Additionally, `~/.aws/config` has a stale `[profile pasted]` entry from the earlier parsing bug (Phase 29).

## Root Cause

**`removeINIBlock()` fails to find and remove the existing block** before the new one is appended. There are two bugs:

### Bug 1: `removeINIBlock` line comparison may fail due to whitespace

Line 221: `if l == "[\(blockName)]"` does an exact string comparison. If the existing file has any trailing whitespace, `\r`, or other invisible characters on the `[header]` line, the comparison fails and the old block is never removed.

**Fix:** Use `.trimmingCharacters(in: .whitespacesAndNewlines)` on `l` before comparing (currently uses `.whitespaces` which doesn't strip `\r` or `\n`).

### Bug 2: `removeINIBlock` for config file uses wrong format

Line 202 calls `removeINIBlock(from: existingConfig, named: "pasted")` which looks for `[pasted]`. But the config file uses `[profile pasted]` format. The block is never found.

**Fix:** The `removeINIBlock` function needs to handle both INI header formats:
- Credentials format: `[blockName]`
- Config format: `[profile blockName]`

## Fix

### Phase 30A: Fix `removeINIBlock()`

Rewrite to be robust against both formats and whitespace:

```swift
private nonisolated func removeINIBlock(from content: String, named blockName: String) -> String {
    let lines = content.components(separatedBy: "\n")
    var filtered: [String] = []
    var skipping = false
    for line in lines {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match both [blockName] and [profile blockName] formats
        if l == "[\(blockName)]" || l == "[profile \(blockName)]" {
            skipping = true
            continue
        }
        // Stop skipping when we hit the next block header
        if skipping && l.hasPrefix("[") && l.hasSuffix("]") {
            skipping = false
        }
        if !skipping {
            filtered.append(line)
        }
    }
    return filtered.joined(separator: "\n")
}
```

### Phase 30B: Clean Up the User's Files

After the `removeINIBlock` fix, the next time `addPortalCredentials()` runs it will correctly remove old duplicates. But the user's current files are already corrupted. Add cleanup logic:

1. In `addPortalCredentials()`, after writing the credentials file, **verify there are no duplicate headers**:
   ```swift
   // Safety check: remove any remaining duplicates
   let finalCreds = try String(contentsOf: credPath, encoding: .utf8)
   let cleanedCreds = deduplicateINIBlocks(finalCreds)
   if cleanedCreds != finalCreds {
       try cleanedCreds.write(to: credPath, atomically: true, encoding: .utf8)
       try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credPath.path)
   }
   ```

2. Add a `deduplicateINIBlocks()` helper that keeps only the LAST occurrence of each `[header]`:
   ```swift
   private nonisolated func deduplicateINIBlocks(_ content: String) -> String {
       // Parse all blocks, keeping track of order
       // If a block name appears multiple times, keep only the last one
       // This handles the case where removeINIBlock failed previously
   }
   ```

3. Also remove the stale `[profile pasted]` from config (the existing line 202 should now work with the fixed `removeINIBlock`).

### Phase 30C: Also fix whitespace in `addPortalCredentials()` line trimming

Verify that ALL `.trimmingCharacters(in: .whitespaces)` calls in the file are changed to `.trimmingCharacters(in: .whitespacesAndNewlines)` to handle `\r` consistently. There may be other places in the profile parsing code (`parseINIBlocks`, `parseProfiles`, etc.) that have the same issue.

Search the entire `AWSAuthService.swift` file for `.whitespaces)` and replace with `.whitespacesAndNewlines)` everywhere that parses INI content from files.

---

## General Guidelines

- Run `swift build` to verify.
- Commit with descriptive message.
