//
//  SitePrefsView.swift
//  IINA+
//
//  Created by xjbeta on 2025/8/9.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import SwiftUI

struct SitePrefsView: View {
    
    enum Status {
        case loading
        case error
        case loggedIn
        case loggedOut
    }
    
    enum BiliCodec: Int, CaseIterable, Identifiable {
        var id: Int {
            rawValue
        }
        case av1, hevc, avc
        var name: String {
            switch self {
            case .av1:
                return "AV1"
            case .hevc:
                return "HEVC"
            case .avc:
                return "AVC"
            }
        }
    }
    
    @State var biliStatus: Status = .loading
    @State var biliUserName = ""
    @State var biliLoginSheet = false

    @State var douyuStatus: Status = .loading
    @State var douyuUserName = ""
    @State var douyuLoginSheet = false

    @AppStorage(PreferenceKeys.bilibiliCodec.rawValue)
    private var bilibiliCodec: Int = BiliCodec.avc.id
    
    @AppStorage(PreferenceKeys.bililiveHevc.rawValue)
    private var bililiveHevc: Bool = false
    
    @AppStorage(PreferenceKeys.bilibiliHTMLDecoder.rawValue)
    private var bilibiliHTMLDecoder: Bool = false
    
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            douyuSection

            Divider()
                .gridCellUnsizedAxes(.horizontal)

            biliSection

            Divider()
                .gridCellUnsizedAxes(.horizontal)

            GridRow {
                LocalizedText("QVl-54-yko.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Picker("", selection: $bilibiliCodec) {
                    ForEach(BiliCodec.allCases) {
                        Text($0.name).tag($0.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            
            GridRow(alignment: .center) {
                LocalizedText("iTL-J0-MpL.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Toggle(isOn: $bililiveHevc) {
                }
                .toggleStyle(.checkbox)
            }
            
            GridRow(alignment: .center) {
                LocalizedText("vR2-ZU-hgL.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Toggle(isOn: $bilibiliHTMLDecoder) {
                }
                .toggleStyle(.checkbox)
            }
        }
        .onAppear {
            initStatus()
            initDouyuStatus()
        }
        .sheet(isPresented: $biliLoginSheet) {
            BiliLoginSheetView(
                loginSheet: $biliLoginSheet,
                status: $biliStatus,
                userName: $biliUserName)
        }
        .sheet(isPresented: $douyuLoginSheet) {
            DouyuLoginSheetView(
                loginSheet: $douyuLoginSheet,
                status: $douyuStatus)
        }
        .padding(EdgeInsets(top: 28, leading: 35, bottom: 28, trailing: 35))
        .fixedSize()
    }
    
    @ViewBuilder
    private var douyuSection: some View {
        if douyuStatus == .loggedOut {
            GridRow {
                Text("Douyu:")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                douyuStatusText
            }
        } else {
            GridRow {
                Text("Douyu:")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                douyuStatusText
            }
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                douyuStatusAction
            }
        }
    }
    
    @ViewBuilder
    private var biliSection: some View {
        if biliStatus == .loggedOut {
            GridRow {
                Text("Bilibili:")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                biliStatusText
            }
        } else {
            GridRow {
                Text("Bilibili:")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                biliStatusText
            }
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                biliStatusAction
            }
        }
    }
    
    @ViewBuilder
    private var douyuStatusText: some View {
        switch douyuStatus {
        case .loggedIn:
            Text(douyuUserName)
        case .loggedOut:
            Button {
                douyuLoginSheet = true
            } label: {
                Text("Login")
                    .padding(.horizontal, 8)
            }
        case .loading, .error:
            Text("")
        }
    }
    
    @ViewBuilder
    private var douyuStatusAction: some View {
        switch douyuStatus {
        case .loading:
            ProgressView()
        case .error:
            Button {
                initDouyuStatus()
            } label: {
                Text("Retry")
                    .padding(.horizontal, 8)
            }
        case .loggedIn:
            Button {
                Task {
                    do {
                        try await Douyu().logout()
                        initDouyuStatus()
                    } catch let error {
                        Log("Logout douyu error: \(error)")
                        douyuStatus = .error
                    }
                }
            } label: {
                LocalizedText("Uo2-li-KKl.title", tableName: .preferences)
            }
        case .loggedOut:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var biliStatusText: some View {
        switch biliStatus {
        case .loggedIn:
            Text(biliUserName)
        case .error:
            LocalizedText("HyX-XU-Dxf.title", tableName: .preferences)
        case .loggedOut:
            Button {
                biliLoginSheet = true
            } label: {
                Text("Login")
                    .padding(.horizontal, 8)
            }
        case .loading:
            Text("")
        }
    }
    
    @ViewBuilder
    private var biliStatusAction: some View {
        switch biliStatus {
        case .loading:
            ProgressView()
        case .error:
            Button {
                initStatus()
            } label: {
                LocalizedText("6g4-C2-AIh.title", tableName: .preferences)
                    .padding(.horizontal, 8)
            }
        case .loggedIn:
            Button {
                Task {
                    do {
                        try await Bilibili.shared.logout()
                        initStatus()
                    } catch let error {
                        Log("Logout bilibili error: \(error)")
                        biliStatus = .error
                    }
                }
            } label: {
                LocalizedText("Uo2-li-KKl.title", tableName: .preferences)
            }
        case .loggedOut:
            EmptyView()
        }
    }
    
    func initStatus() {
        biliStatus = .loading
        Task {
            do {
                let re = try await Bilibili.shared.isLogin()
                biliStatus = re.0 ? .loggedIn : .loggedOut
                biliUserName = re.1
            } catch let error {
                Log("Init bilibili status error: \(error)")
                biliStatus = .error
            }
        }
    }

    func initDouyuStatus() {
        douyuStatus = .loading
        Task {
            do {
                let re = try await Douyu().isLogin()
                douyuStatus = re.0 ? .loggedIn : .loggedOut
                douyuUserName = re.1
            } catch let error {
                Log("Init douyu status error: \(error)")
                douyuStatus = .error
            }
        }
    }
}

#Preview {
    SitePrefsView()
}
