import XCTest
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

    func testGemOffersAllCostSomething() {
        for offer in GemShopCatalog.all {
            XCTAssertGreaterThan(offer.gemCost, 0, "\(offer.id) is free")
            XCTAssertFalse(offer.title.isEmpty)
        }
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
        XCTAssertEqual(clampedScore(.nan), 0)
        XCTAssertEqual(clampedScore(.infinity), 9_000_000_000_000_000_000)
        XCTAssertEqual(clampedScore(-1), 0)
        XCTAssertEqual(clampedScore(1234.7), 1234)
    }
}
