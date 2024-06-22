//
//  YouGet.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Marshal
import PromiseKit
import Cocoa

class Processes: NSObject {
    
    static let shared = Processes()
    let videoDecoder = VideoDecoder()
    let httpServer = HttpServer()
	let iina = IINAApp()
    
	private var decodeTask: Task<YouGetJSON, any Error>?
	
    fileprivate override init() {
    }
    
    var urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@?/" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: generalDelimitersToEncode + subDelimitersToEncode)
        
        return allowed
    }()
    
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
    
    func openWithPlayer(_ json: YouGetJSON, _ key: String) {
        let task = Process()
        let pipe = Pipe()
        task.standardInput = pipe
        
		let type = iina.archiveType()
		let buildVersion = iina.buildVersion()
        
		
        guard let u = json.videoUrl(key),
              u != "",
              let iinaUrl = json.iinaUrl(key, type: type) else {
            Log("Not Found YouGetJSON Url.")
            return
        }
        
        switch Preferences.shared.livePlayer {
        case .iina where type == .plugin:
            openWithURLScheme(iinaUrl)
        case .iina where type == .danmaku && buildVersion >= 15:
//            IINA-Danmaku 1.1.2 NEW API
            openWithURLScheme(iinaUrl)
        case .iina where type == .danmaku && buildVersion < 15:
            openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
        case .iina where type == .normal && buildVersion >= 90:
//            1.0.0 beta3 build 86  URL Scheme without mpv options
//            1.0.0 beta4 build 90
            if [.bilibili, .bangumi, .biliLive].contains(json.site) {
                openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
            } else {
                openWithURLScheme(iinaUrl)
            }
        case .iina where type == .normal && buildVersion >= 56:
//            iinc-cli build 56
            openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
        case .mpv:
            openWithProcess(u, args: json.mpvOptions, uuid: json.uuid)
        default:
            break
        }
        
    }
    
    func openWithYtdl(_ url: String) {
        // Use IINA's ytdl to open the raw url
		let buildVersion = iina.buildVersion()
        guard let v = url.addingPercentEncoding(withAllowedCharacters: urlQueryValueAllowed) else { return }
        if buildVersion >= 90 {
            let u = "iina://open?url=\(v)"
            guard let uu = URL(string: u) else { return }
            Log("Open IINA URL:  \(u)")
            NSWorkspace.shared.open(uu)
        } else if buildVersion >= 56 {
            openWithProcess(url, args: [], uuid: "")
        }
    }
    
    func openWithProcess(_ url: String, args: [String], uuid: String) {
        let livePlayer = Preferences.shared.livePlayer
        let isIINA = livePlayer == .iina
        var args = args
		
        if isIINA {
			let type = iina.archiveType()
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
			Log("Not found launchPath")
			return
		}
		
		
		args.insert(launchPath, at: 0)
		
        Log("Player arguments: \(args)")
		
		let _ = Process.run(args, wait: false)
		
    }
    
    func openWithURLScheme(_ url: String) {
        guard let u = URL(string: url) else {
            Log("Invalid url scheme \(url).")
            return
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
