# Boomi SRE App — Phase 48: Persistent AI Bar — Copilot Available on Every Screen

## Context

You are working on a native macOS SwiftUI application at `~/github/Boomi-SRE/`. This is Phase D of the v2 evolution (see `docs/VISION_V2.md`).

**Read these files first:**
- `docs/VISION_V2.md` — the "Persistent AI Bar" section
- `BoomiSRE/Sources/Views/Panels/CopilotChatView.swift` — current full Copilot chat view
- `BoomiSRE/Sources/ViewModels/ChatViewModel.swift` — chat ViewModel (currently `@StateObject` inside CopilotChatView)
- `BoomiSRE/Sources/Views/ContentView.swift` — main layout with sidebar + detail
- `BoomiSRE/Sources/Views/BoomiSREApp.swift` — app lifecycle, existing `@StateObject` instances
- `BoomiSRE/Sources/Models/ChatModels.swift` — CopilotMessage, ContextType, QuickAction

---

## Goal

The AI Copilot is currently a separate section the user navigates to. Most SREs never open it because it's buried in the sidebar. Move it to a **persistent bottom bar** visible on every screen. The SRE can type a question from anywhere without navigating away from what they're looking at.

The bar has two states:
1. **Collapsed** (default) — a thin input bar at the bottom: `🤖 Ask anything... (⌘/)`
2. **Expanded** — slides up to show the full chat history, context chips, and conversation

---

## Implementation

### Phase 48A: Elevate ChatViewModel to App Lifecycle

The `ChatViewModel` is currently created as `@StateObject` inside `CopilotChatView`, which means it's destroyed when the user navigates away and recreated when they come back. Conversation history is lost (or reloaded from disk each time).

1. **Move `ChatViewModel` to `BoomiSREApp.swift`:**
   ```swift
   @StateObject private var chatVM = ChatViewModel()
   ```

2. **Pass it as `@EnvironmentObject`:**
   ```swift
   ContentView()
       .environmentObject(appState)
       .environmentObject(notificationVM)
       .environmentObject(updateVM)
       .environmentObject(chatVM)     // ← add
       // ... other environment objects
   ```

3. **In `CopilotChatView`, replace:**
   ```swift
   // Old:
   @StateObject private var viewModel = ChatViewModel()
   // New:
   @EnvironmentObject var viewModel: ChatViewModel
   ```
   This way the CopilotChatView (in the Knowledge & Tools tab) and the persistent AI bar share the same ViewModel and conversation history.

### Phase 48B: Create the Persistent AI Bar

Create `BoomiSRE/Sources/Views/Shared/AIBar.swift`:

```swift
struct AIBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatVM: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView
            }
            Divider()
            collapsedBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Collapsed Bar (always visible)

    private var collapsedBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.accentColor)

            TextField("Ask anything... (⌘/)", text: $chatVM.inputText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isInputFocused)
                .onSubmit {
                    Task { await chatVM.send(appState: appState) }
                }

            if chatVM.isLoading || chatVM.isGatheringContext {
                ProgressView().scaleEffect(0.6)
            }

            // Expand/collapse toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse chat" : "Expand chat history")

            // Send button (visible when there's text)
            if !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await chatVM.send(appState: appState) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(chatVM.isLoading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Expanded View (chat history)

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Header with context chips and clear button
            HStack {
                Text("AI Copilot")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !chatVM.messages.isEmpty {
                    Button("Clear") { chatVM.clearHistory() }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            Divider()

            // Chat messages (scrollable, limited height)
            if chatVM.messages.isEmpty {
                HStack(spacing: 8) {
                    Text("Ask me anything about your infrastructure, tickets, alerts, or procedures.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(chatVM.messages) { msg in
                                compactMessageRow(msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .onChange(of: chatVM.messages.count) {
                        if let last = chatVM.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let error = chatVM.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
        .frame(maxHeight: 300)  // limit expanded height — don't take over the whole screen
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Compact Message Row (for the expanded bar)

    private func compactMessageRow(_ msg: CopilotMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == "user" {
                Image(systemName: "person.circle.fill")
                    .font(.caption).foregroundStyle(.accentColor)
            } else {
                Image(systemName: "sparkles")
                    .font(.caption).foregroundStyle(.purple)
            }
            Text(msg.content)
                .font(.caption)
                .foregroundStyle(msg.role == "user" ? .primary : .secondary)
                .textSelection(.enabled)
                .lineLimit(msg.role == "user" ? 2 : 8)
        }
    }
}
```

### Phase 48C: Place the AI Bar in the Main Layout

In `ContentView.swift`, add the AI bar at the bottom of the entire layout, below the detail pane:

```swift
var body: some View {
    VStack(spacing: 0) {
        NavigationSplitView {
            SidebarView()
        } detail: {
            // ... existing detail routing
        }

        // Persistent AI bar — always visible at the bottom
        AIBar()
            .environmentObject(appState)
            .environmentObject(chatVM)
    }
}
```

The AI bar sits **below** the `NavigationSplitView`, so it's visible regardless of which sidebar section is selected. It's part of the window chrome, not the content.

### Phase 48D: Keyboard Shortcut ⌘/ to Focus the AI Bar

Add a keyboard shortcut that focuses the AI bar input field from anywhere:

1. **In the `CommandMenu` (BoomiSREApp.swift):**
   ```swift
   Button("AI Copilot") {
       // Post a notification to focus the AI bar
       NotificationCenter.default.post(name: .focusAIBar, object: nil)
   }
   .keyboardShortcut("/", modifiers: .command)
   ```

2. **In `AIBar`, listen for the notification:**
   ```swift
   .onReceive(NotificationCenter.default.publisher(for: .focusAIBar)) { _ in
       isInputFocused = true
       if !isExpanded { withAnimation { isExpanded = true } }
   }
   ```

3. **Define the notification name:**
   ```swift
   extension Notification.Name {
       static let focusAIBar = Notification.Name("focusAIBar")
   }
   ```

This means from ANY screen, ⌘/ opens the AI bar and focuses the input — the SRE starts typing immediately.

### Phase 48E: Context-Aware Prompts

The AI bar should know what screen the SRE is currently viewing and inject that context:

1. **Add `currentScreenContext` to AppState:**
   ```swift
   @Published var currentScreenContext: String = ""
   // Examples: "Viewing On-Call schedules", "Viewing AWS Health for CAM",
   //           "Viewing PR #23769 in apim-sre-terraform-iac"
   ```

2. **Each detail view sets the context on appear:**
   ```swift
   // In AlertsOnCallView:
   .onAppear { appState.currentScreenContext = "Viewing Alerts & On-Call" }

   // In IncidentCommandView:
   .onAppear { appState.currentScreenContext = "Viewing Incidents" }

   // In MyWorkView:
   .onAppear { appState.currentScreenContext = "Viewing My Work — Tickets" }
   ```

3. **ChatViewModel uses the context in its system prompt:**
   ```swift
   // In the send() method, include screen context:
   let screenContext = appState.currentScreenContext.isEmpty ? "" :
       "\n\nThe user is currently \(appState.currentScreenContext)."
   // Append to system prompt
   ```

This way when an SRE is looking at the On-Call page and types "what does this alert mean?", the AI knows they're on the On-Call page and can reference the visible alerts.

### Phase 48F: Keep CopilotChatView as a Full-Screen Option

The full `CopilotChatView` in the Knowledge & Tools tab should still work — it's useful for longer conversations. But now it shares the same `ChatViewModel`, so the conversation started in the bottom bar carries over to the full view and vice versa.

Update `CopilotChatView` to use `@EnvironmentObject var viewModel: ChatViewModel` instead of `@StateObject`. The view itself doesn't need changes — it just reads from the shared ViewModel.

---

## Build & Release

After making all changes:
1. Run `swift build -c release` to verify the release build compiles. Fix any errors.
2. Run `swift build` to verify the debug build.
3. Commit with message: "Add persistent AI bar — Copilot available on every screen via ⌘/"
4. `git push origin main`
5. `bash build_app.sh`
6. `bash release.sh`
7. Verify with `gh release list --limit 1`

If any step fails, fix the issue and retry before moving on. Do not skip steps.
