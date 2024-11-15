//
//  GereralViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/21.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class GereralViewController: NSViewController, NSMenuDelegate {
    
	@IBOutlet weak var pluginButton: NSButton!
    @IBOutlet weak var playerPopUpButton: NSPopUpButton!
    @IBOutlet var playerTextField: NSTextField!
    
    @IBOutlet var portTextField: NSTextField!
    @IBOutlet var portTestButton: NSButton!
    
    @IBAction func testInBrowser(_ sender: NSButton) {
        let port = pref.dmPort
        let u = "http://127.0.0.1:\(port)/danmaku/test.htm"
        guard let url = URL(string: u) else { return }
        
        NSWorkspace.shared.open(url)
    }
    
    
    let pref = Preferences.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initMenu(for: playerPopUpButton)
		portTextField.isEnabled = false
		initDanmakuPrefs()
		initPluginInfo()
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
	
	func initDanmakuPrefs() {
		Task { @MainActor in
			let iina = Processes.shared.iina
			let archiveType = await iina.archiveType
			let buildVersion = await iina.buildVersion
			
			let allowDanmaku = (archiveType == .danmaku && buildVersion > 16) || archiveType == .plugin
			
			portTextField.isEnabled = pref.enableDanmaku && allowDanmaku
		}
	}
	
	func initPluginInfo() {
		let pluginState = IINAApp.pluginState()
		
		switch pluginState {
		case .ok(let version):
			pluginButton.title = version
		case .needsUpdate(let plugin):
			pluginButton.title = "Update \(plugin.version) to \(IINAApp.internalPluginVersion)"
		case .needsInstall:
			pluginButton.title = "Install"
		case .newer(let plugin):
			pluginButton.title = "\(plugin.version) is newer"
		case .isDev:
			pluginButton.title = "DEV"
		case .multiple:
			pluginButton.title = "Update"
		case .error(let error):
			Log("list all plugins error \(error)")
			pluginButton.title = "Error"
		}
	}
    
    func initPlayerVersion() {
		Task {
			playerTextField.stringValue = await playerText()
		}
    }
	
	func playerText() async -> String {
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
		return s
	}
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
		if let vc = segue.destinationController as? PluginViewController {
			vc.updatePlugin = {
				self.initPluginInfo()
			}
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
