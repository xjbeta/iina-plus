//
//  AdvancedViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/8/13.
//  Copyright © 2018 xjbeta. All rights reserved.
//

@preconcurrency import Cocoa
import SDWebImage
import WebKit

class AdvancedViewController: NSViewController, NSMenuDelegate {
    
    @IBOutlet weak var cacheSizeTextField: NSTextField!
    @IBAction func cleanUpCache(_ sender: NSButton) {
        SDImageCache.shared.clearDisk(onCompletion: nil)
        initCacheSize()
		
		WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSince1970: 0), completionHandler:{ })
    }
    
    
// MARK: - Live State Color
    @IBOutlet var livingColorPick: ColorPickButton!
    @IBOutlet var offlineColorPick: ColorPickButton!
    @IBOutlet var replayColorPick: ColorPickButton!
    @IBOutlet var unknownColorPick: ColorPickButton!
    
    
    var colorPanelCloseNotification: NSObjectProtocol?
    var currentPicker: ColorPickButton?
    
    @IBAction func pickColor(_ sender: ColorPickButton) {
        currentPicker = sender
        
        let colorPanel = NSColorPanel.shared
        colorPanel.color = sender.color
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorDidChange))
        colorPanel.makeKeyAndOrderFront(self)
        colorPanel.isContinuous = true
    }
    
    let pref = Preferences.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        colorPanelCloseNotification = NotificationCenter.default.addObserver(forName: NSColorPanel.willCloseNotification, object: nil, queue: .main) { _ in
			Task { @MainActor in
				self.currentPicker = nil
			}
        }
        
        livingColorPick.color = pref.stateLiving
        offlineColorPick.color = pref.stateOffline
        replayColorPick.color = pref.stateReplay
        unknownColorPick.color = pref.stateUnknown
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        initCacheSize()
    }
    
    func initCacheSize() {
        SDImageCache.shared.calculateSize { count, size in
            let s = String(format: "%.2f MB", Double(size) / 1024 / 1024)
            self.cacheSizeTextField.stringValue = s
        }
    }
    
    @objc func colorDidChange(sender: NSColorPanel) {
        let colorPanel = sender
        guard let picker = currentPicker else { return }
        
        picker.color = colorPanel.color
        
        switch picker {
        case livingColorPick:
            pref.stateLiving = colorPanel.color
        case offlineColorPick:
            pref.stateOffline = colorPanel.color
        case replayColorPick:
            pref.stateReplay = colorPanel.color
        case unknownColorPick:
            pref.stateUnknown = colorPanel.color
        default:
            break
        }
    }
    
	deinit {
        if let n = colorPanelCloseNotification {
            NotificationCenter.default.removeObserver(n)
        }
    }
}

