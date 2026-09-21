//
//  DouyuLoginSheetView.swift
//  IINA+
//
//  Created by xjbeta on 2026/9/22.
//  Copyright © 2026 xjbeta. All rights reserved.
//

import SwiftUI

struct DouyuLoginSheetView: View {

    @Binding var loginSheet: Bool
    @Binding var status: SitePrefsView.Status

    var body: some View {
        LoginSheetContainer(size: CGSize(width: 840, height: 600), onCancel: {
            loginSheet = false
        }) {
            LoginWebView(
                url: URL(string: "https://passport.douyu.com/index/login?client_id=1")!,
                userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36",
                successCookies: ["dy_auth", "acf_auth"],
                loginHandler: { isLogin in
                    defer {
                        loginSheet = false
                    }
                    guard isLogin else {
                        status = .error
                        return
                    }
                    do {
                        let re = try await Douyu().isLogin()
                        status = re.0 ? .loggedIn : .error
                    } catch let error {
                        Log("Douyu login error: \(error)")
                        status = .error
                    }
                })
        }
    }
}

#Preview {
    DouyuLoginSheetView(loginSheet: .init(get: {
        true
    }, set: { _ in
    }), status: .init(get: {
        .error
    }, set: { _ in
    }))
}