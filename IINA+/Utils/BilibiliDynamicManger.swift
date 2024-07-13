//
//  BilibiliDynamicManger.swift
//  IINA+
//
//  Created by xjbeta on 2024/7/12.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

protocol BilibiliDynamicMangerDelegate {
	func bilibiliDynamicStatusChanged(_ isLoading: Bool)
	
	func bilibiliDynamicCardsContains(_ bvid: String) -> Bool
	
	func bilibiliDynamicInitCards(_ cards: [BilibiliCard])
	func bilibiliDynamicAppendCards(_ cards: [BilibiliCard])
	func bilibiliDynamicInsertCards(_ cards: [BilibiliCard])
	
	func bilibiliDynamicCards() -> [BilibiliCard]
}

actor BilibiliDynamicManger {

	private var lock = NSLock()
	
	private var bookmarkLoaderTimer: Date?
	
	let bilibili = Processes.shared.videoDecoder.bilibili
	
	var canLoadMore = true
	
	private var delegate: BilibiliDynamicMangerDelegate?
	
	func setDelegate(_ newDelegate: BilibiliDynamicMangerDelegate) {
		delegate = newDelegate
	}
	
	func loadBilibiliCards(_ action: BilibiliDynamicAction = .init😅) {
		Task {
			await withCheckedContinuation { continuation in
				lock.lock()
				defer { lock.unlock() }
				Task {
					await loadCards(action)
					continuation.resume()
				}
			}
		}
	}
	
	private func loadCards(_ action: BilibiliDynamicAction = .init😅) async {
		guard canLoadMore, let delegate = delegate else { return }
		
		if let date = bookmarkLoaderTimer,
		   date.secondsSinceNow < 5 {
			Log("ignore load more")
			return
		}
		
		let uuid = UUID().uuidString
		canLoadMore = false
		
		await MainActor.run {
			delegate.bilibiliDynamicStatusChanged(true)
		}
		
		var dynamicID = -1
		
		
		let bilibiliCards = delegate.bilibiliDynamicCards()
		
		switch action {
		case .history:
			dynamicID = bilibiliCards.last?.dynamicId ?? -1
		case .new:
			dynamicID = bilibiliCards.first?.dynamicId ?? -1
		default:
			break
		}
		
		Log("\(uuid), start, \(dynamicID)")
		
		do {
			let uid = try await bilibili.getUid()
			let cards = try await bilibili.dynamicList(uid, action, dynamicID)
			
			await MainActor.run {
				switch action {
				case .init😅:
					delegate.bilibiliDynamicInitCards(cards)
				case .history:
					let appends = cards.filter { card in
						!delegate.bilibiliDynamicCardsContains(card.bvid)
					}
					delegate.bilibiliDynamicAppendCards(appends)
				case .new:
					let appends = cards.filter { card in
						!delegate.bilibiliDynamicCardsContains(card.bvid)
					}
					if appends.count > 0 {
						delegate.bilibiliDynamicInsertCards(appends)
					}
				}
			}
		} catch let error {
			Log("Get bilibili dynamicList error: \(error)")
		}
		
		canLoadMore = true
		await MainActor.run {
			delegate.bilibiliDynamicStatusChanged(false)
		}
		bookmarkLoaderTimer = Date()
		Log("\(uuid), finish, \(dynamicID)")
	}
	
}
