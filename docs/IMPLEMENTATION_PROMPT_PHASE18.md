# Boomi SRE App — Phase 18: Inspirational Message of the Day

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. It is an SRE command center built with Swift Package Manager (macOS 15+, Swift 6.2). The architecture is MVVM with actor-based services, and file-based credential/config storage.

**Read these files first:**
- `BoomiSRE/Sources/Views/WelcomeView.swift` or `BoomiSRE/Sources/Views/Panels/DashboardView.swift` — current home page (whichever exists)
- `BoomiSRE/Sources/Models/AppState.swift` — refresh triggers, timer
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app lifecycle

**Key constraints (same as all prior phases):**
- Pure SwiftUI + Swift Charts. No third-party UI frameworks.

---

## The Vision

The Boomi SRE team are **reliability ninjas**. When they do their job well, no one knows they exist. They maintain one of the world's most powerful integration platforms on the planet. This Message of the Day (MOTD) feature should remind them of that — with a mix of team philosophy, SRE wisdom, and just enough whimsy to make them smile at 2 AM during an incident.

The tone should be: **proud, witty, occasionally funny, always empowering**. These aren't generic corporate slogans — they're battle cries from the trenches of production infrastructure.

---

## Implementation

### Phase 18A: Message of the Day Model & Data

**Create `BoomiSRE/Sources/Models/MOTDModels.swift`:**

```swift
struct MOTDMessage: Identifiable {
    let id = UUID()
    let quote: String
    let attribution: String      // who said it / where it's from
    let category: MOTDCategory
    let emoji: String            // a single emoji that sets the mood
}

enum MOTDCategory: String, CaseIterable {
    case teamPhilosophy   // CAM SRE Team Philosophies
    case sreWisdom        // Industry SRE quotes
    case boomiPride       // Boomi company culture
    case ninjaSpirit      // The reliability ninja ethos
}
```

**Create `BoomiSRE/Sources/Models/MOTDData.swift`:**

Hardcode the full message collection. This is intentional — no API call needed, instant load, works offline. The messages should be carefully written to feel personal and earned, not corporate.

```swift
enum MOTDLibrary {
    static let messages: [MOTDMessage] = [

        // ═══════════════════════════════════════════════════════════
        // CAM SRE TEAM PHILOSOPHIES (from Confluence)
        // ═══════════════════════════════════════════════════════════

        MOTDMessage(
            quote: "Proactively envision the end state. Prioritize accordingly. Generate symbiosis through empathetic communication.",
            attribution: "CAM SRE Team Mantra",
            category: .teamPhilosophy,
            emoji: "🎯"
        ),
        MOTDMessage(
            quote: "Fair Compensation + Autonomy + Mastery + Purpose = Motivation. That's not theory — that's our operating system.",
            attribution: "CAM SRE Team Philosophies — inspired by Daniel Pink's Drive",
            category: .teamPhilosophy,
            emoji: "🧠"
        ),
        MOTDMessage(
            quote: "Two is One and One is None — so always use three. Eliminate single points of failure.",
            attribution: "CAM SRE Team Philosophies — Navy SEAL motto, applied to infrastructure",
            category: .teamPhilosophy,
            emoji: "🔱"
        ),
        MOTDMessage(
            quote: "You build it, you run it! APIM ENG writes the app code. APIM SRE writes the infrastructure code. That's the deal.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "🤝"
        ),
        MOTDMessage(
            quote: "The best runbook is the one you don't need to write. Monitor it, alert on it, then build self-healing into the architecture.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "🩹"
        ),
        MOTDMessage(
            quote: "The only way to eat an elephant is one bite at a time. Break it down, categorize it, work it in order.",
            attribution: "CAM SRE Team Philosophies — via the Eisenhower Matrix",
            category: .teamPhilosophy,
            emoji: "🐘"
        ),
        MOTDMessage(
            quote: "The best way to learn something is to teach it to others. You only truly know it when you can explain it.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "📖"
        ),
        MOTDMessage(
            quote: "We don't push buttons — we write the code behind the button. Our goal is to replace ourselves with automation.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "🤖"
        ),
        MOTDMessage(
            quote: "Seek to understand. The first step in troubleshooting is finding the root cause, not chasing the symptoms.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "🔍"
        ),
        MOTDMessage(
            quote: "Trust, and verify! We hold ourselves to a very high standard. Trust our colleagues, verify our work.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "✅"
        ),
        MOTDMessage(
            quote: "What is the single source of truth? If you don't know, you could be chasing a ghost in the machine.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "👻"
        ),
        MOTDMessage(
            quote: "Limit the blast radius of your code. Clear boundaries, autonomous teams, reduced conflict.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "💥"
        ),
        MOTDMessage(
            quote: "Keep your code DRY. Don't repeat yourself. Replace repetition with abstractions. Avoid redundancy.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "🌵"
        ),
        MOTDMessage(
            quote: "Slow is smooth, and smooth is fast. Sometimes to go fast, you have to slow down, breathe, re-focus, and continue deliberately.",
            attribution: "CAM SRE Team Philosophies — Navy SEAL motto",
            category: .teamPhilosophy,
            emoji: "🧘"
        ),
        MOTDMessage(
            quote: "The whole is greater than the sum of the parts. If you want to go far, go together. 1+1+1=5.",
            attribution: "CAM SRE Team Philosophies",
            category: .teamPhilosophy,
            emoji: "💪"
        ),

        // ═══════════════════════════════════════════════════════════
        // SRE INDUSTRY WISDOM
        // ═══════════════════════════════════════════════════════════

        MOTDMessage(
            quote: "Hope is not a strategy. Build robust systems, implement automation, and rely on data.",
            attribution: "Google SRE Mantra",
            category: .sreWisdom,
            emoji: "⚙️"
        ),
        MOTDMessage(
            quote: "Embrace failure, but automate the recovery. Every incident is a gift — if you learn from it.",
            attribution: "SRE Principle",
            category: .sreWisdom,
            emoji: "🎁"
        ),
        MOTDMessage(
            quote: "If it hurts, do it more often. Automate the pain away. Frequent small releases beat rare big bangs.",
            attribution: "Continuous Delivery Principle",
            category: .sreWisdom,
            emoji: "🔄"
        ),
        MOTDMessage(
            quote: "SLIs and SLOs are the contract of trust. They matter more than raw uptime metrics.",
            attribution: "SRE Principle",
            category: .sreWisdom,
            emoji: "📊"
        ),
        MOTDMessage(
            quote: "Reduce toil. Eliminate manual, repetitive operational work through automation. That's the mission.",
            attribution: "Google SRE Principle",
            category: .sreWisdom,
            emoji: "🛠️"
        ),
        MOTDMessage(
            quote: "The only thing worse than an alert that wakes you up is an alert that wakes you up for nothing.",
            attribution: "Every On-Call Engineer, 3 AM",
            category: .sreWisdom,
            emoji: "🔔"
        ),
        MOTDMessage(
            quote: "Monitoring is not observability. Dashboards show you what happened. Observability helps you understand why.",
            attribution: "Charity Majors",
            category: .sreWisdom,
            emoji: "👁️"
        ),
        MOTDMessage(
            quote: "The most dangerous phrase in engineering: 'It works on my machine.'",
            attribution: "Every Incident Postmortem",
            category: .sreWisdom,
            emoji: "🔥"
        ),
        MOTDMessage(
            quote: "Automate yourself out of a job — then find a harder problem to solve.",
            attribution: "SRE Career Philosophy",
            category: .sreWisdom,
            emoji: "🚀"
        ),
        MOTDMessage(
            quote: "An error budget is not a target to spend. It's a safety margin for velocity.",
            attribution: "SRE Principle",
            category: .sreWisdom,
            emoji: "🏦"
        ),
        MOTDMessage(
            quote: "The best incident response is the one that happens before the customer notices.",
            attribution: "SRE Principle",
            category: .sreWisdom,
            emoji: "🥷"
        ),
        MOTDMessage(
            quote: "Cattle, not pets. If it's broken, replace it. Don't nurse it back to health.",
            attribution: "Cloud Infrastructure Principle",
            category: .sreWisdom,
            emoji: "🐄"
        ),
        MOTDMessage(
            quote: "Everything fails, all the time. Design for it.",
            attribution: "Werner Vogels, CTO of Amazon",
            category: .sreWisdom,
            emoji: "🌊"
        ),
        MOTDMessage(
            quote: "A postmortem without action items is just a story. A postmortem with action items is progress.",
            attribution: "SRE Principle",
            category: .sreWisdom,
            emoji: "📝"
        ),
        MOTDMessage(
            quote: "Your systems are only as reliable as the least reliable thing you didn't think about.",
            attribution: "Production Wisdom",
            category: .sreWisdom,
            emoji: "🧩"
        ),

        // ═══════════════════════════════════════════════════════════
        // BOOMI PRIDE
        // ═══════════════════════════════════════════════════════════

        MOTDMessage(
            quote: "Connect everything to achieve anything.™ That's not a tagline — that's what we enable every single day.",
            attribution: "Boomi",
            category: .boomiPride,
            emoji: "🔗"
        ),
        MOTDMessage(
            quote: "Boomi: the Data Activation Company. Connecting the world's data, one integration at a time.",
            attribution: "Boomi",
            category: .boomiPride,
            emoji: "⚡"
        ),
        MOTDMessage(
            quote: "The Boomi Difference: People. The technology is incredible. The people behind it are what make it extraordinary.",
            attribution: "Boomi Culture",
            category: .boomiPride,
            emoji: "💙"
        ),
        MOTDMessage(
            quote: "Over 20,000 customers trust Boomi to connect their world. We're the ones who make sure it stays connected.",
            attribution: "Boomi SRE Pride",
            category: .boomiPride,
            emoji: "🌍"
        ),
        MOTDMessage(
            quote: "Boomi processes billions of data transactions. Every. Single. Month. And we keep it running.",
            attribution: "Boomi SRE Pride",
            category: .boomiPride,
            emoji: "📈"
        ),
        MOTDMessage(
            quote: "Behind every seamless Boomi integration is an SRE who made sure the infrastructure didn't blink.",
            attribution: "Boomi SRE",
            category: .boomiPride,
            emoji: "🏗️"
        ),

        // ═══════════════════════════════════════════════════════════
        // NINJA SPIRIT — the reliability ninja ethos
        // ═══════════════════════════════════════════════════════════

        MOTDMessage(
            quote: "When we do our job well, no one knows we exist. We are Boomi Ninjas. 🥷",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🥷"
        ),
        MOTDMessage(
            quote: "A reliability ninja doesn't wait for the fire — they fireproof the building.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🏯"
        ),
        MOTDMessage(
            quote: "We Keep The Lights On. Not because anyone asks. Because millions of data flows depend on it.",
            attribution: "Boomi SRE — KTLO",
            category: .ninjaSpirit,
            emoji: "💡"
        ),
        MOTDMessage(
            quote: "Our invisibility is our superpower. The best SRE work is the kind nobody ever has to think about.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🦸"
        ),
        MOTDMessage(
            quote: "We don't just maintain infrastructure. We maintain trust. Every API call that succeeds is a promise kept.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🤞"
        ),
        MOTDMessage(
            quote: "At 3 AM, when the pager goes off, we don't complain. We troubleshoot, we fix, we learn, and we make it so it never happens again.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🌙"
        ),
        MOTDMessage(
            quote: "We are the reason the demo works. We are the reason the customer doesn't churn. We are SRE.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🎤"
        ),
        MOTDMessage(
            quote: "One platform. Billions of connections. A handful of ninjas keeping it all humming. That's us.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🎶"
        ),
        MOTDMessage(
            quote: "Today's the day you automate something that used to keep you up at night. Go get it. 💪",
            attribution: "Boomi SRE — Daily Motivation",
            category: .ninjaSpirit,
            emoji: "☀️"
        ),
        MOTDMessage(
            quote: "You chose one of the hardest jobs in tech. That's not a burden — that's a badge of honor.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🎖️"
        ),
        MOTDMessage(
            quote: "Every terraform apply, every ansible playbook, every alert you tune — that's you making Boomi better.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🛡️"
        ),
        MOTDMessage(
            quote: "The customer never sees us. The sales team never mentions us. But without us? None of it works.",
            attribution: "Boomi SRE Spirit",
            category: .ninjaSpirit,
            emoji: "🥷"
        ),
    ]

    /// Returns a pseudo-random message based on the current time, ensuring variety.
    static func messageOfTheMoment() -> MOTDMessage {
        let minutesSinceEpoch = Int(Date().timeIntervalSince1970) / 300  // changes every 5 minutes
        let index = abs(minutesSinceEpoch.hashValue) % messages.count
        return messages[index]
    }
}
```

**That's 42+ messages.** Feel free to add more! The mix should be roughly:
- ~35% Team Philosophies (the team's own words)
- ~25% SRE Wisdom (industry-wide)
- ~15% Boomi Pride (company culture)
- ~25% Ninja Spirit (empowerment, recognition)

---

### Phase 18B: MOTD View Component

**Create `BoomiSRE/Sources/Views/Shared/MOTDView.swift`:**

A small, elegant, non-intrusive widget that displays one message at a time.

**Design:**
- Subtle, blends into the home page — not a giant banner
- Placed near the bottom of the home page, or in a subtle card below the greeting, or as a footer strip
- The quote text in a slightly larger italic font (`.body.italic()`)
- The attribution in small secondary text below
- The emoji at the leading edge, adding personality
- A thin accent-colored left border or top/bottom rule for visual polish
- Clicking the message cycles to a random next one (fun easter egg)
- A very subtle fade-in animation when the message changes
- Category badge in `.caption2` font (tiny, muted — "Team Philosophy" / "SRE Wisdom" / "Boomi" / "Ninja Spirit")

**Example layout:**
```
┌──────────────────────────────────────────────────────┐
│ 🥷  "When we do our job well, no one knows we exist. │
│      We are Boomi Ninjas."                           │
│                                                      │
│      — Boomi SRE Spirit              Ninja Spirit    │
└──────────────────────────────────────────────────────┘
```

**Sizing:** The card should be ~80-100pt tall, full width, with rounded corners, a very subtle background (accent color at 3% opacity), and a 3pt accent-colored left border bar.

---

### Phase 18C: MOTD Rotation Timer

**Implementation:**

1. **In the home page view** (DashboardView or WelcomeView), add state:
   ```swift
   @State private var currentMOTD = MOTDLibrary.messageOfTheMoment()
   @State private var motdOpacity: Double = 1.0
   ```

2. **Rotation triggers — the message changes on:**
   - **App launch:** `messageOfTheMoment()` on `.onAppear`
   - **Every 5 minutes:** Use a `Timer.publish(every: 300)` that picks a new random message
   - **Service refresh:** Observe `appState.refreshTrigger` changes and pick a new message
   - **User click:** Tapping the MOTD card picks a new random message immediately

3. **Transition animation:**
   - When the message changes, fade out (opacity 0) over 0.3s, swap the message, fade in (opacity 1) over 0.3s
   - Use `.animation(.easeInOut(duration: 0.3), value: currentMOTD.id)`

4. **Ensure variety:**
   - `messageOfTheMoment()` uses a time-based hash so it's deterministic within each 5-minute window (same message if you switch away and back) but changes every 5 minutes
   - On manual click/refresh, use `messages.randomElement()!` with a check that it's different from the current one

---

## General Guidelines

- **Compile after each sub-phase.** Run `swift build` and fix any errors before moving on.
- **Don't break existing features.** The home page should look and work exactly as before, with the MOTD added.
- **The MOTD must not be annoying.** It should feel like discovering a fortune cookie, not being lectured. Subtle, small, delightful.
- **Dark mode:** Must look good in both light and dark macOS appearances. The accent-color tint works in both.
- **Commit after each phase** (18A, 18B, 18C) with a descriptive commit message.
