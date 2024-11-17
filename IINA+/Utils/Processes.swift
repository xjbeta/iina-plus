//
//  YouGet.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal
import Cocoa
 
@MainActor
final class Processes: NSObject, Sendable {
    
	enum ProcessesError: Error {
		case openFailed(String)
		case urlNotFound
		case notSupported
	}
	
    static let shared = Processes()
    let videoDecoder = VideoDecoder()
    let iina = IINAApp()
    
    
    let httpServer = HttpServer()
    
	private var decodeTask: Task<YouGetJSON, any Error>?
	
    fileprivate override init() {
        
    }
    
    func which(_ str: String) -> [String] {
        // which you-get
        // command -v you-get
        // type -P you-get
		
		guard Preferences.shared.customMpvPath == "" else {
			return [Preferences.shared.customMpvPath]
		}
		
		let (process, outText, errText) = Process.run([
			"/bin/bash", "-l", "-c", "which mpv"
		])
		
		guard process.terminationStatus == 0, let out = outText else {
			Log("outText: \(outText ?? "none")")
			Log("errText: \(errText ?? "none")")
			return []
		}
		
		return out.components(separatedBy: "\n").filter({ $0 != "" })
    }

    func mpvVersion() -> String {
		
		var cmd = "mpv -V"
		
		if Preferences.shared.customMpvPath != "" {
			cmd = Preferences.shared.customMpvPath + " -V"
		}
		
		let (process, outText, errText) = Process.run([
			"/bin/bash", "-l", "-c", cmd
		])
		
		guard process.terminationStatus == 0, let out = outText else {
			Log("outText: \(outText ?? "none")")
			Log("errText: \(errText ?? "none")")
			return "unknown"
		}
		
		let str = out.components(separatedBy: "\n").filter {
			$0 != ""
			&& $0.starts(with: "mpv")
			&& $0.contains("Copyright")
		}.first ?? ""
		
		return str.subString(from: "mpv", to: "Copyright").replacingOccurrences(of: " ", with: "")
    }
    
    func decodeURL(_ url: String) async throws -> YouGetJSON {
        decodeTask?.cancel()
		
		let task = Task {
			try await videoDecoder.decodeUrl(url)
		}
		
		decodeTask = task
		return try await task.value
    }
    
    enum DecodeUrlError: Error {
        case normalExit
        
        case notFoundDecoder
    }
    
    func stopDecodeURL() {
		decodeTask?.cancel()
    }
    
	func openWithPlayer(_ json: YouGetJSON, _ key: String) async throws {
		await iina.updateIINAState()
		let type = await iina.archiveType
		let buildVersion = await iina.buildVersion
        
		let urlScheme = json.iinaURLScheme(key, type: type)
		
        switch Preferences.shared.livePlayer {
        case .iina where type == .plugin:
			// IINA Danmaku Plguin
            try openWithURLScheme(urlScheme)
        case .iina where type == .normal && buildVersion >= 90:
			// IINA Official with URL Scheme + MPV Options
            // 1.0.0 beta3 build 86  URL Scheme without mpv options
            // 1.0.0 beta4 build 90
			try openWithURLScheme(urlScheme)
		case .iina where type == .danmaku && buildVersion >= 15:
			// IINA-Danmaku 1.1.2 NEW API
			try openWithURLScheme(urlScheme)
		case .iina where type == .danmaku && buildVersion < 15:
			// IINA-Danmaku cli
			try await openWithProcess(json.videoUrl(key), args: json.mpvOptions, uuid: json.uuid)
        case .iina where type == .normal && buildVersion >= 56:
			// IINA Official with cli
			// iinc-cli build 56
            try await openWithProcess(json.videoUrl(key, forDash: true), args: json.mpvOptions, uuid: json.uuid)
        case .mpv:
            try await openWithProcess(json.videoUrl(key), args: json.mpvOptions, uuid: json.uuid)
        default:
			throw ProcessesError.notSupported
        }
    }
    
	private func openWithProcess(_ url: String?, args: [String], uuid: String) async throws {
		guard let url, url != "" else {
			throw ProcessesError.openFailed("Nil url")
		}
		
        let livePlayer = Preferences.shared.livePlayer
        let isIINA = livePlayer == .iina
        var args = args
		
        if isIINA {
			let type = await iina.archiveType
            args = args.map {
                "--mpv-" + $0
            }
            if type == .danmaku {
                if Preferences.shared.enableDanmaku {
                    args.append("--danmaku")
                    args.append("--uuid=\(uuid)")
                }
                args.append("--directly")
            }
        } else {
            args.append(MPVOption.Terminal.reallyQuiet)
			args.append(MPVOption.Terminal.noTerminal)
            args = args.map {
                "--" + $0
            }
        }
        args.insert(url, at: 0)
		
		let launchPath = isIINA ? livePlayer.rawValue : "\(self.which(livePlayer.rawValue).first ?? "")"
		
		guard launchPath != "" else {
			throw ProcessesError.openFailed("Not found launchPath")
		}
		
		args.insert(launchPath, at: 0)
		
        Log("Player arguments: \(args)")
		
		let _ = Process.run(args, wait: false)
		
    }
    
    private func openWithURLScheme(_ url: String?) throws {
        guard let url, url != "", let u = URL(string: url) else {
			throw ProcessesError.openFailed("Invalid url scheme \(url ?? "nil url").")
        }
        Log("openWithURLScheme \(url).")
        NSWorkspace.shared.open(u)
    }
}


extension Process {
	@discardableResult
	static func run(_ cmd: [String], at currentDir: URL? = nil, wait: Bool = true) -> (process: Process, outText: String?, errText: String?) {
		guard cmd.count > 0 else {
			fatalError("Process.launch: the command should not be empty")
		}
		
		let (stdout, stderr) = (Pipe(), Pipe())
		let process = Process()
		process.executableURL = URL(fileURLWithPath: cmd[0])
		process.currentDirectoryURL = currentDir ?? Bundle.main.resourceURL
		
		process.arguments = [String](cmd.dropFirst())
		process.standardOutput = stdout
		process.standardError = stderr
		process.launch()
	
		guard wait else {
			return (process, nil, nil)
		}
		
		process.waitUntilExit()
		
		let outText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
		let errText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
		
		return (process, outText, errText)
	}
}
