//
//  BilibiliDynamicManger.swift
//  IINA+
//
//  Created by xjbeta on 2024/7/12.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

@MainActor
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
	
    var delegate: BilibiliDynamicMangerDelegate?
	
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
		
        await delegate.bilibiliDynamicStatusChanged(true)
		
		var dynamicID = -1
		
		
        let bilibiliCards = await delegate.bilibiliDynamicCards()
		
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
			
			switch action {
			case .init😅:
                await delegate.bilibiliDynamicInitCards(cards)
			case .history:
				let appends = await withTaskGroup(of: BilibiliCard?.self) { group -> [BilibiliCard] in
					for card in cards {
						group.addTask {
                            if await delegate.bilibiliDynamicCardsContains(card.bvid) {
								return nil
							} else {
								return card
							}
						}
					}
					delegate.bilibiliDynamicAppendCards(appends)
				case .new:
					let appends = cards.filter { card in
						!delegate.bilibiliDynamicCardsContains(card.bvid)
					}
					return results
				}
                await delegate.bilibiliDynamicAppendCards(appends)
			case .new:
				let appends = await withTaskGroup(of: BilibiliCard?.self) { group -> [BilibiliCard] in
					for card in cards {
						group.addTask {
                            if await delegate.bilibiliDynamicCardsContains(card.bvid) {
								return nil
							} else {
								return card
							}
						}
					}
					
					var results = [BilibiliCard]()
					for await result in group {
						if let result {
							results.append(result)
						}
					}
					return results
				}
				if appends.count > 0 {
                    await delegate.bilibiliDynamicInsertCards(appends)
				}
			}
		} catch let error {
			Log("Get bilibili dynamicList error: \(error)")
		}
		
		canLoadMore = true
        await delegate.bilibiliDynamicStatusChanged(false)
		bookmarkLoaderTimer = Date()
		Log("\(uuid), finish, \(dynamicID)")
	}
	
}
