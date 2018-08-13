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
        
        if menuItem.action == #selector(reloadMainWindow) {
            if let splitViewController = NSApp.keyWindow?.contentViewController as? NSSplitViewController,
                splitViewController.splitViewItems.count > 1,
                let mainViewController = splitViewController.splitViewItems[1].viewController as? MainViewController {
                switch mainViewController.mainTabViewSelectedIndex {
                case 0:
                    menuItem.title = "Reload Live Status"
                    return true
                case 1:
                    menuItem.title = "Reload Bilibili List"
                    return true
                default: break
                }   
            }
        }
        
        if menuItem.action == #selector(help) {
            return true
        }
        return false
    }
    
    @IBAction func reloadMainWindow(_ sender: Any) {
        NotificationCenter.default.post(name: .reloadMainWindowTableView, object: nil)
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
    @IBAction func help(_ sender: Any) {
        if let url = URL(string: "https://github.com/xjbeta/iina-plus") {
            NSWorkspace.shared.open(url)
        }
    }
    
}
