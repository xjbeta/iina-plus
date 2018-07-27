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
    static let suggestionsTableCellView = NSUserInterfaceItemIdentifier(rawValue: "SuggestionsTableCell")
    static let waitingTableCell = NSUserInterfaceItemIdentifier(rawValue: "WaitingTableCell")
    static let liveStatusTableCellView = NSUserInterfaceItemIdentifier(rawValue: "LiveStatusTableCell")
}
