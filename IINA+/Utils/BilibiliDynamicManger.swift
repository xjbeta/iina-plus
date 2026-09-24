//
//  BilibiliDynamicManger.swift
//  IINA+
//
//  Created by xjbeta on 2024/7/12.
//  Copyright © 2024 xjbeta. All rights reserved.
//

import Cocoa

@MainActor
protocol BilibiliDynamicMangerDelegate: Sendable {
	func bilibiliDynamicStatusChanged(_ isLoading: Bool)
	
	func bilibiliDynamicCardsContains(_ bvid: String) -> Bool
	
	func bilibiliDynamicInitCards(_ cards: [BilibiliCard])
	func bilibiliDynamicAppendCards(_ cards: [BilibiliCard])
	func bilibiliDynamicInsertCards(_ cards: [BilibiliCard])
	func bilibiliDynamicDeleteCards(_ cards: [BilibiliCard])
	
	func bilibiliDynamicCards() -> [BilibiliCard]
}

actor BilibiliDynamicManger {

    private let tokenBucket = TokenBucket(tokens: 1)
    
    private var initDate: Date?
    private var newDate: Date?
    private var historyDate: Date?
    private var historyOffset = ""
	
    var delegate: BilibiliDynamicMangerDelegate?
	
	func setDelegate(_ newDelegate: BilibiliDynamicMangerDelegate) {
		delegate = newDelegate
	}
	
	func loadBilibiliCards(_ action: BilibiliDynamicAction = .init😅) {
        Task {
            await tokenBucket.withToken {
                await loadCards(action)
            }
        }
	}
    
	private func loadCards(_ action: BilibiliDynamicAction = .init😅) async {
        
        guard let delegate = delegate else { return }
			
		let uuid = UUID().uuidString
		
        await delegate.bilibiliDynamicStatusChanged(true)
			
        defer {
            Task {
                await delegate.bilibiliDynamicStatusChanged(false)
            }
        }
        
		var offset = ""
			
		switch action {
		case .history:
            if historyDate != nil, historyDate!.secondsSinceNow < 1 {
//                Log("\(uuid), ignore, \(action)")
                return
            }
            guard !historyOffset.isEmpty else { return }
            offset = historyOffset
		case .new:
            if newDate != nil, newDate!.secondsSinceNow < 5 {
//                Log("\(uuid), ignore, \(action)")
                return
            }
        case .init😅:
            if initDate != nil, initDate!.secondsSinceNow < 15 {
//                Log("\(uuid), ignore, \(action)")
                return
            }
		}
		
		Log("\(uuid), start, \(action), \(offset)")
		
		do {
			let (cards, nextOffset) = try await Bilibili.shared.dynamicList(action, offset)
			
			switch action {
			case .init😅:
                await delegate.bilibiliDynamicInitCards(cards)
                self.historyOffset = nextOffset
                self.initDate = Date()
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
					
					var results = [BilibiliCard]()
					for await result in group {
						if let result {
							results.append(result)
						}
					}
					return results
				}
                await delegate.bilibiliDynamicAppendCards(appends)
                Log("[BiliDynamic] history loaded=\(cards.count) appends=\(appends.count) nextOffset=\(nextOffset)")
                self.historyOffset = nextOffset
                self.historyDate = Date()
			case .new:
				// Cards above the home feed tail but missing from it are removed posts
				let homeDynamicIds = Set(cards.map { $0.dynamicId })
				if let homeLastDynamicId = cards.last?.dynamicId, !cards.isEmpty {
					let currentCards = await delegate.bilibiliDynamicCards()
					let removed = currentCards.filter {
						!homeDynamicIds.contains($0.dynamicId) && $0.dynamicId > homeLastDynamicId
					}
					if !removed.isEmpty {
						Log("[BiliDynamic] new removed=\(removed.count)")
						await delegate.bilibiliDynamicDeleteCards(removed)
					}
				}
				
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
					Log("[BiliDynamic] new inserted=\(appends.count)")
                    await delegate.bilibiliDynamicInsertCards(appends)
				}
                self.historyOffset = nextOffset
                self.newDate = Date()
			}
		} catch let error {
			Log("Get bilibili dynamicList error: \(error)")
		}
		
		Log("\(uuid), finish, \(offset)")
	}
	
}
