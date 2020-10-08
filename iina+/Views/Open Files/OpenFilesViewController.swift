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
        var yougetJSON: YouGetJSON?
        let id = UUID().uuidString
        getVideo().get {
            yougetJSON = $0
        }.then { _ in
            self.getDanmaku(id)
        }.done {
            guard let stream = yougetJSON?.streams.sorted(by: { $0.key < $1.key }).first?.value,
                let urlStr = stream.url else {
                return
            }
            NotificationCenter.default.post(name: .loadDanmaku, object: nil, userInfo: ["id": id])
            
            if self.isBilibiliVideo() {
                Processes.shared.openWithPlayer([urlStr], audioUrl: yougetJSON?.audio ?? "", title: yougetJSON?.title ?? "", options: .bilibili, uuid: id)
            } else {
                Processes.shared.openWithPlayer([urlStr], title: yougetJSON?.title ?? "", options: .withoutYtdl, uuid: id)
            }
            
            self.view.window?.close()
        }.catch {
            Log($0)
        }
    }
    
    var videoURL: URL?
    var danmakuURL: URL?
    
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
    
    func isBilibiliVideo() -> Bool {
        if videoURL == nil {
            let videoStr = videoTextField.stringValue
            return videoStr.starts(with: "av") || videoStr.starts(with: "https://www.bilibili.com/video/av")
        } else {
            return false
        }
    }
    
    func getVideo() -> Promise<(YouGetJSON)> {
        return Promise { resolver in
            guard videoURL == nil else {
                if let path = videoURL?.path {
                    resolver.fulfill(YouGetJSON(url: path))
                } else {
                    resolver.reject(OpenFilesError.invalidVideoUrl)
                }
                return
            }
            
            let videoStr = videoTextField.stringValue
            
            if videoStr.starts(with: "av") || videoStr.starts(with: "https://www.bilibili.com/video/av") {
                guard let aid = Int(videoStr.subString(from: "av")) else {
                        resolver.reject(OpenFilesError.invalidVideoString)
                        return
                }
                Processes.shared.videoGet.decodeUrl("https://www.bilibili.com/video/av\(aid)").done {
                    resolver.fulfill($0)
                    }.catch {
                        resolver.reject($0)
                }
            } else {
                resolver.fulfill(YouGetJSON(url: videoStr))
            }
        }
    }
    
    func getDanmaku(_ id: String) -> Promise<()> {
        return Promise { resolver in
            guard danmakuURL == nil else {
                if let url = danmakuURL {
                    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                        resolver.reject(VideoGetError.prepareDMFailed)
                        return
                    }
                    let folderName = "danmaku"
                    var filesURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    filesURL.appendPathComponent(bundleIdentifier)
                    filesURL.appendPathComponent(folderName)
                    let fileName = "danmaku" + "-" + id + ".xml"
                    filesURL.appendPathComponent(fileName)
                    
                    try? FileManager.default.removeItem(atPath: filesURL.path)
                    try FileManager.default.copyItem(atPath: url.path, toPath: filesURL.path)
                    resolver.fulfill(())
                } else {
                    resolver.reject(OpenFilesError.invalidDanmakuUrl)
                }
                return
            }
            
            
            let danmakuStr = danmakuTextField.stringValue
            
            if danmakuStr.starts(with: "av") || danmakuStr.starts(with: "https://www.bilibili.com/video/av") {
                guard let aid = Int(danmakuStr.subString(from: "av")), let url = URL(string: "https://www.bilibili.com/video/av\(aid)") else {
                    resolver.reject(OpenFilesError.invalidVideoString)
                    return
                }
                Processes.shared.videoGet.prepareDanmakuFile(url, id: id).done {
                    resolver.fulfill(())
                    }.catch {
                        resolver.reject($0)
                }
            } else {
                resolver.reject(OpenFilesError.unsupported)
            }
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
