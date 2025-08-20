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
    ) var allBookmarks: FetchedResults<Bookmark>
    
    
    @State private var bookmarksListPredicate = ""
    
    let liveState = MainViewController.LiveStateMenuItems.self
    @State private var liveStateSelection: Int = 2
    
    var liveStatePicker: some View {
        Picker("Live State", selection: $liveStateSelection) {
            Text("All").tag(liveState.all.rawValue)
            Divider()
            Text("Living").tag(liveState.living.rawValue)
            Text("Offline").tag(liveState.offline.rawValue)
            Divider()
            Text("Other").tag(liveState.other.rawValue)
        }
        .onChange(of: liveStateSelection) { _ in
            self.updateFilter()
        }
    }
    
    @State private var siteSelection: String = "All"
    
    var sites: [SupportSites] {
        get {
            let sites = allBookmarks.map {
                $0.url
            }.compactMap(SupportSites.init(url: ))
                .filter {
                    $0 != .unsupported
                }
            
            return Array(Set(sites))
                .sorted {
                    $0.siteName > $1.siteName
                }
        }
    }
    
    
    var sitePicker: some View {
        Picker("Site", selection: $siteSelection) {
            Text("All Sites").tag("All")
            Divider()
            ForEach(sites, id: \.rawValue) {
                Text($0.siteName).tag($0.rawValue)
            }
        }
        .onChange(of: siteSelection) { _ in
            self.updateFilter()
        }
    }
    
    var bookmarksView: some View {
        BookmarksListView(predicate: bookmarksListPredicate) {
            bookmarkUrl = $0.url
            isDecoding = true
        }
    }
    
    

    @State private var isDecoding = false
    @State private var bookmarkUrl = ""
    
    var body: some View {
        ScrollView {
            bookmarksView
                .padding()
        }
        .frame(minWidth: 300, maxWidth: .infinity)
        .toolbar {
            liveStatePicker
            sitePicker
        }
        .sheet(isPresented: $isDecoding) {
            print("Stop Decoding")
        } content: {
            DecodeSheetView(isVisible: $isDecoding,
                            url: $bookmarkUrl)
        }
    }
    
    func updateFilter() {
        var f = ""
        
        switch liveState.init(rawValue: liveStateSelection) {
        case .all:
            f = ""
        case .living:
            f = "state == 1"
        case .offline:
            f = "state == 0"
        case .other:
            // Bangumi bilibili -99
            f = "state == -1"
        case .none:
            f = ""
        }
        
        
        var f2 = ""
        
        
        
        switch siteSelection {
        case "All":
            f2 = ""
        default:
            f2 = "url CONTAINS '\(siteSelection)'"
            if siteSelection == SupportSites.bilibili.rawValue
                || siteSelection == SupportSites.bangumi.rawValue {
                f = ""
            }
        }

        let format = [f, f2].filter {
            $0 != ""
        }.joined(separator: " && ")
        
        guard format != "" else {
            bookmarksListPredicate = ""
            Log("Remove Filters")
            return
        }

        if bookmarksListPredicate == format {
            return
        }
        
        Log("New Filters: \(format)")
        bookmarksListPredicate = format
    }
}

//struct MainContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        MainContentView()
//    }
//}
