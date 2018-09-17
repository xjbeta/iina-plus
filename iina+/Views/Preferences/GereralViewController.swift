//
//  GereralViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/21.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class GereralViewController: NSViewController, NSMenuDelegate {
    @IBOutlet weak var playerPopUpButton: NSPopUpButton!
    @IBOutlet weak var decoderPopUpButton: NSPopUpButton!
    @IBOutlet weak var enableDanmaku: NSButton!
    @IBAction func enableDanmaku(_ sender: Any) {
        if enableDanmaku.state == .on {
            acquirePrivileges { success in
                DispatchQueue.main.async {
                    Preferences.shared.enableDanmaku = success
                    self.enableDanmaku.state = success ? .on : .off
                }
            }
        } else {
            Preferences.shared.enableDanmaku = false
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        enableDanmaku.state = Preferences.shared.enableDanmaku ? .on : .off
        initMenu(for: playerPopUpButton)
        initMenu(for: decoderPopUpButton)
    }
    
    func menuDidClose(_ menu: NSMenu) {
        switch menu {
        case playerPopUpButton.menu:
            Preferences.shared.livePlayer = LivePlayer(index: playerPopUpButton.indexOfSelectedItem)
        case decoderPopUpButton.menu:
            Preferences.shared.liveDecoder = LiveDecoder(index: decoderPopUpButton.indexOfSelectedItem)
        default:
            break
        }
    }
    
    func initMenu(for popUpButton: NSPopUpButton) {
        switch popUpButton {
        case playerPopUpButton:
            popUpButton.selectItem(at: Preferences.shared.livePlayer.index())
        case decoderPopUpButton:
            popUpButton.autoenablesItems = false
            popUpButton.item(at: 0)?.isEnabled = false
            popUpButton.selectItem(at: Preferences.shared.liveDecoder.index())
        default:
            break
        }
    }
    
    func acquirePrivileges(_ block: @escaping (Bool) -> Void) {
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let privOptions = [trusted: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(privOptions)
        Logger.log("accessEnabled: \(accessEnabled)")
        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = "Enable IINA+ Danmaku"
            alert.informativeText = "Once you have enabled IINA+ in System Preferences, click OK."
            
            guard let window = view.window else {
                block(false)
                return
            }
            alert.beginSheetModal(for: window) { _ in
                let t = AXIsProcessTrustedWithOptions(privOptions)
                Logger.log("accessEnabled: \(t)")
                block(t)
            }
        } else {
            block(true)
        }
    }
    
}


enum LivePlayer: String {
    case iina = "/Applications/IINA.app/Contents/MacOS/iina-cli"
    case mpv = "mpv"
    
    init(raw: String) {
        if let player = LivePlayer.init(rawValue: raw) {
            self = player
        } else {
            self = .iina
        }
    }
    
    init(index: Int) {
        switch index {
        case 1:
            self = .mpv
        default:
            self = .iina
        }
    }
    
    func index() -> Int {
        switch self {
        case .iina:
            return 0
        case .mpv:
            return 1
        }
    }
}

enum LiveDecoder: String {
    case internal😀
    case internalYKDL
    case ykdl
    case youget = "you-get"
    
    init(raw: String) {
        if let decoder = LiveDecoder(rawValue: raw) {
            self = decoder
        } else {
            self = .internalYKDL
        }
    }
    
    init(index: Int) {
        switch index {
        case 0:
            self = .internal😀
        case 2:
            self = .ykdl
        case 3:
            self = .youget
        default:
            self = .internalYKDL
        }
    }
    
    func index() -> Int {
        switch self {
        case .internal😀:
            return 0
        case .internalYKDL:
            return 1
        case .ykdl:
            return 2
        case .youget:
            return 3
        }
    }
}
