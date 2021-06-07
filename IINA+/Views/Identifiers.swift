//
//  Identifiers.swift
//  iina+
//
//  Created by xjbeta on 2018/7/7.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Foundation
import Cocoa


extension NSStoryboard.Name {
    static let main = "Main"
}

extension NSStoryboard.SceneIdentifier {
    static let suggestionsWindowController = "SuggestionsWindowController"
}

extension NSUserInterfaceItemIdentifier {
    static let suggestionsTableCellView = NSUserInterfaceItemIdentifier(rawValue: "SuggestionsTableCellView")
    static let waitingTableCellView = NSUserInterfaceItemIdentifier(rawValue: "WaitingTableCellView")
    static let liveStatusTableCellView = NSUserInterfaceItemIdentifier(rawValue: "LiveStatusTableCellView")
    static let liveUrlTableCellView = NSUserInterfaceItemIdentifier(rawValue: "LiveUrlTableCellView")
    static let bilibiliCardTableCellView = NSUserInterfaceItemIdentifier(rawValue: "BilibiliCardTableCellView")
    static let sidebarTableCellView = NSUserInterfaceItemIdentifier(rawValue: "SidebarTableCellView")
    
    
}

extension Notification.Name {
    static let reloadMainWindowTableView = Notification.Name("com.xjbeta.iina+.ReloadMainWindowTableView")
    static let sideBarSelectionChanged = Notification.Name("com.xjbeta.iina+.SideBarSelectionChanged")
    static let updateSideBarSelection = Notification.Name("com.xjbeta.iina+.updateSideBarSelection")
    static let progressStatusChanged = Notification.Name("com.xjbeta.iina+.ProgressStatusChanged")
    static let biliStatusChanged = Notification.Name("com.xjbeta.iina+.BiliStatusChanged")
    static let updateDanmakuWindow = Notification.Name("com.xjbeta.iina+.DanmakuWindow.Update")
    static let updateDanmukuFont = Notification.Name("com.xjbeta.iina+.DanmakuWindow.FontChanged")
    static let loadDanmaku = Notification.Name("com.xjbeta.iina+.LoadDanmaku")
}
