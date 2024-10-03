//
//  Preferences.swift
//  iina+
//
//  Created by xjbeta on 2018/7/17.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

final class Preferences: NSObject, Sendable {
    static let shared = Preferences()
    
    private override init() {
    }

	nonisolated(unsafe) let prefs = UserDefaults.standard
	
    let keys = PreferenceKeys.self
    
    var livePlayer: LivePlayer {
        get {
            return LivePlayer(raw: defaults(.livePlayer) as? String ?? "")
        }
        set {
            defaultsSet(newValue.rawValue, forKey: .livePlayer)
        }
    }
    
    @objc var enableFlvjs: Bool {
        get {
            return defaults(.enableFlvjs) as? Bool ?? false
        }
        set {
            defaultsSet(newValue, forKey: .enableFlvjs)
        }
    }
    
    @objc var autoOpenResult: Bool {
        get {
            return defaults(.autoOpenResult) as? Bool ?? false
        }
        set {
            defaultsSet(newValue, forKey: .autoOpenResult)
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
    
    @objc var danmukuFontFamilyName: String {
        get {
            return defaults(.danmukuFontFamilyName) as? String ?? "SimHei"
        }
        set {
            defaultsSet(newValue, forKey: .danmukuFontFamilyName)
            didChangeValue(for: \.danmukuFontFamilyName)
        }
    }
    
    @objc var danmukuFontWeight: String {
        get {
            return defaults(.danmukuFontWeight) as? String ?? "Regular"
        }
        set {
            defaultsSet(newValue, forKey: .danmukuFontWeight)
            didChangeValue(for: \.danmukuFontWeight)
        }
    }
    
    @objc var danmukuFontSize: Int {
        get {
//            return defaults(.danmukuFontSize) as? Int ?? 24
            return 24
        }
        set {
            defaultsSet(newValue, forKey: .danmukuFontSize)
            didChangeValue(for: \.danmukuFontSize)
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
    
    @objc dynamic var dmPort: Int {
        get {
			if IINAApp.getBuildVersion() > 16 {
                return defaults(.dmPort) as? Int ?? 19080
            } else {
                return 19080
            }
        }
        set {
            defaultsSet(newValue, forKey: .dmPort)
            didChangeValue(for: \.dmPort)
        }
    }

    @objc dynamic var stateLiving: NSColor {
        get {
            return colorDecode(defaults(.stateLiving)) ?? .systemGreen
        }
        set {
            defaultsSet(colorEncode(newValue), forKey: .stateLiving)
        }
    }
    
    @objc dynamic var stateOffline: NSColor {
        get {
            
            return colorDecode(defaults(.stateOffline)) ?? .systemRed
        }
        set {
            defaultsSet(colorEncode(newValue), forKey: .stateOffline)
        }
    }
    
    @objc dynamic var stateReplay: NSColor {
        get {
            return colorDecode(defaults(.stateReplay)) ?? .controlAccentColor
        }
        set {
            defaultsSet(colorEncode(newValue), forKey: .stateReplay)
        }
    }
    
    @objc dynamic var stateUnknown: NSColor {
        get {
            return colorDecode(defaults(.stateUnknown)) ?? .systemGray
        }
        set {
            defaultsSet(colorEncode(newValue), forKey: .stateUnknown)
        }
    }
	
	@objc dynamic var bilibiliHTMLDecoder: Bool {
		get {
			return defaults(.bilibiliHTMLDecoder) as? Bool ?? false
		}
		set {
			defaultsSet(newValue, forKey: .bilibiliHTMLDecoder)
		}
	}
    
    @objc dynamic var bilibiliCodec: Int {
        get {
            return defaults(.bilibiliCodec) as? Int ?? 1
        }
        set {
            defaultsSet(newValue, forKey: .bilibiliCodec)
        }
    }
    
    @objc dynamic var bililiveHevc: Bool {
        get {
            return defaults(.bililiveHevc) as? Bool ?? false
        }
        set {
            defaultsSet(newValue, forKey: .bililiveHevc)
        }
    }
	
	var updateInfo070: Bool {
		get {
			return defaults(.updateInfo070) as? Bool ?? false
		}
		set {
			defaultsSet(newValue, forKey: .updateInfo070)
		}
	}
	
	
	var customMpvPath: String {
		get {
			return defaults(.customMpvPath) as? String ?? ""
		}
		set {
			defaultsSet(newValue, forKey: .customMpvPath)
		}
	}
    
    private func colorEncode(_ color: NSColor) -> Data {
        (try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)) ?? Data()
    }
    
    private func colorDecode(_ value: Any?) -> NSColor? {
        guard let data = value as? Data,
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else { return nil }
        return color
    }
}

private extension Preferences {
    
    func defaults(_ key: PreferenceKeys) -> Any? {
		prefs.value(forKey: key.rawValue) as Any?
    }
    
    func defaultsSet(_ value: Any, forKey key: PreferenceKeys) {
        prefs.setValue(value, forKey: key.rawValue)
    }
}

enum PreferenceKeys: String {
    case livePlayer
    case enableFlvjs
    case autoOpenResult
    
    case enableDanmaku
    case danmukuFontFamilyName
    case danmukuFontWeight
    case danmukuFontSize
    case dmSpeed
    case dmOpacity
    case dmBlockType
    case dmBlockList
    case dmPort
    
    case stateLiving
    case stateOffline
    case stateReplay
    case stateUnknown
    
	case bilibiliHTMLDecoder
    case bilibiliCodec
    case bililiveHevc
	
	case updateInfo070
	
	case customMpvPath
}
