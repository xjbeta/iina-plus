//
//  IINAApp.swift
//  IINA+
//
//  Created by xjbeta on 2023/7/15.
//  Copyright © 2023 xjbeta. All rights reserved.
//

import Cocoa

actor IINAApp {
	
	enum PluginState {
		case ok(String)
		case needsUpdate(PluginInfo)
		case needsInstall
		case newer(PluginInfo)
		case isDev
		case multiple
		case error(Error)
	}
	
	enum IINAError: Error {
		case cannotUnpackage
		case onlyDevPlugin
		case missingPluginFile
	}
	
	struct PluginInfo: Decodable {
		let name: String
		let identifier: String
		let version: String
		let ghVersion: Int
		
		var path = ""
		var isDev = false
		
		enum CodingKeys: CodingKey {
			case name, identifier, version, ghVersion
		}
	}
	
	static let internalPluginVersion = "0.1.12"
	static let internalPluginBuild = 9
	
	static let minIINABuild = 135
	
	var buildVersion: Int = 0
	var archiveType: IINAUrlType = .none
	
	func updateIINAState() {
		buildVersion = IINAApp.getBuildVersion()
		archiveType = IINAApp.getArchiveType()
	}
	
	static func getBuildVersion() -> Int {
		let b = Bundle(path: "/Applications/IINA.app")
		let build = b?.infoDictionary?["CFBundleVersion"] as? String ?? ""
		return Int(build) ?? 0
	}
	
	static func getArchiveType() -> IINAUrlType {
		let build = getBuildVersion()
		
		let b = Bundle(path: "/Applications/IINA.app")
		guard let version = b?.infoDictionary?["CFBundleShortVersionString"] as? String else {
			return .none
		}
		if version.contains("Danmaku") {
			return .danmaku
		} else if version.contains("plugin") {
			return .plugin
		} else if build >= minIINABuild {
			switch pluginState() {
			case .isDev, .ok(_):
				return .plugin
			default:
				break
			}
		}
		return .normal
	}
	
	static func pluginState() -> PluginState {
		do {
			let plugins = try listPlugins()
			switch plugins.count {
			case 0:
				return .needsInstall
			case 1 where plugins[0].isDev:
				return .isDev
			case 1 where !plugins[0].isDev:
				let plugin = plugins[0]
				if plugin.ghVersion == internalPluginBuild {
					return .ok(internalPluginVersion)
				} else if plugin.ghVersion < internalPluginBuild {
					return .needsUpdate(plugin)
				} else if plugin.ghVersion > internalPluginBuild {
					return .newer(plugin)
				} else {
					return .needsInstall
				}
			case _ where plugins.count > 1:
				return .multiple
			default:
				return .needsInstall
			}
		} catch let error {
			return .error(error)
		}
	}
	
	static func pluginFolder() throws -> String {
//		/Users/xxx/Library/Application Support/com.colliderli.iina/plugins
		let fm = FileManager.default
		let url = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
		let path = url.path + "/com.colliderli.iina/plugins/"
		
		if !fm.fileExists(atPath: path) {
			try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
		}
		return path
	}
	
	static func listPlugins() throws -> [PluginInfo] {
		let fm = FileManager.default
		let path = try pluginFolder()
		return try fm.contentsOfDirectory(atPath: path).filter {
			$0.hasSuffix("iinaplugin") || $0.hasSuffix("iinaplugin-dev")
		}.compactMap {
			let isDev = $0.hasSuffix("iinaplugin-dev")
			
			guard let data = fm.contents(atPath: path + $0 + "/" + "Info.json"),
				  var info = try? JSONDecoder().decode(PluginInfo.self, from: data) else { return nil }
			
			info.path = path + $0
			info.isDev = isDev
			return info
		}.filter {
			$0.identifier == "com.xjbeta.danmaku"
		}
	}
	
	static func uninstallPlugins(_ plugins: [PluginInfo]) {
		plugins.filter {
			!$0.isDev
		}.forEach {
			try? FileManager.default.removeItem(atPath: $0.path)
		}
	}
	
	static func installPlugin() throws {
		guard let path = Bundle.main.path(forResource: "iina-plugin-danmaku", ofType: "iinaplgz"),
			  FileManager.default.fileExists(atPath: path) else {
			throw IINAError.missingPluginFile
		}
		
		// IINA create(fromPackageURL url: URL)
		
		Log("Installing plugin from file: \(path)")
		
		let pluginsRoot = try pluginFolder()
		let tempFolder = ".temp.\(UUID().uuidString)"
		let tempZipFile = "\(tempFolder).zip"
		let tempDecompressDir = "\(tempFolder)-1"
		
		defer {
			[tempZipFile, tempDecompressDir].forEach { item in
				try? FileManager.default.removeItem(atPath: pluginsRoot + item)
			}
		}
		
		func removeTempPluginFolder() {
			try? FileManager.default.removeItem(atPath: pluginsRoot + tempFolder)
		}
		
		let cmd = [
			"cp '\(path)' '\(tempZipFile)'",
			"mkdir '\(tempFolder)' '\(tempDecompressDir)'",
			"unzip '\(tempZipFile)' -d '\(tempDecompressDir)'",
			"mv '\(tempDecompressDir)'/* '\(tempFolder)'/"
		].joined(separator: " && ")
		let (process, outText, errText) = Process.run(["/bin/bash", "-c", cmd], at: .init(fileURLWithPath: pluginsRoot))
		
		guard process.terminationStatus == 0 else {
			Log("outText: \(outText ?? "none")")
			Log("errText: \(errText ?? "none")")
			
			removeTempPluginFolder()
			throw IINAError.cannotUnpackage
		}
		
		try FileManager.default.moveItem(atPath: pluginsRoot + tempFolder, toPath: pluginsRoot + "com.xjbeta.danmaku.iinaplugin")
	}
}
