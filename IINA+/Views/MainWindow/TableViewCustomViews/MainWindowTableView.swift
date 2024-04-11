//
//  MainWindowTableView.swift
//  IINA+
//
//  Created by xjbeta on 2024/4/11.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

// https://stackoverflow.com/a/63446191
class MainWindowTableView: NSTableView {

	private var _clickedRow: Int = -1
	override var clickedRow: Int {
		get {
			_clickedRow
		}
		set {
			_clickedRow = newValue
		}
	}
	
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
	override func menu(for event: NSEvent) -> NSMenu? {
		let location: CGPoint = convert(event.locationInWindow, from: nil)
		clickedRow = row(at: location)
				
		if clickedRow >= 0,
		   let rowView = rowView(atRow: clickedRow, makeIfNecessary: false) as? MainWindowTableRowView {
			rowView.isContextualMenuTarget = true
		}
		
		return self.menu
	}
	
	override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
		super.didCloseMenu(menu, with: event)
		
		if clickedRow >= 0,
		   let rowView = rowView(atRow: clickedRow, makeIfNecessary: false) as? MainWindowTableRowView {
			rowView.isContextualMenuTarget = false
		}
	}
}
