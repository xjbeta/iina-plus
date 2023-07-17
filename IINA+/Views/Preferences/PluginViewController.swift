//
//  PluginViewController.swift
//  IINA+
//
//  Created by xjbeta on 2023/7/16.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa

class PluginViewController: NSViewController {

	@IBOutlet weak var pluginSystemState: NSButton!
	
	@IBOutlet weak var enablePluginSystemButton: NSButton!
	@IBAction func enablePluginSystem(_ sender: NSButton) {
		defaultsWrite(.systemEnable, boolValue: true)
		initStates()
	}
	
	@IBOutlet weak var pluginInstallState: NSButton!
	@IBOutlet weak var installPluginButton: NSButton!
	@IBAction func installPlugin(_ sender: NSButton) {
		do {
			let plugins = try iina.listPlugins()
			iina.uninstallPlugins(plugins)
			try iina.installPlugin()
		} catch let error {
			Log(error)
		}
		
		initStates()
		updatePlugin?()
	}
	
	@IBOutlet weak var enableDanmakuState: NSButton!
	@IBOutlet weak var enableDanmakuButton: NSButton!
	@IBAction func enableDanmaku(_ sender: NSButton) {
		defaultsWrite(.pluginEnable, boolValue: true)
		defaultsWrite(.parseEnable, stringValue: "1")
		initStates()
	}
	
	@IBOutlet weak var tapsTextField: NSTextField!
	
	var updatePlugin: (() -> Void)?
	let iina = Processes.shared.iina
	
	enum PlistKeys: String {
		case systemEnable = "iinaEnablePluginSystem"
		case pluginEnable = "PluginEnabled.com.xjbeta.danmaku"
		case parseEnable = "enableIINAPLUSOptsParse"
		
		var domain: String {
			get {
				if self == .parseEnable {
					let path = (try? Processes.shared.iina.pluginFolder() + ".preferences/") ?? ""
					
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
		pluginSystemState.state = .mixed
		pluginInstallState.state = .mixed
		enableDanmakuState.state = .mixed
		
		enablePluginSystemButton.isEnabled = false
		installPluginButton.isEnabled = false
		enableDanmakuButton.isEnabled = false
		
		tapsTextField.stringValue = ""
		
		// plugin system
		let systemState = getPluginSystemState()
		pluginSystemState.state = systemState ? .on : .off
		enablePluginSystemButton.isEnabled = systemState ? false : true
		
		guard systemState else { return }
		
		// danmaku plugin
		let pluginState = iina.pluginState()
		
		var installState = false
		
		switch pluginState {
		case .ok(_):
			installPluginButton.title = "Install"
			installPluginButton.isEnabled = false
			installState = true
			
		case .needsUpdate(let plugin):
			installPluginButton.title = "Update \(plugin.version) to \(iina.internalPluginVersion)"
			installPluginButton.isEnabled = true
		case .needsInstall:
			installPluginButton.title = "Install"
			installPluginButton.isEnabled = true
		case .newer(let plugin):
			installPluginButton.title = "\(plugin.version) is newer"
			installPluginButton.isEnabled = true
		case .isDev:
			installPluginButton.title = "DEV"
			installPluginButton.isEnabled = false
			installState = true
		case .multiple:
			installPluginButton.title = "Update"
			installPluginButton.isEnabled = true
		case .error(let error):
			Log("list all plugins error \(error)")
			installPluginButton.title = "Error"
		}
		
		pluginInstallState.state = installState ? .on : .off
		guard installState else { return }
		
		// enable danmaku plugin
		let danmakuState = getDanmakuState()
		
		enableDanmakuState.state = danmakuState ? .on : .off
		enableDanmakuButton.isEnabled = danmakuState ? false : true
		
		guard danmakuState else { return }
		
		// tips
		tapsTextField.stringValue = "\nEverything OK  ✅\nRestart IINA to take effect"
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
		let (process, stdout, stderr) = Process.run(["/bin/bash", "-c", "defaults read \(key.domain) \(key.rawValue)"])
		
		guard process.terminationStatus == 0,
			  let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.replacingOccurrences(of: "\n", with: "") else {
			
			let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "None"
			
			Log(errText)
			return nil
		}
		
		return outText
	}
}
