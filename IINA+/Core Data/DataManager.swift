//
//  DataManager.swift
//  iina+
//
//  Created by xjbeta on 2018/7/27.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa

@MainActor
class DataManager: NSObject {
    
    let context = (NSApp.delegate as! AppDelegate).persistentContainer.viewContext
	
    let sortDescriptors = [NSSortDescriptor(key: #keyPath(Bookmark.order), ascending: true)]
    
    private let tokenBucket = TokenBucket(tokens: 1)
    private var bookmarkReloadDate = [NSManagedObjectID: TimeInterval]()
    
    func requestData() -> [Bookmark] {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")
        request.sortDescriptors = sortDescriptors
        if let fetch = try? context.fetch(request),
            let re = fetch as? [Bookmark] {
            return re
        }
        return []
    }
    
    func reloadAllBookmark() {
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for i in requestData() {
                    let id = i.objectID
                    group.addTask {
                        await self.reloadBookmark(id)
                    }
                }
            }
        }
    }
    
    func reloadBookmark(_ id: NSManagedObjectID) async {
        guard let obj = try? context.existingObject(with: id) as? Bookmark else { return }
        let site = SupportSites(url: obj.url)
        if site == .unsupported {
            obj.state = LiveState.none.raw
            save()
            return
        }
        
        let refreshInterval: CGFloat = [.bangumi, .bilibili, .unsupported].contains(site) ? 300 : 20
        
        let rt = await tokenBucket.withToken {
            // Inited
            if let ti = await bookmarkReloadDate[id] {
                // Updating
                if ti == -1 {
                    return 1
                }
                
                if Date(timeIntervalSince1970: ti).secondsSinceNow < refreshInterval {
                    return 1
                }
            }
            return 0
        }
        
        if rt == 1 {
            return
        }
        
        do {
            let info = try await Processes.shared.videoDecoder.liveInfo(obj.url)
            await obj.setInfo(info)
        } catch let error {
            obj.setInfoError(error)
        }

        save()
        
        await tokenBucket.withToken { @MainActor in
            bookmarkReloadDate[id] = Date().timeIntervalSince1970
        }
    }
    
    func addBookmark(_ str: String) {
        let newBookmark = Bookmark(context: context)
        newBookmark.url = str
        if let last = requestData().last {
            newBookmark.order = last.order + 1
        } else {
            newBookmark.order = 0
        }
        save()
        Task {
            await reloadBookmark(newBookmark.objectID)
        }
    }
    
    func deleteBookmark(_ index: Int) {
        let bookmark = requestData()[index]
        context.delete(bookmark)
        save()
    }
    
    func delete(_ bookmark: Bookmark) {
        context.delete(bookmark)
        save()
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
        save()
    }

    func save() {
        try? context.save()
    }
}
