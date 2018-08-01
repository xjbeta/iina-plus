//
//  DataManager.swift
//  iina+
//
//  Created by xjbeta on 2018/7/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class DataManager: NSObject {
    
    var appDelegate: AppDelegate {
        return NSApp.delegate as! AppDelegate
    }
    
    func requestData() -> [Bookmark] {
        let context = appDelegate.persistentContainer.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")
        
        if let fetch = try? context.fetch(request),
            let re = fetch as? [Bookmark] {
            return re
        }
        return []
    }
    
    func addBookmark(_ str: String) {
        let context = appDelegate.persistentContainer.viewContext
        let newBookmark = Bookmark(context: context)
        newBookmark.url = str
        try? context.save()
    }
    
    func deleteBookmark(_ index: Int) {
        let context = appDelegate.persistentContainer.viewContext
        let bookmark = requestData()[index]
        context.delete(bookmark)
        try? context.save()
    }
    
    func checkURL(_ url: String) -> Bool {
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count))
            return matches.count == 1
        } catch {
            return false
        }
    }

}
