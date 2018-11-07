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
    
    var dmBlockType: [String] {
        get {
            return defaults(.dmBlockType) as? [String] ?? []
        }
        set {
            defaultsSet(newValue, forKey: .dmBlockType)
        }
    }
    
    var dmBlockList: BlockList {
        get {
            if let data = defaults(.dmBlockList) as? Data,
                let dmBlockList = BlockList(data: data) {
                return dmBlockList
            } else {
                return BlockList()
            }
        }
        set {
            defaultsSet(newValue.encode(), forKey: .dmBlockList)
        }
    }
    
    @objc var danmukuFontFamilyName: String? {
        get {
            return defaults(.danmukuFontFamilyName) as? String
        }
        set {
            defaultsSet(newValue ?? "", forKey: .danmukuFontFamilyName)
            didChangeValue(for: \.danmukuFontFamilyName)
        }
    }
    
    @objc dynamic var dmSpeed: Double {
        get {
            return defaults(.dmSpeed) as? Double ?? 680
        }
        set {
            defaultsSet(newValue, forKey: .dmSpeed)
            didChangeValue(for: \.dmSpeed)
        }
    }
    
    @objc dynamic var dmOpacity: Double {
        get {
            return defaults(.dmOpacity) as? Double ?? 1
        }
        set {
            defaultsSet(newValue, forKey: .dmOpacity)
            didChangeValue(for: \.dmOpacity)
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
    case dmSpeed
    case dmOpacity
    case dmBlockType
    case dmBlockList
}
