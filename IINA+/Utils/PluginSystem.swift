//
//  PluginSystem.swift
//  IINA+
//
//  Created by xjbeta on 2022/10/20.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import Cocoa

class PluginSystem: NSObject {
    
    enum PluginError: Error {
        case pluginNotFound
        case versionNotFound
        case versionFormatError
        case fileNotFound(String)
    }
    
    static func pluginVersion() throws -> String {
        struct Info: Decodable {
            let version: String
            let identifier: String
        }
        
        let fm = FileManager.default
        let url = try pluginURL()
        
        guard fm.fileExists(atPath: url.path) else {
            throw PluginError.pluginNotFound
        }
        let infoUrl = url.appendingPathComponent("Info.json")
        guard let data = fm.contents(atPath: infoUrl.path),
              let info = try? JSONDecoder().decode(Info.self, from: data),
              info.identifier == "com.xjbeta.danmaku"
        else {
            throw PluginError.versionNotFound
        }
        
        return info.version
    }
    
    static func pluginNumberVersion() throws -> Int {
        let version = try pluginVersion()
        
        let vs = version.split(separator: ".").compactMap({ Int($0) })
        guard vs.count == 3 else {
            throw PluginError.versionFormatError
        }
        
        return vs[0] * 1_000_000 + vs[1] * 1_000 + vs[2]
    }
    
    static func pluginURL() throws -> URL {
//        /Users/xxx/Library/Application Support/com.colliderli.iina/com.xjbeta.danmaku.iinaplugin
        
        var path = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        path.appendPathComponent("com.colliderli.iina")
        path.appendPathComponent("plugins")
        path.appendPathComponent("com.xjbeta.danmaku.iinaplugin")
        return path
    }
    
    /*
    static func installPlugin() throws {
        let fm = FileManager.default
        let path = Bundle.main.path(forResource: "iina-plugin-danmaku", ofType: "iinaplgz")

        let pluginUrl = try pluginURL()

        guard fm.fileExists(atPath: plgzPath) else {
            throw PluginError.fileNotFound(path ?? "nil path")
        }


        let pluginFolder = pluginUrl.deletingLastPathComponent()
        if !fm.fileExists(atPath: pluginFolder.path) {
            try fm.createDirectory(at: pluginFolder, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: pluginUrl.path) {
            try fm.removeItem(atPath: pluginUrl.path)
        }
        try fm.copyItem(atPath: plgzPath, toPath: pluginUrl.path)
    }
     */
}
