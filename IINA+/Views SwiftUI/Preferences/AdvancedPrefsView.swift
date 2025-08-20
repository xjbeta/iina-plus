//
//  AdvancedPrefsView.swift
//  IINA+
//
//  Created by xjbeta on 2025/8/9.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import SwiftUI
import SDWebImage
import WebKit

struct AdvancedPrefsView: View {
    
    @State var cacheSizeText: String = ""
    
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline) {
            GridRow {
                LocalizedText("Rpn-D1-AxI.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                Text(cacheSizeText)
                    .padding(.trailing)
                
                Button {
                    SDImageCache.shared.clearDisk {
                        initCacheSize()
                    }
                    WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSince1970: 0), completionHandler:{ })
                    initCacheSize()
                } label: {
                    LocalizedText("56d-bd-mk7.title", tableName: .preferences)
                        .padding(.horizontal)
                }
            }
            
            Divider()
                .padding(.horizontal, -8)
            
            GridRow {
                LocalizedText("CfS-Ci-nxw.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                LocalizedText("1ly-MG-PV5.title", tableName: .preferences)
                
                ColorPicker("", selection: .init(get: {
                    Preferences.shared.stateLiving.color
                }, set: {
                    Preferences.shared.stateLiving = $0.nsColor
                }))
                    .labelsHidden()
            }
            
            GridRow {
                Spacer()
                
                LocalizedText("Of0-KI-IUP.title", tableName: .preferences)
                
                ColorPicker("", selection: .init(get: {
                    Preferences.shared.stateOffline.color
                }, set: {
                    Preferences.shared.stateOffline = $0.nsColor
                }))
                    .labelsHidden()
            }
            
            GridRow {
                Spacer()
                
                LocalizedText("9Rb-3A-pS4.title", tableName: .preferences)
                
                ColorPicker("", selection: .init(get: {
                    Preferences.shared.stateReplay.color
                }, set: {
                    Preferences.shared.stateReplay = $0.nsColor
                }))
                    .labelsHidden()
            }
            
            GridRow {
                Spacer()
                
                LocalizedText("o7B-lQ-AHT.title", tableName: .preferences)
                
                ColorPicker("", selection: .init(get: {
                    Preferences.shared.stateUnknown.color
                }, set: {
                    Preferences.shared.stateUnknown = $0.nsColor
                }))
                    .labelsHidden()
            }
            
        }
        .onAppear {
            initCacheSize()
        }
        .padding(EdgeInsets(top: 28, leading: 35, bottom: 28, trailing: 35))
        .fixedSize()
    }
    
    func initCacheSize() {
        SDImageCache.shared.calculateSize { count, size in
            cacheSizeText = String(format: "%.2f MB", Double(size) / 1024 / 1024)
        }
    }
}

#Preview {
    AdvancedPrefsView()
}
