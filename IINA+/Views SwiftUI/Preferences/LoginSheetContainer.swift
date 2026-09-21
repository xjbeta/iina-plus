//
//  LoginSheetContainer.swift
//  IINA+
//
//  Created by xjbeta on 2026/9/22.
//  Copyright © 2026 xjbeta. All rights reserved.
//

import SwiftUI

// Shared login sheet container that fixes the WebView size and layout.
struct LoginSheetContainer<Content: View>: View {

    let size: CGSize
    let content: Content
    let onCancel: () -> Void

    init(size: CGSize, onCancel: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.size = size
        self.onCancel = onCancel
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content
            Button("Cancel") {
                onCancel()
            }
            .padding()
        }
        .frame(width: size.width, height: size.height)
    }
}

#Preview {
    LoginSheetContainer(size: CGSize(width: 500, height: 700), onCancel: {}) {
        Text("Login")
    }
}