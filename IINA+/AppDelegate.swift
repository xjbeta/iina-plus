//
//  AppDelegate.swift
//  iina+
//
//  Created by xjbeta on 2018/7/5.
//  Copyright © 2018 xjbeta. All rights reserved.
//

import Cocoa
import SDWebImage
import Sparkle

@main
class AppDelegate: NSObject, NSApplicationDelegate {

	let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
	
    lazy var logUrl: URL? = {
        do {
            var logPath = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            logPath.appendPathComponent(Bundle.main.bundleIdentifier!)
            var isDir = ObjCBool(false)
            if !FileManager.default.fileExists(atPath: logPath.path, isDirectory: &isDir) {
                try FileManager.default.createDirectory(at: logPath, withIntermediateDirectories: true, attributes: nil)
            }
            guard let appName = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String else {
                return nil
            }
            logPath.appendPathComponent("\(appName).log")
            return logPath
        } catch let error {
            Log(error)
            return nil
        }
    }()
	
    func applicationDidFinishLaunching(_ aNotification: Notification) {
		
		#if DEBUG
		updaterController.updater.automaticallyChecksForUpdates = false
		#endif
		
        deleteUselessFiles()
        Log("App did finish launch")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        Log("App Version \(version) (Build \(build))")
        Log("macOS " + ProcessInfo().operatingSystemVersionString)

        persistentContainer.persistentStoreDescriptions.forEach {
            Log("CoreData Path: \($0.url?.path ?? "none")")
        }
        
        initImageCache()
        
        Processes.shared.httpServer.start()
		
		showUpdateAlert()
    }


    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.windowController is MainWindowController {
                    window.makeKeyAndOrderFront(self)
                }
            }
        }
        return true
    }
    
	@MainActor
	func showUpdateAlert() {
		guard !Preferences.shared.updateInfo070 else { return }
		Preferences.shared.updateInfo070 = true
		
		
		let alert = NSAlert()
		alert.messageText = "IINA-Plus 0.7.0"
		alert.informativeText = """
🎉

IINA-Plus 弹幕插件已经和原版IINA v1.3.2+ 兼容
请安装原版IINA 后进入IINA-Plus 设置 安装/更新 插件
The IINA-Plus danmaku plugin is compatible with the official IINA v1.3.2+.
Please go to IINA-Plus settings after installing official IINA to install/update the plugin.

IINA official website
https://iina.io/
"""
		
		alert.alertStyle = .warning
		alert.addButton(withTitle: "OK")
		let _ = alert.runModal()
	}
	
    func initImageCache() {
        Log("Image Cache Path: \(SDImageCache.shared.diskCachePath)")
        
        SDImageCache.shared.config.maxDiskAge = 60 * 60 * 24 * 14
        SDImageCache.shared.deleteOldFiles(completionBlock: nil)
        
        ImageLoader.removeOld()
    }
    
    func deleteUselessFiles() {
        if let url = logUrl {
            try? FileManager.default.removeItem(at: url)
        }
        
        UserDefaults.standard.removeObject(forKey: "enableLogging")
        UserDefaults.standard.removeObject(forKey: "logLevel")
        // delete log files for old api.
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        let logsUrl = libraryPath.first!.appendingPathComponent("Logs", isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier!
        let logDirURL = logsUrl.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.removeItem(at: logDirURL)
    }
    
    // MARK: - Core Data stack
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "DataModel")
        let shouldInitOrder = !checkForMigration()
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unresolved error \(error)")
            }
            container.viewContext.automaticallyMergesChangesFromParent = true
            container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        }
        
        if shouldInitOrder {
            // set dafault value for orders
            if container.managedObjectModel.entitiesByName["Bookmark"]?.versionHashModifier == "added order" {
                try? container.viewContext.fetch(NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")).enumerated().forEach {
                    if let bookmark = $0.element as? Bookmark {
                        bookmark.setValue($0.offset, forKey: "order")
                    }
                }
                try? container.viewContext.save()
            }
        }
        return container
    }()
    
    // MARK: - Core Data Saving and Undo support
    
    @IBAction func saveAction(_ sender: AnyObject?) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        let context = persistentContainer.viewContext
        
//        if !context.commitEditing() {
//            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
//        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)
            }
        }
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return persistentContainer.viewContext.undoManager
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let context = persistentContainer.viewContext
        
//        if !context.commitEditing() {
//            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing to terminate")
//            return .terminateCancel
//        }
        
        if !context.hasChanges {
            return .terminateNow
        }
        
        do {
            try context.save()
        } catch {
            let nserror = error as NSError
            
            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .terminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .terminateNow
    }
    
    
    func checkForMigration() -> Bool {
        let container = NSPersistentContainer(name: "DataModel")
        if let storeUrl = container.persistentStoreDescriptions.first?.url,
            let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeUrl) {
            return container.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        }
        return false
    }
}
