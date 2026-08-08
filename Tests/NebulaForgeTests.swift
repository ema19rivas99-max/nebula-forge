import XCTest
import UIKit
@testable import NebulaForge

/// Tests for the rules that decide what a player gets — merge outcomes,
/// prestige payout, store grants and offer pricing.
///
/// Deliberately pure: nothing here builds a GameViewModel, because that starts
/// timers and loads Core Data, which makes failures about the harness rather
/// than the logic. The grid functions take a grid, so they can be exercised
/// directly.
final class MergeRuleTests: XCTestCase {

    private func item(_ chain: String, _ tier: Int) -> CelestialItem {
        guard let made = ItemCatalog.makeItem(chainID: chain, tier: tier) else {
            fatalError("catalog is missing \(chain) tier \(tier)")
        }
        return made
    }

    func testSameChainMergeTiersUp() throws {
        let merged = try XCTUnwrap(
            CelestialItem.merge(item1: item("fire_basic", 0), item2: item("fire_basic", 0)))
        XCTAssertEqual(merged.tier, 1)
        XCTAssertEqual(merged.chainID, "fire_basic")
        XCTAssertEqual(merged.name, "Ember")
    }

    func testProductionTriplesPerTier() {
        let chain = ItemCatalog.chain(for: "fire_basic")!
        XCTAssertEqual(chain.production(atTier: 1), chain.production(atTier: 0) * 3, accuracy: 1e-9)
        XCTAssertEqual(chain.production(atTier: 3), chain.production(atTier: 0) * 27, accuracy: 1e-9)
    }

    func testMismatchedTiersCannotMerge() {
        XCTAssertNil(CelestialItem.merge(item1: item("fire_basic", 0),
                                         item2: item("fire_basic", 1)))
    }

    func testMaxTierCannotMergeFurther() {
        let chain = ItemCatalog.chain(for: "fire_basic")!
        let top = chain.tierNames.count - 1
        let capped = item("fire_basic", top)
        XCTAssertTrue(capped.isMaxTier)
        XCTAssertNil(CelestialItem.merge(item1: capped, item2: capped))
    }

    func testFusionRequiresMinimumTier() {
        // Below the threshold, two different chains simply don't combine.
        XCTAssertNil(CelestialItem.merge(item1: item("fire_basic", 0),
                                         item2: item("ice_basic", 0)))

        let fused = CelestialItem.merge(item1: item("fire_basic", FusionCatalog.minTier),
                                        item2: item("ice_basic", FusionCatalog.minTier))
        XCTAssertEqual(fused?.chainID, "tempest_hybrid")
        // A fusion holds its tier rather than advancing one.
        XCTAssertEqual(fused?.tier, FusionCatalog.minTier)
    }

    func testFusionBeatsTheTierUpItReplaces() throws {
        let tier = FusionCatalog.minTier
        let fused = try XCTUnwrap(CelestialItem.merge(item1: item("fire_basic", tier),
                                                      item2: item("ice_basic", tier)))
        let tieredUp = try XCTUnwrap(CelestialItem.merge(item1: item("fire_basic", tier),
                                                         item2: item("fire_basic", tier)))
        // Otherwise there'd be no reason ever to fuse.
        XCTAssertGreaterThan(fused.baseProduction, tieredUp.baseProduction)
    }

    func testUnpairedChainsNeverFuse() {
        // fire + radiant isn't a recipe; it must stay impossible.
        XCTAssertNil(FusionCatalog.recipe(for: "fire_basic", "radiant_basic"))
        XCTAssertNil(CelestialItem.merge(item1: item("fire_basic", 5),
                                         item2: item("radiant_basic", 5)))
    }

    func testBlockReasonExplainsEveryFailure() {
        XCTAssertNotNil(CelestialItem.mergeBlockReason(item1: item("fire_basic", 0),
                                                       item2: item("fire_basic", 1)))
        XCTAssertNotNil(CelestialItem.mergeBlockReason(item1: item("fire_basic", 0),
                                                       item2: item("ice_basic", 0)))
        // A valid pair has nothing to explain.
        XCTAssertNil(CelestialItem.mergeBlockReason(item1: item("fire_basic", 0),
                                                    item2: item("fire_basic", 0)))
    }

    func testEveryHybridIsReachableAndEveryRecipeLands() {
        // A hybrid with no recipe is unreachable content; a recipe pointing at
        // a chain that isn't a hybrid means fusion produces something forgeable.
        let reachableByFusion = Set(FusionCatalog.all.map(\.outputChainID))
        let hybrids = Set(ItemCatalog.chains.filter(\.isHybrid).map(\.id))
        XCTAssertEqual(hybrids, reachableByFusion,
                       "every hybrid needs a recipe, and every recipe a hybrid")
    }

    func testEveryChainHasNamesForEveryTier() {
        for chain in ItemCatalog.chains {
            XCTAssertFalse(chain.tierNames.isEmpty, "\(chain.id) has no tiers")
            for tier in chain.tierNames.indices {
                XCTAssertNotNil(ItemCatalog.name(chainID: chain.id, tier: tier),
                                "\(chain.id) tier \(tier) has no name")
            }
        }
    }
}

/// Element placement rules — the thing that makes position matter.
final class ProductionTests: XCTestCase {

    private func grid(_ placements: [(Int, Int, String, Int)]) -> [[GridTile]] {
        var tiles = (0..<5).map { row in
            (0..<5).map { col in
                GridTile(row: row, col: col, isUnlocked: true, placedItem: nil)
            }
        }
        for (row, col, chain, tier) in placements {
            var made = ItemCatalog.makeItem(chainID: chain, tier: tier)!
            made.position = (row, col)
            tiles[row][col].placedItem = made
        }
        return tiles
    }

    func testLoneItemGetsNoBonus() {
        let engine = IdleEngine()
        let g = grid([(2, 2, "fire_basic", 0)])
        let out = engine.production(for: g[2][2], in: g)
        XCTAssertEqual(out.selfBonus, 1.0, accuracy: 1e-9)
        XCTAssertEqual(out.neighbourBonus, 1.0, accuracy: 1e-9)
        XCTAssertFalse(out.isModified)
    }

    func testFireStacksWithAdjacentFire() {
        let engine = IdleEngine()
        // (2,2) and (2,1) are neighbours in the offset layout.
        let g = grid([(2, 2, "fire_basic", 0), (2, 1, "fire_basic", 0)])
        let out = engine.production(for: g[2][2], in: g)
        XCTAssertEqual(out.selfBonus, 1.25, accuracy: 1e-9)
    }

    func testVoidDrainsItsNeighbour() {
        let engine = IdleEngine()
        let g = grid([(2, 2, "fire_basic", 0), (2, 1, "void_basic", 0)])
        let fire = engine.production(for: g[2][2], in: g)
        XCTAssertEqual(fire.neighbourBonus, 0.85, accuracy: 1e-9)

        // And the Void itself gains from having someone to drain.
        let void = engine.production(for: g[2][1], in: g)
        XCTAssertEqual(void.selfBonus, 1.50, accuracy: 1e-9)
    }

    func testRadiantBuffsItsNeighbour() {
        let engine = IdleEngine()
        let g = grid([(2, 2, "fire_basic", 0), (2, 1, "radiant_basic", 0)])
        let fire = engine.production(for: g[2][2], in: g)
        XCTAssertEqual(fire.neighbourBonus, 1.20, accuracy: 1e-9)
    }

    func testDrainedTileNeverGoesToZero() {
        let engine = IdleEngine()
        // Surround a tile with as much Void as the layout allows.
        let g = grid([(2, 2, "fire_basic", 0),
                      (2, 1, "void_basic", 0), (2, 3, "void_basic", 0),
                      (1, 2, "void_basic", 0), (1, 3, "void_basic", 0),
                      (3, 2, "void_basic", 0), (3, 3, "void_basic", 0)])
        let out = engine.production(for: g[2][2], in: g)
        XCTAssertGreaterThanOrEqual(out.neighbourBonus, 0.1)
        XCTAssertGreaterThan(out.total, 0)
    }
}

/// Anything that decides what a player is owed for money or time.
final class EconomyTests: XCTestCase {

    func testEveryStoreProductHasAPayload() {
        for (id, grant) in StoreCatalog.grants {
            XCTAssertFalse(id.isEmpty)
            let givesSomething = grant.gems > 0 || grant.shards > 0
                || grant.productionMultiplier > 1 || grant.offlineHours > 0
                || !grant.themeIDs.isEmpty
            XCTAssertTrue(givesSomething, "\(id) charges money and grants nothing")
        }
    }

    func testStoreThemesAllExist() {
        let known = Set(CosmeticCatalog.all.map(\.id))
        for (id, grant) in StoreCatalog.grants {
            for theme in grant.themeIDs {
                XCTAssertTrue(known.contains(theme),
                              "\(id) promises theme '\(theme)' that doesn't exist")
            }
        }
    }

    func testSubscriptionTiersAreDistinctAndOrdered() {
        let subs = StoreCatalog.grants.values.filter { $0.kind == .subscription }
        let tiers = subs.map(\.tier)
        XCTAssertEqual(Set(tiers).count, tiers.count, "two subscriptions share a tier")

        // A higher tier must be worth more, or upgrading is a downgrade.
        let sorted = subs.sorted { $0.tier < $1.tier }
        for (lower, higher) in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(higher.productionMultiplier, lower.productionMultiplier)
            XCTAssertGreaterThanOrEqual(higher.gems, lower.gems)
        }
    }

    func testGemPacksAreStrictlyIncreasing() {
        // Two packs with the same gem count means one of them is pointless.
        let packs = StoreCatalog.grants
            .filter { $0.value.kind == .consumable }
            .values
            .sorted { $0.gems < $1.gems }
        XCTAssertGreaterThan(packs.count, 1)
        for (small, large) in zip(packs, packs.dropFirst()) {
            XCTAssertGreaterThan(large.gems, small.gems)
        }
    }

    func testDailyRewardGrowsThenCaps() {
        let day1 = DailyReward.forStreak(1)
        let day7 = DailyReward.forStreak(7)
        XCTAssertGreaterThan(day7.shards, day1.shards)

        // Beyond the cap it must plateau rather than run away.
        let beyond = DailyReward.forStreak(99)
        XCTAssertEqual(beyond.day, DailyReward.maxStreakDay)
        XCTAssertEqual(beyond.shards, day7.shards)
        XCTAssertEqual(beyond.gems, day7.gems)
    }

    func testDailyRewardHandlesZeroAndNegativeStreaks() {
        XCTAssertEqual(DailyReward.forStreak(0).day, 1)
        XCTAssertEqual(DailyReward.forStreak(-5).day, 1)
    }

    func testOfferIsDiscountedAndTimeBoxed() throws {
        let offer = try XCTUnwrap(OfferCatalog.current())
        XCTAssertLessThan(offer.salePrice, offer.fullPrice)
        XCTAssertGreaterThan(offer.discountPercent, 0)
        XCTAssertGreaterThan(offer.expiresAt, Date())
    }

    func testOfferIsStableWithinItsWindowAndRotatesAcross() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sameWindow = now.addingTimeInterval(60)
        let nextWindow = now.addingTimeInterval(OfferCatalog.windowHours * 3600)

        XCTAssertEqual(OfferCatalog.current(now: now)?.id,
                       OfferCatalog.current(now: sameWindow)?.id,
                       "the deal must not change while its timer is running")
        XCTAssertNotEqual(OfferCatalog.current(now: now)?.expiresAt,
                          OfferCatalog.current(now: nextWindow)?.expiresAt)
    }

    func testGoalIDsAreUniqueAndAllPayOut() {
        let ids = GoalCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "two goals share an id")
        for goal in GoalCatalog.all {
            XCTAssertGreaterThan(goal.target, 0, "\(goal.id) has no target")
            XCTAssertGreaterThan(goal.shardReward + goal.gemReward, 0,
                                 "\(goal.id) rewards nothing")
        }
    }

    func testEveryGoalCategoryHasGoals() {
        for category in Goal.Category.allCases {
            XCTAssertFalse(GoalCatalog.inCategory(category).isEmpty,
                           "\(category.rawValue) is an empty tab")
        }
    }

    func testBoardIsBigEnoughToKeepMerging() {
        // Merging consumes two tiles to make one, so a board that's only just
        // big enough to hold a run stalls it. 5x5 was too small in practice.
        XCTAssertGreaterThanOrEqual(GameViewModel.totalTiles, 36)
        XCTAssertEqual(GameViewModel.totalTiles,
                       GameViewModel.gridRows * GameViewModel.gridCols)
    }

    func testBoardFitsAPhoneWidth() {
        // Six columns at this size plus the odd-row offset must not overflow
        // the narrowest supported iPhone.
        let perColumn = HexTileView.tileWidth + HexTileView.columnSpacing
        let width = perColumn * CGFloat(GameViewModel.gridCols)
            + HexTileView.tileWidth / 2
        XCTAssertLessThan(width, 375, "the board would overflow an iPhone SE")
    }

    func testUnlockEveryTileGoalMatchesTheBoard() {
        let goal = GoalCatalog.all.first { $0.id == "tiles_all" }
        XCTAssertEqual(goal?.target, GameViewModel.totalTiles,
                       "the goal would be unreachable or trivially complete")
    }

    // MARK: - Starlight Array

    func testStarlightTrackIDsAreUniqueAndWiredToSomething() {
        let ids = StarlightCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate Starlight track ID")
        // Each track is read by ID at exactly one call site in the view model.
        // A renamed or added track with no consumer would silently do nothing.
        XCTAssertEqual(Set(ids), ["lens", "cascade", "well"],
                       "a Starlight track exists that nothing in the game reads")
    }

    func testStarlightCostsAlwaysGrow() {
        for upgrade in StarlightCatalog.all {
            XCTAssertGreaterThan(upgrade.growth, 1, "\(upgrade.id) would never get pricier")
            XCTAssertGreaterThan(upgrade.perLevel, 0, "\(upgrade.id) buys nothing")
            for level in 0..<40 {
                XCTAssertGreaterThan(upgrade.cost(atLevel: level + 1),
                                     upgrade.cost(atLevel: level),
                                     "\(upgrade.id) stops getting more expensive at level \(level)")
            }
        }
    }

    func testStarlightOutscalesTheOnlyOtherShardSink() {
        // The whole point of the Array: the tile board costs a fixed ~3,200 to
        // open and then asks for nothing, so shards need a sink that keeps
        // taking. Twenty levels of any one track must cost more than opening
        // every tile from a post-Supernova board, or the surplus comes back.
        let unlockAllTiles = (12..<GameViewModel.totalTiles)
            .reduce(0) { $0 + max(5, ($1 - 5) * 5) }
        for upgrade in StarlightCatalog.all {
            let twentyLevels = (0..<20).reduce(0) { $0 + upgrade.cost(atLevel: $1) }
            XCTAssertGreaterThan(twentyLevels, unlockAllTiles,
                                 "\(upgrade.id) is cheaper than the sink it replaces")
        }
    }

    func testDailyQuestsAreThreeAndDistinct() {
        let quests = DailyQuestCatalog.today()
        XCTAssertEqual(quests.count, 3)
        XCTAssertEqual(Set(quests.map(\.id)).count, 3, "the same quest twice in one day")
    }

    func testUnavailableQuestsAreNeverDealt() {
        // The bug: "Unlock 3 tiles" was dealt on a fully-open board, where
        // nothing can be unlocked until the next Supernova. It quietly ate one
        // of the day's three gem slots.
        let tileQuests: Set<String> = ["q_tile_1", "q_tile_3"]
        let available = DailyQuestCatalog.pool.filter { !tileQuests.contains($0.id) }

        for offset in 0..<400 {
            let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(offset) * 86_400)
            let dealt = DailyQuestCatalog.deal(from: available, date: date).map(\.id)
            XCTAssertEqual(dealt.count, 3, "day \(offset) dealt \(dealt.count) quests")
            XCTAssertEqual(Set(dealt).count, 3, "day \(offset) dealt a duplicate")
            XCTAssertTrue(tileQuests.isDisjoint(with: Set(dealt)),
                          "day \(offset) dealt an unfinishable tile quest")
        }
    }

    func testFilteredDealIsStillStableWithinADay() {
        let available = DailyQuestCatalog.pool.filter { $0.id != "q_tile_3" }
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(DailyQuestCatalog.deal(from: available, date: day).map(\.id),
                       DailyQuestCatalog.deal(from: available,
                                              date: day.addingTimeInterval(3600)).map(\.id),
                       "filtering must not make the day's quests reroll")
    }

    func testDealFallsBackRatherThanReturningTooFewQuests() {
        // A pool filtered down below three would otherwise strand the player
        // with a short list and less gem income than the day owes them.
        let starved = Array(DailyQuestCatalog.pool.prefix(2))
        XCTAssertEqual(DailyQuestCatalog.deal(from: starved).count, 3)
    }

    // MARK: - Remote config

    func testOutOfRangeRemoteValuesAreDroppedNotClamped() {
        // A typo in the published JSON must fall back to the shipped constant.
        // Clamping to the boundary would silently ship the most extreme legal
        // balance instead, which is worse than ignoring the value.
        var config = RemoteConfig()
        config.forgeCostGrowth = 900
        config.prestigePowerRequirement = -5
        config.arrayCostMultiplier = 0

        let clean = config.sanitized
        XCTAssertNil(clean.forgeCostGrowth)
        XCTAssertNil(clean.prestigePowerRequirement)
        XCTAssertNil(clean.arrayCostMultiplier)
    }

    func testInRangeRemoteValuesSurvive() {
        var config = RemoteConfig()
        config.forgeCostGrowth = 1.08
        config.arrayCostMultiplier = 0.5

        let clean = config.sanitized
        XCTAssertEqual(clean.forgeCostGrowth, 1.08)
        XCTAssertEqual(clean.arrayCostMultiplier, 0.5)
    }

    func testNonFiniteRemoteValuesAreRejected() {
        var config = RemoteConfig()
        config.forgeCostGrowth = .nan
        config.arrayCostMultiplier = .infinity
        let clean = config.sanitized
        XCTAssertNil(clean.forgeCostGrowth)
        XCTAssertNil(clean.arrayCostMultiplier)
    }

    func testEventOnlyAppliesInsideItsWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = RemoteConfig.Event(name: "Surge", production: 2, shards: nil,
                                       startsAt: start,
                                       endsAt: start.addingTimeInterval(86_400))

        XCTAssertFalse(event.isActive(at: start.addingTimeInterval(-1)), "started early")
        XCTAssertTrue(event.isActive(at: start.addingTimeInterval(3600)))
        XCTAssertFalse(event.isActive(at: start.addingTimeInterval(86_401)), "outlived its window")
    }

    func testEventWithNoMultipliersIsInert() {
        let event = RemoteConfig.Event(name: "Empty", production: nil, shards: nil,
                                       startsAt: nil, endsAt: nil)
        XCTAssertFalse(event.isActive(), "an event granting nothing must not show a banner")
    }

    func testOversizedEventMultiplierIsRejected() {
        var config = RemoteConfig()
        config.event = RemoteConfig.Event(name: "Runaway", production: 1000, shards: nil,
                                          startsAt: nil, endsAt: nil)
        XCTAssertFalse(config.sanitized.event?.isActive() ?? false,
                       "a runaway multiplier must not reach the economy")
    }

    func testNoticeNeedsBodyAndRespectsExpiry() {
        let past = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(RemoteConfig.Notice(id: "a", body: nil, endsAt: nil).isActive())
        XCTAssertFalse(RemoteConfig.Notice(id: "a", body: "", endsAt: nil).isActive())
        XCTAssertFalse(RemoteConfig.Notice(id: "a", body: "hi", endsAt: past).isActive())
        XCTAssertTrue(RemoteConfig.Notice(id: "a", body: "hi", endsAt: nil).isActive())
    }

    func testShippedConfigFileIsInert() throws {
        // The published file must decode to no overrides, so shipping it can't
        // change the balance until someone deliberately edits it.
        let json = """
        {"_readme": "notes", "_example": {"event": {"name": "x", "production": 2}}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(RemoteConfig.self, from: Data(json.utf8))
        XCTAssertNil(config.event, "underscore-prefixed keys must not take effect")
        XCTAssertNil(config.forgeCostGrowth)
    }

    func testDailyQuestsAreStableWithinADayAndRotateAcross() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let sameDay = day.addingTimeInterval(3600)
        let nextDay = day.addingTimeInterval(86_400)

        XCTAssertEqual(DailyQuestCatalog.today(day).map(\.id),
                       DailyQuestCatalog.today(sameDay).map(\.id),
                       "quests must not reroll during the day")
        XCTAssertNotEqual(DailyQuestCatalog.today(day).map(\.id),
                          DailyQuestCatalog.today(nextDay).map(\.id),
                          "quests must change day to day")
    }

    func testEveryQuestPaysGems() {
        for quest in DailyQuestCatalog.pool {
            XCTAssertGreaterThan(quest.gemReward, 0, "\(quest.id) pays nothing")
            XCTAssertGreaterThan(quest.target, 0)
        }
    }

    func testGemOffersAllCostSomething() {
        for offer in GemShopCatalog.all {
            XCTAssertGreaterThan(offer.gemCost, 0, "\(offer.id) is free")
            XCTAssertFalse(offer.title.isEmpty)
        }
    }

    func testProfileCosmeticIDsAreUniqueWithinEachSet() {
        func assertUnique<C: Cosmetic>(_ items: [C], _ label: String) {
            let ids = items.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate id in \(label)")
            XCTAssertFalse(items.contains { $0.name.isEmpty }, "\(label) has an unnamed entry")
        }
        assertUnique(AvatarCatalog.all, "avatars")
        assertUnique(FrameCatalog.all, "frames")
        assertUnique(BannerCatalog.all, "banners")
        assertUnique(TitleCatalog.all, "titles")
    }

    func testEveryCosmeticSetHasAFreeDefault() {
        // The default must be free, or a new player has no valid profile.
        XCTAssertEqual(AvatarCatalog.avatar(for: AvatarCatalog.defaultID).unlock, .free)
        XCTAssertEqual(FrameCatalog.frame(for: FrameCatalog.defaultID).unlock, .free)
        XCTAssertEqual(BannerCatalog.banner(for: BannerCatalog.defaultID).unlock, .free)
        XCTAssertEqual(TitleCatalog.title(for: TitleCatalog.defaultID).unlock, .free)
    }

    func testGoalLockedCosmeticsPointAtRealGoals() {
        let goalIDs = Set(GoalCatalog.all.map(\.id))
        func check<C: Cosmetic>(_ items: [C], _ label: String) {
            for item in items {
                if case .goal(let id) = item.unlock {
                    XCTAssertTrue(goalIDs.contains(id),
                                  "\(label) '\(item.id)' needs goal '\(id)', which doesn't exist")
                }
            }
        }
        check(AvatarCatalog.all, "avatar")
        check(FrameCatalog.all, "frame")
        check(BannerCatalog.all, "banner")
        check(TitleCatalog.all, "title")
    }

    func testPurchaseLockedCosmeticsPointAtRealProducts() {
        let products = Set(StoreCatalog.grants.keys)
        func check<C: Cosmetic>(_ items: [C], _ label: String) {
            for item in items {
                if case .purchase(let id) = item.unlock {
                    XCTAssertTrue(products.contains(id),
                                  "\(label) '\(item.id)' needs product '\(id)', which doesn't exist")
                }
            }
        }
        check(AvatarCatalog.all, "avatar")
        check(FrameCatalog.all, "frame")
        check(BannerCatalog.all, "banner")
        check(TitleCatalog.all, "title")
    }

    func testNicknameFallsBackRatherThanShowingNothing() {
        var profile = PlayerProfile.default
        XCTAssertFalse(profile.displayName.isEmpty)
        profile.nickname = "   "
        XCTAssertFalse(profile.displayName.isEmpty, "whitespace must not render as blank")
        profile.nickname = "Manny"
        XCTAssertEqual(profile.displayName, "Manny")
    }

    func testProfileSurvivesEncoding() throws {
        var profile = PlayerProfile.default
        profile.nickname = "Architect"
        profile.avatarID = "crown"
        let data = try JSONEncoder().encode(profile)
        let back = try JSONDecoder().decode(PlayerProfile.self, from: data)
        XCTAssertEqual(back, profile)
    }

    func testEverySkinHasArtForEveryReachableTier() {
        // A missing asset renders as a blank tile, which looks like a bug and
        // would be worst on the skin someone paid for.
        // Only the skins actually offered for sale. The catalog also holds
        // packs whose art hasn't shipped, and those are filtered out of the
        // shop rather than rendered blank.
        XCTAssertFalse(SkinCatalog.available.isEmpty)
        for skin in SkinCatalog.available {
            for chain in ItemCatalog.chains {
                let lowest = chain.isHybrid ? FusionCatalog.minTier : 0
                for tier in lowest..<chain.tierNames.count {
                    let name = chain.assetName(forTier: tier, skin: skin.prefix)
                    XCTAssertNotNil(UIImage(named: name),
                                    "\(skin.name) is missing \(name)")
                }
            }
        }
    }

    func testEveryPaidSkinIsATradeoffNotJustPower() {
        // Straight upgrades would make owning the set optimal, stack into
        // nonsense, and turn the leaderboard into a spending ranking.
        for skin in SkinCatalog.all where skin.gemCost > 0 {
            let e = skin.effect
            let upsides = [e.production > 1, e.shards > 1, e.fusionShards > 1,
                           e.cometInterval < 1, e.cometValue > 1,
                           e.offlineHours > 0, e.forgeCost < 1]
                + Element.allCases.map { (e.elementBonus[$0] ?? 1) > 1 }
            let downsides = [e.production < 1, e.shards < 1, e.fusionShards < 1,
                             e.cometInterval > 1, e.cometValue < 1, e.forgeCost > 1]
                + Element.allCases.map { (e.elementBonus[$0] ?? 1) < 1 }

            XCTAssertTrue(upsides.contains(true), "\(skin.name) gives nothing")
            XCTAssertTrue(downsides.contains(true),
                          "\(skin.name) is a pure upgrade with no cost")
        }
    }

    func testFreeCosmeticsCarryNoEffect() {
        XCTAssertEqual(SkinCatalog.skin(for: SkinCatalog.defaultID).effect, .none)
        XCTAssertEqual(CosmeticCatalog.theme(for: CosmeticCatalog.defaultID).effect, .none)
    }

    func testEveryPaidCosmeticActuallyDoesSomething() {
        // A cosmetic advertised as having an effect must have one, or the shop
        // is lying about what the price buys.
        for skin in SkinCatalog.all where skin.gemCost > 0 {
            XCTAssertTrue(skin.effect.isMeaningful, "\(skin.name) has no effect")
            XCTAssertFalse(skin.effect.summary.isEmpty, "\(skin.name) shows no tags")
        }
        for theme in CosmeticCatalog.all where theme.gemCost > 0 {
            XCTAssertTrue(theme.effect.isMeaningful, "\(theme.name) has no effect")
        }
    }

    func testEffectsCombineMultiplicativelyAndAddOfflineHours() {
        let a = CosmeticEffect(production: 1.2, shards: 0.9, offlineHours: 3,
                               elementBonus: [.fire: 1.4])
        let b = CosmeticEffect(production: 0.95, shards: 1.3, offlineHours: 8,
                               elementBonus: [.fire: 1.1, .ice: 0.85])
        let c = CosmeticEffect.combine(a, b)

        XCTAssertEqual(c.production, 1.2 * 0.95, accuracy: 1e-9)
        XCTAssertEqual(c.shards, 0.9 * 1.3, accuracy: 1e-9)
        XCTAssertEqual(c.offlineHours, 11, accuracy: 1e-9)
        XCTAssertEqual(c.elementBonus[.fire] ?? 0, 1.4 * 1.1, accuracy: 1e-9)
        XCTAssertEqual(c.elementBonus[.ice] ?? 0, 0.85, accuracy: 1e-9)
    }

    func testCombiningWithNothingChangesNothing() {
        let a = CosmeticEffect(production: 1.25, cometInterval: 0.6)
        XCTAssertEqual(CosmeticEffect.combine(a, .none), a)
        XCTAssertEqual(CosmeticEffect.combine(.none, .none), .none)
    }

    func testEffectSummaryNamesBothDirections() {
        let e = CosmeticEffect(production: 0.95, shards: 1.30)
        let tags = e.summary.joined(separator: " ")
        XCTAssertTrue(tags.contains("-5%"), "penalty must be shown: \(tags)")
        XCTAssertTrue(tags.contains("+30%"), "bonus must be shown: \(tags)")
    }

    func testSkinsAreUniqueAndOneIsFree() {
        let ids = SkinCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(SkinCatalog.skin(for: SkinCatalog.defaultID).gemCost, 0)
        XCTAssertEqual(SkinCatalog.skin(for: SkinCatalog.defaultID).prefix,
                       SkinCatalog.defaultPrefix)
    }

    func testHybridArtIsClampedToReachableTiers() {
        // Hybrids have no art below the fusion threshold; asking for tier 0
        // must fall back rather than name a file that doesn't exist.
        let hybrid = ItemCatalog.chains.first { $0.isHybrid }!
        let name = hybrid.assetName(forTier: 0, skin: "anime")
        XCTAssertTrue(name.hasSuffix("_t\(FusionCatalog.minTier)"), name)
        XCTAssertNotNil(UIImage(named: name))
    }

    func testThemeIDsAreUnique() {
        let ids = CosmeticCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "two themes share an id")
        XCTAssertNotNil(CosmeticCatalog.all.first { $0.id == CosmeticCatalog.defaultID })
    }

    func testDefaultThemeIsFree() {
        XCTAssertEqual(CosmeticCatalog.theme(for: CosmeticCatalog.defaultID).gemCost, 0)
    }
}

/// The cloud save is the path an unspent gem balance travels between devices,
/// and StoreKit cannot restore consumables, so a serialisation bug here loses
/// money that was actually paid.
final class SaveSnapshotTests: XCTestCase {

    private func sample() -> SaveSnapshot {
        SaveSnapshot(
            savedAt: Date(timeIntervalSince1970: 1_800_000_000),
            stardust: 12_345.678,
            starlightShards: 42,
            nebulaGems: 16_000,
            galaxyMarks: 7,
            celestialRank: 3,
            permanentMultiplier: 2.5,
            hasPrestiged: true,
            totalMerges: 913,
            totalFusions: 12,
            itemsForged: 55,
            highestTierReached: 6,
            claimedGoalIDs: ["merge_1", "fusion_1"],
            upgradeLevels: ["production": 4, "offline": 2],
            unlockedTiles: ["0,0", "0,1", "1,0"],
            dailyStreak: 5,
            lastDailyClaim: Date(timeIntervalSince1970: 1_799_900_000),
            hasMadeFirstPurchase: true,
            ownedThemeIDs: ["deep_void", "crimson"],
            selectedThemeID: "crimson",
            items: [
                .init(chainID: "fire_basic", tier: 3, row: 0, col: 0),
                .init(chainID: "tempest_hybrid", tier: 4, row: 1, col: 0),
                .init(chainID: "ice_basic", tier: 0, row: nil, col: nil),
            ])
    }

    private func roundTrip(_ snapshot: SaveSnapshot) throws -> SaveSnapshot {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SaveSnapshot.self, from: encoder.encode(snapshot))
    }

    func testCurrenciesSurviveARoundTrip() throws {
        let original = sample()
        let restored = try roundTrip(original)

        XCTAssertEqual(restored.nebulaGems, original.nebulaGems)
        XCTAssertEqual(restored.starlightShards, original.starlightShards)
        XCTAssertEqual(restored.galaxyMarks, original.galaxyMarks)
        XCTAssertEqual(restored.stardust, original.stardust, accuracy: 1e-6)
        XCTAssertEqual(restored.hasMadeFirstPurchase, original.hasMadeFirstPurchase)
    }

    func testBoardAndProgressSurviveARoundTrip() throws {
        let original = sample()
        let restored = try roundTrip(original)

        XCTAssertEqual(restored.items.count, original.items.count)
        XCTAssertEqual(restored.unlockedTiles, original.unlockedTiles)
        XCTAssertEqual(restored.upgradeLevels, original.upgradeLevels)
        XCTAssertEqual(Set(restored.claimedGoalIDs), Set(original.claimedGoalIDs))
        XCTAssertEqual(restored.permanentMultiplier, original.permanentMultiplier, accuracy: 1e-9)
        XCTAssertEqual(restored.selectedThemeID, original.selectedThemeID)

        // Tray items must stay in the tray, not silently acquire a position.
        let tray = restored.items.filter { $0.row == nil }
        XCTAssertEqual(tray.count, 1)
        XCTAssertEqual(tray.first?.chainID, "ice_basic")
    }

    func testDatesSurviveARoundTrip() throws {
        let original = sample()
        let restored = try roundTrip(original)
        XCTAssertEqual(restored.savedAt.timeIntervalSince1970,
                       original.savedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(restored.lastDailyClaim?.timeIntervalSince1970 ?? 0,
                       original.lastDailyClaim?.timeIntervalSince1970 ?? 0, accuracy: 1)
    }

    func testEverySavedItemCanBeRebuilt() throws {
        // A snapshot referencing a chain that no longer exists must not be able
        // to resurrect it as something else.
        for item in try roundTrip(sample()).items {
            XCTAssertNotNil(ItemCatalog.makeItem(chainID: item.chainID, tier: item.tier),
                            "\(item.chainID) tier \(item.tier) can't be rebuilt")
        }
    }

    func testSaveIsSmallEnoughForKeyValueStorage() throws {
        // iCloud key-value storage caps a single value at 1MB.
        var big = sample()
        big.items = (0..<25).map {
            .init(chainID: "fire_basic", tier: 7, row: $0 / 5, col: $0 % 5)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(big)
        XCTAssertLessThan(data.count, 100_000,
                          "a full board should be kilobytes, not near the 1MB cap")
    }
}

/// Number formatting sits in front of unbounded idle values, where a naive
/// conversion traps.
final class FormattingTests: XCTestCase {

    func testAbbreviatesByMagnitude() {
        XCTAssertEqual(abbreviatedNumber(0), "0")
        XCTAssertEqual(abbreviatedNumber(999), "999")
        XCTAssertEqual(abbreviatedNumber(1_500), "1.5K")
        XCTAssertEqual(abbreviatedNumber(2_500_000), "2.5M")
    }

    func testSurvivesInfinityAndNaN() {
        XCTAssertEqual(abbreviatedNumber(.infinity), "0")
        XCTAssertEqual(abbreviatedNumber(.nan), "0")
        XCTAssertEqual(abbreviatedNumber(-5), "0")
    }

    func testClampedScoreNeverTraps() {
        // Infinity fails the isFinite guard before the clamp is reached, so it
        // comes back as 0 rather than the ceiling.
        XCTAssertEqual(clampedScore(.infinity), 0)
        XCTAssertEqual(clampedScore(.nan), 0)
        XCTAssertEqual(clampedScore(-1), 0)
        XCTAssertEqual(clampedScore(0), 0)
        XCTAssertEqual(clampedScore(1234.7), 1234)

        // A finite but absurd value is what the clamp actually exists for.
        XCTAssertEqual(clampedScore(1e30), 9_000_000_000_000_000_000)
    }
}
