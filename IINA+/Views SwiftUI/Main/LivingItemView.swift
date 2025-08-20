//
//  LivingItemView.swift
//  IINA+
//
//  Created by xjbeta on 1/17/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import SwiftUI
import SDWebImageSwiftUI

struct LivingItemView: View {
    @ObservedObject var bookmark: Bookmark
    @State private var isPressed: Bool = false
    
    
    var body: some View {
        let tap = TapGesture().onEnded {
            isPressed = !isPressed
        }
        
        Group {
            if bookmark.site == .unsupported {
                Text(bookmark.url)
                    .frame(maxWidth: .infinity)
            } else {
                oldLivingItem
                    .onAppear {
                        bookmark.updateState()
                    }
            }
        }
        .padding(6)
        .background(isPressed ? Color.secondary : .clear)
        .contentShape(Rectangle())
        .cornerRadius(6)
//        .gesture(tap)

        
    }
    
    var oldLivingItem: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                WebImage(url: {
                    guard let avatar = bookmark.avatar else {
                        return nil
                    }
                    
                    return .init(string:  avatar)
                }())
                    .resizable()
                    .indicator(.activity)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(5)
                    .frame(width: 40, height: 40)
                
                Text(bookmark.liveTitle)
                    .lineLimit(1)
                Spacer()
                Text(bookmark.liveName)
                    .font(.subheadline)
                    .lineLimit(1)
                
                if bookmark.state != -99 {
                    RoundedRectangle(cornerSize: .init(width: 5, height: 5))
                        .foregroundColor(
                            {
                                switch bookmark.state {
                                case 1:
                                    return .green
                                case 0:
                                    return .red
                                case -1:
                                    return .gray
                                default:
                                    return nil
                                }
                            }()
                        )
                        .frame(width: 10, height: 10)
                }
            }

            Divider().padding(.leading, 48)
        }
    }
    
    
    
    
    var newLivingItem: some View {
        Group {
            if bookmark.site == .unsupported {
                unsupportItem
            } else {
                imageItem
            }
        }
        .padding(8)
    }
    
    var unsupportItem: some View {
        Group {
            Text(bookmark.url)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color.purple)
        .cornerRadius(5)
    }
    
    var imageItem: some View {
        VStack(alignment: .leading) {
            WebImage(url: {
                guard var cover = bookmark.cover else {
                    return nil
                }
                
                if cover == "",
                   let c = bookmark.avatar {
                    cover = c
                }
                return .init(string:  cover)
            }())
                .resizable()
                .indicator(.activity)
                .aspectRatio(16/9, contentMode: .fit)
                .cornerRadius(5)
            Text(bookmark.liveTitle)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(bookmark.liveName)
                    .font(.subheadline)
                    .lineLimit(1)
                
                bookmarkStateView
            }
        }
    }
    
    var bookmarkStateView: some View {
        HStack {
            switch bookmark.state {
            case 1:
                Spacer()
                Text("living")
            case 0:
                Spacer()
                Text("offline")
            case -99:
                // Bilibili Bangumi
                EmptyView()
            case -1:
                // Error
                EmptyView()
            default:
                EmptyView()
            }
        }
    }
}

struct LivingItemView_Previews: PreviewProvider {
    static let persistence = PersistenceController.preview
    
    static var bookmark: Bookmark = {
        let context = persistence.container.viewContext
        let bookmark = Bookmark(context: context)
        bookmark.liveName = "Live Name"
        bookmark.liveTitle = "Live Title"
        bookmark.state = 1
        bookmark.cover = "https://s1.hdslb.com/bfs/static/blive/live-assets/common/images/no-cover.png@1e_1c_100q.png"
        
        
        return bookmark
    }()

    
    static var previews: some View {
        LivingItemView(bookmark: bookmark)
    }
}
