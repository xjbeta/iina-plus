//
//  IINA+App.swift
//  IINA+
//
//  Created by xjbeta on 1/17/22.
//  Copyright © 2022 xjbeta. All rights reserved.
//

import SwiftUI

@main
struct IINA_App: App {
    
    @Environment(\.scenePhase) var scenePhase
    let persistenceController = PersistenceController.shared
    
    init() {
        Processes.shared.httpServer.start()
    }
    
    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }.onChange(of: scenePhase) { _ in
            persistenceController.saveContext()
        }
        
        Settings {
//            SettingsView()
            MainContentView()
        }
    }
    
    
}
