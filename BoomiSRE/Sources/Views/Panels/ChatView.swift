import SwiftUI
import WebKit

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = true

    private var chatURL: URL {
        // Use the user's email index (u/0) for the primary account
        URL(string: "https://mail.google.com/mail/u/0/#chat/home")!
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Text("Google Chat")
                    .font(.title2.bold())
                if !appState.googleEmail.isEmpty {
                    Text(appState.googleEmail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                if isLoading {
                    ProgressView().scaleEffect(0.6)
                    Text("Loading...").font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    NSWorkspace.shared.open(chatURL)
                } label: {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Embedded Google Chat via WebView
            GoogleChatWebView(url: chatURL, isLoading: $isLoading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - WebView wrapper for Google Chat

struct GoogleChatWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        // Pretend to be Chrome so Google doesn't block the embedded view
        config.applicationNameForUserAgent = "Chrome/120.0.0.0"

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        // Only reload if URL changed
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: GoogleChatWebView

        init(_ parent: GoogleChatWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        // Allow navigation to Google auth pages
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host ?? ""
                // Allow Google domains
                if host.hasSuffix("google.com") || host.hasSuffix("googleapis.com") || host.hasSuffix("gstatic.com") || host.hasSuffix("googleusercontent.com") {
                    decisionHandler(.allow)
                    return
                }
                // External links: open in browser
                if navigationAction.navigationType == .linkActivated {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}
