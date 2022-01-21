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
        LazyVGrid(columns: gridItemLayout, spacing: 20) {
            ForEach(bookmarks, id: \.uuid) { bookmark in
            }
        }
    }
    
    
    private var gridItemLayout = [
        GridItem(.adaptive(minimum: 160))
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
