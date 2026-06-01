# Boomi SRE App — Phase 29: Fix AWS Portal Credentials Parsing

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Services/AWSAuthService.swift` — `addPortalCredentials()` method (line ~150), profile parsing from `~/.aws/config` and `~/.aws/credentials`
- `BoomiSRE/Sources/Views/SettingsView.swift` — AWS settings tab, `addCredentials()` method, profile dropdown, paste text area

---

## The Bug

When a user pastes AWS portal credentials like:
```
[554825952155_ReadOnlyAccess]
aws_access_key_id=ASIAIOSFODNN7EXAMPLE
aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
aws_session_token=IQoJb3JpZ2luX2VjEXAMPLESESSIONTOKEN...
```

The credentials ARE correctly saved to `~/.aws/credentials` under `[554825952155_ReadOnlyAccess]`. However:

1. **The profile name is parsed as "pasted" instead of "554825952155_ReadOnlyAccess"** — the parsing at line 161-168 of `AWSAuthService.swift` falls through to the default `"pasted"`.
2. **`~/.aws/config` gets a `[profile pasted]` entry** instead of `[profile 554825952155_ReadOnlyAccess]`.
3. **The dropdown shows "pasted"** because it reads profiles from `~/.aws/config`.
4. **Authentication fails** because the app tries to use `--profile pasted` but the credentials are stored under `[554825952155_ReadOnlyAccess]` in `~/.aws/credentials`.

## Root Cause

The profile name extraction loop (lines 161-168) does this:
```swift
var profileName = "pasted"
for line in trimmed.components(separatedBy: "\n") {
    let l = line.trimmingCharacters(in: .whitespaces)
    if l.hasPrefix("[") && l.hasSuffix("]") {
        profileName = String(l.dropFirst().dropLast())
        break
    }
}
```

This SHOULD work for `[554825952155_ReadOnlyAccess]`. The likely failure causes:

1. **`\r\n` line endings** — the AWS portal or macOS clipboard may use Windows-style line breaks. `.trimmingCharacters(in: .whitespaces)` does NOT strip `\r`. After trimming, the line would be `[554825952155_ReadOnlyAccess]\r` which does NOT end with `]` — it ends with `\r]` wait no, `\r` comes before `]`... actually `\r` would be at the end: the raw line is `[554825952155_ReadOnlyAccess]\r`, trimming whitespaces removes spaces/tabs but NOT `\r`, so `hasSuffix("]")` fails because the last char is `\r`.

2. **SwiftUI TextEditor formatting** — TextEditor may inject different whitespace or line break characters.

## Fix

### Phase 29A: Fix Profile Name Parsing

In `addPortalCredentials()` in `AWSAuthService.swift`:

1. **Strip `\r` characters** from the entire pasted text before processing:
   ```swift
   let trimmed = pastedText
       .replacingOccurrences(of: "\r\n", with: "\n")
       .replacingOccurrences(of: "\r", with: "\n")
       .trimmingCharacters(in: .whitespacesAndNewlines)
   ```

2. **Also trim `\r` from each line** in the profile name extraction:
   ```swift
   for line in trimmed.components(separatedBy: "\n") {
       let l = line.trimmingCharacters(in: .whitespacesAndNewlines)  // ← use whitespacesAndNewlines, not just whitespaces
       if l.hasPrefix("[") && l.hasSuffix("]") {
           profileName = String(l.dropFirst().dropLast())
           break
       }
   }
   ```

3. **Validate the extracted profile name** — if it's empty or only whitespace after extraction, fall back to generating a name from the account ID:
   ```swift
   if profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
       // Try to infer from the access key or other content
       profileName = "portal-\(Date().timeIntervalSince1970)"
   }
   ```

### Phase 29B: Fix Config File Entry to Match Credentials File

The config entry must use the SAME profile name as the credentials file header. Currently the code writes the credentials raw (preserving the original `[header]`) but writes a config entry using the parsed `profileName`. If parsing fails, they mismatch.

After writing credentials, verify the names match:
```swift
// Write credentials with the ORIGINAL header from the pasted text
try newCreds.write(to: credPath, atomically: true, encoding: .utf8)

// The config entry MUST match the credentials header exactly
let configHeader = "[profile \(profileName)]"
```

This should already work if the parsing is fixed. But add a safety check: after writing, read back the credentials file and verify the profile name appears as a `[header]`.

### Phase 29C: Clean Up Stale "pasted" Profile

The user's `~/.aws/config` currently has a stale `[profile pasted]` entry from the previous bug. While the code shouldn't clean up user files proactively, add this:

1. **In the profile loading code**, filter out profiles named exactly "pasted" — this is clearly a bug artifact, not a real profile.
2. Or better: when `addPortalCredentials()` successfully extracts a real profile name, check if a `[profile pasted]` entry exists in config and remove it (it was created by a previous failed parse).

### Phase 29D: Improve the Paste UX

1. **Show the detected profile name** immediately after pasting, before the user clicks "Add Profile":
   ```
   Detected profile: 554825952155_ReadOnlyAccess ✓
   [Add Profile]
   ```
   If detection fails (name would be "pasted"), show a warning:
   ```
   ⚠️ Could not detect profile name from pasted text.
   The header line should look like: [AccountId_RoleName]
   ```

2. **After adding, select the new profile** in the dropdown and immediately test it:
   - Set `appState.awsSSOProfile = profileName`
   - Run `checkStatus(profile:)` to verify it works
   - Show green "Connected as Account 554825952155" or red error

3. **Show a note about session tokens:** "Portal credentials are temporary session tokens. They expire after the session timeout configured by your organization (typically 1-12 hours). You'll need to paste new credentials when they expire."

---

## General Guidelines

- Run `swift build` to verify.
- Commit with descriptive message.
