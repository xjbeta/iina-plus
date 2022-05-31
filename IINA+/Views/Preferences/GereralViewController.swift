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
    @IBOutlet var playerTextField: NSTextField!
    
    @IBOutlet var portTextField: NSTextField!
    @IBOutlet var portTestButton: NSButton!
    
    @IBAction func testInBrowser(_ sender: NSButton) {
        let port = pref.dmPort
        let u = "http://127.0.0.1:\(port)/danmaku/index.htm"
        guard let url = URL(string: u) else { return }
        
        NSWorkspace.shared.open(url)
    }
    
    
    let pref = Preferences.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initFontSelector()
        initMenu(for: playerPopUpButton)
        
        let proc = Processes.shared
        portTextField.isEnabled = pref.enableDanmaku
        && ((proc.iinaArchiveType() == .danmaku && proc.iinaBuildVersion() > 16) || proc.iinaArchiveType() == .plugin)
            
    }
    
    func menuDidClose(_ menu: NSMenu) {
        switch menu {
        case playerPopUpButton.menu:
            pref.livePlayer = LivePlayer(index: playerPopUpButton.indexOfSelectedItem)
            initPlayerVersion()
        default:
            break
        }
    }
    
    func initMenu(for popUpButton: NSPopUpButton) {
        switch popUpButton {
        case playerPopUpButton:
            popUpButton.selectItem(at: pref.livePlayer.index())
            initPlayerVersion()
        default:
            break
        }
    }
    
    func initPlayerVersion() {
        let proc = Processes.shared
        var s = ""
        switch pref.livePlayer {
        case .iina:
            switch proc.iinaArchiveType() {
            case .danmaku:
                s = "danmaku"
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
        playerTextField.stringValue = s
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
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
        
        let name = pref.danmukuFontFamilyName
        let weight = pref.danmukuFontWeight
        
//        let size = pref.danmukuFontSize
//        fontSelectorButton.title = "\(name) - \(weight) \(size)px"
        fontSelectorButton.title = "\(name) - \(weight)"
    }
    
    func checkFontWeight() {
        
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
