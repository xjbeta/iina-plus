//
//  PluginViewController.swift
//  IINA+
//
//  Created by xjbeta on 2023/7/16.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa


class PluginViewController: NSViewController {
	

	@objc dynamic var stepValue = 0
	
	@objc dynamic var enablePluginSystemButton = false
	@objc dynamic var enableInstallPluginButton = false
	@objc dynamic var enableDanmakuButton = false
	
	@objc dynamic var installPluginTitle = "Install"
	@objc dynamic var tipsTitle = ""
	
	
	@IBAction func enablePluginSystem(_ sender: NSButton) {
		defaultsWrite(.systemEnable, boolValue: true)
		initStates()
	}
	
	@IBAction func installPlugin(_ sender: NSButton) {
		do {
			let plugins = try IINAApp.listPlugins()
			IINAApp.uninstallPlugins(plugins)
			try IINAApp.installPlugin()
		} catch let error {
			Log(error)
		}
		
		initStates()
		updatePlugin?()
	}
	
	@IBAction func enableDanmaku(_ sender: NSButton) {
		defaultsWrite(.pluginEnable, boolValue: true)
		defaultsWrite(.parseEnable, stringValue: "1")
		initStates()
	}
	
	
	var updatePlugin: (() -> Void)?
	let iina = Processes.shared.iina
	
	enum PlistKeys: String {
		case systemEnable = "iinaEnablePluginSystem"
		case pluginEnable = "PluginEnabled.com.xjbeta.danmaku"
		case parseEnable = "enableIINAPLUSOptsParse"
		
		var domain: String {
			get {
				if self == .parseEnable {
					let path = (try? IINAApp.pluginFolder() + ".preferences/") ?? ""
					
					let fm = FileManager.default
					if !fm.fileExists(atPath: path) {
						try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
					}
					
					return "'" + path + "com.xjbeta.danmaku.plist" + "'"
				} else {
					return "com.colliderli.iina"
				}
			}
		}
	}
	
	
	override func viewDidLoad() {
        super.viewDidLoad()
		
		initStates()
    }
	
	func initStates() {
		// reset
		enablePluginSystemButton = false
		enableInstallPluginButton = false
		enableDanmakuButton = false
		
		installPluginTitle = ""
		tipsTitle = ""
		stepValue = 0
		
		// plugin system
		let systemState = getPluginSystemState()
		enablePluginSystemButton = !systemState
		
		guard systemState else { return }
		
		// danmaku plugin
		let pluginState = IINAApp.pluginState()
		
		var installState = false
		
		switch pluginState {
		case .ok(_):
			installPluginTitle = "Install"
			enableInstallPluginButton = false
			installState = true
			
		case .needsUpdate(let plugin):
			installPluginTitle = "Update \(plugin.version) to \(IINAApp.internalPluginVersion)"
			enableInstallPluginButton = true
		case .needsInstall:
			installPluginTitle = "Install"
			enableInstallPluginButton = true
		case .newer(let plugin):
			installPluginTitle = "\(plugin.version) is newer"
			enableInstallPluginButton = true
		case .isDev:
			installPluginTitle = "DEV"
			enableInstallPluginButton = false
			installState = true
		case .multiple:
			installPluginTitle = "Update"
			enableInstallPluginButton = true
		case .error(let error):
			Log("list all plugins error \(error)")
			installPluginTitle = "Error"
		}
		stepValue = 1
		guard installState else { return }
		
		// enable danmaku plugin
		let danmakuState = getDanmakuState()
		
		enableDanmakuButton = danmakuState ? false : true
		stepValue = 2
		guard danmakuState else { return }
		
		stepValue = 3
		// tips
		tipsTitle = NSLocalizedString("PluginInstaller.tips", comment: "")
	}
	
	func getPluginSystemState() -> Bool {
		// defaults read com.colliderli.iina iinaEnablePluginSystem
		(defaultsRead(.systemEnable) ?? "0") == "1"
	}
	
	
	func getDanmakuState() -> Bool {
		(defaultsRead(.pluginEnable) ?? "0") == "1"
		&& (defaultsRead(.parseEnable) ?? "0") == "1"
	}
	
	func defaultsWrite(_ key: PlistKeys, stringValue: String) {
		let _ = Process.run(["/bin/bash", "-c", "defaults write \(key.domain) \(key.rawValue) \(stringValue)"])
	}
	
	func defaultsWrite(_ key: PlistKeys, boolValue: Bool) {
		let _ = Process.run(["/bin/bash", "-c", "defaults write \(key.domain) \(key.rawValue) -bool \(boolValue ? "true" : "false")"])
	}
	
	func defaultsRead(_ key: PlistKeys) -> String? {
		let (process, outText, errText) = Process.run(["/bin/bash", "-c", "defaults read \(key.domain) \(key.rawValue)"])
		
		guard process.terminationStatus == 0, let out = outText else {
			Log("outText: \(outText ?? "none")")
			Log("errText: \(errText ?? "none")")
			return nil
		}
		
		return out.replacingOccurrences(of: "\n", with: "")
	}
}
