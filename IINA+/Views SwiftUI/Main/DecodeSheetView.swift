//
//  DecodeSheetView.swift
//  IINA+
//
//  Created by xjbeta on 1/19/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import SwiftUI

struct DecodeSheetView: View {
    @Binding var isVisible: Bool
    @Binding var url: String
    
    
    enum DecodeState {
        case inited, decoding, selectP, result, error
    }
    
    @State private var state: DecodeState = .inited
    @State private var result: YouGetJSON?
    
    @State private var resultKeys: [String] = []
    
    
    private let proc = Processes.shared

    struct ResultItemView: View {
        let key: String
        var body: some View {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(key)
                    .padding(.leading, 4)
                Divider()
            }
            .padding(1)
            .contentShape(Rectangle())
            .frame(width: 180)
            .cornerRadius(5)
        }
    }
    
    var body: some View {
        VStack(alignment: state == .decoding ? .center : .leading) {
//            Text("Decoding...")
//                .font(.title)
            
            
            switch state {
            case .decoding:
                VStack {
                    Text("Decoding...")
                        .frame(width: 100)
                    ProgressView()
                }
                Spacer()
                    .frame(height: 15)
            case .selectP:
                EmptyView()
            case .result where resultKeys.count > 0:
                VStack(alignment: .leading) {
                    ForEach(resultKeys, id: \.self) { key in
                        ResultItemView(key: key)
                            .onTapGesture {
                                open(key)
                            }
                    }
                }
                .padding(8)
            default:
                EmptyView()
            }

            Button(action: {
                isVisible = false
            }) {
                Text("Cancel")
                    .frame(width: 50)
            }
            .keyboardShortcut(.cancelAction)
        }
//        .frame(width: 215)
        .padding()
        .onAppear {
            guard state == .inited else {
                return
            }
            state = .decoding
            
            proc.videoGet.decodeUrl(url).done(on: .main) {
                result = $0
                resultKeys = $0.videos.map({ $0.key })
                state = .result
            }.catch(on: .main) {
                state = .error
                print("Decode url errror: ", $0)
            }
        }
    }
    
    func open(_ key: String) {
        guard var json = result else {
            state = .error
            return
        }
        let videoGet = proc.videoGet
        let pref = Preferences.shared
        let site = SupportSites(url: url)
        
        videoGet.prepareVideoUrl(json, key).get {
            json = $0
        }.then { _ in
            videoGet.prepareDanmakuFile(json)
        }.done {
            // init Danmaku
            if pref.enableDanmaku,
               pref.livePlayer == .iina,
               proc.iinaArchiveType() != .normal {
                switch site {
                case .bilibili, .bangumi, .biliLive, .douyu, .huya:
                    proc.httpServer.register(json.uuid, site: site, url: url)
                default:
                    break
                }
            }
            
            proc.openWithPlayer(json, key)
            isVisible = false
        }.catch {
            Log("Prepare DM file error : \($0)")
        }
        
    }
}

struct DecodeSheetView_Previews: PreviewProvider {
    @State static var isVisible = true
    @State static var url = "https://live.bilibili.com/3"
    
    static var previews: some View {
        DecodeSheetView(isVisible: $isVisible, url: $url)
    }
}
