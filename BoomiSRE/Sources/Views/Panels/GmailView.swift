import SwiftUI
import WebKit

struct GmailView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = GmailViewModel()
    @State private var showAddQuery = false
    @State private var newQueryName = ""
    @State private var newQueryValue = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if vm.isLoading && vm.messages.isEmpty {
                VStack { Spacer(); ProgressView().scaleEffect(1.5); Text("Loading emails...").font(.headline).foregroundStyle(.secondary); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.messages.isEmpty {
                VStack(spacing: 12) { Spacer()
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(.red)
                    Text(error).font(.callout).foregroundStyle(.secondary).frame(maxWidth: 500).multilineTextAlignment(.center).textSelection(.enabled)
                    Button("Retry") { vm.fetch(credentials: appState.googleCredentials) }.buttonStyle(.borderedProminent)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.messages.isEmpty {
                VStack(spacing: 12) { Spacer()
                    Image(systemName: "envelope.open").font(.system(size: DesignTokens.emptyIconSize)).foregroundStyle(.secondary)
                    Text("No messages").font(.headline).foregroundStyle(.secondary)
                    Text("Try a different filter or refresh.").font(.callout).foregroundStyle(.tertiary)
                    Button("Refresh") { vm.fetch(credentials: appState.googleCredentials) }.buttonStyle(.bordered)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    messageList
                        .frame(minWidth: 320, idealWidth: 400, maxWidth: 500)
                    readingPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if vm.messages.isEmpty { vm.fetch(credentials: appState.googleCredentials) }
        }
        .onChange(of: appState.refreshTrigger) { vm.fetch(credentials: appState.googleCredentials) }
        .sheet(isPresented: $showAddQuery) { addQuerySheet }
    }

    // MARK: - Add Query Sheet

    private var addQuerySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Gmail Query").font(.title3.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("e.g. Team Alerts", text: $newQueryName)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Gmail Query").font(.caption.bold()).foregroundStyle(.secondary)
                TextField("e.g. from:alerts@boomi.com is:unread", text: $newQueryValue)
                    .textFieldStyle(.roundedBorder)
                Text("Uses Gmail search syntax: is:unread, from:, to:, subject:, label:, has:attachment, etc.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            HStack {
                Button("Cancel") { showAddQuery = false }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    let q = newQueryValue.trimmingCharacters(in: .whitespaces)
                    let n = newQueryName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty {
                        appState.gmailSavedQueries.append(
                            GmailSavedQuery(name: n, query: q, icon: "magnifyingglass"))
                        appState.saveConfig()
                        vm.query = q
                        vm.fetch(credentials: appState.googleCredentials)
                    }
                    newQueryName = ""; newQueryValue = ""
                    showAddQuery = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newQueryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            newQueryValue = vm.query
            newQueryName = ""
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Gmail")
                .font(.title2.bold())

            if !appState.googleEmail.isEmpty {
                Text(appState.googleEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Saved query picker
            Picker("", selection: $vm.query) {
                ForEach(appState.gmailSavedQueries) { sq in
                    Label(sq.name, systemImage: sq.icon).tag(sq.query)
                }
            }
            .frame(width: 140)
            .onChange(of: vm.query) { vm.fetch(credentials: appState.googleCredentials) }

            // Custom query field
            TextField("Gmail search query…", text: $vm.customQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit {
                    vm.query = vm.customQuery
                    vm.fetch(credentials: appState.googleCredentials)
                }

            Menu {
                Button { showAddQuery = true } label: {
                    Label("Save Current Query…", systemImage: "plus")
                }
                if appState.gmailSavedQueries.count > GmailSavedQuery.defaults.count {
                    Divider()
                    ForEach(appState.gmailSavedQueries.filter { sq in
                        !GmailSavedQuery.defaults.contains(where: { $0.query == sq.query && $0.name == sq.name })
                    }) { sq in
                        Button(role: .destructive) {
                            appState.gmailSavedQueries.removeAll { $0.id == sq.id }
                            appState.saveConfig()
                        } label: {
                            Label("Remove \"\(sq.name)\"", systemImage: "trash")
                        }
                    }
                }
                Divider()
                Button {
                    appState.gmailSavedQueries = GmailSavedQuery.defaults
                    appState.saveConfig()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

            // Actions on selected message
            if vm.selectedId != nil {
                Divider().frame(height: 20)

                Button { vm.markRead(credentials: appState.googleCredentials) } label: {
                    Label("Mark Read", systemImage: "envelope.open")
                }
                .help("Mark as read")
                .accessibilityLabel("Mark as read")
                .disabled(!(vm.selectedMessage?.isUnread ?? false))

                Button { vm.archive(credentials: appState.googleCredentials) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("Archive")
                .accessibilityLabel("Archive message")

                Button { vm.toggleStarAction(credentials: appState.googleCredentials) } label: {
                    Label("Star", systemImage: (vm.selectedMessage?.isStarred ?? false) ? "star.fill" : "star")
                }
                .help("Toggle star")
                .accessibilityLabel("Toggle star")
            }

            Divider().frame(height: 20)

            Button { vm.fetch(credentials: appState.googleCredentials) } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(vm.isLoading)

            if vm.isLoading { ProgressView().scaleEffect(0.6) }

            Text("\(vm.messages.count) messages")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Message List

    private var messageList: some View {
        List(vm.messages, selection: $vm.selectedId) { msg in
            messageRow(msg)
                .tag(msg.id)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .onChange(of: vm.selectedId) {
            if let id = vm.selectedId {
                vm.loadFullMessage(id: id, credentials: appState.googleCredentials)
            }
        }
    }

    private func messageRow(_ msg: GmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if msg.isUnread {
                    Circle().fill(.blue).frame(width: 8, height: 8)
                } else {
                    Circle().fill(.clear).frame(width: 8, height: 8)
                }
                if msg.isStarred {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
                Text(msg.senderName)
                    .font(msg.isUnread ? .callout.bold() : .callout)
                    .lineLimit(1)
                Spacer()
                Text(formatDate(msg.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(msg.subject.isEmpty ? "(no subject)" : msg.subject)
                .font(.caption)
                .foregroundStyle(msg.isUnread ? .primary : .secondary)
                .lineLimit(1)
            Text(msg.snippet)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Reading Pane

    private var readingPane: some View {
        Group {
            if vm.isLoadingBody {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if let full = vm.fullMessage {
                VStack(alignment: .leading, spacing: 0) {
                    // Header (fixed, non-scrolling)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(full.message.subject.isEmpty ? "(no subject)" : full.message.subject)
                            .font(.title3.bold())
                            .textSelection(.enabled)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                headerField("From", value: full.message.from)
                                headerField("To", value: full.message.to)
                                if !full.message.cc.isEmpty {
                                    headerField("Cc", value: full.message.cc)
                                }
                            }
                            Spacer()
                            Text(full.message.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(full.message.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                    Divider()

                    // Body (fills remaining space)
                    if !full.bodyHTML.isEmpty {
                        HTMLView(html: full.bodyHTML)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !full.bodyText.isEmpty {
                        ScrollView {
                            Text(full.bodyText)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("(empty message)")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "envelope.open").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Select a message to read").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func headerField(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Formatters.timeOnly.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), date > weekAgo {
            return Formatters.weekday.string(from: date)
        } else {
            return Formatters.monthDay.string(from: date)
        }
    }
}

// MARK: - HTML Rendering (WKWebView wrapper)

struct HTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // Wrap in a basic style for readability
        let styled = """
        <html><head><meta charset="utf-8">
        <style>
            body { font-family: -apple-system, sans-serif; font-size: 13px;
                   color: #333; background: transparent; padding: 0; margin: 0;
                   word-wrap: break-word; }
            @media (prefers-color-scheme: dark) {
                body { color: #ddd; }
                a { color: #6cb4ff; }
            }
            img { max-width: 100%; height: auto; }
            blockquote { border-left: 3px solid #ccc; margin: 8px 0; padding-left: 12px; color: #888; }
        </style></head><body>\(html)</body></html>
        """
        wv.loadHTMLString(styled, baseURL: nil)
    }
}

// MARK: - ViewModel

@MainActor
final class GmailViewModel: ObservableObject {
    @Published var messages: [GmailMessage] = []
    @Published var selectedId: String?
    @Published var fullMessage: GmailFullMessage?
    @Published var isLoading = false
    @Published var isLoadingBody = false
    @Published var errorMessage: String?
    @Published var query: String = "is:unread"
    @Published var customQuery: String = ""

    private let service = GoogleService()

    var selectedMessage: GmailMessage? {
        messages.first { $0.id == selectedId }
    }

    func fetch(credentials: GoogleCredentials?) {
        guard let creds = credentials else { errorMessage = "Google not configured."; return }
        isLoading = true; errorMessage = nil
        let q = query
        Task {
            do {
                let msgs = try await service.listMessages(credentials: creds, query: q, maxResults: 50)
                self.messages = msgs; self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription; self.isLoading = false
            }
        }
    }

    func loadFullMessage(id: String, credentials: GoogleCredentials?) {
        guard let creds = credentials else { return }
        isLoadingBody = true; fullMessage = nil
        Task {
            do {
                let full = try await service.getFullMessage(credentials: creds, id: id)
                self.fullMessage = full; self.isLoadingBody = false
                // Auto-mark as read
                if full.message.isUnread {
                    try? await service.markAsRead(credentials: creds, id: id)
                    if let idx = messages.firstIndex(where: { $0.id == id }) {
                        let m = messages[idx]
                        messages[idx] = GmailMessage(
                            id: m.id, threadId: m.threadId, subject: m.subject,
                            from: m.from, to: m.to, cc: m.cc,
                            snippet: m.snippet, date: m.date, dateString: m.dateString,
                            isUnread: false, isStarred: m.isStarred, labelIds: m.labelIds.filter { $0 != "UNREAD" }
                        )
                    }
                }
            } catch {
                self.isLoadingBody = false
            }
        }
    }

    func markRead(credentials: GoogleCredentials?) {
        guard let creds = credentials, let id = selectedId else { return }
        Task {
            try? await service.markAsRead(credentials: creds, id: id)
            if let idx = messages.firstIndex(where: { $0.id == id }) {
                let m = messages[idx]
                messages[idx] = GmailMessage(
                    id: m.id, threadId: m.threadId, subject: m.subject,
                    from: m.from, to: m.to, cc: m.cc,
                    snippet: m.snippet, date: m.date, dateString: m.dateString,
                    isUnread: false, isStarred: m.isStarred, labelIds: m.labelIds.filter { $0 != "UNREAD" }
                )
            }
        }
    }

    func archive(credentials: GoogleCredentials?) {
        guard let creds = credentials, let id = selectedId else { return }
        Task {
            try? await service.archiveMessage(credentials: creds, id: id)
            messages.removeAll { $0.id == id }
            selectedId = nil; fullMessage = nil
        }
    }

    func toggleStarAction(credentials: GoogleCredentials?) {
        guard let creds = credentials, let id = selectedId,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let wasStarred = messages[idx].isStarred
        Task {
            try? await service.toggleStar(credentials: creds, id: id, starred: !wasStarred)
            let m = messages[idx]
            messages[idx] = GmailMessage(
                id: m.id, threadId: m.threadId, subject: m.subject,
                from: m.from, to: m.to, cc: m.cc,
                snippet: m.snippet, date: m.date, dateString: m.dateString,
                isUnread: m.isUnread, isStarred: !wasStarred, labelIds: m.labelIds
            )
        }
    }
}
