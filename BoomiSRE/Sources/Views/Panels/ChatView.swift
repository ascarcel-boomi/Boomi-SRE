import SwiftUI

/// Native Google Chat viewer — uses Google Chat API via GoogleService.
struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var spaces: [ChatSpace] = []
    @State private var selectedSpace: ChatSpace?
    @State private var messages: [ChatMessage] = []
    @State private var isLoadingSpaces = false
    @State private var isLoadingMessages = false
    @State private var error: String?

    private let googleService = GoogleService()

    var body: some View {
        HSplitView {
            // Left: space list
            VStack(spacing: 0) {
                HStack {
                    Text("Google Chat").font(.headline)
                    Spacer()
                    if isLoadingSpaces { ProgressView().scaleEffect(0.7) }
                    Button { Task { await loadSpaces() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Refresh spaces")
                }
                .padding(12)

                Divider()

                if spaces.isEmpty && !isLoadingSpaces {
                    VStack(spacing: 8) {
                        Spacer()
                        if let err = error {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title).foregroundStyle(.red)
                            Text(err)
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title).foregroundStyle(.secondary)
                            Text("No chat spaces found")
                                .font(.callout).foregroundStyle(.secondary)
                            if appState.googleCredentials == nil {
                                Text("Configure Google credentials in Settings to use Google Chat.")
                                    .font(.caption).foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        Spacer()
                    }.padding()
                } else {
                    List(selection: $selectedSpace) {
                        ForEach(Array(spaces.enumerated()), id: \.element.id) { idx, space in
                            HStack(spacing: 8) {
                                Image(systemName: spaceIcon(space))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(space.displayName)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text(spaceTypeLabel(space))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(space)
                            .listRowBackground(idx.isMultiple(of: 2)
                                ? Color(nsColor: .controlBackgroundColor).opacity(0.4)
                                : Color.clear)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            // Right: messages
            VStack(spacing: 0) {
                if let space = selectedSpace {
                    // Header
                    HStack {
                        Image(systemName: spaceIcon(space))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(space.displayName).font(.title3.bold())
                            Text(spaceTypeLabel(space))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isLoadingMessages { ProgressView().scaleEffect(0.7) }
                        Button { Task { await loadMessages(space: space) } } label: {
                            Image(systemName: "arrow.clockwise")
                        }.buttonStyle(.plain)
                        Button {
                            // Open in browser
                            let spaceId = space.name.replacingOccurrences(of: "spaces/", with: "")
                            if let url = URL(string: "https://chat.google.com/room/\(spaceId)") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("Open in Browser", systemImage: "arrow.up.right.square")
                        }
                    }
                    .padding(16)

                    Divider()

                    // Messages
                    if messages.isEmpty && !isLoadingMessages {
                        VStack(spacing: 8) {
                            Spacer()
                            Text("No messages")
                                .font(.headline).foregroundStyle(.secondary)
                            Text("This space may be empty or require additional Chat API permissions.")
                                .font(.caption).foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(messages.reversed().enumerated()), id: \.element.id) { idx, msg in
                                    messageRow(msg, isEven: idx.isMultiple(of: 2))
                                }
                            }
                            .padding(16)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("Select a space to view messages")
                            .font(.headline).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if spaces.isEmpty { Task { await loadSpaces() } }
        }
        .onChange(of: selectedSpace) {
            if let space = selectedSpace {
                Task { await loadMessages(space: space) }
            }
        }
    }

    // MARK: - Data Loading

    private func loadSpaces() async {
        guard let creds = appState.googleCredentials else {
            error = "Google credentials not configured. Set up Google Workspace in Settings."
            return
        }
        isLoadingSpaces = true; error = nil
        do {
            spaces = try await googleService.listChatSpaces(credentials: creds)
        } catch {
            self.error = "Failed to load spaces: \(error.localizedDescription)"
        }
        isLoadingSpaces = false
    }

    private func loadMessages(space: ChatSpace) async {
        guard let creds = appState.googleCredentials else { return }
        messages = []; isLoadingMessages = true
        do {
            messages = try await googleService.listChatMessages(
                credentials: creds, spaceName: space.name, maxResults: 50)
        } catch {
            self.error = "Failed to load messages: \(error.localizedDescription)"
        }
        isLoadingMessages = false
    }

    // MARK: - Message Row

    private func messageRow(_ msg: ChatMessage, isEven: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: msg.senderType == "BOT" ? "cpu" : "person.circle.fill")
                .foregroundStyle(msg.senderType == "BOT" ? .orange : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(msg.senderName.isEmpty ? "Unknown" : msg.senderName)
                        .font(.callout.bold())
                    if !msg.createTime.isEmpty {
                        Text(formatTime(msg.createTime))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(msg.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isEven
            ? Color(nsColor: .controlBackgroundColor).opacity(0.3)
            : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private func spaceIcon(_ space: ChatSpace) -> String {
        switch space.spaceType {
        case "DIRECT_MESSAGE": return "person"
        case "GROUP_CHAT": return "person.2"
        case "SPACE": return "number"
        default: return "bubble.left"
        }
    }

    private func spaceTypeLabel(_ space: ChatSpace) -> String {
        switch space.spaceType {
        case "DIRECT_MESSAGE": return "Direct Message"
        case "GROUP_CHAT": return "Group Chat"
        case "SPACE": return "Space"
        default: return space.spaceType
        }
    }

    private func formatTime(_ isoString: String) -> String {
        // "2026-03-17T08:30:00.000Z" → "Mar 17, 8:30 AM"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
        return String(isoString.prefix(16))
    }
}
