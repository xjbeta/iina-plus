//
//  GereralViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/21.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class GereralViewController: NSViewController, NSMenuDelegate {
    
    @IBOutlet weak var fontPicker: NSPopUpButton!
    @IBOutlet weak var playerPopUpButton: NSPopUpButton!
    @IBOutlet weak var decoderPopUpButton: NSPopUpButton!
    @IBOutlet weak var enableDanmaku: NSButton!
    
    @IBAction func enableDanmaku(_ sender: Any) {
        Preferences.shared.enableDanmaku = enableDanmaku.state == .on
    }
    
    @IBAction func newFontSet(_ sender: NSPopUpButton) {
        let newFamilyName = sender.selectedItem?.title
        Preferences.shared.danmukuFontFamilyName = newFamilyName
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        enableDanmaku.state = Preferences.shared.enableDanmaku ? .on : .off
        initMenu(for: playerPopUpButton)
        initMenu(for: decoderPopUpButton)
        
        // Configure the font picker
        let names = NSFontManager.shared.availableFontFamilies
        fontPicker.addItems(withTitles: names)
        if let lastFamilyName = Preferences.shared.danmukuFontFamilyName {
            let item = fontPicker.itemArray.filter() { $0.title == lastFamilyName }.first
            fontPicker.select(item)
        }
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
            popUpButton.selectItem(at: Preferences.shared.liveDecoder.index())
        default:
            break
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
    case ykdl
    case youget = "you-get"
    
    init(raw: String) {
        if let decoder = LiveDecoder(rawValue: raw) {
            self = decoder
        } else {
            self = .internal😀
        }
    }
    
    init(index: Int) {
        switch index {
        case 1:
            self = .ykdl
        case 2:
            self = .youget
        default:
            self = .internal😀
        }
    }
    
    func index() -> Int {
        switch self {
        case .internal😀:
            return 0
        case .ykdl:
            return 1
        case .youget:
            return 2
        }
    }
}
