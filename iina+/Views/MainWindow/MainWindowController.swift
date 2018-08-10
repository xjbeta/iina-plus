//
//  MainWindowController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/13.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class MainWindowController: NSWindowController, NSWindowDelegate {
    let suggestionsWindowController = NSStoryboard(name: .main, bundle: nil).instantiateController(withIdentifier:.suggestionsWindowController) as! SuggestionsWindowController
    @IBOutlet weak var searchField: NSSearchField!
    @IBAction func startSearch(_ sender: Any) {
        let str = searchField.stringValue
        guard str != "" else {
            suggestionsWindowController.cancelSuggestions()
            return
        }
        
        
        if str.isUrl {
            suggestionsWindowController.begin(for: searchField, with: str)
        }
    }
    
    @IBOutlet weak var mainTabViewSegmentedControl: NSSegmentedControl!
    @IBAction func switchMainTabView(_ sender: Any) {
        if let mainViewController = window?.contentViewController as? MainViewController {
            mainViewController.mainTabViewSelectedIndex = mainTabViewSegmentedControl.selectedSegment
        }
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.isMovableByWindowBackground = true
        switchMainTabView(self)
    }
    
    func windowDidBecomeMain(_ notification: Notification) {
        NotificationCenter.default.post(name: .reloadMainWindowTableView, object: nil)
    }
    
    func windowDidResignMain(_ notification: Notification) {
        suggestionsWindowController.cancelSuggestions()
    }
    
    func windowWillStartLiveResize(_ notification: Notification) {
        suggestionsWindowController.cancelSuggestions()
    }
    
}


