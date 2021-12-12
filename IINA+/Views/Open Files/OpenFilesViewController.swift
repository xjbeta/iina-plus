//
//  OpenFilesViewController.swift
//  iina+
//
//  Created by xjbeta on 2019/6/11.
//  Copyright © 2019 xjbeta. All rights reserved.
//

import Cocoa
import PromiseKit

class OpenFilesViewController: NSViewController {
    @IBOutlet weak var videoTextField: NSTextField!
    @IBOutlet weak var danmakuTextField: NSTextField!
    
    @IBOutlet weak var videoButton: NSButton!
    @IBOutlet weak var danmakuButton: NSButton!
    
    @IBAction func select(_ sender: NSButton) {
        guard let window = view.window else { return }
        
        panel.beginSheetModal(for: window) { [weak self] in
            guard $0 == .OK, let url = self?.panel.url else {
                return
            }
            switch sender {
            case self?.videoButton:
                self?.videoURL = url
                self?.videoTextField.stringValue = url.lastPathComponent
            case self?.danmakuButton:
                self?.danmakuURL = url
                self?.danmakuTextField.stringValue = url.lastPathComponent
            default:
                break
            }
        }
    }
    
    @IBAction func cancel(_ sender: NSButton) {
        view.window?.close()
    }
    
    @IBAction func open(_ sender: NSButton) {
        getVideo().then {
            self.getDanmaku($0)
        }.done {
            guard let key = $0.videos.max (by: {
                $0.value.quality < $1.value.quality
            })?.key else {
                return
            }
            
            let id = $0.uuid
            NotificationCenter.default.post(name: .loadDanmaku, object: nil, userInfo: ["id": id])

            Processes.shared.openWithPlayer($0, key)
            self.view.window?.close()
        }.catch {
            Log($0)
        }
    }
    
    var videoURL: URL?
    var danmakuURL: URL?
    
    enum BilibiliIdType: String {
        case ep
        case ss
        case bv = "BV"
        case av
    }
    
    lazy var panel: NSOpenPanel = {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.canChooseFiles = true
        return p
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
    
    func formatBiliUrl(_ string: String) -> BilibiliUrl? {
        var string = string
        
        guard string.count > 2 else {
            return nil
        }
        
        if let type = BilibiliIdType(rawValue: String(string.prefix(2))) {
            switch type {
            case .av, .bv:
                string = "https://www.bilibili.com/video/" + string
            case .ep, .ss:
                string = "https://www.bilibili.com/bangumi/play/" + string
            }
        }
        
        return BilibiliUrl(url: string)
    }
    
    func getVideo() -> Promise<(YouGetJSON)> {
        let string = videoTextField.stringValue
        
        guard videoURL == nil else {
            if let path = videoURL?.absoluteString, path != "" {
                var json = YouGetJSON(url: path)
                json.site = .local
                return .value(json)
            } else {
                return .init(error: OpenFilesError.invalidVideoUrl)
            }
        }
        
        guard let bUrl = formatBiliUrl(string) else {
            return .init(error: OpenFilesError.invalidVideoUrl)
        }
        
        return Processes.shared.videoGet.decodeUrl(bUrl.fUrl)
    }
    
    func getDanmaku(_ yougetJSON: YouGetJSON) -> Promise<(YouGetJSON)> {
        let videoGet = Processes.shared.videoGet
        var json = yougetJSON
        guard danmakuURL == nil else {
            let url = danmakuURL!
            let data = FileManager.default.contents(atPath: url.path)
            videoGet.saveDMFile(data, with: json.uuid)
            return .value(json)
        }
        
        let s = danmakuTextField.stringValue
        
        if s == "" {
            return .value(json)
        }
        
        guard let bUrl = formatBiliUrl(s),
              let url = URL(string: bUrl.fUrl) else {
            return .init(error: OpenFilesError.invalidDanmakuUrl)
        }
        
        return videoGet.bilibiliPrepareID(url).map {
            json.id = $0.id
            json.bvid = $0.bvid
            json.duration = $0.duration
            return json
        }.then {
            videoGet.prepareDanmakuFile(yougetJSON: $0, id: json.uuid)
        }.map {
            json
        }
    }
    
    enum OpenFilesError: Error {
        case invalidVideoString
        case invalidVideoUrl
        case invalidDanmakuString
        case invalidDanmakuUrl
        case unsupported
    }
}

extension OpenFilesViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        switch control {
        case videoTextField:
            videoURL = nil
        case danmakuTextField:
            danmakuURL = nil
        default:
            return false
        }
        
        return true
    }
}
