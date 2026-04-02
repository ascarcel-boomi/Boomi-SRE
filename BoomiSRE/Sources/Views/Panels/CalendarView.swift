import SwiftUI
import WebKit

struct CalendarView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = CalendarViewModel()
    @State private var selectedEventId: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if vm.isLoading && vm.events.isEmpty {
                VStack { Spacer(); ProgressView().scaleEffect(1.5)
                    Text("Loading calendar...").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.events.isEmpty {
                VStack(spacing: 12) { Spacer()
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 48)).foregroundStyle(.red)
                    Text(error).font(.callout).foregroundStyle(.secondary).frame(maxWidth: 500).multilineTextAlignment(.center).textSelection(.enabled)
                    Button("Retry") { vm.fetch(credentials: appState.googleCredentials) }.buttonStyle(.borderedProminent)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.events.isEmpty {
                VStack(spacing: 12) { Spacer()
                    Image(systemName: "calendar").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("No upcoming events").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    eventList
                        .frame(minWidth: 350, idealWidth: 450, maxWidth: 600)
                    eventDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if vm.events.isEmpty { vm.fetch(credentials: appState.googleCredentials) }
        }
        .onChange(of: appState.refreshTrigger) { vm.fetch(credentials: appState.googleCredentials) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Calendar")
                .font(.title2.bold())
            if !appState.googleEmail.isEmpty {
                Text(appState.googleEmail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            Picker("Range", selection: $vm.daysAhead) {
                Text("Today").tag(1)
                Text("3 Days").tag(3)
                Text("This Week").tag(7)
                Text("2 Weeks").tag(14)
                Text("This Month").tag(30)
            }
            .frame(width: 140)
            .onChange(of: vm.daysAhead) { vm.fetch(credentials: appState.googleCredentials) }

            Button { vm.fetch(credentials: appState.googleCredentials) } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(vm.isLoading)

            if vm.isLoading { ProgressView().scaleEffect(0.6) }

            Text("\(vm.events.count) events")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Event List (grouped by day)

    private var eventList: some View {
        List(selection: $selectedEventId) {
            ForEach(groupedByDay, id: \.key) { day, events in
                Section {
                    ForEach(events) { event in
                        eventRow(event)
                            .tag(event.id)
                    }
                } header: {
                    Text(day).font(.headline)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var groupedByDay: [(key: String, value: [CalendarEvent])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let displayFmt = DateFormatter()
        displayFmt.dateStyle = .full

        var groups: [(String, String, [CalendarEvent])] = []
        var current = ""
        var currentDisplay = ""
        var currentEvents: [CalendarEvent] = []

        for event in vm.events {
            let dateStr = String(event.startDateTime.prefix(10))
            if dateStr != current {
                if !currentEvents.isEmpty { groups.append((current, currentDisplay, currentEvents)) }
                current = dateStr
                if let date = fmt.date(from: dateStr) {
                    if Calendar.current.isDateInToday(date) {
                        currentDisplay = "Today — \(displayFmt.string(from: date))"
                    } else if Calendar.current.isDateInTomorrow(date) {
                        currentDisplay = "Tomorrow — \(displayFmt.string(from: date))"
                    } else {
                        currentDisplay = displayFmt.string(from: date)
                    }
                } else { currentDisplay = dateStr }
                currentEvents = []
            }
            currentEvents.append(event)
        }
        if !currentEvents.isEmpty { groups.append((current, currentDisplay, currentEvents)) }
        return groups.map { (key: $0.1, value: $0.2) }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 10) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(eventColor(event))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    // Time
                    if event.isAllDay {
                        Text("All day")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .frame(width: 65, alignment: .leading)
                    } else {
                        Text(formatTime(event.startDateTime))
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 65, alignment: .leading)
                    }

                    Text(event.summary)
                        .font(.callout)
                        .lineLimit(1)

                    Spacer()

                    if !event.hangoutLink.isEmpty {
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if !event.isAllDay {
                        Text(formatDuration(start: event.startDateTime, end: event.endDateTime))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 8) {
                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if event.attendees.count > 1 {
                        Label("\(event.attendees.count)", systemImage: "person.2")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Event Detail

    private var eventDetail: some View {
        Group {
            if let id = selectedEventId, let event = vm.events.first(where: { $0.id == id }) {
                GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text(event.summary)
                            .font(.title2.bold())
                            .textSelection(.enabled)

                        // Time
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            if event.isAllDay {
                                Text("All day — \(formatFullDate(event.startDateTime))")
                                    .font(.body)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(formatFullDate(event.startDateTime))")
                                        .font(.body)
                                    Text("\(formatTime(event.startDateTime)) — \(formatTime(event.endDateTime))  (\(formatDuration(start: event.startDateTime, end: event.endDateTime)))")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Location
                        if !event.location.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(.red)
                                    .frame(width: 20)
                                Text(event.location)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                        }

                        // Meet link
                        if !event.hangoutLink.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "video.fill")
                                    .foregroundStyle(.green)
                                    .frame(width: 20)
                                Button {
                                    if let url = URL(string: event.hangoutLink) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Label("Join Google Meet", systemImage: "arrow.up.right")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }

                        // Organizer
                        if !event.organizer.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle")
                                    .foregroundStyle(.purple)
                                    .frame(width: 20)
                                VStack(alignment: .leading) {
                                    Text("Organizer").font(.caption).foregroundStyle(.secondary)
                                    Text(event.organizer).font(.body).textSelection(.enabled)
                                }
                            }
                        }

                        // Attendees
                        if !event.attendees.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "person.2")
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Attendees (\(event.attendees.count))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(event.attendees, id: \.self) { email in
                                        Text(email)
                                            .font(.callout)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }

                        // Description
                        if !event.description.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.caption).foregroundStyle(.secondary)
                                if event.description.contains("<") && event.description.contains(">") {
                                    CalendarHTMLView(html: event.description)
                                        .frame(minHeight: 120, maxHeight: 400)
                                } else {
                                    Text(event.description)
                                        .font(.body)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        // Open in Google Calendar
                        if !event.htmlLink.isEmpty {
                            Divider()
                            Button {
                                if let url = URL(string: event.htmlLink) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label("Open in Google Calendar", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                } // GeometryReader
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "calendar").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Select an event to view details").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func eventColor(_ event: CalendarEvent) -> Color {
        if event.isAllDay { return .orange }
        if !event.hangoutLink.isEmpty { return .green }
        return .blue
    }

    private func formatTime(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: iso) {
            let tf = DateFormatter(); tf.timeStyle = .short
            return tf.string(from: date)
        }
        if iso.count >= 16 { return String(iso.dropFirst(11).prefix(5)) }
        return iso
    }

    private func formatFullDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: iso) {
            let df = DateFormatter(); df.dateStyle = .full
            return df.string(from: date)
        }
        // All-day events use yyyy-MM-dd
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        if let date = df.date(from: String(iso.prefix(10))) {
            let display = DateFormatter(); display.dateStyle = .full
            return display.string(from: date)
        }
        return iso
    }

    private func formatDuration(start: String, end: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let s = fmt.date(from: start), let e = fmt.date(from: end) else { return "" }
        let mins = Int(e.timeIntervalSince(s) / 60)
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60; let rem = mins % 60
        return rem > 0 ? "\(hours)h \(rem)m" : "\(hours)h"
    }
}

// MARK: - HTML Rendering for Calendar event descriptions

struct CalendarHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
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
            p { margin: 4px 0; }
        </style></head><body>\(html)</body></html>
        """
        wv.loadHTMLString(styled, baseURL: nil)
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var daysAhead: Int = 7

    private let service = GoogleService()

    func fetch(credentials: GoogleCredentials?) {
        guard let creds = credentials else { errorMessage = "Google not configured."; return }
        isLoading = true; errorMessage = nil
        let days = daysAhead
        Task {
            do {
                let evts = try await service.listEvents(credentials: creds, maxResults: 100, daysAhead: days)
                self.events = evts; self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription; self.isLoading = false
            }
        }
    }
}
