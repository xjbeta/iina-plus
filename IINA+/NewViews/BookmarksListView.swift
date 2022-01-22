//
//  BookmarksList.swift
//  IINA+
//
//  Created by xjbeta on 1/22/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import SwiftUI

struct BookmarksListView: View {
    
    var predicate: String
    var bookmarksRequest: FetchRequest<Bookmark>
    var bookmarks: FetchedResults<Bookmark> {
        bookmarksRequest.wrappedValue
    }
    
    var action: (Bookmark) -> Void
    
    init(predicate: String,
         perform action: @escaping (Bookmark) -> Void) {
        
        self.predicate = predicate
        self.action = action
        
        bookmarksRequest = .init(
            entity: Bookmark.entity(),
            sortDescriptors: [
                NSSortDescriptor(key: #keyPath(Bookmark.order), ascending: true)
            ],
            predicate: predicate == "" ? nil : .init(format: predicate),
            
            animation: Animation.default)
    }
    
    private var gridItemLayout = [
//        GridItem(.adaptive(minimum: 160))
        GridItem()
    ]
    
    
    var body: some View {
        LazyVGrid(columns: gridItemLayout, spacing: 5) {
            ForEach(bookmarks, id: \.uuid) { bookmark in
                LivingItemView(bookmark: bookmark)
                    .onTapGesture(count: 2) {
                        action(bookmark)
                    }
            }
        }
    }
}

struct BookmarksList_Previews: PreviewProvider {
    static var previews: some View {
        BookmarksListView(predicate: "") { _ in
        }
    }
}
