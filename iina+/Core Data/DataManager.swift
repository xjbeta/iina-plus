//
//  DataManager.swift
//  iina+
//
//  Created by xjbeta on 2018/7/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

class DataManager: NSObject {
    
    let context = (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
    let sortDescriptors = [NSSortDescriptor(key: #keyPath(Bookmark.order), ascending: true)]
    
    func requestData() -> [Bookmark] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")
        request.sortDescriptors = sortDescriptors
        if let fetch = try? context.fetch(request),
            let re = fetch as? [Bookmark] {
            return re
        }
        return []
    }
    
    func addBookmark(_ str: String) {
        let newBookmark = Bookmark(context: context)
        newBookmark.url = str
        if let last = requestData().last {
            newBookmark.order = last.order + 1
        } else {
            newBookmark.order = 0
        }
        try? context.save()
    }
    
    func deleteBookmark(_ index: Int) {
        let bookmark = requestData()[index]
        context.delete(bookmark)
        try? context.save()
    }
    
    func moveBookmark(at oldIndex: Int, to newIndex: Int) {
        let bookmarks = requestData()
        let oldBookmark = bookmarks[oldIndex]
        
        switch newIndex {
        case 0:
            oldBookmark.order = bookmarks[0].order - 1
        case bookmarks.count - 1:
            oldBookmark.order = bookmarks[newIndex].order + 1
        case _ where newIndex > oldIndex:
            oldBookmark.order = (bookmarks[newIndex].order + bookmarks[newIndex + 1].order) / 2
        case _ where newIndex < oldIndex:
            oldBookmark.order = (bookmarks[newIndex].order + bookmarks[newIndex - 1].order) / 2
        default:
            break
        }        
        try? context.save()
    }

}
