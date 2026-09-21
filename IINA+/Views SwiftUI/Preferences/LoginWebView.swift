//
//  LoginWebView.swift
//  IINA+
//
//  Created by xjbeta on 2026/9/22.
//  Copyright © 2026 xjbeta. All rights reserved.
//

import SwiftUI
import WebKit

// Loads the login URL and copies target session cookies into HTTPCookieStorage.shared.
struct LoginWebView: NSViewRepresentable {

    let url: URL
    let userAgent: String
    let successCookies: [String]
    let loginHandler: @MainActor (Bool) async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(successCookies: successCookies, loginHandler: loginHandler)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.customUserAgent = userAgent
        webView.load(URLRequest(url: url))
        context.coordinator.webView = webView
        Task { @MainActor in
            await context.coordinator.startPolling()
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }

    final class Coordinator: NSObject {
        let successCookies: [String]
        let loginHandler: @MainActor (Bool) async -> Void

        @MainActor
        var webView: WKWebView?

        @MainActor
        private var completed = false

        init(successCookies: [String], loginHandler: @escaping @MainActor (Bool) async -> Void) {
            self.successCookies = successCookies
            self.loginHandler = loginHandler
            super.init()
        }

        @MainActor
        func startPolling() async {
            while !completed {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await checkLogin()
            }
        }

        @MainActor
        func checkLogin() async {
            guard !completed, let webView else { return }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard cookies.contains(where: { successCookies.contains($0.name) }) else { return }

            completed = true
            cookies.forEach {
                HTTPCookieStorage.shared.setCookie($0)
            }
            await loginHandler(true)
        }
    }
}

#Preview {
    LoginWebView(
        url: URL(string: "https://www.douyu.com")!,
        userAgent: "Mozilla/5.0",
        successCookies: ["dy_auth"],
        loginHandler: { _ in })
    .frame(width: 500, height: 700)
}