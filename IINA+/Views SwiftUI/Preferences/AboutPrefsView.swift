//
//  AboutPrefsView.swift
//  IINA+
//
//  Created by xjbeta on 2025/8/10.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import SwiftUI

struct AboutPrefsView: View {
    
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown"
    }
    
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "version: \(version) (\(build))"
    }
    
    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ??
        "Copyright Unknown."
    }
    
    private let githubURL = URL(string: "https://github.com/xjbeta/iina-plus")!
    
    var body: some View {
        VStack(alignment: .center) {
            Image("WX_Payment")
                .resizable()
                .frame(width: 250, height: 250)
            
            Spacer(minLength: 12)
            
            HStack(alignment: .center) {
                Text(appName)
                    .font(.title2)
                    .fontWeight(.medium)
                
                Link(destination: githubURL) {
                    HStack(spacing: 2) {
                        Image(systemName: "link")
                        Text("GitHub")
                    }
                    .font(.callout)
                    .foregroundColor(.blue)
                }
            }
            
            Text(version)
            
            Text(copyright)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding(EdgeInsets(top: 28, leading: 35, bottom: 28, trailing: 35))
    }
}

#Preview {
    AboutPrefsView()
}
