//
//  GeneralPrefsView.swift
//  IINA+
//
//  Created by xjbeta on 2025/5/7.
//  Copyright © 2025 xjbeta. All rights reserved.
//

import SwiftUI

struct GeneralPrefsView: View {
    
    @State private var currentPlayer: LivePlayer = .iina
    @State private var playerTips = ""
    @State private var mpvPath: String = ""
    @State private var mpvSheet = false
    
    // Plugin
    @State private var pluginButtonTitle: String = ""
    @State private var pluginSheet = false
    
    private let textWidth: CGFloat = Locale.current.language.languageCode == .chinese ? 55 : 75

    let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 1024
        formatter.maximum = 65535
        formatter.allowsFloats = false
        formatter.generatesDecimalNumbers = false
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                LocalizedText("RGN-E6-zAU.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Picker("", selection: Binding<LivePlayer>(get: {
                    Preferences.shared.livePlayer
                }, set: {
                    Preferences.shared.livePlayer = $0
                    currentPlayer = $0
                    Task {
                        await updatePlayerTips()
                    }
                })) {
                    ForEach(LivePlayer.allCases) {
                        Text($0.name).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            
            GridRow(alignment: .firstTextBaseline) {
                Spacer()
                VStack(alignment: .leading) {
                    if currentPlayer == .mpv {
                        TextField("mpv path", text: .init(get: {
                            Preferences.shared.customMpvPath
                        }, set: {
                            Preferences.shared.customMpvPath = $0
                            
                            Task {
                                await updatePlayerTips()
                            }
                        }))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                    }
                    HStack {
                        Spacer()
                        HStack {
                            Text(playerTips)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Button {
                                switch currentPlayer {
                                case .iina:
                                    NSWorkspace.shared.open(.init(string: "https://iina.io/")!)
                                case .mpv:
                                    mpvSheet = true
                                }
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 15))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(Color.blue)
                        }
                    }
                }
            }
            
            GridRow {
                Spacer()
                Toggle(isOn: .init(get: {
                    Preferences.shared.enableFlvjs
                }, set: {
                    Preferences.shared.enableFlvjs = $0
                })) {
                    LocalizedText("nYK-y9-7tF.title", tableName: .preferences)
                }
                .toggleStyle(.checkbox)
            }
            
            GridRow {
                Spacer()
                Toggle(isOn: .init(get: {
                    Preferences.shared.autoOpenResult
                }, set: {
                    Preferences.shared.autoOpenResult = $0
                })) {
                    LocalizedText("hPC-yj-akr.title", tableName: .preferences)
                }
                .toggleStyle(.checkbox)
            }
            
            Divider()
                .padding(.horizontal, -8)
            
            GridRow {
                LocalizedText("ajR-RS-oZ6.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Button {
                    pluginSheet = true
                } label: {
                    Text(pluginButtonTitle)
                        .padding(.horizontal)
                }
            }
            
            Divider()
                .padding(.horizontal, -8)
            
            GridRow {
                LocalizedText("wRZ-RD-AEu.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Toggle(isOn: .init(get: {
                    Preferences.shared.enableDanmaku
                }, set: {
                    Preferences.shared.enableDanmaku = $0
                })) {
                    
                }
                .toggleStyle(.switch)
            }
            
            GridRow(alignment: .firstTextBaseline) {
                LocalizedText("BAX-B0-esq.title", tableName: .preferences)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .leading) {
                    HStack {
                        TextField("19080", value: Binding<Int>(get: {
                            Preferences.shared.dmPort
                        }, set: {
                            Preferences.shared.dmPort = $0
                        }), formatter: portFormatter)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)
                        
                        Button {
                            let port = Preferences.shared.dmPort
                            let u = "http://127.0.0.1:\(port)/danmaku/test.htm"
                            guard let url = URL(string: u) else { return }
                            
                            NSWorkspace.shared.open(url)
                        } label: {
                            LocalizedText("FbN-8d-UIb.title", tableName: .preferences)
                        }
                    }
                    LocalizedText("CNd-nb-X32.title", tableName: .preferences)
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $mpvSheet) {
            mpvSheetView
        }
        .sheet(isPresented: $pluginSheet) {
            PluginSheetView(pluginSheet: $pluginSheet)
        }
        .onAppear {
            currentPlayer = Preferences.shared.livePlayer
            initPluginInfo()
            Task {
                await Processes.shared.iina.updateIINAState()
                await updatePlayerTips()
            }
        }
        .padding(EdgeInsets(top: 28, leading: 35, bottom: 28, trailing: 35))
        .fixedSize()
    }
    

    
    var mpvSheetView: some View {
        VStack {
            HStack {
                TextField("", text: .init(get: {
                    "which mpv"
                }, set: { _ in
                }))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button {
                    openTerminal()
                } label: {
                    Text("Open Terminal")
                }
            }.padding(.horizontal, 12)
            
            Spacer(minLength: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Example")
                    .font(.system(size: 21))
                    .padding(.leading, 12)
                
                Image("zsh_example")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 450)
            }
            
            Spacer(minLength: 15)
            
            HStack {
                Spacer()
                Button {
                    initPluginInfo()
                    mpvSheet = false
                } label: {
                    Text("Cancel")
                        .frame(width: 65)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
    }
    
    func updatePlayerTips() async {
        let pref = Preferences.shared
        let proc = Processes.shared
        let iina = Processes.shared.iina
        var s = ""
        switch pref.livePlayer {
        case .iina:
            switch await iina.archiveType {
            case .danmaku:
                s = "danmaku"
            case .plugin where await iina.buildVersion >= IINAApp.minIINABuild:
                s = "official"
            case .plugin:
                s = "plugin"
            case .normal:
                s = "official"
            case .none:
                s = "not found"
            }
        case .mpv:
            s = proc.mpvVersion()
        }
        playerTips = s
    }
    
    func openTerminal() {
        guard let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([FileManager.default.homeDirectoryForCurrentUser], withApplicationAt: appUrl, configuration: config)
    }
    
    func initPluginInfo() {
        let pluginState = IINAApp.pluginState()
        
        switch pluginState {
        case .ok(let version):
            pluginButtonTitle = version
        case .needsUpdate(let plugin):
            pluginButtonTitle = "Update \(plugin.version) to \(IINAApp.internalPluginVersion)"
        case .needsInstall:
            pluginButtonTitle = "Install"
        case .newer(let plugin):
            pluginButtonTitle = "\(plugin.version) is newer"
        case .isDev:
            pluginButtonTitle = "DEV"
        case .multiple:
            pluginButtonTitle = "Update"
        case .error(let error):
            Log("list all plugins error \(error)")
            pluginButtonTitle = "Error"
        }
    }

}

struct PluginStepView<Content: View>: View {
    let stepNumber: Int
    let content: Content
    let backgroundColor: Color
    
    init(stepNumber: Int, backgroundColor: Color, @ViewBuilder content: () -> Content) {
        self.stepNumber = stepNumber
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        VStack {
            Text("# \(stepNumber)")
                .font(.headline)
                .padding(.bottom, 5)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor.opacity(0.15))
        .cornerRadius(8)
        
    }
}

#Preview {
    GeneralPrefsView()
}
