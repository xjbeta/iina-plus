//
//  MainMenu.swift
//  iina+
//
//  Created by xjbeta on 2018/7/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class MainMenu: NSObject {
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        if let window = NSApp.keyWindow,
            let appDelegate = NSApp.delegate as? AppDelegate,
            let undoManager = appDelegate.persistentContainer.viewContext.undoManager {
            
            if menuItem.action == #selector(undo) {
                return window.windowController is MainWindowController && undoManager.canUndo
            }
            if menuItem.action == #selector(redo) {
                return window.windowController is MainWindowController && undoManager.canRedo
            }
        }
        
        if menuItem.action == #selector(reloadLiveStatus) {
            return NSApp.keyWindow?.windowController is MainWindowController
        }
        return false
    }
    
    @IBAction func reloadLiveStatus(_ sender: Any) {
        NotificationCenter.default.post(name: .reloadLiveStatus, object: nil)
    }
    
    @IBAction func undo(_ sender: Any) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.persistentContainer.viewContext.undo()
        }
    }
    
    @IBAction func redo(_ sender: Any) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.persistentContainer.viewContext.redo()
        }
    }
    
}
