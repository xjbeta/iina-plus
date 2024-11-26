//
//  DanmakuWS.swift
//  IINA+
//
//  Created by xjbeta on 2024/11/25.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Foundation
import WebKit

enum DanamkuMethod: String, Encodable {
    case start,
    stop,
    initDM,
    resize,
    customFont,
    loadDM,
    sendDM,
    liveDMServer,
    dmSpeed,
    dmOpacity,
    dmFontSize,
    dmBlockList
}


struct DanmakuComment: Encodable {
    var text: String
    var imageSrc: String?
    var imageWidth: Int?
}

struct DanmakuEvent: Encodable {
    var method: DanamkuMethod
    var text: String
    
    var dms: [DanmakuComment]?
    
    func string() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}


protocol DanmakuWSDelegate {
    func writeDanmakuEventText(contextName: String, _ string: String)
}

struct DanmakuWS {
    var id: String
    var site: SupportSites
    var url: String
    var contextName: String
    var version = 0
    
    var delegate: DanmakuWSDelegate? = nil
    var webview: WKWebView? = nil
    
    
    @MainActor
    func send(_ event: DanmakuEvent) {
        switch version {
        case 0 where event.method == .sendDM:
            event.dms?.forEach {
                let de = DanmakuEvent(method: .sendDM, text: $0.text)
                guard let str = de.string() else { return }
                delegate?.writeDanmakuEventText(contextName: contextName, str)
            }
        default:
            guard let str = event.string() else { return }
            if let delegate {
                delegate.writeDanmakuEventText(contextName: contextName, str)
            } else if let wv = webview {
                wv.evaluateJavaScript("window.dmMessage(\(str));") { _,_ in }
            }
            
            if !str.contains("sendDM") {
                Log("WriteText to \(id): \(str)")
            }
        }
    }
    
    @MainActor
    func loadCustomFont() {
        let pref = Preferences.shared
        let font = pref.danmukuFontFamilyName
        let size = pref.danmukuFontSize
        let weight = pref.danmukuFontWeight
        
        var text = ".customFont {"
        text += "color: #fff;"
        text += "font-family: '\(font) \(weight)', SimHei, SimSun, Heiti, 'MS Mincho', 'Meiryo', 'Microsoft YaHei', monospace;"
        text += "font-size: \(size)px;"
        
        
        text += "letter-spacing: 0;line-height: 100%;margin: 0;padding: 3px 0 0 0;position: absolute;text-decoration: none;text-shadow: -1px 0 black, 0 1px black, 1px 0 black, 0 -1px black;-webkit-text-size-adjust: none;-ms-text-size-adjust: none;text-size-adjust: none;-webkit-transform: matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);transform: matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);-webkit-transform-origin: 0% 0%;-ms-transform-origin: 0% 0%;transform-origin: 0% 0%;white-space: pre;word-break: keep-all;}"
        
        Log("Danmaku font \(font) \(weight), \(size)px.")
        
        send(.init(method: .customFont, text: text))
    }

    @MainActor
    func customDMSpeed() {
        send(.init(method: .dmSpeed, text: "\(Int(Preferences.shared.dmSpeed))"))
    }

    @MainActor
    func customDMOpdacity() {
        send(.init(method: .dmOpacity, text: "\(Preferences.shared.dmOpacity)"))
    }
    
    func loadFilters() {
//        var types = Preferences.shared.dmBlockType
//        if Preferences.shared.dmBlockList.type != .none {
//            types.append("List")
//        }
//        send(.init(method: .dmBlockList, text: types.joined(separator: ", ")))
    }
    
    @MainActor
    func loadXMLDM() {
        send(.init(method: .loadDM, text: id))
    }
}
