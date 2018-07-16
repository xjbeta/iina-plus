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
    static let main = NSStoryboard.Name(rawValue: "Main")
}

extension NSStoryboard.SceneIdentifier {
    static let suggestionsWindowController = NSStoryboard.SceneIdentifier(rawValue: "SuggestionsWindowController")
}

extension NSUserInterfaceItemIdentifier {
    static let suggestionsTableCellView = NSUserInterfaceItemIdentifier(rawValue: "SuggestionsTableCell")
    static let waitingTableCell = NSUserInterfaceItemIdentifier(rawValue: "WaitingTableCell")
}
