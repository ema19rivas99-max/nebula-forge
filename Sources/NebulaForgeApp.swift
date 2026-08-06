import SwiftUI
import StoreKit
import GameKit
import CoreData
import Combine
import SpriteKit

// MARK: - App Entry Point & Privacy Compliance
@main
struct NebulaForgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var privacyManager = PrivacyManager.shared
    @StateObject private var gameVM = GameViewModel()

    var body: some Scene {
        WindowGroup {
            if !privacyManager.hasAcceptedPrivacy {
                PrivacyConsentView()
                    .environmentObject(privacyManager)
            } else {
                ContentView()
                    .environmentObject(gameVM)
                    .environmentObject(privacyManager)
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Initialize Game Center
        authenticateGameCenterPlayer()

        // Register for StoreKit transaction updates
        Task {
            await listenForTransactions()
        }

        return true
    }

    func authenticateGameCenterPlayer() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            if let vc = viewController {
                // Present Game Center sign-in if needed
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(vc, animated: true)
                }
            } else if let error = error {
                print("Game Center auth failed: \(error.localizedDescription)")
            } else if GKLocalPlayer.local.isAuthenticated {
                print("Game Center authenticated")
                GameCenterManager.shared.playerAuthenticated()
            }
        }
    }

    func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await IAPManager.shared.processTransaction(transaction)
        }
    }
}

// MARK: - Privacy Manager
class PrivacyManager: ObservableObject {
    static let shared = PrivacyManager()

    @Published var hasAcceptedPrivacy: Bool {
        didSet { UserDefaults.standard.set(hasAcceptedPrivacy, forKey: "hasAcceptedPrivacy") }
    }

    private init() {
        self.hasAcceptedPrivacy = UserDefaults.standard.bool(forKey: "hasAcceptedPrivacy")
    }

    func acceptPrivacyPolicy() {
        hasAcceptedPrivacy = true
    }
}

// MARK: - Privacy Consent View (GDPR & Apple 5.1.1 Compliant)
struct PrivacyConsentView: View {
    @EnvironmentObject var privacyManager: PrivacyManager
    @State private var showPrivacyPolicy = false

    var body: some View {
        ZStack {
            // Cosmic background
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.3), Color(red: 0.1, green: 0.05, blue: 0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 25) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow, .orange)
                    .shadow(radius: 20)

                Text("Nebula Forge")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("Cosmic Architect")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 15) {
                    Text("Your Privacy Matters")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("• Your game progress is saved only on this device.")
                        .foregroundColor(.white.opacity(0.8))

                    Text("• We do not collect, share, or sell any personal data.")
                        .foregroundColor(.white.opacity(0.8))

                    Text("• Leaderboard participation is optional and only shares your Game Center nickname and score.")
                        .foregroundColor(.white.opacity(0.8))

                    Text("• This game contains no ads and does not track you.")
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(15)

                Button(action: {
                    showPrivacyPolicy = true
                }) {
                    Text("Read Full Privacy Policy")
                        .underline()
                        .foregroundColor(.blue)
                }
                .sheet(isPresented: $showPrivacyPolicy) {
                    PrivacyPolicyView()
                }

                Button(action: {
                    privacyManager.acceptPrivacyPolicy()
                }) {
                    Text("Agree & Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(15)
                }
                .padding(.horizontal, 40)
            }
            .padding()
        }
    }
}

// MARK: - Privacy Policy WebView
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                // In production, replace with WKWebView loading your actual privacy policy URL
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Privacy Policy for Nebula Forge")
                            .font(.title.bold())

                        Text("Last Updated: August 2026")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("1. Information We Collect")
                            .font(.headline)
                        Text("Your game progress is stored only on this device. We do not upload it, and we cannot access it. If you use Game Center, Apple provides us your Game Center nickname and submitted scores for leaderboard functionality.")

                        Text("2. How We Use Your Information")
                            .font(.headline)
                        Text("Game data is used solely to save your progress on this device. Leaderboard scores, if you choose to use Game Center, are shared publicly alongside your Game Center nickname.")

                        Text("3. Third-Party Services")
                            .font(.headline)
                        Text("We use Apple's Game Center for optional leaderboards. This game contains no advertising, no analytics, and no third-party trackers, and does not track you across apps or websites.")

                        Text("4. Your Rights")
                            .font(.headline)
                        Text("Deleting the app removes all game data stored on your device. You can opt out of Game Center features at any time in your device Settings.")

                        Text("5. Contact")
                            .font(.headline)
                        Text("Email: privacy@nebulaforgegame.com")

                        Text("6. Children's Privacy")
                            .font(.headline)
                        Text("Nebula Forge is rated 4+ and does not knowingly collect personal information from children under 13. The only optional data sharing is through Apple's Game Center, which requires parental approval for child accounts.")
                    }
                    .padding()
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Game Center Manager
class GameCenterManager: NSObject, ObservableObject {
    static let shared = GameCenterManager()

    @Published var isAuthenticated: Bool = false
    @Published var playerAlias: String = ""

    func playerAuthenticated() {
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        playerAlias = GKLocalPlayer.local.alias
    }

    func submitScore(_ score: Int64, leaderboardID: String = "nebulaforge.totalstarlight") {
        guard isAuthenticated else { return }

        GKLeaderboard.submitScore(Int(score), context: 0, player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]) { error in
            if let error = error {
                print("Failed to submit score: \(error.localizedDescription)")
            }
        }
    }

    func showLeaderboard() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let gcVC = GKGameCenterViewController(leaderboardID: "nebulaforge.totalstarlight", playerScope: .global, timeScope: .allTime)
        gcVC.gameCenterDelegate = self
        rootVC.present(gcVC, animated: true)
    }
}

extension GameCenterManager: GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

// MARK: - StoreKit IAP Manager
@MainActor
class IAPManager: ObservableObject {
    static let shared = IAPManager()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs = Set<String>()

    let productIDs = [
        "nebulaforge.starterpack",
        "nebulaforge.architectkit",
        "nebulaforge.pileofgems",
        "nebulaforge.nebulapass.monthly",
        "nebulaforge.gemsubscription.weekly"
    ]

    private var updates: Task<Void, Never>? = nil

    init() {
        updates = observeTransactionUpdates()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updates?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return }
            await transaction.finish()
            await updatePurchasedProducts()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func processTransaction(_ transaction: StoreKit.Transaction) async {
        purchasedProductIDs.insert(transaction.productID)
    }

    func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            purchasedProductIDs.insert(transaction.productID)
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                purchasedProductIDs.insert(transaction.productID)
            }
        }
    }
}

// MARK: - Loot Box Odds Disclosure (Apple Guideline 3.1.1)
struct LootBoxOddsView: View {
    @Environment(\.dismiss) var dismiss

    let odds = [
        ("Common Stardust Pack", "60%", Color.gray),
        ("Rare Comet Shard", "30%", Color.blue),
        ("Epic Guardian Egg", "8%", Color.purple),
        ("Legendary Mythic Item", "2%", Color.orange)
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Cosmic Chest Contents")
                    .font(.title2.bold())

                Text("All paid loot boxes display exact probabilities as required by platform policies.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ForEach(odds, id: \.0) { item, chance, color in
                    HStack {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                        Text(item)
                        Spacer()
                        Text(chance)
                            .bold()
                            .foregroundColor(color)
                    }
                    .padding(.horizontal)
                }

                Text("Probabilities are fixed and verified. No manipulation occurs based on player behavior or spending.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding()

                Spacer()
            }
            .padding()
            .navigationTitle("Drop Rates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Core Data Models
// @objc keeps the Objective-C runtime name unmangled so it matches
// `representedClassName` in the .xcdatamodel; without it Core Data can't
// resolve the entity and throws on insert.
@objc(CelestialItemEntity)
class CelestialItemEntity: NSManagedObject {}

extension CelestialItemEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CelestialItemEntity> {
        return NSFetchRequest<CelestialItemEntity>(entityName: "CelestialItemEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var chainID: String?
    @NSManaged public var tier: Int16
    @NSManaged public var element: String?
    @NSManaged public var name: String?
    @NSManaged public var baseProduction: Double
    @NSManaged public var gridRow: Int16
    @NSManaged public var gridCol: Int16
    @NSManaged public var isPlaced: Bool
}

// MARK: - Persistence Controller (iCloud Sync)
class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "NebulaForge")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("Core Data failed to load: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Failed to save context: \(error)")
            }
        }
    }
}

// MARK: - Core Game Models
struct CelestialItem: Identifiable, Codable {
    let id: UUID
    let chainID: String
    let tier: Int
    var element: Element
    let baseProduction: Double
    let name: String
    var position: (row: Int, col: Int)?

    enum CodingKeys: String, CodingKey {
        case id, chainID, tier, element, baseProduction, name
    }

    init(id: UUID, chainID: String, tier: Int, element: Element, baseProduction: Double, name: String, position: (row: Int, col: Int)?) {
        self.id = id
        self.chainID = chainID
        self.tier = tier
        self.element = element
        self.baseProduction = baseProduction
        self.name = name
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        chainID = try container.decode(String.self, forKey: .chainID)
        tier = try container.decode(Int.self, forKey: .tier)
        element = try container.decode(Element.self, forKey: .element)
        baseProduction = try container.decode(Double.self, forKey: .baseProduction)
        name = try container.decode(String.self, forKey: .name)
        position = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(chainID, forKey: .chainID)
        try container.encode(tier, forKey: .tier)
        try container.encode(element, forKey: .element)
        try container.encode(baseProduction, forKey: .baseProduction)
        try container.encode(name, forKey: .name)
    }

    static func merge(item1: CelestialItem, item2: CelestialItem) -> CelestialItem? {
        guard item1.chainID == item2.chainID, item1.tier == item2.tier else { return nil }
        guard let chain = ItemCatalog.chain(for: item1.chainID) else { return nil }

        let nextTier = item1.tier + 1
        // The chain tops out; merging past its final form isn't possible.
        guard nextTier < chain.tierNames.count else { return nil }

        return CelestialItem(
            id: UUID(),
            chainID: chain.id,
            tier: nextTier,
            element: chain.element,
            baseProduction: chain.production(atTier: nextTier),
            name: chain.tierNames[nextTier],
            position: nil
        )
    }

    /// Whether this item has reached the end of its chain.
    var isMaxTier: Bool {
        guard let chain = ItemCatalog.chain(for: chainID) else { return false }
        return tier >= chain.tierNames.count - 1
    }
}

enum Element: String, CaseIterable, Codable {
    case fire, ice, void, radiant

    var displayName: String {
        switch self {
        case .fire: return "Fire"
        case .ice: return "Ice"
        case .void: return "Void"
        case .radiant: return "Radiant"
        }
    }
}

// MARK: - Goals
/// A milestone the player works toward. Progress is derived from game state
/// rather than tracked separately, so goals can never desync from reality.
struct Goal: Identifiable {
    let id: String
    let title: String
    let detail: String
    let target: Int
    let shardReward: Int
    let gemReward: Int
    let progress: (GameViewModel) -> Int

    func currentProgress(_ vm: GameViewModel) -> Int {
        min(progress(vm), target)
    }

    func isComplete(_ vm: GameViewModel) -> Bool {
        progress(vm) >= target
    }
}

enum GoalCatalog {
    static let all: [Goal] = [
        Goal(id: "merge_1", title: "First Fusion", detail: "Merge two items together",
             target: 1, shardReward: 3, gemReward: 0) { $0.totalMerges },
        Goal(id: "place_5", title: "Taking Shape", detail: "Place 5 items in your galaxy",
             target: 5, shardReward: 5, gemReward: 0) { vm in
                 vm.gridTiles.flatMap { $0 }.filter { $0.placedItem != nil }.count },
        Goal(id: "merge_10", title: "Forge Master", detail: "Complete 10 merges",
             target: 10, shardReward: 10, gemReward: 1) { $0.totalMerges },
        Goal(id: "tier_3", title: "Rising Power", detail: "Create a tier 3 item",
             target: 1, shardReward: 15, gemReward: 2) { vm in
                 vm.highestTierReached >= 3 ? 1 : 0 },
        Goal(id: "place_10", title: "Constellation", detail: "Place 10 items at once",
             target: 10, shardReward: 20, gemReward: 2) { vm in
                 vm.gridTiles.flatMap { $0 }.filter { $0.placedItem != nil }.count },
        Goal(id: "prestige_1", title: "Reborn", detail: "Trigger your first Supernova",
             target: 1, shardReward: 25, gemReward: 5) { $0.galaxyMarks > 0 ? 1 : 0 },
        Goal(id: "tier_5", title: "Stellar Architect", detail: "Create a tier 5 item",
             target: 1, shardReward: 40, gemReward: 5) { vm in
                 vm.highestTierReached >= 5 ? 1 : 0 },
        Goal(id: "merge_100", title: "Century", detail: "Complete 100 merges",
             target: 100, shardReward: 60, gemReward: 10) { $0.totalMerges }
    ]
}

// MARK: - Prestige Upgrades
/// Permanent perks bought with Galaxy Marks. These are the reason to prestige
/// more than once — without them a Supernova just resets you with a multiplier.
struct PrestigeUpgrade: Identifiable {
    let id: String
    let title: String
    let detail: String
    let maxLevel: Int
    let baseCost: Int

    func cost(atLevel level: Int) -> Int {
        baseCost * (level + 1)
    }
}

enum UpgradeCatalog {
    static let all: [PrestigeUpgrade] = [
        PrestigeUpgrade(id: "production", title: "Stellar Density",
                        detail: "+25% Stardust production per level",
                        maxLevel: 10, baseCost: 2),
        PrestigeUpgrade(id: "shard_yield", title: "Fracture Harvest",
                        detail: "+100% Starlight Shards from merges per level",
                        maxLevel: 5, baseCost: 3),
        PrestigeUpgrade(id: "forge_cost", title: "Efficient Forging",
                        detail: "-5% Stardust cost to forge items per level",
                        maxLevel: 8, baseCost: 3),
        PrestigeUpgrade(id: "starting_items", title: "Seeded Nebula",
                        detail: "+1 item on the board after each Supernova",
                        maxLevel: 6, baseCost: 5),
        PrestigeUpgrade(id: "offline", title: "Long Orbit",
                        detail: "+2 hours of offline production per level",
                        maxLevel: 8, baseCost: 4)
    ]

    static func upgrade(for id: String) -> PrestigeUpgrade? {
        all.first { $0.id == id }
    }
}

// MARK: - Item Catalog
/// Every merge chain in the game. Each tier has a real name rather than the
/// previous scheme of appending "II" repeatedly ("Stardust II II II").
struct ItemChain {
    let id: String
    let element: Element
    let baseProduction: Double
    let tierNames: [String]

    /// Production triples with each tier, matching the old merge maths.
    func production(atTier tier: Int) -> Double {
        baseProduction * pow(3.0, Double(tier))
    }
}

enum ItemCatalog {
    static let chains: [ItemChain] = [
        ItemChain(
            id: "fire_basic",
            element: .fire,
            baseProduction: 1.0,
            tierNames: ["Stardust", "Ember", "Cinder", "Flare",
                        "Solar Wisp", "Corona", "Sunforge", "Helios Core"]
        ),
        ItemChain(
            id: "ice_basic",
            element: .ice,
            baseProduction: 1.0,
            tierNames: ["Frost Dust", "Rime", "Glacier Shard", "Comet",
                        "Ice Moon", "Cryosphere", "Frozen Titan", "Absolute Zero"]
        ),
        ItemChain(
            id: "void_basic",
            element: .void,
            baseProduction: 1.5,
            tierNames: ["Dark Matter", "Shadow Wisp", "Null Fragment", "Void Rift",
                        "Singularity", "Event Horizon", "Dark Star", "Oblivion"]
        ),
        ItemChain(
            id: "radiant_basic",
            element: .radiant,
            baseProduction: 2.0,
            tierNames: ["Sunmote", "Gleam", "Prism", "Radiant Core",
                        "Starlight", "Quasar", "Pulsar", "Lumen Eternal"]
        )
    ]

    static func chain(for id: String) -> ItemChain? {
        chains.first { $0.id == id }
    }

    /// Canonical name for a chain/tier pair, used to repair names loaded from
    /// saves written before the catalog existed.
    static func name(chainID: String, tier: Int) -> String? {
        guard let chain = chain(for: chainID), chain.tierNames.indices.contains(tier) else { return nil }
        return chain.tierNames[tier]
    }

    static func makeItem(chainID: String, tier: Int = 0) -> CelestialItem? {
        guard let chain = chain(for: chainID), chain.tierNames.indices.contains(tier) else { return nil }
        return CelestialItem(
            id: UUID(),
            chainID: chain.id,
            tier: tier,
            element: chain.element,
            baseProduction: chain.production(atTier: tier),
            name: chain.tierNames[tier],
            position: nil
        )
    }
}

// MARK: - Idle Engine
class IdleEngine: ObservableObject {
    @Published var totalProductionPerSec: Double = 0
    private var timer: Timer?
    var permanentMultiplier: Double = 1.0
    /// Set by the view model from purchased prestige upgrades.
    var upgradeMultiplier: Double = 1.0

    private let tickInterval: TimeInterval = 0.1

    /// Called every tick with the stardust produced during that tick.
    var onTick: ((Double) -> Void)?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.totalProductionPerSec > 0 else { return }
            self.onTick?(self.totalProductionPerSec * self.tickInterval)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func recalculate(from grid: [[GridTile]]) {
        var base = 0.0
        for row in grid {
            for tile in row {
                guard let item = tile.placedItem else { continue }
                // Neighbouring items of the same element reinforce each other.
                let sameElementNeighbours = neighbours(of: tile, in: grid)
                    .filter { $0.element == item.element }
                    .count
                base += item.baseProduction * (1.0 + 0.15 * Double(sameElementNeighbours))
            }
        }
        totalProductionPerSec = base * permanentMultiplier * upgradeMultiplier
    }

    /// Items placed on the six tiles adjacent to `tile` in the offset hex layout.
    private func neighbours(of tile: GridTile, in grid: [[GridTile]]) -> [CelestialItem] {
        // Even and odd rows are staggered, so the diagonal offsets differ.
        let isEvenRow = tile.row % 2 == 0
        let offsets: [(Int, Int)] = isEvenRow
            ? [(0, -1), (0, 1), (-1, 0), (-1, 1), (1, 0), (1, 1)]
            : [(0, -1), (0, 1), (-1, -1), (-1, 0), (1, -1), (1, 0)]

        var result: [CelestialItem] = []
        for offset in offsets {
            let row = tile.row + offset.0
            let col = tile.col + offset.1
            guard grid.indices.contains(row), grid[row].indices.contains(col) else { continue }
            if let neighbour = grid[row][col].placedItem {
                result.append(neighbour)
            }
        }
        return result
    }

    func applyPermanentMultiplier(_ mult: Double) {
        permanentMultiplier *= mult
    }
}

struct GridTile: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    var isUnlocked: Bool
    var placedItem: CelestialItem?
}

// MARK: - Main Game ViewModel
class GameViewModel: ObservableObject {
    @Published var stardust: Double = 0
    @Published var starlightShards: Int = 0
    @Published var nebulaGems: Int = 50
    @Published var galaxyMarks: Int = 0
    @Published var boardItems: [CelestialItem] = []
    @Published var gridTiles: [[GridTile]] = []
    @Published var showLootBoxOdds = false
    @Published var celestialRank: Int = 1

    @Published var totalMerges: Int = 0
    @Published var itemsForged: Int = 0
    @Published var highestTierReached: Int = 0
    @Published var claimedGoalIDs: Set<String> = []
    @Published var upgradeLevels: [String: Int] = [:]
    /// Stardust earned while the app was closed, surfaced once on launch.
    @Published var pendingOfflineEarnings: Double = 0
    /// Transient banner text describing the most recent merge.
    @Published var lastMergeSummary: String?
    @Published var hasSeenTutorial: Bool = UserDefaults.standard.bool(forKey: "nf.hasSeenTutorial") {
        didSet { UserDefaults.standard.set(hasSeenTutorial, forKey: "nf.hasSeenTutorial") }
    }

    let idleEngine = IdleEngine()
    private let persistence = PersistenceController.shared
    private var hasPrestiged = false

    /// Offline production is credited on relaunch, but capped so that leaving
    /// the game for weeks doesn't hand back an absurd (and unreadable) balance.
    private let baseOfflineHours: Double = 8

    /// Cost in Starlight Shards to unlock one additional grid tile. Starts
    /// cheap so the board can grow before the first prestige is reachable.
    var tileUnlockCost: Int {
        let unlocked = gridTiles.flatMap { $0 }.filter { $0.isUnlocked }.count
        return max(5, (unlocked - 5) * 5)
    }

    /// Cost in Nebula Gems to conjure a fresh tier-0 item onto the board.
    let itemSummonCost = 5

    /// Stardust price of forging a new item. This is the primary sink and the
    /// only renewable source of items — without it the board can only shrink
    /// (merging consumes two to make one) and prestige is unreachable.
    var forgeItemCost: Double {
        25 * pow(1.18, Double(itemsForged)) * forgeCostFactor
    }

    /// Placed items required before a Supernova can be triggered.
    static let prestigeRequirement = 10

    private enum DefaultsKey {
        static let hasSavedState = "nf.hasSavedState"
        static let stardust = "nf.stardust"
        static let starlightShards = "nf.starlightShards"
        static let nebulaGems = "nf.nebulaGems"
        static let galaxyMarks = "nf.galaxyMarks"
        static let celestialRank = "nf.celestialRank"
        static let permanentMultiplier = "nf.permanentMultiplier"
        static let hasPrestiged = "nf.hasPrestiged"
        static let totalMerges = "nf.totalMerges"
        static let itemsForged = "nf.itemsForged"
        static let highestTierReached = "nf.highestTierReached"
        static let claimedGoalIDs = "nf.claimedGoalIDs"
        static let upgradeLevels = "nf.upgradeLevels"
        static let unlockedTiles = "nf.unlockedTiles"
        static let lastSaveDate = "nf.lastSaveDate"
    }

    init() {
        setupIdleCollection()
        if !loadGameState() {
            initializeBoard()
        }
    }

    func setupIdleCollection() {
        idleEngine.onTick = { [weak self] produced in
            self?.stardust += produced
        }
        idleEngine.start()
    }

    func initializeBoard() {
        // Start with matched pairs so the first merge is immediately possible.
        boardItems = ["fire_basic", "fire_basic", "ice_basic",
                      "ice_basic", "void_basic", "void_basic"]
            .compactMap { ItemCatalog.makeItem(chainID: $0) }
        for _ in 0..<bonusStartingItems {
            boardItems.append(randomStarterItem())
        }

        // Initialize 5x5 hex grid
        gridTiles = (0..<5).map { row in
            (0..<5).map { col in
                GridTile(row: row, col: col, isUnlocked: row < 2 && col < 3, placedItem: nil)
            }
        }

        idleEngine.recalculate(from: gridTiles)
    }

    func attemptMerge(_ item1: CelestialItem, _ item2: CelestialItem) -> Bool {
        guard let merged = CelestialItem.merge(item1: item1, item2: item2) else {
            HapticManager.shared.mergeFail()
            return false
        }

        boardItems.removeAll { $0.id == item1.id || $0.id == item2.id }
        boardItems.append(merged)

        // Merging is the main source of Starlight Shards; higher tiers pay more.
        let shardsGained = max(1, merged.tier * 2) * shardYieldMultiplier
        starlightShards += shardsGained
        totalMerges += 1
        highestTierReached = max(highestTierReached, merged.tier)

        announceMerge("\(merged.name)   +\(shardsGained)")
        celestialRank = 1 + totalMerges / 10

        HapticManager.shared.mergeSuccess()

        saveGameState()
        return true
    }

    /// Spends Starlight Shards to unlock the next locked tile, nearest first.
    @discardableResult
    func unlockNextTile() -> Bool {
        guard starlightShards >= tileUnlockCost else { return false }
        for row in gridTiles.indices {
            for col in gridTiles[row].indices where !gridTiles[row][col].isUnlocked {
                starlightShards -= tileUnlockCost
                gridTiles[row][col].isUnlocked = true
                HapticManager.shared.itemPlace()
                saveGameState()
                return true
            }
        }
        return false
    }

    /// A fresh tier-0 item. Common chains are weighted higher so early boards
    /// tend to contain matching pairs the player can actually merge.
    private func randomStarterItem() -> CelestialItem {
        let weighted = ["fire_basic", "fire_basic", "ice_basic", "ice_basic",
                        "void_basic", "radiant_basic"]
        let chainID = weighted.randomElement()!
        return ItemCatalog.makeItem(chainID: chainID) ?? ItemCatalog.makeItem(chainID: "fire_basic")!
    }

    /// Spends Stardust to forge a new item — the main progression loop.
    @discardableResult
    func forgeItem() -> Bool {
        guard stardust >= forgeItemCost else { return false }
        stardust -= forgeItemCost
        itemsForged += 1
        boardItems.append(randomStarterItem())
        HapticManager.shared.itemPlace()
        saveGameState()
        return true
    }

    /// Spends Nebula Gems to add a random tier-0 item to the merge board.
    @discardableResult
    func summonItem() -> Bool {
        guard nebulaGems >= itemSummonCost else { return false }
        nebulaGems -= itemSummonCost
        boardItems.append(randomStarterItem())
        HapticManager.shared.itemPlace()
        saveGameState()
        return true
    }

    // MARK: Upgrade effects

    func upgradeLevel(_ id: String) -> Int {
        upgradeLevels[id] ?? 0
    }

    /// Multiplier applied on top of the prestige multiplier.
    var upgradeProductionMultiplier: Double {
        1.0 + 0.25 * Double(upgradeLevel("production"))
    }

    /// Shards from a merge are multiplied by this.
    var shardYieldMultiplier: Int {
        1 + upgradeLevel("shard_yield")
    }

    /// Fraction of the base forge price actually charged.
    var forgeCostFactor: Double {
        max(0.5, 1.0 - 0.05 * Double(upgradeLevel("forge_cost")))
    }

    /// Extra items granted when a run begins.
    var bonusStartingItems: Int {
        upgradeLevel("starting_items")
    }

    var offlineCapHours: Double {
        baseOfflineHours + 2 * Double(upgradeLevel("offline"))
    }

    @discardableResult
    func purchaseUpgrade(_ upgrade: PrestigeUpgrade) -> Bool {
        let level = upgradeLevel(upgrade.id)
        guard level < upgrade.maxLevel else { return false }
        let price = upgrade.cost(atLevel: level)
        guard galaxyMarks >= price else { return false }

        galaxyMarks -= price
        upgradeLevels[upgrade.id] = level + 1

        // Production upgrades change output immediately.
        syncUpgradeEffects()
        HapticManager.shared.mergeSuccess()
        saveGameState()
        return true
    }

    /// Shows a short-lived banner describing the last merge, then clears it.
    private func announceMerge(_ summary: String) {
        lastMergeSummary = summary
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            // Only clear if a newer merge hasn't replaced it in the meantime.
            if self?.lastMergeSummary == summary {
                self?.lastMergeSummary = nil
            }
        }
    }

    /// Pushes upgrade-derived values into the idle engine and recomputes output.
    /// Must run after any change to `upgradeLevels`, including on load.
    func syncUpgradeEffects() {
        idleEngine.upgradeMultiplier = upgradeProductionMultiplier
        idleEngine.recalculate(from: gridTiles)
    }

    /// Goals finished but not yet collected.
    var claimableGoals: [Goal] {
        GoalCatalog.all.filter { $0.isComplete(self) && !claimedGoalIDs.contains($0.id) }
    }

    @discardableResult
    func claimGoal(_ goal: Goal) -> Bool {
        guard goal.isComplete(self), !claimedGoalIDs.contains(goal.id) else { return false }
        claimedGoalIDs.insert(goal.id)
        starlightShards += goal.shardReward
        nebulaGems += goal.gemReward
        HapticManager.shared.mergeSuccess()
        saveGameState()
        return true
    }

    /// Items on the board that could merge with `item`.
    func mergeCandidates(for item: CelestialItem) -> Set<UUID> {
        Set(
            boardItems
                .filter { $0.id != item.id && $0.chainID == item.chainID && $0.tier == item.tier }
                .map(\.id)
        )
    }

    /// The single most useful next action, surfaced as a hint in the UI.
    var nextStepHint: String {
        let placed = gridTiles.flatMap { $0 }.filter { $0.placedItem != nil }.count
        if boardItems.isEmpty && placed == 0 {
            return "Forge an item to begin."
        }
        if !boardItems.isEmpty && placed == 0 {
            return "Place an item on your Galaxy grid to start earning Stardust."
        }
        if boardItems.count >= 2 {
            return "Tap two matching items to merge them into a stronger one."
        }
        if placed >= Self.prestigeRequirement {
            return "You can trigger a Supernova on the Nova tab."
        }
        return "Forge more items, then place them in your Galaxy."
    }

    func placeItemOnGrid(_ item: CelestialItem, row: Int, col: Int) -> Bool {
        guard row < gridTiles.count, col < gridTiles[row].count else { return false }
        guard gridTiles[row][col].isUnlocked, gridTiles[row][col].placedItem == nil else { return false }

        var itemToPlace = item
        itemToPlace.position = (row, col)
        gridTiles[row][col].placedItem = itemToPlace
        boardItems.removeAll { $0.id == item.id }

        idleEngine.recalculate(from: gridTiles)

        // Submit score to Game Center
        GameCenterManager.shared.submitScore(clampedScore(stardust))

        saveGameState()
        return true
    }

    func removeItemFromGrid(row: Int, col: Int) {
        guard var item = gridTiles[row][col].placedItem else { return }
        item.position = nil
        boardItems.append(item)
        gridTiles[row][col].placedItem = nil

        idleEngine.recalculate(from: gridTiles)
        saveGameState()
    }

    func triggerSupernova() -> Bool {
        // Check if board has enough placed items
        let placedCount = gridTiles.flatMap { $0 }.filter { $0.placedItem != nil }.count
        guard placedCount >= Self.prestigeRequirement else { return false }

        // Calculate Galaxy Marks earned
        let earnedMarks = placedCount / 5
        galaxyMarks += earnedMarks
        // Prestiging is the only source of Nebula Gems.
        nebulaGems += earnedMarks * 2
        hasPrestiged = true

        // Apply permanent boost
        let multiplier = 1.0 + (Double(earnedMarks) * 0.1)
        idleEngine.applyPermanentMultiplier(multiplier)

        // Start a new cycle, then unlock the larger post-prestige grid
        // (must happen after initializeBoard(), which would otherwise reset
        // the grid back to the small starting pattern).
        initializeBoard()
        gridTiles = (0..<5).map { row in
            (0..<5).map { col in
                GridTile(row: row, col: col, isUnlocked: row < 3 && col < 4, placedItem: nil)
            }
        }
        idleEngine.recalculate(from: gridTiles)

        // Submit prestige achievement
        GameCenterManager.shared.submitScore(Int64(galaxyMarks), leaderboardID: "nebulaforge.prestige")

        HapticManager.shared.supernova()

        saveGameState()
        return true
    }

    func saveGameState() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.hasSavedState)
        defaults.set(stardust, forKey: DefaultsKey.stardust)
        defaults.set(starlightShards, forKey: DefaultsKey.starlightShards)
        defaults.set(nebulaGems, forKey: DefaultsKey.nebulaGems)
        defaults.set(galaxyMarks, forKey: DefaultsKey.galaxyMarks)
        defaults.set(celestialRank, forKey: DefaultsKey.celestialRank)
        defaults.set(idleEngine.permanentMultiplier, forKey: DefaultsKey.permanentMultiplier)
        defaults.set(hasPrestiged, forKey: DefaultsKey.hasPrestiged)
        defaults.set(totalMerges, forKey: DefaultsKey.totalMerges)
        defaults.set(itemsForged, forKey: DefaultsKey.itemsForged)
        defaults.set(highestTierReached, forKey: DefaultsKey.highestTierReached)
        defaults.set(Array(claimedGoalIDs), forKey: DefaultsKey.claimedGoalIDs)
        defaults.set(upgradeLevels, forKey: DefaultsKey.upgradeLevels)
        defaults.set(Date(), forKey: DefaultsKey.lastSaveDate)

        // Tiles can be unlocked by spending shards, so the unlocked set has to
        // be stored rather than recomputed from prestige state alone.
        let unlockedKeys = gridTiles.flatMap { $0 }
            .filter { $0.isUnlocked }
            .map { "\($0.row),\($0.col)" }
        defaults.set(unlockedKeys, forKey: DefaultsKey.unlockedTiles)

        let context = persistence.viewContext

        // Replace all stored items with the current in-memory state rather
        // than trying to diff/upsert — the item counts here are tiny.
        if let existing = try? context.fetch(CelestialItemEntity.fetchRequest()) {
            for entity in existing {
                context.delete(entity)
            }
        }

        for item in boardItems {
            insertEntity(for: item, isPlaced: false, row: 0, col: 0, in: context)
        }
        for row in gridTiles {
            for tile in row {
                if let item = tile.placedItem {
                    insertEntity(for: item, isPlaced: true, row: tile.row, col: tile.col, in: context)
                }
            }
        }

        persistence.save()
    }

    private func insertEntity(for item: CelestialItem, isPlaced: Bool, row: Int, col: Int, in context: NSManagedObjectContext) {
        // Look the entity up by name rather than relying on class-name
        // resolution, which is fragile across Swift/ObjC name mangling.
        guard let description = NSEntityDescription.entity(forEntityName: "CelestialItemEntity", in: context) else {
            print("Missing CelestialItemEntity in the Core Data model")
            return
        }

        let entity = CelestialItemEntity(entity: description, insertInto: context)
        entity.id = item.id
        entity.chainID = item.chainID
        entity.tier = Int16(item.tier)
        entity.element = item.element.rawValue
        entity.name = item.name
        entity.baseProduction = item.baseProduction
        entity.isPlaced = isPlaced
        entity.gridRow = Int16(row)
        entity.gridCol = Int16(col)
    }

    /// Restores saved state and returns whether any was found. When `false`,
    /// the caller should fall back to `initializeBoard()` for a fresh start.
    @discardableResult
    func loadGameState() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.hasSavedState) else { return false }

        stardust = defaults.double(forKey: DefaultsKey.stardust)
        starlightShards = defaults.integer(forKey: DefaultsKey.starlightShards)
        nebulaGems = defaults.integer(forKey: DefaultsKey.nebulaGems)
        galaxyMarks = defaults.integer(forKey: DefaultsKey.galaxyMarks)
        celestialRank = max(1, defaults.integer(forKey: DefaultsKey.celestialRank))
        hasPrestiged = defaults.bool(forKey: DefaultsKey.hasPrestiged)
        totalMerges = defaults.integer(forKey: DefaultsKey.totalMerges)
        itemsForged = defaults.integer(forKey: DefaultsKey.itemsForged)
        highestTierReached = defaults.integer(forKey: DefaultsKey.highestTierReached)
        claimedGoalIDs = Set(defaults.stringArray(forKey: DefaultsKey.claimedGoalIDs) ?? [])
        upgradeLevels = defaults.dictionary(forKey: DefaultsKey.upgradeLevels) as? [String: Int] ?? [:]
        idleEngine.permanentMultiplier = defaults.object(forKey: DefaultsKey.permanentMultiplier) as? Double ?? 1.0

        // Saves written before tile unlocking existed have no stored set, so
        // fall back to deriving it from prestige state.
        let unlockedKeys = Set(defaults.stringArray(forKey: DefaultsKey.unlockedTiles) ?? [])
        gridTiles = (0..<5).map { row in
            (0..<5).map { col in
                let unlocked = unlockedKeys.isEmpty
                    ? (hasPrestiged ? (row < 3 && col < 4) : (row < 2 && col < 3))
                    : unlockedKeys.contains("\(row),\(col)")
                return GridTile(row: row, col: col, isUnlocked: unlocked, placedItem: nil)
            }
        }

        let context = persistence.viewContext
        let request = CelestialItemEntity.fetchRequest()

        do {
            let savedItems = try context.fetch(request)
            var loadedBoardItems: [CelestialItem] = []

            for entity in savedItems {
                guard let id = entity.id,
                      let chainID = entity.chainID,
                      let elementStr = entity.element,
                      let name = entity.name,
                      let element = Element(rawValue: elementStr) else { continue }

                let tier = Int(entity.tier)
                // Saves written before the item catalog carry generated names
                // like "Stardust II II"; prefer the canonical name when known.
                let canonicalName = ItemCatalog.name(chainID: chainID, tier: tier) ?? name

                let item = CelestialItem(
                    id: id,
                    chainID: chainID,
                    tier: tier,
                    element: element,
                    baseProduction: entity.baseProduction,
                    name: canonicalName,
                    position: entity.isPlaced ? (Int(entity.gridRow), Int(entity.gridCol)) : nil
                )

                if entity.isPlaced {
                    let row = Int(entity.gridRow)
                    let col = Int(entity.gridCol)
                    if gridTiles.indices.contains(row), gridTiles[row].indices.contains(col) {
                        gridTiles[row][col].placedItem = item
                    }
                } else {
                    loadedBoardItems.append(item)
                }
            }

            boardItems = loadedBoardItems
        } catch {
            print("Failed to load game state: \(error)")
        }

        syncUpgradeEffects()

        // Credit production earned while the app was closed, capped so a long
        // absence can't return a nonsensical balance.
        if let lastSave = defaults.object(forKey: DefaultsKey.lastSaveDate) as? Date {
            let elapsed = min(Date().timeIntervalSince(lastSave), offlineCapHours * 3600)
            let earned = idleEngine.totalProductionPerSec * elapsed
            // Only worth interrupting the player for a meaningful amount.
            if elapsed > 60, earned > 1 {
                stardust += earned
                pendingOfflineEarnings = earned
            } else if earned > 0 {
                stardust += earned
            }
        }

        return true
    }
}

// MARK: - Content View (Main Game)
struct ContentView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @State private var selectedTab = 0
    @State private var showTutorial = false
    @State private var showOfflineEarnings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            MergeBoardView()
                .tabItem {
                    Label("Merge", systemImage: "circle.grid.cross.fill")
                }
                .tag(0)

            GalacticCanvasView()
                .tabItem {
                    Label("Galaxy", systemImage: "sparkles")
                }
                .tag(1)

            PrestigeView()
                .tabItem {
                    Label("Nova", systemImage: "burst.fill")
                }
                .tag(2)

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }
                .badge(gameVM.claimableGoals.count)
                .tag(3)

            ShopView()
                .tabItem {
                    Label("Shop", systemImage: "cart.fill")
                }
                .tag(4)
        }
        .tint(.purple)
        .sheet(isPresented: $showTutorial, onDismiss: {
            gameVM.hasSeenTutorial = true
        }) {
            TutorialView()
        }
        .sheet(isPresented: $showOfflineEarnings, onDismiss: {
            gameVM.pendingOfflineEarnings = 0
        }) {
            OfflineEarningsView(amount: gameVM.pendingOfflineEarnings)
        }
        .onAppear {
            if !gameVM.hasSeenTutorial {
                showTutorial = true
            } else if gameVM.pendingOfflineEarnings > 0 {
                showOfflineEarnings = true
            }
        }
    }
}

// MARK: - Merge Board View
struct MergeBoardView: View {
    @EnvironmentObject var gameVM: GameViewModel
    // Tap-to-select rather than drag-and-drop: drag gestures fight the
    // enclosing ScrollView on iPhone and were effectively unusable.
    @State private var selectedItemID: UUID?
    @State private var showTutorial = false

    let columns = [GridItem(.adaptive(minimum: 80))]

    private var selectedItem: CelestialItem? {
        gameVM.boardItems.first { $0.id == selectedItemID }
    }

    private var mergeableIDs: Set<UUID> {
        guard let selectedItem else { return [] }
        return gameVM.mergeCandidates(for: selectedItem)
    }

    private func handleTap(on item: CelestialItem) {
        guard let current = selectedItem else {
            selectedItemID = item.id
            return
        }

        if current.id == item.id {
            selectedItemID = nil
            return
        }

        if gameVM.attemptMerge(current, item) {
            selectedItemID = nil
        } else {
            // Not a valid pair — treat the tap as picking a new item instead
            // of failing silently.
            selectedItemID = item.id
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground()

                VStack(spacing: 8) {
                    // Resource Bar
                    HStack {
                        ResourceBadge(icon: "star.fill", value: gameVM.stardust, color: .yellow)
                        Spacer()
                        ResourceBadge(icon: "sparkle", value: gameVM.starlightShards, color: .blue)
                        Spacer()
                        ResourceBadge(icon: "diamond.fill", value: gameVM.nebulaGems, color: .purple)
                    }
                    .padding()
                    .background(.ultraThinMaterial)

                    Text(gameVM.nextStepHint)
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack {
                        Text("\(abbreviatedNumber(gameVM.idleEngine.totalProductionPerSec))/sec")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Button {
                            _ = gameVM.summonItem()
                        } label: {
                            Label("\(gameVM.itemSummonCost)", systemImage: "diamond.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .disabled(gameVM.nebulaGems < gameVM.itemSummonCost)

                        Button {
                            _ = gameVM.forgeItem()
                        } label: {
                            Label("Forge (\(abbreviatedNumber(gameVM.forgeItemCost)))", systemImage: "hammer.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(gameVM.stardust < gameVM.forgeItemCost)
                    }
                    .padding(.horizontal)

                    if gameVM.boardItems.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.orange.opacity(0.8))
                            Text("No items yet")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Forge one with Stardust, or place items in your Galaxy to earn more.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 15) {
                                ForEach(gameVM.boardItems) { item in
                                    Button {
                                        handleTap(on: item)
                                    } label: {
                                        ItemCard(item: item)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        selectedItemID == item.id ? Color.yellow
                                                            : (mergeableIDs.contains(item.id) ? Color.green : Color.clear),
                                                        lineWidth: selectedItemID == item.id ? 3 : 2
                                                    )
                                            )
                                            .scaleEffect(selectedItemID == item.id ? 1.08 : 1.0)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                            .animation(.spring(response: 0.3), value: selectedItemID)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let summary = gameVM.lastMergeSummary {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text(summary)
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.yellow))
                    .shadow(radius: 8)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: gameVM.lastMergeSummary)
            .navigationTitle("Merge Board")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showTutorial = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        GameCenterManager.shared.showLeaderboard()
                    }) {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }
            .sheet(isPresented: $showTutorial) {
                TutorialView()
            }
        }
    }
}

// MARK: - Upgrade Row
struct UpgradeRow: View {
    @EnvironmentObject var gameVM: GameViewModel
    let upgrade: PrestigeUpgrade

    private var level: Int { gameVM.upgradeLevel(upgrade.id) }
    private var maxed: Bool { level >= upgrade.maxLevel }
    private var price: Int { upgrade.cost(atLevel: level) }
    private var affordable: Bool { gameVM.galaxyMarks >= price }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(upgrade.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("Lv \(level)/\(upgrade.maxLevel)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Text(upgrade.detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            if maxed {
                Text("MAX")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            } else {
                Button {
                    gameVM.purchaseUpgrade(upgrade)
                } label: {
                    Label("\(price)", systemImage: "burst.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!affordable)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .opacity(maxed ? 0.65 : 1)
    }
}

// MARK: - Goals View
struct GoalsView: View {
    @EnvironmentObject var gameVM: GameViewModel

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(GoalCatalog.all) { goal in
                            GoalRow(goal: goal)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Goals")
        }
    }
}

struct GoalRow: View {
    @EnvironmentObject var gameVM: GameViewModel
    let goal: Goal

    private var claimed: Bool { gameVM.claimedGoalIDs.contains(goal.id) }
    private var complete: Bool { goal.isComplete(gameVM) }
    private var progress: Int { goal.currentProgress(gameVM) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: claimed ? "checkmark.seal.fill" : (complete ? "gift.fill" : "target"))
                .font(.title2)
                .foregroundColor(claimed ? .green : (complete ? .yellow : .white.opacity(0.5)))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(goal.detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                if !claimed {
                    ProgressView(value: Double(progress), total: Double(goal.target))
                        .tint(complete ? .yellow : .blue)
                    Text("\(progress) / \(goal.target)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                HStack(spacing: 10) {
                    if goal.shardReward > 0 {
                        Label("\(goal.shardReward)", systemImage: "sparkle")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if goal.gemReward > 0 {
                        Label("\(goal.gemReward)", systemImage: "diamond.fill")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
            }

            Spacer()

            if claimed {
                Text("Claimed")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else if complete {
                Button("Claim") {
                    gameVM.claimGoal(goal)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .font(.caption)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .opacity(claimed ? 0.6 : 1)
    }
}

// MARK: - Offline Earnings
struct OfflineEarningsView: View {
    @Environment(\.dismiss) var dismiss
    let amount: Double

    var body: some View {
        ZStack {
            CosmicBackground()

            VStack(spacing: 20) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow, .orange)

                Text("Welcome Back")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("Your galaxy kept working while you were away.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("+\(abbreviatedNumber(amount))")
                        .font(.title.bold())
                        .foregroundColor(.white)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)

                Button {
                    dismiss()
                } label: {
                    Text("Collect")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.purple, .blue],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(15)
                }
                .padding(.horizontal, 40)
            }
            .padding()
        }
    }
}

// MARK: - Tutorial
struct TutorialView: View {
    @Environment(\.dismiss) var dismiss

    private let steps: [(icon: String, title: String, detail: String)] = [
        ("hammer.fill", "Forge Items",
         "Spend Stardust to forge new celestial items. This is where every run begins."),
        ("circle.grid.cross.fill", "Merge Matching Items",
         "Tap one item, then tap a matching one. They combine into a stronger item worth triple the production."),
        ("sparkles", "Build Your Galaxy",
         "Place items on the hex grid. Placed items generate Stardust every second, even while you're away."),
        ("link", "Chain Elements",
         "Items of the same element sitting next to each other boost each other's output by 15%."),
        ("burst.fill", "Go Supernova",
         "With \(GameViewModel.prestigeRequirement) items placed, trigger a Supernova. You lose the board but keep a permanent multiplier and earn Gems.")
    ]

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Grow a galaxy from a single mote of dust.")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.bottom, 4)

                        ForEach(steps, id: \.title) { step in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: step.icon)
                                    .font(.title2)
                                    .foregroundColor(.yellow)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Text(step.detail)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.75))
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Start") { dismiss() }
                        .bold()
                }
            }
        }
    }
}

struct ItemCard: View {
    let item: CelestialItem

    var body: some View {
        VStack {
            CelestialItemSprite(item: item, size: 50)

            Text(item.name)
                .font(.caption)
                .foregroundColor(.white)

            Text("Tier \(item.tier)")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(width: 80, height: 110)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

/// Clamps an unbounded idle value into `Int64` range. A raw conversion traps on
/// overflow or NaN, which is reachable once idle production compounds.
func clampedScore(_ value: Double) -> Int64 {
    guard value.isFinite, value > 0 else { return 0 }
    return Int64(min(value, 9_000_000_000_000_000_000))
}

/// Formats large idle-game numbers compactly (1.2K, 3.4M, …). Also avoids
/// converting unbounded `Double`s to `Int`, which traps on overflow or NaN.
func abbreviatedNumber(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    let magnitude = max(0, value)
    let units = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx"]

    var scaled = magnitude
    var unitIndex = 0
    while scaled >= 1000, unitIndex < units.count - 1 {
        scaled /= 1000
        unitIndex += 1
    }

    if unitIndex == 0 {
        return String(format: "%.0f", scaled)
    }
    return String(format: "%.1f%@", scaled, units[unitIndex])
}

struct ResourceBadge: View {
    let icon: String
    let value: String
    let color: Color

    init(icon: String, value: String, color: Color) {
        self.icon = icon
        self.value = value
        self.color = color
    }

    init(icon: String, value: Int, color: Color) {
        self.init(icon: icon, value: String(value), color: color)
    }

    init(icon: String, value: Double, color: Color) {
        self.init(icon: icon, value: abbreviatedNumber(value), color: color)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }
}

// MARK: - Galactic Canvas (Hex Grid)
struct GalacticCanvasView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @State private var selectedItem: CelestialItem?

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground()

                VStack {
                    Text("Your Galaxy")
                        .font(.headline)
                        .foregroundColor(.white)

                    HStack {
                        ResourceBadge(icon: "sparkle", value: gameVM.starlightShards, color: .blue)

                        Spacer()

                        Button {
                            _ = gameVM.unlockNextTile()
                        } label: {
                            Label("Unlock Tile (\(gameVM.tileUnlockCost))", systemImage: "lock.open.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(gameVM.starlightShards < gameVM.tileUnlockCost)
                    }
                    .padding(.horizontal)

                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: -10) {
                            ForEach(0..<gameVM.gridTiles.count, id: \.self) { row in
                                HStack(spacing: -5) {
                                    ForEach(0..<gameVM.gridTiles[row].count, id: \.self) { col in
                                        HexTileView(
                                            tile: gameVM.gridTiles[row][col],
                                            isSelected: selectedItem != nil,
                                            onPlace: {
                                                if let item = selectedItem {
                                                    _ = gameVM.placeItemOnGrid(item, row: row, col: col)
                                                    selectedItem = nil
                                                }
                                            },
                                            onRemove: {
                                                gameVM.removeItemFromGrid(row: row, col: col)
                                            }
                                        )
                                        .offset(x: row % 2 == 0 ? 25 : 0)
                                    }
                                }
                            }
                        }
                        .padding()
                    }

                    // Item picker for placement
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(gameVM.boardItems) { item in
                                Button(action: {
                                    selectedItem = item
                                }) {
                                    ItemCard(item: item)
                                        .scaleEffect(0.8)
                                        .opacity(selectedItem?.id == item.id ? 1.0 : 0.6)
                                        .overlay(
                                            selectedItem?.id == item.id ?
                                            RoundedRectangle(cornerRadius: 12).stroke(Color.yellow, lineWidth: 2) :
                                            nil
                                        )
                                }
                            }
                        }
                        .padding()
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Galaxy")
        }
    }
}

// MARK: - Celestial Item Sprite
struct CelestialItemSprite: View {
    let item: CelestialItem
    let size: CGFloat
    @State private var pulse = false

    private var baseColor: Color {
        switch item.element {
        case .fire: return .orange
        case .ice: return .cyan
        case .void: return .indigo
        case .radiant: return .yellow
        }
    }

    var body: some View {
        ZStack {
            if item.tier >= 3 {
                Circle()
                    .fill(baseColor.opacity(0.3))
                    .frame(width: size + 10, height: size + 10)
                    .blur(radius: glowRadius)
                    // Higher tiers breathe, so power reads at a glance.
                    .scaleEffect(pulse ? 1.12 : 0.95)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear { pulse = true }
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: baseColor.opacity(0.7), radius: item.tier >= 5 ? 12 : 5)

            Image(systemName: symbolName)
                .font(.system(size: size * symbolScale))
                .foregroundColor(.white)
                .shadow(radius: item.tier > 3 ? 2 : 0)

            if item.tier >= 6 {
                ForEach(0..<min(item.tier - 5, 3), id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                        .offset(
                            x: cos(Double(i) * 2.0) * size / 2.5,
                            y: sin(Double(i) * 2.0) * size / 2.5
                        )
                }
            }
        }
        .frame(width: size + 20, height: size + 20)
    }

    private var glowRadius: CGFloat { min(2 + CGFloat(item.tier) * 1.5, 15) }

    // Clamped so very high tiers don't overflow the circle.
    private var symbolScale: CGFloat { min(0.7 + CGFloat(item.tier) * 0.05, 0.95) }

    private var gradientColors: [Color] {
        switch item.tier {
        case 0...2: return [baseColor.opacity(0.6), baseColor]
        case 3...5: return [baseColor, baseColor.opacity(0.8), .white.opacity(0.6)]
        default: return [baseColor, .white.opacity(0.9), baseColor]
        }
    }

    private var symbolName: String {
        switch item.element {
        case .fire: return item.tier > 5 ? "flame.fill" : "flame"
        case .ice: return "snowflake"
        case .void: return item.tier > 3 ? "moon.stars.fill" : "moon.stars"
        case .radiant: return "sun.max.fill"
        }
    }
}

struct HexTileView: View {
    let tile: GridTile
    let isSelected: Bool
    let onPlace: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: {
            if tile.placedItem != nil {
                onRemove()
            } else if isSelected && tile.isUnlocked {
                onPlace()
            }
        }) {
            ZStack {
                HexagonShape()
                    .fill(
                        tile.isUnlocked
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.gray.opacity(0.1))
                    )
                    .overlay(
                        HexagonShape()
                            .stroke(
                                isSelected && tile.isUnlocked && tile.placedItem == nil
                                ? Color.yellow
                                : (tile.isUnlocked ? Color.white.opacity(0.4) : Color.gray.opacity(0.3)),
                                lineWidth: isSelected && tile.isUnlocked ? 2.5 : 1.5
                            )
                    )
                    .frame(width: 65, height: 75)

                if let item = tile.placedItem {
                    CelestialItemSprite(item: item, size: 40)
                        .transition(.scale.combined(with: .opacity))
                }

                if !tile.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .animation(.spring(response: 0.3), value: tile.placedItem != nil)
        }
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        for i in 0..<6 {
            let angle = CGFloat.pi / 3 * CGFloat(i) - CGFloat.pi / 6
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Particle Effects
class SupernovaScene: SKScene {
    override func sceneDidLoad() {
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let emitter = SKEmitterNode()
        emitter.particleBirthRate = 300
        emitter.particleLifetime = 1.5
        emitter.particleSpeed = 200
        emitter.particleSpeedRange = 100
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.2
        emitter.particleScaleSpeed = -0.1
        emitter.particleColor = .white
        emitter.particleColorBlendFactor = 0.5
        emitter.particleTexture = SKTexture(imageNamed: "spark")
        emitter.position = .zero
        addChild(emitter)

        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 2.0)
        emitter.run(fadeOut) { [weak self] in
            self?.removeAllChildren()
        }
    }
}

struct SupernovaEffect: View {
    // Built once and held, so SwiftUI re-rendering doesn't restart the burst.
    @State private var scene: SKScene = {
        let scene = SupernovaScene()
        scene.size = UIScreen.main.bounds.size
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene, options: .allowsTransparency)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - Cosmic Background
struct CosmicBackground: View {
    // Generated once so the starfield doesn't reshuffle every frame.
    private let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, opacity: Double)] = (0..<80).map { _ in
        (
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            r: CGFloat.random(in: 0.5...2.5),
            opacity: Double.random(in: 0.3...1)
        )
    }

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.02, green: 0.01, blue: 0.15),
                        Color(red: 0.05, green: 0.02, blue: 0.3)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            for star in stars {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: star.x * size.width,
                        y: star.y * size.height,
                        width: star.r,
                        height: star.r
                    )),
                    with: .color(.white.opacity(star.opacity))
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Prestige View
struct PrestigeView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @State private var showConfirmation = false
    @State private var supernovaAnimation = false

    var placedCount: Int {
        gameVM.gridTiles.flatMap { $0 }.filter { $0.placedItem != nil }.count
    }

    var potentialMarks: Int {
        placedCount / 5
    }

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground()

                if supernovaAnimation {
                    Color.white
                        .opacity(0.85)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    SupernovaEffect()
                }

                ScrollView {
                    VStack(spacing: 22) {
                        Text(placedCount >= GameViewModel.prestigeRequirement ? "Supernova Ready" : "Supernova Locked")
                            .font(.title.bold())
                            .foregroundColor(.white)

                        VStack {
                            Text("\(placedCount) / \(GameViewModel.prestigeRequirement) items placed")
                                .foregroundColor(.white.opacity(0.8))
                            Text("Potential Galaxy Marks: \(potentialMarks)")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            Text("Celestial Rank: \(gameVM.celestialRank)")
                                .foregroundColor(.purple)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(15)

                        Text("Resetting destroys everything in this galaxy, but Galaxy Marks are permanent — spend them below.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal)

                        Button(action: {
                            showConfirmation = true
                        }) {
                            Text("Trigger Supernova")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(15)
                        }
                        .disabled(placedCount < GameViewModel.prestigeRequirement)
                        .padding(.horizontal)

                        Divider().background(Color.white.opacity(0.3))

                        HStack {
                            Text("Permanent Upgrades")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Label("\(gameVM.galaxyMarks)", systemImage: "burst.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 10) {
                            ForEach(UpgradeCatalog.all) { upgrade in
                                UpgradeRow(upgrade: upgrade)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .alert("Confirm Supernova", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset Galaxy", role: .destructive) {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        supernovaAnimation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        _ = gameVM.triggerSupernova()
                        withAnimation {
                            supernovaAnimation = false
                        }
                    }
                }
            } message: {
                Text("This will reset your galaxy but grant \(potentialMarks) permanent Galaxy Marks. Continue?")
            }
            .navigationTitle("Prestige")
        }
    }
}

// MARK: - Shop View (with Loot Box Odds)
struct ShopView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @StateObject private var iapManager = IAPManager.shared
    @State private var showOdds = false

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        Text("Nebula Store")
                            .font(.title.bold())
                            .foregroundColor(.white)

                        // Gems display
                        HStack {
                            Image(systemName: "diamond.fill")
                                .foregroundColor(.purple)
                            Text("\(gameVM.nebulaGems) Gems")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(15)

                        // Products
                        ForEach(iapManager.products, id: \.id) { product in
                            ShopProductRow(product: product, iapManager: iapManager)
                        }

                        // Loot Box Odds Button
                        Button(action: {
                            showOdds = true
                        }) {
                            HStack {
                                Image(systemName: "info.circle")
                                Text("View Drop Rates")
                            }
                            .foregroundColor(.blue)
                        }
                        .sheet(isPresented: $showOdds) {
                            LootBoxOddsView()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Shop")
        }
        .task {
            await iapManager.loadProducts()
        }
    }
}

struct ShopProductRow: View {
    let product: Product
    @ObservedObject var iapManager: IAPManager

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(product.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Button(action: {
                Task {
                    try? await iapManager.purchase(product)
                }
            }) {
                Text(product.displayPrice)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.purple)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
}

// MARK: - Haptic Manager
class HapticManager {
    static let shared = HapticManager()

    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        notificationGenerator.prepare()
        impactGenerator.prepare()
        heavyImpact.prepare()
        lightImpact.prepare()
    }

    func mergeSuccess() {
        impactGenerator.impactOccurred()
    }

    func mergeFail() {
        notificationGenerator.notificationOccurred(.error)
    }

    func supernova() {
        heavyImpact.impactOccurred()
    }

    func itemPlace() {
        lightImpact.impactOccurred()
    }
}
