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

    @AppStorage(PreferenceKeys.bilibiliCodec.rawValue)
    private var bilibiliCodec: Int = BiliCodec.avc.id
    
    @AppStorage(PreferenceKeys.bililiveHevc.rawValue)
    private var bililiveHevc: Bool = false
    
    @AppStorage(PreferenceKeys.bilibiliHTMLDecoder.rawValue)
    private var bilibiliHTMLDecoder: Bool = false
    
    var body: some View {
        VStack {
            switch biliStatus {
            case .loading:
                ProgressView()
            case .error:
                VStack {
                    LocalizedText("HyX-XU-Dxf.title", tableName: .preferences)
                        .font(.title2)
                    
                    Button {
                        initStatus()
                    } label: {
                        LocalizedText("6g4-C2-AIh.title", tableName: .preferences)
                            .padding(.horizontal, 8)
                    }
                }
            case .loggedIn:
                VStack {
                    Text(biliUserName)
                        .font(.title2)
                    
                    Button {
                        Task {
                            do {
                                let bilibili = await Processes.shared.videoDecoder.bilibili
                                try await bilibili.logout()
                                initStatus()
                            } catch let error {
                                Log("Logout bilibili error: \(error)")
                                biliStatus = .error
                            }
                        }
                    } label: {
                        LocalizedText("Uo2-li-KKl.title", tableName: .preferences)
                            .padding(.horizontal, 8)
                    }
                    
                }
            case .loggedOut:
                Button {
                    biliLoginSheet = true
                } label: {
                    LocalizedText("tFa-ZK-G6I.title", tableName: .preferences)
                        .padding(.horizontal, 8)
                }
            }
            
            Divider()
                .padding(EdgeInsets.init(top: 12, leading: -8, bottom: 12, trailing: -8))
        
            Grid(alignment: .leadingFirstTextBaseline) {
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
        }
        .onAppear {
            initStatus()
        }
        .sheet(isPresented: $biliLoginSheet) {
            BiliLoginSheetView(
                loginSheet: $biliLoginSheet,
                status: $biliStatus,
                userName: $biliUserName)
        }
        .padding(EdgeInsets(top: 28, leading: 35, bottom: 28, trailing: 35))
        .fixedSize()
    }
    
    func initStatus() {
        biliStatus = .loading
        Task {
            do {
                let bilibili = await Processes.shared.videoDecoder.bilibili
                let re = try await bilibili.isLogin()
                biliStatus = re.0 ? .loggedIn : .loggedOut
                biliUserName = re.1
            } catch let error {
                Log("Init bilibili status error: \(error)")
                biliStatus = .error
            }
        }
    }
}

#Preview {
    SitePrefsView()
}
