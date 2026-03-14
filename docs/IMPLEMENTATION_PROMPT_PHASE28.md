# Boomi SRE App — Phase 28: Fix On-Call — Team ID vs Schedule ID Mismatch

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`.

**Read these files first:**
- `BoomiSRE/Sources/Views/Panels/OnCallView.swift` — renders on-call cards per favorited team
- `BoomiSRE/Sources/ViewModels/OnCallViewModel.swift` — `loadOnCall(for:)` and `loadTeams()`
- `BoomiSRE/Sources/Services/JSMOpsService.swift` — `getOnCall(scheduleId:)` and `listSchedules()`
- `BoomiSRE/Sources/Models/JSMOpsModels.swift` — OpsTeam, OpsSchedule, OnCallParticipant

---

## Root Cause (Confirmed by Live API Testing)

The "Who's On-Call" cards spin forever because `loadOnCall(for: team.id)` passes a **team ID** to the on-call API, but the endpoint requires a **schedule ID**.

**The on-call endpoint is:** `GET /v1/schedules/{scheduleId}/on-calls`

- Passing a team ID (e.g., `og-90b86004-f391-4213-9742-3c0f47d8731b`) returns **404**: `"No schedule exists with id [og-90b86004...]"`
- Passing a schedule ID (e.g., `91b865f0-f11f-4f4b-ac15-dd7cfe29193c`) returns **200** with on-call participants

**The relationship:** Each team has multiple schedules. For example, team "CAM SRE" (`og-90b86004...`) has three schedules:
- `CAMSRE_PrimarySchedule` (schedule ID: `91b865f0...`)
- `CAMSRE_SecondarySchedule` (schedule ID: `fc0d725f...`)
- `CAMSRE_IncidentCommanderSchedule` (schedule ID: `4f9691b9...`)

Schedules have a `teamId` field that links them to their parent team.

**The user's favorites** (`appState.favoriteJSMTeams`) contain **team IDs**, which is correct — the user picks teams, not individual schedules.

---

## Fix

### Phase 28A: Load Schedules Per Team, Then On-Call Per Schedule

Rewrite the on-call loading flow:

1. **In `loadTeams()` (OnCallViewModel):**
   - After loading teams, also load ALL schedules via `listSchedules()`
   - Store them: `@Published var allSchedules: [OpsSchedule] = []`
   - Group schedules by teamId for easy lookup

2. **Replace `loadOnCall(for teamId:)` with `loadOnCallForTeam(teamId:)`:**
   ```swift
   func loadOnCallForTeam(teamId: String, appState: AppState) async {
       guard appState.isJiraConfigured else { return }
       isLoadingOnCall = true

       // Find all schedules belonging to this team
       let teamSchedules = allSchedules.filter { $0.teamId == teamId }

       // For each schedule, fetch who is on call
       for schedule in teamSchedules {
           do {
               let participants = try await service.getOnCall(
                   baseURL: appState.jiraBaseURL,
                   email: appState.jiraEmail,
                   apiToken: appState.jiraAPIToken,
                   scheduleId: schedule.id   // ← schedule ID, NOT team ID
               )
               onCallResults[schedule.id] = participants

               // Resolve display names for any new accountIds
               for p in participants where displayNames[p.name] == nil {
                   if let name = try? await service.resolveDisplayName(
                       accountId: p.name,
                       baseURL: appState.jiraBaseURL,
                       email: appState.jiraEmail,
                       apiToken: appState.jiraAPIToken
                   ) {
                       displayNames[p.name] = name
                   }
               }
           } catch {
               // Individual schedule failure shouldn't block others
           }
       }
       isLoadingOnCall = false
   }
   ```

3. **Update `onCallResults` key** — currently keyed by the ID passed to `loadOnCall`, which was the team ID (wrong). Now it should be keyed by **schedule ID** since each schedule has its own on-call rotation.

### Phase 28B: Update OnCallView to Show Schedules Per Team

The `onCallCard(team)` view currently looks up `vm.onCallResults[team.id]` which will always be empty now that results are keyed by schedule ID.

**Rewrite the on-call card to show schedules within the team:**

```swift
private func onCallCard(_ team: OpsTeam) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        // Team header
        HStack {
            Text(team.name).font(.callout.bold())
            Spacer()
            // JSM link button (existing)
        }

        // Find schedules for this team
        let teamSchedules = vm.allSchedules.filter { $0.teamId == team.id }

        if teamSchedules.isEmpty {
            Text("No schedules configured for this team")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(teamSchedules) { schedule in
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    let participants = vm.onCallResults[schedule.id] ?? []
                    if participants.isEmpty && vm.isLoadingOnCall {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.5)
                            Text("Loading…").font(.caption2).foregroundStyle(.tertiary)
                        }
                    } else if participants.isEmpty {
                        Text("No one on call").font(.caption).foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(participants.enumerated()), id: \.offset) { i, p in
                            HStack(spacing: 8) {
                                Image(systemName: i == 0 ? "person.fill" : "person")
                                    .foregroundStyle(i == 0 ? Color.accentColor : .secondary)
                                    .frame(width: 18)
                                Text(vm.displayNames[p.name] ?? p.name)
                                    .font(.callout)
                                if i == 0 {
                                    Text("Primary")
                                        .font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    .task { await vm.loadOnCallForTeam(teamId: team.id, appState: appState) }
}
```

**Key changes:**
- The `.task` now calls `loadOnCallForTeam(teamId:)` (team ID) which internally finds schedules and calls on-call per schedule
- Each schedule within the team is shown as a sub-section with its name (e.g., "CAMSRE_PrimarySchedule", "CAMSRE_SecondarySchedule")
- Participants are shown under each schedule, not lumped together
- This gives the SRE a clear view: "For this team, here's who's primary on the primary rotation, who's on secondary, who's IC"

### Phase 28C: Also Load On-Call in `loadTeams()`

Currently `loadTeams()` calls `loadOnCall(for:)` for each favorite (line 136-138). Update this to use the new method:

```swift
// In loadTeams(), after loading schedules:
for teamId in appState.favoriteJSMTeams {
    await loadOnCallForTeam(teamId: teamId, appState: appState)
}
```

This means when the On-Call page loads, it fetches teams + schedules, then immediately loads on-call for all favorited teams — no need for the `.task` on each card to trigger separately (though keeping it as a fallback is fine).

---

## General Guidelines

- Run `swift build` to verify.
- Commit with message: "Fix On-Call: use schedule IDs for on-call lookup, show schedules per team".
