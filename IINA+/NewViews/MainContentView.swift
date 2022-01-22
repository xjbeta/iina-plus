//
//  MainContentView.swift
//  IINA+
//
//  Created by xjbeta on 1/17/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import SwiftUI

struct MainContentView: View {
    @FetchRequest(entity: Bookmark.entity(),
                  sortDescriptors: [],
                  predicate: nil,
                  animation: Animation.default
    ) var bookmarks: FetchedResults<Bookmark>
    
    var bookmarksView: some View {
        LazyVGrid(columns: gridItemLayout, spacing: 5) {
            ForEach(bookmarks, id: \.uuid) { bookmark in
                LivingItemView(bookmark: bookmark)
                    .onTapGesture(count: 2) {
                        print(bookmark.url)
                        bookmarkUrl = bookmark.url
                        isDecoding = true
                    }
            }
        }
    }
    
    
    private var gridItemLayout = [
//        GridItem(.adaptive(minimum: 160))
        GridItem()
    ]
    
    @State private var isDecoding = false
    @State private var bookmarkUrl = ""
    
    var body: some View {
        ScrollView {
            bookmarksView
                .padding()
        }
        .frame(minWidth: 300, maxWidth: .infinity)
    }
}

//struct MainContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        MainContentView()
//    }
//}
