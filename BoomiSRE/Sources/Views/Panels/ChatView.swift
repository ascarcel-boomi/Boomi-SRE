import SwiftUI
import WebKit

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = true
    @State private var showSignInBanner = false
    @State private var webViewRef: WKWebView?

    private let chatURL = URL(string: "https://chat.google.com/")!

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                Text("Google Chat").font(.title2.bold())
                if !appState.googleEmail.isEmpty {
                    Text(appState.googleEmail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.6) }
                Button {
                    webViewRef?.goBack()
                } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).disabled(webViewRef?.canGoBack == false)

                Button {
                    webViewRef?.goForward()
                } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).disabled(webViewRef?.canGoForward == false)

                Button {
                    webViewRef?.reload()
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Reload")

                Button {
                    NSWorkspace.shared.open(chatURL)
                } label: { Label("Open in Browser", systemImage: "arrow.up.right.square") }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider()

            // Sign-in banner
            if showSignInBanner {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
                    Text("Sign in to your Google account to view Chat. Your session will be remembered.")
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") { showSignInBanner = false }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                Divider()
            }

            GoogleChatWebView(url: chatURL, isLoading: $isLoading, showSignInBanner: $showSignInBanner, webViewRef: $webViewRef)
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
    @Binding var showSignInBanner: Bool
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()  // persistent session
        config.preferences.isElementFullscreenEnabled = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        wv.load(URLRequest(url: url))
        DispatchQueue.main.async { self.webViewRef = wv }
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) { }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: GoogleChatWebView

        init(_ parent: GoogleChatWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                // Show sign-in banner if we landed on an accounts.google.com page
                if let host = webView.url?.host, host.contains("accounts.google.com") {
                    self.parent.showSignInBanner = true
                } else {
                    self.parent.showSignInBanner = false
                }
            }
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
