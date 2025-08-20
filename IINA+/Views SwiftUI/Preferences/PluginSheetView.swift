//
//  PluginSheetView.swift
//  IINA+
//
//  Created by xjbeta on 2025/5/16.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import SwiftUI

struct PluginSheetView: View {
    
    @Binding var pluginSheet: Bool
    @State private var stepValue = 0
    @State private var installPluginTitle = ""
    
    var defaultColor = Color.gray
    
    enum PlistKeys: String {
        case systemEnable = "iinaEnablePluginSystem"
        case pluginEnable = "PluginEnabled.com.xjbeta.danmaku"
        case parseEnable = "enableIINAPLUSOptsParse"
        
        var domain: String {
            get {
                if self == .parseEnable {
                    let path = (try? IINAApp.pluginFolder() + ".preferences/") ?? ""
                    
                    let fm = FileManager.default
                    if !fm.fileExists(atPath: path) {
                        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
                    }
                    
                    return "'" + path + "com.xjbeta.danmaku.plist" + "'"
                } else {
                    return "com.colliderli.iina"
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 12) {
                PluginStepView(stepNumber: 1, backgroundColor: stepValue > 0 ? .blue : defaultColor) {
                    LocalizedText("naV-oK-pw1.title", tableName: .preferences)
                    Spacer(minLength: 15)
                    if stepValue == 0 {
                        Button {
                            stepValue += 1
                        } label: {
                            LocalizedText("OSx-Ln-aqZ.title", tableName: .preferences)
                        }
                        .disabled(stepValue != 0)
                    }
                }
                PluginStepView(stepNumber: 2, backgroundColor: stepValue > 1 ? .green : defaultColor) {
                    LocalizedText("UsF-Nh-nOS.title", tableName: .preferences)
                    Spacer(minLength: 15)
                    if stepValue == 1 {
                        Button {
                            stepValue += 1
                        } label: {
                            //                        LocalizedText("cgt-Fm-5UC.title", tableName: .preferences)
                            Text(installPluginTitle)
                        }
                        .opacity(stepValue != 1 ? 0 : 1)
                    }
                }
                PluginStepView(stepNumber: 3, backgroundColor: stepValue > 2 ? .orange : defaultColor) {
                    LocalizedText("kHc-Ut-v2Y.title", tableName: .preferences)
                    Spacer(minLength: 15)
                    if stepValue == 2 {
                        Button {
                            stepValue += 1
                        } label: {
                            LocalizedText("VgB-qp-s9y.title", tableName: .preferences)
                        }
                        .disabled(stepValue != 2)
                    }
                }
            }
            
            if stepValue == 3 {
//                Text(k)
//                    .padding(.horizontal)
                
                Text(NSLocalizedString("PluginInstaller.tips", comment: ""))
                
            }
            
            Spacer(minLength: 15)
            
            HStack {
                Spacer()
                Button {
                    pluginSheet = false
                } label: {
                    Text("Cancel")
                        .frame(width: 65)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .onAppear {
//            initPluginStates()
        }
    }
    
    

    
    func initPluginStates() {
        // reset
        
        // step2 button
//        installPluginTitle = ""
        
        
        stepValue = 0
        
        // plugin system
        guard getPluginSystemState() else {
            return
        }
        
        // danmaku plugin
        let pluginState = IINAApp.pluginState()
        
        var installState = false
        
        switch pluginState {
        case .ok(_):
            installPluginTitle = "Install"
            installState = true
        case .needsUpdate(let plugin):
            installPluginTitle = "Update \(plugin.version) to \(IINAApp.internalPluginVersion)"
        case .needsInstall:
            installPluginTitle = "Install"
        case .newer(let plugin):
            installPluginTitle = "\(plugin.version) is newer"
        case .isDev:
            installPluginTitle = "DEV"
            installState = true
        case .multiple:
            installPluginTitle = "Update"
        case .error(let error):
            Log("list all plugins error \(error)")
            installPluginTitle = "Error"
        }
        stepValue = 1
        guard installState else { return }
        
        // enable danmaku plugin
        let danmakuState = getDanmakuState()
        
        stepValue = 2
        guard danmakuState else { return }
        
        stepValue = 3
    }
    
    func getPluginSystemState() -> Bool {
        // defaults read com.colliderli.iina iinaEnablePluginSystem
        (defaultsRead(.systemEnable) ?? "0") == "1"
        
//        IINAApp.getBuildVersion()
    }
    
    
    func getDanmakuState() -> Bool {
        (defaultsRead(.pluginEnable) ?? "0") == "1"
        && (defaultsRead(.parseEnable) ?? "0") == "1"
    }
    
    func defaultsWrite(_ key: PlistKeys, stringValue: String) {
        let _ = Process.run(["/bin/bash", "-c", "defaults write \(key.domain) \(key.rawValue) \(stringValue)"])
    }
    
    func defaultsWrite(_ key: PlistKeys, boolValue: Bool) {
        let _ = Process.run(["/bin/bash", "-c", "defaults write \(key.domain) \(key.rawValue) -bool \(boolValue ? "true" : "false")"])
    }
    
    func defaultsRead(_ key: PlistKeys) -> String? {
        let (process, outText, errText) = Process.run(["/bin/bash", "-c", "defaults read \(key.domain) \(key.rawValue)"])
        
        guard process.terminationStatus == 0, let out = outText else {
            Log("outText: \(outText ?? "none")")
            Log("errText: \(errText ?? "none")")
            return nil
        }
        
        return out.replacingOccurrences(of: "\n", with: "")
    }
}

#Preview {
    PluginSheetView(pluginSheet: .init(get: {
        true
    }, set: { _ in
        
    }))
}
