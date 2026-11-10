import SwiftUI
import WebKit

struct LoginSite: Sendable {
    let title: String
    let url: URL
    let cookieDomain: String
    let signedInCookie: String
    let userAgent: String?

    static func site(for platform: Platform) -> LoginSite {
        switch platform {
        case .douyu:
            LoginSite(
                title: "登录斗鱼",
                url: URL(
                    string:
                        "https://passport.douyu.com/index/login?client_id=1&state=https%3A%2F%2Fwww.douyu.com%2F&type=login"
                )!,
                cookieDomain: "douyu.com", signedInCookie: "acf_uid", userAgent: nil)
        case .douyin:
            LoginSite(
                title: "登录抖音", url: URL(string: "https://www.douyin.com/")!, cookieDomain: "douyin.com",
                signedInCookie: "sessionid", userAgent: DouyinAPI.userAgent)
        }
    }
}

struct LoginSheet: View {
    let site: LoginSite
    let onSignedIn: ([String: String]) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(site.title).font(.headline)
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
            }
            .padding(Theme.Spacing.medium)
            LoginWebView(site: site, onSignedIn: onSignedIn)
        }
        .frame(width: Theme.Login.size.width, height: Theme.Login.size.height)
    }
}

private struct LoginWebView: NSViewRepresentable {
    let site: LoginSite
    let onSignedIn: ([String: String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(site: site, onSignedIn: onSignedIn)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = site.userAgent
        context.coordinator.observe(configuration.websiteDataStore.httpCookieStore)
        webView.load(URLRequest(url: site.url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: NSObject, WKHTTPCookieStoreObserver {
        private static let settleDelay = Duration.milliseconds(600)

        private let site: LoginSite
        private let onSignedIn: ([String: String]) -> Void
        private var store: WKHTTPCookieStore?
        private var isFinishing = false

        init(site: LoginSite, onSignedIn: @escaping ([String: String]) -> Void) {
            self.site = site
            self.onSignedIn = onSignedIn
        }

        func observe(_ store: WKHTTPCookieStore) {
            self.store = store
            store.add(self)
        }

        func stopObserving() {
            store?.remove(self)
            store = nil
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !isFinishing else { return }
            Task {
                guard siteCookies(in: await cookieStore.allCookies())[site.signedInCookie] != nil else { return }
                guard !isFinishing else { return }
                isFinishing = true
                try? await Task.sleep(for: Self.settleDelay)
                onSignedIn(siteCookies(in: await cookieStore.allCookies()))
            }
        }

        private func siteCookies(in cookies: [HTTPCookie]) -> [String: String] {
            var result: [String: String] = [:]
            for cookie in cookies where cookie.domain.hasSuffix(site.cookieDomain) && !cookie.value.isEmpty {
                result[cookie.name] = cookie.value
            }
            return result
        }
    }
}
