//
//  GereralViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/21.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class GereralViewController: NSViewController, NSMenuDelegate {
    
    @IBOutlet var fontSelectorButton: NSButton!
    @IBOutlet weak var playerPopUpButton: NSPopUpButton!
    @IBOutlet weak var decoderPopUpButton: NSPopUpButton!
    
    @IBOutlet var portTextField: NSTextField!
    @IBOutlet var portTestButton: NSButton!
    
    @IBAction func testInBrowser(_ sender: NSButton) {
        let port = Preferences.shared.dmPort
        let u = "http://127.0.0.1:\(port)/danmaku/index.htm"
        guard let url = URL(string: u) else { return }
        
        NSWorkspace.shared.open(url)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initFontSelector()
        initMenu(for: playerPopUpButton)
        initMenu(for: decoderPopUpButton)
        
        portTextField.isEnabled = Preferences.shared.enableDanmaku
            && Processes.shared.iinaArchiveType() != .normal
            && Processes.shared.iinaBuildVersion() > 16
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
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        let pref = Preferences.shared
        guard let vc = segue.destinationController as? FontSelectorViewController else { return }
        checkFontWeight()
        
        let name = pref.danmukuFontFamilyName
        vc.delegate = self
        vc.families = NSFontManager.shared.availableFontFamilies
        vc.family = name
        vc.styles = fontWeights(ofFontFamily: name)
        vc.style = pref.danmukuFontWeight
        vc.size = pref.danmukuFontSize
    }
    
    func fontWeights(ofFontFamily name: String) -> [String] {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: name) else { return [] }
        
        let names = members.filter {
            $0.count == 4
        }.compactMap {
            $0[1] as? String
        }
        
        return names
    }
    
    func initFontSelector() {
        checkFontWeight()
        
        let pref = Preferences.shared
        let name = pref.danmukuFontFamilyName
        let weight = pref.danmukuFontWeight
        
//        let size = pref.danmukuFontSize
//        fontSelectorButton.title = "\(name) - \(weight) \(size)px"
        fontSelectorButton.title = "\(name) - \(weight)"
    }
    
    func checkFontWeight() {
        let pref = Preferences.shared
        let name = pref.danmukuFontFamilyName
        let weight = pref.danmukuFontWeight
        let weights = fontWeights(ofFontFamily: name)
        if !weights.contains(weight),
           let w = weights.first {
            pref.danmukuFontWeight = w
        }
    }
}

extension GereralViewController: FontSelectorDelegate {
    func fontDidUpdated() {
        initFontSelector()
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
