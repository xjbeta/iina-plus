//
//  BiliLoginSheetView.swift
//  IINA+
//
//  Created by xjbeta on 2025/8/9.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import SwiftUI

struct BiliLoginSheetView: View {
    
    @Binding var loginSheet: Bool
    @Binding var status: SitePrefsView.Status
    @Binding var userName: String
    
    var body: some View {
        BiliLoginViewController {
            defer {
                loginSheet = false
            }
            guard let re = $0 else {
                status = .error
                return
            }
            status = re.0 ? .loggedIn : .loggedOut
            userName = re.1
        }
        .frame(width: 500, height: 700)
    }
}

#Preview {
    BiliLoginSheetView(loginSheet: .init(get: {
        true
    }, set: { _ in
        
    }), status: .init(get: {
        .error
    }, set: { _ in
    }), userName: .init(get: {
        ""
    }, set: { _ in
        
    }))
}
