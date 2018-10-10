//
//  Preferences.swift
//  iina+
//
//  Created by xjbeta on 2018/7/17.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class Preferences: NSObject {
    static let shared = Preferences()
    
    private override init() {
    }

    let prefs = UserDefaults.standard
    let keys = PreferenceKeys.self
    
    var livePlayer: LivePlayer {
        get {
            return LivePlayer(raw: defaults(.livePlayer) as? String ?? "")
        }
        set {
            defaultsSet(newValue.rawValue, forKey: .livePlayer)
        }
    }
    
    var liveDecoder: LiveDecoder {
        get {
            return LiveDecoder(raw: defaults(.liveDecoder) as? String ?? "")
        }
        set {
            defaultsSet(newValue.rawValue, forKey: .liveDecoder)
        }
    }
    
    var enableLogging: Bool {
        get {
            return defaults(.enableLogging) as? Bool ?? false
        }
        set {
            defaultsSet(newValue, forKey: .enableLogging)
        }
    }
    
    var logLevel: Int {
        get {
            return defaults(.logLevel) as? Int ?? Logger.Level.debug.rawValue
        }
        set {
            defaultsSet(newValue, forKey: .logLevel)
        }
    }
    
    @objc var enableDanmaku: Bool {
        get {
            return defaults(.enableDanmaku) as? Bool ?? false
        }
        set {
            defaultsSet(newValue, forKey: .enableDanmaku)
        }
    }
    
    var danmukuFontFamilyName: String? {
        get {
            return defaults(.danmukuFontFamilyName) as? String
        }
        set {
            defaultsSet(newValue ?? "", forKey: .danmukuFontFamilyName)
            NotificationCenter.default.post(name: .updateDanmukuFont, object: nil)
        }
    }
    
}

private extension Preferences {
    
    func defaults(_ key: PreferenceKeys) -> Any? {
        return prefs.value(forKey: key.rawValue) as Any?
    }
    
    func defaultsSet(_ value: Any, forKey key: PreferenceKeys) {
        prefs.setValue(value, forKey: key.rawValue)
    }
}

enum PreferenceKeys: String {
    case livePlayer
    case liveDecoder
    case enableLogging
    case logLevel
    case enableDanmaku
    case danmukuFontFamilyName
}
