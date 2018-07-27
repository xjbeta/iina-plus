//
//  AddBookmarkViewController.swift
//  iina+
//
//  Created by xjbeta on 2018/7/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class AddBookmarkViewController: NSViewController {
    @IBOutlet weak var urlTextField: NSTextField!
    @IBAction func addToBookmarks(_ sender: Any) {
        let str = urlTextField.stringValue
        if dataManager.checkURL(str) {
            dataManager.addBookmark(str)
            self.dismiss(nil)
        }
        
    }
    let dataManager = DataManager()
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
