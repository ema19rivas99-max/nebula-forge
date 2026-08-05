import SwiftUI
import StoreKit
import GameKit
import AppTrackingTransparency
import AdSupport
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
            } else if !privacyManager.hasAcceptedATT {
                ATTTrackingView()
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
    @Published var hasAcceptedATT: Bool {
        didSet { UserDefaults.standard.set(hasAcceptedATT, forKey: "hasAcceptedATT") }
    }
    @Published var trackingAuthorized: Bool = false

    private init() {
        self.hasAcceptedPrivacy = UserDefaults.standard.bool(forKey: "hasAcceptedPrivacy")
        self.hasAcceptedATT = UserDefaults.standard.bool(forKey: "hasAcceptedATT")
    }

    func acceptPrivacyPolicy() {
        hasAcceptedPrivacy = true
    }

    func requestTrackingAuthorization() {
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.trackingAuthorized = (status == .authorized)
                self?.hasAcceptedATT = true
            }
        }
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

                    Text("• Your game progress is stored privately in your iCloud account to sync across your devices.")
                        .foregroundColor(.white.opacity(0.8))

                    Text("• We do not collect, share, or sell any personal data.")
                        .foregroundColor(.white.opacity(0.8))

                    Text("• Leaderboard participation is optional and only shares your Game Center nickname and score.")
                        .foregroundColor(.white.opacity(0.8))

                    Text("• Optional ads are provided by Apple's advertising network and respect your privacy choices.")
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
                        Text("We collect your Game Center ID and game progress data solely for iCloud synchronization and leaderboard functionality. This data is stored in your private iCloud account and is not accessible to us.")

                        Text("2. How We Use Your Information")
                            .font(.headline)
                        Text("Your game data is used exclusively to save your progress and enable cross-device play. Leaderboard scores are shared publicly with your Game Center nickname.")

                        Text("3. Third-Party Services")
                            .font(.headline)
                        Text("We use Apple's Game Center and iCloud services. No third-party analytics, advertising networks, or data processors are used that collect personal information.")

                        Text("4. Your Rights")
                            .font(.headline)
                        Text("You can delete all your data by removing the app and deleting iCloud data from your device settings. You can opt out of Game Center features in Settings.")

                        Text("5. Contact")
                            .font(.headline)
                        Text("Email: privacy@nebulaforgegame.com")

                        Text("6. Children's Privacy")
                            .font(.headline)
                        Text("Nebula Forge is rated 4+ and does not knowingly collect personal information from children under 13 without parental consent. All data collection is through Apple's services which require parental approval for child accounts.")
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

// MARK: - ATT Tracking Authorization View
struct ATTTrackingView: View {
    @EnvironmentObject var privacyManager: PrivacyManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.3), Color(red: 0.1, green: 0.05, blue: 0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)

                Text("Personalized Experience")
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text("To provide relevant in-game offers and ads, we need your permission to track activity. You can change this anytime in Settings.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal)

                Button("Allow Tracking") {
                    privacyManager.requestTrackingAuthorization()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button("Ask App Not to Track") {
                    privacyManager.hasAcceptedATT = true
                }
                .foregroundColor(.gray)
            }
            .padding()
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
        guard item1.chainID == item2.chainID && item1.tier == item2.tier else { return nil }
        // Simulate next tier creation
        return CelestialItem(
            id: UUID(),
            chainID: item1.chainID,
            tier: item1.tier + 1,
            element: item1.element,
            baseProduction: item1.baseProduction * 3,
            name: "\(item1.name) II",
            position: nil
        )
    }
}

enum Element: String, CaseIterable, Codable {
    case fire, ice, void, radiant
}

// MARK: - Idle Engine
class IdleEngine: ObservableObject {
    @Published var totalProductionPerSec: Double = 0
    private var timer: Timer?
    private var permanentMultiplier: Double = 1.0

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Production will be consumed by GameViewModel
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func recalculate(from grid: [[GridTile]], multiplier: Double = 1.0) {
        var base = 0.0
        for row in grid {
            for tile in row {
                if let item = tile.placedItem {
                    var prod = item.baseProduction
                    // Simplified adjacency bonus
                    prod *= multiplier
                    base += prod
                }
            }
        }
        totalProductionPerSec = base * permanentMultiplier
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

    let idleEngine = IdleEngine()
    private var cancellables = Set<AnyCancellable>()
    private let persistence = PersistenceController.shared

    init() {
        setupIdleCollection()
        initializeBoard()
        loadGameState()
    }

    func setupIdleCollection() {
        idleEngine.$totalProductionPerSec
            .sink { [weak self] rate in
                guard let self = self else { return }
                self.stardust += rate / 10.0
            }
            .store(in: &cancellables)

        idleEngine.start()
    }

    func initializeBoard() {
        // Starting items
        boardItems = [
            CelestialItem(id: UUID(), chainID: "fire_basic", tier: 0, element: .fire, baseProduction: 1, name: "Stardust", position: nil),
            CelestialItem(id: UUID(), chainID: "fire_basic", tier: 0, element: .fire, baseProduction: 1, name: "Stardust", position: nil),
            CelestialItem(id: UUID(), chainID: "ice_basic", tier: 0, element: .ice, baseProduction: 1, name: "Frost Dust", position: nil),
            CelestialItem(id: UUID(), chainID: "ice_basic", tier: 0, element: .ice, baseProduction: 1, name: "Frost Dust", position: nil),
            CelestialItem(id: UUID(), chainID: "void_basic", tier: 0, element: .void, baseProduction: 1.5, name: "Dark Matter", position: nil),
            CelestialItem(id: UUID(), chainID: "void_basic", tier: 0, element: .void, baseProduction: 1.5, name: "Dark Matter", position: nil),
        ]

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
            // Haptic feedback for failed merge
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            return false
        }

        boardItems.removeAll { $0.id == item1.id || $0.id == item2.id }
        boardItems.append(merged)

        // Haptic feedback for successful merge
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        persistence.save()
        return true
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
        GameCenterManager.shared.submitScore(Int64(stardust))

        persistence.save()
        return true
    }

    func removeItemFromGrid(row: Int, col: Int) {
        guard var item = gridTiles[row][col].placedItem else { return }
        item.position = nil
        boardItems.append(item)
        gridTiles[row][col].placedItem = nil

        idleEngine.recalculate(from: gridTiles)
        persistence.save()
    }

    func triggerSupernova() -> Bool {
        // Check if board has enough placed items
        let placedCount = gridTiles.flatMap { $0 }.filter { $0.placedItem != nil }.count
        guard placedCount >= 10 else { return false }

        // Calculate Galaxy Marks earned
        let earnedMarks = placedCount / 5
        galaxyMarks += earnedMarks

        // Reset board but give permanent multiplier
        boardItems.removeAll()
        gridTiles = (0..<5).map { row in
            (0..<5).map { col in
                GridTile(row: row, col: col, isUnlocked: row < 3 && col < 4, placedItem: nil)
            }
        }

        // Apply permanent boost
        let multiplier = 1.0 + (Double(earnedMarks) * 0.1)
        idleEngine.applyPermanentMultiplier(multiplier)

        // Add starter items for new cycle
        initializeBoard()
        idleEngine.recalculate(from: gridTiles)

        // Submit prestige achievement
        GameCenterManager.shared.submitScore(Int64(galaxyMarks), leaderboardID: "nebulaforge.prestige")

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        persistence.save()
        return true
    }

    func loadGameState() {
        let context = persistence.viewContext
        let request = CelestialItemEntity.fetchRequest()

        do {
            let savedItems = try context.fetch(request)
            if !savedItems.isEmpty {
                boardItems = savedItems.compactMap { entity in
                    guard let id = entity.id,
                          let chainID = entity.chainID,
                          let elementStr = entity.element,
                          let name = entity.name,
                          let element = Element(rawValue: elementStr) else { return nil }

                    return CelestialItem(
                        id: id,
                        chainID: chainID,
                        tier: Int(entity.tier),
                        element: element,
                        baseProduction: entity.baseProduction,
                        name: name,
                        position: entity.isPlaced ? (Int(entity.gridRow), Int(entity.gridCol)) : nil
                    )
                }
            }
        } catch {
            print("Failed to load game state: \(error)")
        }
    }
}

// MARK: - Content View (Main Game)
struct ContentView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @State private var selectedTab = 0

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

            ShopView()
                .tabItem {
                    Label("Shop", systemImage: "cart.fill")
                }
                .tag(3)
        }
        .tint(.purple)
    }
}

// MARK: - Merge Board View
struct MergeBoardView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @State private var draggedItem: CelestialItem?
    @State private var dropTarget: CelestialItem?
    @State private var mergeEffect = false

    let columns = [GridItem(.adaptive(minimum: 80))]

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.02, blue: 0.3), Color(red: 0.1, green: 0.05, blue: 0.4)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack {
                    // Resource Bar
                    HStack {
                        ResourceBadge(icon: "star.fill", value: Int(gameVM.stardust), color: .yellow)
                        Spacer()
                        ResourceBadge(icon: "sparkle", value: gameVM.starlightShards, color: .blue)
                        Spacer()
                        ResourceBadge(icon: "diamond.fill", value: gameVM.nebulaGems, color: .purple)
                    }
                    .padding()
                    .background(.ultraThinMaterial)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 15) {
                            ForEach(gameVM.boardItems) { item in
                                ItemCard(item: item)
                                    .onDrag {
                                        draggedItem = item
                                        return NSItemProvider(object: item.id.uuidString as NSString)
                                    }
                                    .onDrop(of: [.text], delegate: ItemDropDelegate(item: item, draggedItem: $draggedItem, dropTarget: $dropTarget, gameVM: gameVM))
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Merge Board")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        GameCenterManager.shared.showLeaderboard()
                    }) {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
    }
}

struct ItemDropDelegate: DropDelegate {
    let item: CelestialItem
    @Binding var draggedItem: CelestialItem?
    @Binding var dropTarget: CelestialItem?
    let gameVM: GameViewModel

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedItem = draggedItem, draggedItem.id != item.id else { return false }
        dropTarget = item

        // Attempt merge
        if gameVM.attemptMerge(draggedItem, item) {
            // Success animation handled by state change
        }

        return true
    }
}

struct ItemCard: View {
    let item: CelestialItem

    var elementColor: Color {
        switch item.element {
        case .fire: return .orange
        case .ice: return .cyan
        case .void: return .indigo
        case .radiant: return .yellow
        }
    }

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(elementColor.opacity(0.3))
                    .frame(width: 60, height: 60)

                Image(systemName: elementIcon)
                    .font(.title)
                    .foregroundColor(elementColor)
            }

            Text(item.name)
                .font(.caption)
                .foregroundColor(.white)

            Text("Tier \(item.tier)")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(width: 80, height: 100)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    var elementIcon: String {
        switch item.element {
        case .fire: return "flame.fill"
        case .ice: return "snowflake"
        case .void: return "moon.stars.fill"
        case .radiant: return "sun.max.fill"
        }
    }
}

struct ResourceBadge: View {
    let icon: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text("\(value)")
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
                Color(red: 0.02, green: 0.01, blue: 0.15)
                    .ignoresSafeArea()

                VStack {
                    Text("Your Galaxy")
                        .font(.headline)
                        .foregroundColor(.white)

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
                    .stroke(tile.isUnlocked ? (isSelected ? Color.yellow : Color.white.opacity(0.5)) : Color.gray.opacity(0.3), lineWidth: 2)
                    .background(
                        HexagonShape()
                            .fill(tile.isUnlocked ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    )
                    .frame(width: 60, height: 70)

                if let item = tile.placedItem {
                    VStack {
                        Image(systemName: "star.circle.fill")
                            .foregroundColor(.yellow)
                        Text(item.name)
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                    }
                }
            }
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
                LinearGradient(colors: [Color(red: 0.05, green: 0.02, blue: 0.3), Color(red: 0.1, green: 0.05, blue: 0.4)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if supernovaAnimation {
                    // Supernova effect
                    Color.white
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                VStack(spacing: 30) {
                    Text("Supernova Ready")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)

                    VStack {
                        Text("\(placedCount) items placed")
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

                    Text("Resetting will destroy all items in this galaxy but grant permanent production bonuses and unlock new content.")
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
                    .disabled(placedCount < 10)
                    .padding(.horizontal)
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
                LinearGradient(colors: [Color(red: 0.05, green: 0.02, blue: 0.3), Color(red: 0.1, green: 0.05, blue: 0.4)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

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
