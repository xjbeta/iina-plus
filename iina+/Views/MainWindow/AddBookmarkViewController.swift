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
        if str.isUrl {
            dataManager.addBookmark(str)
            dismiss?()
        }
    }
    
    @IBAction func cancel(_ sender: Any) {
        dismiss?()
    }
    
    let dataManager = DataManager()
    
    var dismiss: (() -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
