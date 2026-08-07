import SwiftUI
import StoreKit
import GameKit
import CoreData
import Combine
import SpriteKit
import AVFoundation
import UserNotifications

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

        // Warm the players for the effects that fire soonest, so the first
        // merge of a session isn't the one that stutters.
        HapticManager.shared.prepare()
        AudioManager.shared.preload()

        // StoreKit transaction updates are observed by IAPManager, which owns
        // the exactly-once grant bookkeeping. A second listener here meant every
        // transaction was finished twice.

        return true
    }

    func authenticateGameCenterPlayer() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            // Always publish the current state, including failure, so the UI can
            // disable Game Center affordances rather than offering a button that
            // opens a modal the player can't escape.
            GameCenterManager.shared.playerAuthenticated()

            if let vc = viewController {
                // Present the sign-in sheet only once the app actually has a
                // foreground scene; at launch `.first` can be one that has no
                // window yet, and presenting on it does nothing.
                guard let scene = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .first(where: { $0.activationState == .foregroundActive }),
                      let root = scene.keyWindow?.rootViewController
                        ?? scene.windows.first?.rootViewController else { return }
                root.present(vc, animated: true)
            } else if let error = error {
                print("Game Center auth failed: \(error.localizedDescription)")
            } else if GKLocalPlayer.local.isAuthenticated {
                print("Game Center authenticated")
                GameCenterManager.shared.playerAuthenticated()
            }
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
                        // Must be an address that actually receives mail —
                        // App Review checks it, and nebulaforgegame.com was
                        // never a domain we owned.
                        Text("Email: emanuelrivas199@gmail.com")

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

    /// Last percentage sent per achievement, so unchanged values aren't
    /// resubmitted on every merge.
    fileprivate var reportedPercent: [String: Double] = [:]

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

    /// Presents Game Center, or does nothing if it isn't usable yet.
    ///
    /// Presenting `GKGameCenterViewController` before authentication completes
    /// puts up a modal that never finishes loading and never shows its Done
    /// button — the app looks frozen with no way back. The guard is the fix; the
    /// button is also disabled in the UI while unauthenticated so the tap isn't
    /// silently ignored.
    /// Retries authentication. GameKit's handler fires once per launch, so a
    /// player who signs in from Settings mid-session has no other way back in.
    func retryAuthentication() {
        guard !isAuthenticated else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, _ in
            self?.playerAuthenticated()
        }
    }

    func showLeaderboard() {
        guard isAuthenticated else { return }

        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController
                ?? scene.windows.first?.rootViewController else { return }

        // Presenting on a controller that is already presenting does nothing at
        // all, so walk to whatever is actually on top.
        var top = root
        while let presented = top.presentedViewController { top = presented }

        let gcVC = GKGameCenterViewController(state: .leaderboards)
        gcVC.gameCenterDelegate = self
        top.present(gcVC, animated: true)
    }
}

// MARK: - Achievements
/// Game Center achievement definitions. `id` must match the Achievement ID
/// configured in App Store Connect exactly, or reporting silently no-ops.
struct GameAchievement: Identifiable {
    let id: String
    let title: String
    /// How far along the player is, 0...1.
    let progress: (GameViewModel) -> Double
}

enum AchievementCatalog {
    static let all: [GameAchievement] = [
        GameAchievement(id: "nebulaforge.ach.firstmerge", title: "First Fusion") {
            min(Double($0.totalMerges), 1)
        },
        GameAchievement(id: "nebulaforge.ach.merge100", title: "Century") {
            Double($0.totalMerges) / 100
        },
        GameAchievement(id: "nebulaforge.ach.merge1000", title: "Forge Master") {
            Double($0.totalMerges) / 1000
        },
        GameAchievement(id: "nebulaforge.ach.firstfusion", title: "Crossed Streams") {
            min(Double($0.totalFusions), 1)
        },
        GameAchievement(id: "nebulaforge.ach.fusion50", title: "Alchemist") {
            Double($0.totalFusions) / 50
        },
        GameAchievement(id: "nebulaforge.ach.tier5", title: "Stellar Architect") {
            Double($0.highestTierReached) / 5
        },
        GameAchievement(id: "nebulaforge.ach.tier7", title: "Ascendant") {
            Double($0.highestTierReached) / 7
        },
        GameAchievement(id: "nebulaforge.ach.prestige", title: "Reborn") {
            min(Double($0.galaxyMarks), 1)
        },
        GameAchievement(id: "nebulaforge.ach.marks100", title: "Cosmic Architect") {
            Double($0.galaxyMarks) / 100
        },
        GameAchievement(id: "nebulaforge.ach.streak7", title: "Regular Orbit") {
            Double($0.dailyStreak) / 7
        },
    ]
}

extension GameCenterManager {
    /// Reports progress for everything that has moved.
    ///
    /// Submissions are cached and only sent when the percentage actually
    /// increases — this is called after every merge, and Game Center will
    /// throttle an app that reports unchanged values continuously.
    func report(_ game: GameViewModel) {
        guard isAuthenticated else { return }

        var toSend: [GKAchievement] = []
        for definition in AchievementCatalog.all {
            let percent = min(max(definition.progress(game), 0), 1) * 100
            if let sent = reportedPercent[definition.id], percent <= sent { continue }
            reportedPercent[definition.id] = percent

            let achievement = GKAchievement(identifier: definition.id)
            achievement.percentComplete = percent
            achievement.showsCompletionBanner = true
            toSend.append(achievement)
        }

        guard !toSend.isEmpty else { return }
        GKAchievement.report(toSend) { error in
            if let error {
                print("Achievement report failed: \(error.localizedDescription)")
            }
        }
    }
}

extension GameCenterManager: GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

// MARK: - Store Catalog
/// What each product actually hands over. Prices live in App Store Connect;
/// this is only the payload, and every number here is meant to be tuned.
///
/// The `kind` must match the product's type in App Store Connect, or StoreKit
/// and the game will disagree about whether something is re-buyable.
struct StoreGrant {
    enum Kind {
        /// Granted on every purchase (gem packs).
        case consumable
        /// Granted once; the multiplier applies for as long as it's owned.
        case nonConsumable
        /// Granted again on every renewal; multiplier applies while active.
        case subscription
    }

    let gems: Int
    let shards: Int
    /// Applied to production for as long as the entitlement is valid.
    let productionMultiplier: Double
    let kind: Kind
    /// Higher tiers of the same subscription group outrank lower ones. Only the
    /// best active tier applies, so upgrading never stacks by accident.
    let tier: Int
    /// Extra offline hours granted while the entitlement is active.
    let offlineHours: Double
    /// Themes unlocked for free by owning this.
    let themeIDs: [String]

    init(gems: Int, shards: Int, productionMultiplier: Double, kind: Kind,
         tier: Int = 0, offlineHours: Double = 0, themeIDs: [String] = []) {
        self.gems = gems
        self.shards = shards
        self.productionMultiplier = productionMultiplier
        self.kind = kind
        self.tier = tier
        self.offlineHours = offlineHours
        self.themeIDs = themeIDs
    }
}

enum StoreCatalog {
    /// Gem packs climb in value per dollar — the standard ladder, so the large
    /// tiers are visibly the better deal rather than just bigger.
    static let grants: [String: StoreGrant] = [
        // Consumable gem ladder: $0.99 -> $99.99
        "nebulaforge.gems.handful": StoreGrant(
            gems: 80, shards: 0, productionMultiplier: 1.0, kind: .consumable),
        "nebulaforge.pileofgems": StoreGrant(
            gems: 500, shards: 0, productionMultiplier: 1.0, kind: .consumable),
        "nebulaforge.gems.crate": StoreGrant(
            gems: 1_200, shards: 200, productionMultiplier: 1.0, kind: .consumable),
        "nebulaforge.gems.vault": StoreGrant(
            gems: 2_800, shards: 600, productionMultiplier: 1.0, kind: .consumable),
        "nebulaforge.gems.hoard": StoreGrant(
            gems: 7_500, shards: 2_000, productionMultiplier: 1.0, kind: .consumable),
        "nebulaforge.gems.galaxy": StoreGrant(
            gems: 16_000, shards: 5_000, productionMultiplier: 1.0, kind: .consumable),

        // One-time bundles.
        "nebulaforge.starterpack": StoreGrant(
            gems: 200, shards: 100, productionMultiplier: 1.25, kind: .nonConsumable,
            themeIDs: ["crimson"]),
        "nebulaforge.architectkit": StoreGrant(
            gems: 400, shards: 250, productionMultiplier: 1.5, kind: .nonConsumable,
            offlineHours: 4, themeIDs: ["aurora"]),

        // Subscriptions. Tier decides which one wins when more than one is
        // somehow active; only the highest applies.
        "nebulaforge.gemsubscription.weekly": StoreGrant(
            gems: 150, shards: 0, productionMultiplier: 1.0, kind: .subscription,
            tier: 1),
        "nebulaforge.nebulapass.monthly": StoreGrant(
            gems: 300, shards: 150, productionMultiplier: 2.0, kind: .subscription,
            tier: 2, offlineHours: 8, themeIDs: ["gilded"]),
        "nebulaforge.nebulapass.plus.monthly": StoreGrant(
            gems: 900, shards: 500, productionMultiplier: 3.5, kind: .subscription,
            tier: 3, offlineHours: 16, themeIDs: ["gilded", "verdant", "abyss"]),
        "nebulaforge.nebulapass.architect.monthly": StoreGrant(
            gems: 2_500, shards: 1_500, productionMultiplier: 6.0, kind: .subscription,
            tier: 4, offlineHours: 24,
            themeIDs: ["gilded", "verdant", "abyss", "ember", "monochrome", "prism"]),
    ]

    static func grant(for productID: String) -> StoreGrant? { grants[productID] }

    /// Short line describing what a product gives, for the shop row.
    static func summary(for productID: String) -> String? {
        guard let grant = grant(for: productID) else { return nil }
        var parts: [String] = []
        if grant.gems > 0 { parts.append("\(grant.gems) Gems") }
        if grant.shards > 0 { parts.append("\(grant.shards) Shards") }
        if grant.productionMultiplier > 1 {
            parts.append(String(format: "%.3gx production", grant.productionMultiplier))
        }
        if grant.offlineHours > 0 {
            parts.append("+\(Int(grant.offlineHours))h offline")
        }
        if !grant.themeIDs.isEmpty {
            parts.append("\(grant.themeIDs.count) theme\(grant.themeIDs.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Gem Shop
/// Things bought with Gems rather than money. This is what gives the Shop tab a
/// reason to exist before any real-money product is approved, and what makes
/// the gems from prestige and purchases worth having.
struct GemOffer: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let gemCost: Int
}

enum GemShopCatalog {
    static let all: [GemOffer] = [
        GemOffer(id: "call_comet", title: "Call a Comet",
                 detail: "Summon a comet immediately, wherever there's room.",
                 icon: "sparkles", gemCost: 15),
        GemOffer(id: "forge_bundle", title: "Forge Bundle",
                 detail: "Five items dropped straight onto the board, free of Stardust.",
                 icon: "hammer.fill", gemCost: 25),
        GemOffer(id: "unlock_tile", title: "Expand the Grid",
                 detail: "Unlock the next tile without spending Shards.",
                 icon: "lock.open.fill", gemCost: 40),
        GemOffer(id: "surge", title: "Stellar Surge",
                 detail: "Double production for thirty minutes.",
                 icon: "bolt.fill", gemCost: 60),
        GemOffer(id: "shard_cache", title: "Shard Cache",
                 detail: "250 Starlight Shards, straight into your pocket.",
                 icon: "sparkle", gemCost: 80),
        GemOffer(id: "forge_reset", title: "Recalibrate the Forge",
                 detail: "Reset the Stardust price of forging back to its floor.",
                 icon: "arrow.counterclockwise", gemCost: 120),
        GemOffer(id: "surge_long", title: "Prolonged Surge",
                 detail: "Double production for four hours.",
                 icon: "bolt.badge.clock.fill", gemCost: 200),
        GemOffer(id: "tier_jump", title: "Forced Fusion",
                 detail: "Upgrade your strongest board item one full tier.",
                 icon: "arrow.up.circle.fill", gemCost: 350),
        GemOffer(id: "open_board", title: "Open the Galaxy",
                 detail: "Unlock every remaining tile at once.",
                 icon: "square.grid.3x3.fill", gemCost: 600),
    ]
}

// MARK: - Limited-time offers
/// A gem-shop item on sale for a fixed window.
///
/// The window is derived from wall-clock time rather than from when the player
/// happened to install, so the countdown is a real deadline and not a per-device
/// fiction that resets whenever the app is reopened.
struct TimedOffer: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let fullPrice: Int
    let salePrice: Int
    let expiresAt: Date

    var discountPercent: Int {
        guard fullPrice > 0 else { return 0 }
        return max(0, 100 - Int((Double(salePrice) / Double(fullPrice)) * 100))
    }

    var secondsRemaining: Int { max(0, Int(expiresAt.timeIntervalSinceNow)) }
    var isExpired: Bool { Date() >= expiresAt }

    var countdown: String {
        let s = secondsRemaining
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%dh %02dm", h, m)
                     : String(format: "%dm %02ds", m, sec)
    }
}

enum OfferCatalog {
    /// Deals rotate on a fixed cadence keyed to the clock, so every player sees
    /// the same offer at the same time and the timer can't be gamed by
    /// reinstalling.
    static let windowHours: Double = 8

    static func current(now: Date = Date()) -> TimedOffer? {
        let pool = GemShopCatalog.all
        guard !pool.isEmpty else { return nil }

        let windowLength = windowHours * 3600
        let window = floor(now.timeIntervalSince1970 / windowLength)
        let endsAt = Date(timeIntervalSince1970: (window + 1) * windowLength)

        let offer = pool[abs(Int(window)) % pool.count]
        // A third off, rounded to something that reads like a price.
        let sale = max(1, Int((Double(offer.gemCost) * 0.65).rounded()))

        return TimedOffer(id: offer.id, title: offer.title, detail: offer.detail,
                          icon: offer.icon, fullPrice: offer.gemCost,
                          salePrice: sale, expiresAt: endsAt)
    }
}

// MARK: - Cosmetics
/// Board themes. Palette-only by design — they restyle the whole galaxy without
/// shipping a single image, so the list can grow freely.
struct CosmeticTheme: Identifiable {
    let id: String
    let name: String
    let detail: String
    let gemCost: Int
    let background: [Color]
    let tileFill: [Color]
    let accent: Color
    let starTint: Color
    /// Soft coloured clouds drawn behind the starfield. This is what stops the
    /// themes reading as "the same screen, slightly different blue".
    let nebula: [Color]

    init(id: String, name: String, detail: String, gemCost: Int,
         background: [Color], tileFill: [Color], accent: Color, starTint: Color,
         nebula: [Color] = []) {
        self.id = id
        self.name = name
        self.detail = detail
        self.gemCost = gemCost
        self.background = background
        self.tileFill = tileFill
        self.accent = accent
        self.starTint = starTint
        self.nebula = nebula
    }
}

enum CosmeticCatalog {
    static let all: [CosmeticTheme] = [
        CosmeticTheme(
            id: "deep_void", name: "Deep Void",
            detail: "The original dark.", gemCost: 0,
            background: [Color(red: 0.02, green: 0.01, blue: 0.15),
                         Color(red: 0.05, green: 0.02, blue: 0.30)],
            tileFill: [Color.blue.opacity(0.15), Color.purple.opacity(0.10)],
            accent: .purple, starTint: .white,
            nebula: [Color.purple.opacity(0.18), Color.blue.opacity(0.14)]),

        CosmeticTheme(
            id: "crimson", name: "Crimson Nebula",
            detail: "A galaxy lit by dying stars.", gemCost: 150,
            background: [Color(red: 0.14, green: 0.02, blue: 0.08),
                         Color(red: 0.30, green: 0.04, blue: 0.12)],
            tileFill: [Color.red.opacity(0.16), Color.orange.opacity(0.10)],
            accent: .orange, starTint: Color(red: 1.0, green: 0.88, blue: 0.80),
            nebula: [Color.red.opacity(0.22), Color.orange.opacity(0.16)]),

        CosmeticTheme(
            id: "aurora", name: "Aurora Drift",
            detail: "Cold light over a green horizon.", gemCost: 250,
            background: [Color(red: 0.01, green: 0.12, blue: 0.13),
                         Color(red: 0.03, green: 0.26, blue: 0.24)],
            tileFill: [Color.teal.opacity(0.18), Color.green.opacity(0.10)],
            accent: .teal, starTint: Color(red: 0.85, green: 1.0, blue: 0.95),
            nebula: [Color.green.opacity(0.20), Color.teal.opacity(0.18)]),

        CosmeticTheme(
            id: "gilded", name: "Golden Expanse",
            detail: "For a galaxy that has clearly done well.", gemCost: 400,
            background: [Color(red: 0.13, green: 0.09, blue: 0.01),
                         Color(red: 0.28, green: 0.20, blue: 0.03)],
            tileFill: [Color.yellow.opacity(0.16), Color.orange.opacity(0.10)],
            accent: .yellow, starTint: Color(red: 1.0, green: 0.97, blue: 0.82),
            nebula: [Color.yellow.opacity(0.20), Color.orange.opacity(0.14)]),

        CosmeticTheme(
            id: "verdant", name: "Verdant Reach",
            detail: "Something is growing out here.", gemCost: 300,
            background: [Color(red: 0.02, green: 0.10, blue: 0.04),
                         Color(red: 0.06, green: 0.22, blue: 0.09)],
            tileFill: [Color.green.opacity(0.18), Color.mint.opacity(0.10)],
            accent: .mint, starTint: Color(red: 0.90, green: 1.0, blue: 0.88),
            nebula: [Color.green.opacity(0.22), Color.yellow.opacity(0.10)]),

        CosmeticTheme(
            id: "abyss", name: "The Abyss",
            detail: "Almost no light reaches here.", gemCost: 500,
            background: [Color(red: 0.01, green: 0.02, blue: 0.05),
                         Color(red: 0.02, green: 0.05, blue: 0.11)],
            tileFill: [Color.cyan.opacity(0.10), Color.blue.opacity(0.06)],
            accent: .cyan, starTint: Color(red: 0.75, green: 0.92, blue: 1.0),
            nebula: [Color.cyan.opacity(0.10), Color.blue.opacity(0.08)]),

        CosmeticTheme(
            id: "ember", name: "Emberfall",
            detail: "Ash on the wind, and something still burning.", gemCost: 550,
            background: [Color(red: 0.12, green: 0.05, blue: 0.02),
                         Color(red: 0.26, green: 0.11, blue: 0.03)],
            tileFill: [Color.orange.opacity(0.20), Color.red.opacity(0.10)],
            accent: .orange, starTint: Color(red: 1.0, green: 0.85, blue: 0.65),
            nebula: [Color.orange.opacity(0.26), Color.red.opacity(0.14)]),

        CosmeticTheme(
            id: "rose", name: "Rose Quartz",
            detail: "Soft light, hard vacuum.", gemCost: 350,
            background: [Color(red: 0.15, green: 0.04, blue: 0.13),
                         Color(red: 0.32, green: 0.10, blue: 0.27)],
            tileFill: [Color.pink.opacity(0.18), Color.purple.opacity(0.10)],
            accent: .pink, starTint: Color(red: 1.0, green: 0.92, blue: 0.96),
            nebula: [Color.pink.opacity(0.24), Color.purple.opacity(0.16)]),

        CosmeticTheme(
            id: "monochrome", name: "Silver Silence",
            detail: "Every colour drained out of it.", gemCost: 700,
            background: [Color(red: 0.06, green: 0.06, blue: 0.07),
                         Color(red: 0.16, green: 0.17, blue: 0.19)],
            tileFill: [Color.white.opacity(0.12), Color.gray.opacity(0.10)],
            accent: .white, starTint: .white,
            nebula: [Color.white.opacity(0.10), Color.gray.opacity(0.12)]),

        CosmeticTheme(
            id: "prism", name: "Prism Field",
            detail: "Light refuses to pick a direction.", gemCost: 900,
            background: [Color(red: 0.06, green: 0.02, blue: 0.16),
                         Color(red: 0.02, green: 0.12, blue: 0.22)],
            tileFill: [Color.purple.opacity(0.18), Color.cyan.opacity(0.12)],
            accent: .purple, starTint: .white,
            nebula: [Color.purple.opacity(0.22), Color.cyan.opacity(0.20),
                     Color.pink.opacity(0.16)]),

        CosmeticTheme(
            id: "solarflare", name: "Solar Flare",
            detail: "Too close to the star, frankly.", gemCost: 800,
            background: [Color(red: 0.20, green: 0.10, blue: 0.00),
                         Color(red: 0.38, green: 0.24, blue: 0.02)],
            tileFill: [Color.yellow.opacity(0.22), Color.red.opacity(0.10)],
            accent: .yellow, starTint: Color(red: 1.0, green: 0.95, blue: 0.75),
            nebula: [Color.yellow.opacity(0.30), Color.orange.opacity(0.22)]),

        CosmeticTheme(
            id: "singularity", name: "Singularity",
            detail: "The end state of every galaxy.", gemCost: 1500,
            background: [Color(red: 0.00, green: 0.00, blue: 0.00),
                         Color(red: 0.08, green: 0.02, blue: 0.14)],
            tileFill: [Color.purple.opacity(0.22), Color.black.opacity(0.30)],
            accent: Color(red: 0.75, green: 0.45, blue: 1.0), starTint: .white,
            nebula: [Color.purple.opacity(0.30), Color.indigo.opacity(0.24)]),
    ]

    static let defaultID = "deep_void"

    static func theme(for id: String) -> CosmeticTheme {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - StoreKit IAP Manager
@MainActor
class IAPManager: ObservableObject {
    static let shared = IAPManager()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs = Set<String>()
    /// Set when loading finds none of the products, which in practice means
    /// they haven't been created in App Store Connect yet.
    @Published var loadFailed = false

    let productIDs = Array(StoreCatalog.grants.keys)

    /// The game receives the goods. Weak so the singleton can't keep a dead
    /// view model alive.
    private weak var game: GameViewModel?

    private var updates: Task<Void, Never>? = nil

    /// Transactions already paid out. Persisted, because a grant must happen
    /// exactly once and StoreKit will happily replay a transaction.
    private static let processedKey = "nf.processedTransactions"
    private var processedTransactionIDs: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: IAPManager.processedKey) ?? [])

    init() {
        updates = observeTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        updates?.cancel()
    }

    func attach(_ game: GameViewModel) {
        self.game = game
        Task { await refreshEntitlements() }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: productIDs)
            products = loaded.sorted { $0.price < $1.price }
            loadFailed = loaded.isEmpty
        } catch {
            print("Failed to load products: \(error)")
            loadFailed = true
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return }
            applyGrant(for: transaction)
            await transaction.finish()
            await refreshEntitlements()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    /// Required by App Review for anything non-consumable.
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Pays out a transaction exactly once.
    ///
    /// Currency is only ever granted from *new* transactions — never from
    /// `currentEntitlements`, which replays every past purchase and would hand
    /// out the gems again on every launch.
    private func applyGrant(for transaction: StoreKit.Transaction) {
        let key = String(transaction.id)
        guard !processedTransactionIDs.contains(key),
              let grant = StoreCatalog.grant(for: transaction.productID) else { return }

        processedTransactionIDs.insert(key)
        UserDefaults.standard.set(Array(processedTransactionIDs), forKey: Self.processedKey)

        game?.applyStoreGrant(grant, productID: transaction.productID)
    }

    /// Recomputes owned products and the purchased production multiplier from
    /// what is currently valid. Rebuilt from scratch each time rather than
    /// accumulated, so a lapsed subscription actually stops applying.
    func refreshEntitlements() async {
        var owned = Set<String>()
        var oneTimeGrants: [StoreGrant] = []
        var bestSubscription: StoreGrant?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            if transaction.revocationDate != nil { continue }

            owned.insert(transaction.productID)
            guard let grant = StoreCatalog.grant(for: transaction.productID) else { continue }

            if grant.kind == .subscription {
                // Tiers replace rather than stack. Someone who upgrades from
                // Pass to Pass+ should get Pass+, not the product of both.
                if bestSubscription == nil || grant.tier > bestSubscription!.tier {
                    bestSubscription = grant
                }
            } else {
                oneTimeGrants.append(grant)
            }
        }

        // One-time bundles do stack with each other and with a subscription.
        var multiplier = 1.0
        var offlineHours = 0.0
        var themes = Set<String>()
        for grant in oneTimeGrants + [bestSubscription].compactMap({ $0 }) {
            multiplier *= grant.productionMultiplier
            offlineHours += grant.offlineHours
            themes.formUnion(grant.themeIDs)
        }

        purchasedProductIDs = owned
        game?.applyEntitlements(multiplier: multiplier,
                                offlineHours: offlineHours,
                                themeIDs: themes)
    }

    /// The highest subscription tier currently active, for the shop UI.
    var activeSubscriptionTier: Int {
        purchasedProductIDs
            .compactMap { StoreCatalog.grant(for: $0) }
            .filter { $0.kind == .subscription }
            .map(\.tier)
            .max() ?? 0
    }

    /// The single listener for the transaction stream. `AppDelegate` used to run
    /// a second one over the same sequence, so every transaction was finished
    /// twice.
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                self?.applyGrant(for: transaction)
                await transaction.finish()
                await self?.refreshEntitlements()
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

    /// Two items combine one of two ways: same chain tiers up, two *different*
    /// chains fuse into a hybrid at the same tier (see `FusionCatalog`).
    static func merge(item1: CelestialItem, item2: CelestialItem) -> CelestialItem? {
        guard item1.tier == item2.tier else { return nil }

        if item1.chainID == item2.chainID {
            guard let chain = ItemCatalog.chain(for: item1.chainID) else { return nil }

            let nextTier = item1.tier + 1
            // The chain tops out; merging past its final form isn't possible.
            guard nextTier < chain.tierNames.count else { return nil }

            return ItemCatalog.makeItem(chainID: chain.id, tier: nextTier)
        }

        guard let recipe = FusionCatalog.recipe(for: item1.chainID, item2.chainID),
              item1.tier >= recipe.minTier else { return nil }
        return ItemCatalog.makeItem(chainID: recipe.outputChainID, tier: item1.tier)
    }

    /// Why a given pair can't combine, for surfacing in the UI instead of a
    /// silent no-op.
    static func mergeBlockReason(item1: CelestialItem, item2: CelestialItem) -> String? {
        if merge(item1: item1, item2: item2) != nil { return nil }
        if item1.tier != item2.tier { return "Tiers must match" }
        if item1.chainID == item2.chainID { return "\(item1.name) is fully evolved" }
        guard let recipe = FusionCatalog.recipe(for: item1.chainID, item2.chainID) else {
            return "These elements can't fuse"
        }
        return "Fusion needs tier \(recipe.minTier) or higher"
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

    /// Each element earns its output a different way, so where you put a thing
    /// matters as much as what it is.
    var roleName: String {
        switch self {
        case .fire: return "Ignition"
        case .ice: return "Lattice"
        case .void: return "Devour"
        case .radiant: return "Beacon"
        }
    }

    var roleDetail: String {
        switch self {
        case .fire: return "+25% for every adjacent Fire. Clusters hard."
        case .ice: return "+8% for every adjacent item, any element. Likes crowds."
        case .void: return "+50% per neighbour, but drains each of them by 15%."
        case .radiant: return "Produces little alone. Gives every neighbour +20%."
        }
    }

    var tint: Color {
        switch self {
        case .fire: return .orange
        case .ice: return .cyan
        // Not `.indigo`: it's within a few shades of the cosmic background and
        // Void items were effectively invisible on the board.
        case .void: return Color(red: 0.68, green: 0.48, blue: 1.0)
        case .radiant: return .yellow
        }
    }
}

// MARK: - Goals
/// A milestone the player works toward. Progress is derived from game state
/// rather than tracked separately, so goals can never desync from reality.
struct Goal: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case merging = "Merging"
        case building = "Building"
        case prestige = "Prestige"
        case habit = "Habit"
        var id: String { rawValue }
    }

    let id: String
    let title: String
    let detail: String
    let target: Int
    let shardReward: Int
    let gemReward: Int
    let category: Category
    let progress: (GameViewModel) -> Int

    init(id: String, title: String, detail: String, target: Int,
         shardReward: Int, gemReward: Int, category: Category = .merging,
         progress: @escaping (GameViewModel) -> Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.target = target
        self.shardReward = shardReward
        self.gemReward = gemReward
        self.category = category
        self.progress = progress
    }

    func currentProgress(_ vm: GameViewModel) -> Int {
        min(progress(vm), target)
    }

    func isComplete(_ vm: GameViewModel) -> Bool {
        progress(vm) >= target
    }
}

enum GoalCatalog {
    /// Every goal pays some gems past the earliest few. That's deliberate: a
    /// player who has never held gems has no idea what they're for, and the
    /// shop may as well not exist. Earning a handful early is what makes the
    /// gem packs legible later.
    static let all: [Goal] = [
        // MARK: Merging
        Goal(id: "merge_1", title: "First Fusion", detail: "Merge two items together",
             target: 1, shardReward: 3, gemReward: 0, category: .merging) { $0.totalMerges },
        Goal(id: "merge_10", title: "Getting Warm", detail: "Complete 10 merges",
             target: 10, shardReward: 10, gemReward: 1, category: .merging) { $0.totalMerges },
        Goal(id: "merge_50", title: "Practised Hand", detail: "Complete 50 merges",
             target: 50, shardReward: 30, gemReward: 3, category: .merging) { $0.totalMerges },
        Goal(id: "merge_100", title: "Century", detail: "Complete 100 merges",
             target: 100, shardReward: 60, gemReward: 5, category: .merging) { $0.totalMerges },
        Goal(id: "merge_500", title: "Forge Master", detail: "Complete 500 merges",
             target: 500, shardReward: 200, gemReward: 15, category: .merging) { $0.totalMerges },
        Goal(id: "merge_2000", title: "The Long Work", detail: "Complete 2,000 merges",
             target: 2000, shardReward: 750, gemReward: 40, category: .merging) { $0.totalMerges },

        Goal(id: "tier_3", title: "Rising Power", detail: "Create a tier 3 item",
             target: 3, shardReward: 15, gemReward: 2, category: .merging) { $0.highestTierReached },
        Goal(id: "tier_5", title: "Stellar Architect", detail: "Create a tier 5 item",
             target: 5, shardReward: 40, gemReward: 5, category: .merging) { $0.highestTierReached },
        Goal(id: "tier_6", title: "Deep Fusion", detail: "Create a tier 6 item",
             target: 6, shardReward: 90, gemReward: 10, category: .merging) { $0.highestTierReached },
        Goal(id: "tier_7", title: "Ascendant", detail: "Reach the end of a chain",
             target: 7, shardReward: 250, gemReward: 25, category: .merging) { $0.highestTierReached },

        Goal(id: "fusion_1", title: "Crossed Streams",
             detail: "Fuse two different elements into a hybrid",
             target: 1, shardReward: 30, gemReward: 4, category: .merging) { $0.totalFusions },
        Goal(id: "fusion_10", title: "Alchemist", detail: "Complete 10 fusions",
             target: 10, shardReward: 90, gemReward: 10, category: .merging) { $0.totalFusions },
        Goal(id: "fusion_50", title: "Opposites Attract", detail: "Complete 50 fusions",
             target: 50, shardReward: 300, gemReward: 25, category: .merging) { $0.totalFusions },
        Goal(id: "hybrids_all", title: "Full Spectrum",
             detail: "Discover all four hybrid chains",
             target: 4, shardReward: 400, gemReward: 40, category: .merging) {
                 $0.discoveredHybridIDs.count },

        // MARK: Building
        Goal(id: "place_5", title: "Taking Shape", detail: "Have 5 items on the board at once",
             target: 5, shardReward: 5, gemReward: 0, category: .building) { $0.placedCount },
        Goal(id: "place_10", title: "Constellation", detail: "Have 10 items on the board at once",
             target: 10, shardReward: 20, gemReward: 2, category: .building) { $0.placedCount },
        Goal(id: "place_20", title: "Crowded Sky", detail: "Have 20 items on the board at once",
             target: 20, shardReward: 120, gemReward: 12, category: .building) { $0.placedCount },
        Goal(id: "tiles_15", title: "Room to Grow", detail: "Unlock 15 tiles",
             target: 15, shardReward: 50, gemReward: 5, category: .building) { $0.unlockedTileCount },
        Goal(id: "tiles_25", title: "The Whole Sky", detail: "Unlock every tile",
             target: 25, shardReward: 300, gemReward: 30, category: .building) { $0.unlockedTileCount },
        Goal(id: "forge_50", title: "Industrious", detail: "Forge 50 items",
             target: 50, shardReward: 40, gemReward: 4, category: .building) { $0.lifetimeForged },
        Goal(id: "forge_250", title: "Foundry", detail: "Forge 250 items",
             target: 250, shardReward: 180, gemReward: 15, category: .building) { $0.lifetimeForged },
        Goal(id: "rate_1k", title: "Steady Output", detail: "Reach 1,000 Stardust per second",
             target: 1000, shardReward: 60, gemReward: 6, category: .building) {
                 Int(min($0.idleEngine.totalProductionPerSec, 1_000_000)) },
        Goal(id: "rate_100k", title: "Industrial Scale",
             detail: "Reach 100,000 Stardust per second",
             target: 100_000, shardReward: 400, gemReward: 35, category: .building) {
                 Int(min($0.idleEngine.totalProductionPerSec, 10_000_000)) },

        // MARK: Prestige
        Goal(id: "prestige_1", title: "Reborn", detail: "Trigger your first Supernova",
             target: 1, shardReward: 25, gemReward: 5, category: .prestige) { $0.prestigeCount },
        Goal(id: "prestige_5", title: "Cycle of Stars", detail: "Trigger 5 Supernovas",
             target: 5, shardReward: 150, gemReward: 15, category: .prestige) { $0.prestigeCount },
        Goal(id: "prestige_25", title: "Eternal Return", detail: "Trigger 25 Supernovas",
             target: 25, shardReward: 600, gemReward: 50, category: .prestige) { $0.prestigeCount },
        Goal(id: "marks_25", title: "Marked", detail: "Earn 25 Galaxy Marks",
             target: 25, shardReward: 100, gemReward: 10, category: .prestige) { $0.galaxyMarks },
        Goal(id: "marks_200", title: "Cosmic Architect", detail: "Earn 200 Galaxy Marks",
             target: 200, shardReward: 500, gemReward: 45, category: .prestige) { $0.galaxyMarks },
        Goal(id: "upgrades_all", title: "Fully Equipped",
             detail: "Max out every permanent upgrade",
             target: UpgradeCatalog.all.reduce(0) { $0 + $1.maxLevel },
             shardReward: 800, gemReward: 75, category: .prestige) { vm in
                 UpgradeCatalog.all.reduce(0) { $0 + vm.upgradeLevel($1.id) } },

        // MARK: Habit
        Goal(id: "streak_3", title: "Regular Orbit", detail: "Collect the daily reward 3 days running",
             target: 3, shardReward: 25, gemReward: 5, category: .habit) { $0.dailyStreak },
        Goal(id: "streak_7", title: "Full Week", detail: "Reach a 7-day streak",
             target: 7, shardReward: 120, gemReward: 20, category: .habit) { $0.dailyStreak },
        Goal(id: "comet_1", title: "Quick Hands", detail: "Catch a comet",
             target: 1, shardReward: 15, gemReward: 2, category: .habit) { $0.cometsCaught },
        Goal(id: "comet_25", title: "Comet Hunter", detail: "Catch 25 comets",
             target: 25, shardReward: 100, gemReward: 12, category: .habit) { $0.cometsCaught },
        Goal(id: "comet_100", title: "Nothing Gets Past You", detail: "Catch 100 comets",
             target: 100, shardReward: 400, gemReward: 40, category: .habit) { $0.cometsCaught },
        Goal(id: "themes_3", title: "Redecorated", detail: "Own 3 themes",
             target: 3, shardReward: 60, gemReward: 5, category: .habit) { $0.ownedThemeIDs.count },
        Goal(id: "themes_6", title: "Interior Designer", detail: "Own 6 themes",
             target: 6, shardReward: 200, gemReward: 20, category: .habit) { $0.ownedThemeIDs.count },
    ]

    static func inCategory(_ category: Goal.Category) -> [Goal] {
        all.filter { $0.category == category }
    }
}

// MARK: - Daily quests
/// Three short tasks that reset every day and pay gems.
///
/// This is the main way a free player accumulates gems, and it is the whole
/// reason the shop means anything to them: someone who has never held gems has
/// no reason to look at what gems buy.
struct DailyQuest: Identifiable {
    let id: String
    let title: String
    let icon: String
    let target: Int
    let gemReward: Int
    /// Measured against counters that reset at midnight.
    let progress: (GameViewModel) -> Int

    func currentProgress(_ vm: GameViewModel) -> Int { min(progress(vm), target) }
    func isComplete(_ vm: GameViewModel) -> Bool { progress(vm) >= target }
}

enum DailyQuestCatalog {
    static let pool: [DailyQuest] = [
        DailyQuest(id: "q_merge_20", title: "Merge 20 items", icon: "circle.grid.cross.fill",
                   target: 20, gemReward: 4) { $0.todayMerges },
        DailyQuest(id: "q_merge_60", title: "Merge 60 items", icon: "circle.grid.cross.fill",
                   target: 60, gemReward: 8) { $0.todayMerges },
        DailyQuest(id: "q_fuse_2", title: "Complete 2 fusions", icon: "wand.and.stars",
                   target: 2, gemReward: 6) { $0.todayFusions },
        DailyQuest(id: "q_forge_10", title: "Forge 10 items", icon: "hammer.fill",
                   target: 10, gemReward: 4) { $0.todayForged },
        DailyQuest(id: "q_comet_3", title: "Catch 3 comets", icon: "sparkles",
                   target: 3, gemReward: 6) { $0.todayComets },
        DailyQuest(id: "q_prestige_1", title: "Trigger a Supernova", icon: "burst.fill",
                   target: 1, gemReward: 10) { $0.todayPrestiges },
        DailyQuest(id: "q_tile_1", title: "Unlock a tile", icon: "lock.open.fill",
                   target: 1, gemReward: 5) { $0.todayTilesUnlocked },
    ]

    /// Three quests, chosen by the calendar day so they're the same on every
    /// device and can't be rerolled by reinstalling.
    static func today(_ date: Date = Date()) -> [DailyQuest] {
        let day = Int(date.timeIntervalSince1970 / 86_400)
        guard pool.count >= 3 else { return pool }
        var picked: [DailyQuest] = []
        var index = abs(day) % pool.count
        while picked.count < 3 {
            let candidate = pool[index % pool.count]
            if !picked.contains(where: { $0.id == candidate.id }) {
                picked.append(candidate)
            }
            index += 1
        }
        return picked
    }
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
    /// Hybrids can't be forged or summoned — the only way in is fusing two
    /// different basic chains, which is what makes them worth chasing.
    let isHybrid: Bool
    /// Prefix of this chain's artwork, e.g. `tempest` -> `item_tempest_t4`.
    /// Basic chains use their element name so existing assets keep resolving.
    let assetKey: String

    init(id: String, element: Element, baseProduction: Double,
         tierNames: [String], isHybrid: Bool = false, assetKey: String? = nil) {
        self.id = id
        self.element = element
        self.baseProduction = baseProduction
        self.tierNames = tierNames
        self.isHybrid = isHybrid
        self.assetKey = assetKey ?? element.rawValue
    }

    /// Hybrids only have art from `FusionCatalog.minTier` up, since lower tiers
    /// are unreachable.
    func assetName(forTier tier: Int) -> String {
        let lowest = isHybrid ? FusionCatalog.minTier : 0
        let clamped = min(max(tier, lowest), tierNames.count - 1)
        return "item_\(assetKey)_t\(clamped)"
    }

    /// Production triples with each tier, matching the old merge maths.
    func production(atTier tier: Int) -> Double {
        baseProduction * pow(3.0, Double(tier))
    }
}

// MARK: - Fusion Recipes
/// Combining two *different* chains of the same tier yields a hybrid at that
/// same tier. A hybrid's much higher base production makes fusing worth more
/// than the ordinary tier-up you gave up to do it.
struct FusionRecipe {
    let inputs: Set<String>
    let outputChainID: String
    let minTier: Int
}

enum FusionCatalog {
    /// Fusion unlocks partway up a chain so it stays a mid-game goal rather
    /// than something the player trips over on turn one.
    static let minTier = 3

    static let all: [FusionRecipe] = [
        FusionRecipe(inputs: ["fire_basic", "ice_basic"],
                     outputChainID: "tempest_hybrid", minTier: minTier),
        FusionRecipe(inputs: ["fire_basic", "void_basic"],
                     outputChainID: "infernal_hybrid", minTier: minTier),
        FusionRecipe(inputs: ["ice_basic", "radiant_basic"],
                     outputChainID: "aurora_hybrid", minTier: minTier),
        FusionRecipe(inputs: ["void_basic", "radiant_basic"],
                     outputChainID: "eclipse_hybrid", minTier: minTier)
    ]

    static func recipe(for a: String, _ b: String) -> FusionRecipe? {
        guard a != b else { return nil }
        let pair: Set<String> = [a, b]
        return all.first { $0.inputs == pair }
    }

    /// Recipes involving `chainID`, for showing the player what a chain leads to.
    static func recipes(involving chainID: String) -> [FusionRecipe] {
        all.filter { $0.inputs.contains(chainID) }
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
            // Deliberately the weakest solo producer — Radiant pays out through
            // the neighbours it buffs, not through itself.
            baseProduction: 1.2,
            tierNames: ["Sunmote", "Gleam", "Prism", "Radiant Core",
                        "Starlight", "Quasar", "Pulsar", "Lumen Eternal"]
        ),

        // Hybrids. Only tiers at or above FusionCatalog.minTier are reachable,
        // but the lower names exist so tier indexing stays uniform.
        ItemChain(
            id: "tempest_hybrid",
            element: .ice,
            baseProduction: 4.0,
            tierNames: ["Squall", "Sleet", "Hailstorm", "Tempest",
                        "Cyclone", "Maelstrom", "Stormcrown", "Eye of Winter"],
            isHybrid: true, assetKey: "tempest"
        ),
        ItemChain(
            id: "infernal_hybrid",
            element: .fire,
            baseProduction: 4.5,
            tierNames: ["Scorch", "Blacksoot", "Pyre", "Infernal Rift",
                        "Hellforge", "Nova Heart", "Cinder Throne", "Ashen God"],
            isHybrid: true, assetKey: "infernal"
        ),
        ItemChain(
            id: "aurora_hybrid",
            element: .radiant,
            baseProduction: 5.0,
            tierNames: ["Shimmer", "Veil", "Corona Veil", "Aurora",
                        "Polar Crown", "Spectrum", "Lightfall", "Firmament"],
            isHybrid: true, assetKey: "aurora"
        ),
        ItemChain(
            id: "eclipse_hybrid",
            element: .void,
            baseProduction: 6.0,
            tierNames: ["Umbra", "Penumbra", "Shadowlight", "Eclipse",
                        "Black Sun", "Devourer", "Endless Night", "Final Dark"],
            isHybrid: true, assetKey: "eclipse"
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
            for tile in row where tile.placedItem != nil {
                base += production(for: tile, in: grid).total
            }
        }
        totalProductionPerSec = base * permanentMultiplier * upgradeMultiplier
    }

    /// Full breakdown of one tile's output, so the board can show the player
    /// exactly what a placement is worth before they commit to it.
    func production(for tile: GridTile, in grid: [[GridTile]]) -> TileProduction {
        guard let item = tile.placedItem else {
            return TileProduction(base: 0, selfBonus: 1, neighbourBonus: 1, notes: [])
        }

        let adjacent = neighbours(of: tile, in: grid)
        var notes: [String] = []

        // What this item's own element does with the company it keeps.
        var selfBonus = 1.0
        switch item.element {
        case .fire:
            let fires = adjacent.filter { $0.element == .fire }.count
            if fires > 0 {
                selfBonus += 0.25 * Double(fires)
                notes.append("+\(fires * 25)% Ignition")
            }
        case .ice:
            if !adjacent.isEmpty {
                selfBonus += 0.08 * Double(adjacent.count)
                notes.append("+\(adjacent.count * 8)% Lattice")
            }
        case .void:
            if !adjacent.isEmpty {
                selfBonus += 0.50 * Double(adjacent.count)
                notes.append("+\(adjacent.count * 50)% Devour")
            }
        case .radiant:
            break
        }

        // What the neighbours do to this item.
        let radiants = adjacent.filter { $0.element == .radiant }.count
        let voids = adjacent.filter { $0.element == .void }.count
        var neighbourBonus = 1.0
        if radiants > 0 {
            neighbourBonus += 0.20 * Double(radiants)
            notes.append("+\(radiants * 20)% Beacon")
        }
        if voids > 0 {
            neighbourBonus -= 0.15 * Double(voids)
            notes.append("-\(voids * 15)% drained")
        }
        // A tile swarmed by Void still contributes something.
        neighbourBonus = max(0.1, neighbourBonus)

        return TileProduction(base: item.baseProduction,
                              selfBonus: selfBonus,
                              neighbourBonus: neighbourBonus,
                              notes: notes)
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

/// One tile's output, split into its parts so the UI can explain the number
/// rather than just print it.
struct TileProduction {
    let base: Double
    let selfBonus: Double
    let neighbourBonus: Double
    let notes: [String]

    var total: Double { base * selfBonus * neighbourBonus }

    /// True when neighbours are changing this tile's output either way.
    var isModified: Bool { !notes.isEmpty }
}

// MARK: - Comet
/// A short-lived bonus that lands on an empty tile and fades if ignored. The
/// game has no fail state by design; this is the only thing that asks the
/// player to act *now* rather than eventually.
struct Comet: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let spawnedAt: Date
    let lifetime: TimeInterval
    let stardust: Double
    let shards: Int

    var expiresAt: Date { spawnedAt.addingTimeInterval(lifetime) }
    var isExpired: Bool { Date() >= expiresAt }

    /// 1 down to 0 over the comet's life, for the drain ring in the UI.
    var remainingFraction: Double {
        let left = expiresAt.timeIntervalSinceNow
        return min(1, max(0, left / lifetime))
    }
}

// MARK: - Daily Reward
struct DailyReward {
    let day: Int
    let shards: Int
    let gems: Int

    /// Streak caps so a long absence doesn't make the game unwinnable to
    /// re-enter, and so day 7 stays the ceiling worth coming back for.
    static let maxStreakDay = 7

    static func forStreak(_ streak: Int) -> DailyReward {
        let day = min(max(1, streak), maxStreakDay)
        return DailyReward(day: day, shards: 10 * day, gems: 2 + day)
    }
}

// MARK: - Main Game ViewModel
class GameViewModel: ObservableObject {
    @Published var stardust: Double = 0
    @Published var starlightShards: Int = 0
    @Published var nebulaGems: Int = 50
    @Published var galaxyMarks: Int = 0
    @Published var boardItems: [CelestialItem] = []
    @Published var gridTiles: [[GridTile]] = []
    @Published var celestialRank: Int = 1

    @Published var totalMerges: Int = 0
    @Published var totalFusions: Int = 0
    /// Resets each Supernova, because it drives the forge price.
    @Published var itemsForged: Int = 0
    /// Never resets — goals measure the whole career, not the current run.
    @Published var lifetimeForged: Int = 0
    @Published var cometsCaught: Int = 0
    @Published var prestigeCount: Int = 0
    /// Which hybrid chains have ever been created, for the collection goal.
    @Published var discoveredHybridIDs: Set<String> = []

    // Daily quest counters. Reset at midnight rather than being derived, since
    // "today" isn't recoverable from lifetime totals.
    @Published var todayMerges: Int = 0
    @Published var todayFusions: Int = 0
    @Published var todayForged: Int = 0
    @Published var todayComets: Int = 0
    @Published var todayPrestiges: Int = 0
    @Published var todayTilesUnlocked: Int = 0
    @Published var claimedQuestIDs: Set<String> = []
    private var questDay: Date?
    @Published var highestTierReached: Int = 0
    @Published var claimedGoalIDs: Set<String> = []
    @Published var upgradeLevels: [String: Int] = [:]
    /// Stardust earned while the app was closed, surfaced once on launch.
    @Published var pendingOfflineEarnings: Double = 0
    /// Transient banner text describing the most recent merge.
    @Published var lastMergeSummary: String?

    /// The comet currently streaking across the board, if any. Nothing is ever
    /// lost by missing one — it just stops being free value.
    @Published var comet: Comet?
    /// Consecutive days the player has opened the game and collected.
    @Published var dailyStreak: Int = 0
    /// Set on launch when today's reward hasn't been taken yet.
    @Published var pendingDailyReward: DailyReward?

    // Starts now rather than in the distant past, so the first comet arrives a
    // few minutes in instead of landing on top of the tutorial.
    /// Production multiplier from real-money entitlements. Recomputed from live
    /// entitlements on every launch rather than saved, so a lapsed subscription
    /// genuinely stops paying out.
    @Published var purchaseMultiplier: Double = 1.0
    /// Extra offline hours from an active entitlement.
    @Published var purchaseOfflineHours: Double = 0
    /// Themes available because of an active purchase, not bought with gems.
    @Published var entitlementThemeIDs: Set<String> = []
    /// End of a Stellar Surge, if one is running.
    @Published var surgeEndsAt: Date?

    /// Whether any paid purchase has ever completed, for the double-gems offer.
    @Published var hasMadeFirstPurchase: Bool = false
    @Published var ownedThemeIDs: Set<String> = [CosmeticCatalog.defaultID]
    @Published var selectedThemeID: String = CosmeticCatalog.defaultID

    var theme: CosmeticTheme { CosmeticCatalog.theme(for: selectedThemeID) }

    /// 2x while a surge is running, 1x otherwise.
    var surgeMultiplier: Double {
        guard let surgeEndsAt, surgeEndsAt > Date() else { return 1.0 }
        return 2.0
    }

    var surgeSecondsRemaining: Int {
        guard let surgeEndsAt else { return 0 }
        return max(0, Int(surgeEndsAt.timeIntervalSinceNow))
    }

    private var lastCloudPush: Date = .distantPast
    private var lastCometSpawn: Date = Date()
    private var lastDailyClaim: Date?
    /// Tracks the surge so its expiry can trigger exactly one resync.
    private var surgeWasActive = false
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
    /// Grows per forge *within a run* so the board can't be filled for free,
    /// but gently enough that production keeps up. At the old 1.18 the price
    /// doubled every four forges and outran output within one session.
    var forgeItemCost: Double {
        25 * pow(1.12, Double(itemsForged)) * forgeCostFactor
    }

    /// Minimum built-up power before a Supernova is allowed.
    ///
    /// This used to be a flat count of placed items, which meant ten tier-0
    /// scraps paid exactly as much as ten fully evolved ones — merging deep was
    /// strictly worse than spamming Forge. Power is the sum of what's actually
    /// on the board, so depth is what pays.
    static let prestigePowerRequirement: Double = 12

    /// Sum of the raw production of every placed item. Deliberately ignores
    /// adjacency bonuses: this measures what you built, not how you arranged it.
    var prestigePower: Double {
        gridTiles.flatMap { $0 }.compactMap { $0.placedItem?.baseProduction }.reduce(0, +)
    }

    /// Marks scale with the square root of power, so each Supernova is worth
    /// more than the last without the curve running away.
    var potentialMarks: Int {
        guard prestigePower > 0 else { return 0 }
        return max(0, Int((prestigePower / 5).squareRoot()))
    }

    var canPrestige: Bool {
        prestigePower >= Self.prestigePowerRequirement && potentialMarks > 0
    }

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
        static let totalFusions = "nf.totalFusions"
        static let lifetimeForged = "nf.lifetimeForged"
        static let cometsCaught = "nf.cometsCaught"
        static let prestigeCount = "nf.prestigeCount"
        static let discoveredHybrids = "nf.discoveredHybrids"
        static let questDay = "nf.questDay"
        static let claimedQuests = "nf.claimedQuests"
        static let todayCounters = "nf.todayCounters"
        static let itemsForged = "nf.itemsForged"
        static let highestTierReached = "nf.highestTierReached"
        static let claimedGoalIDs = "nf.claimedGoalIDs"
        static let upgradeLevels = "nf.upgradeLevels"
        static let unlockedTiles = "nf.unlockedTiles"
        static let lastSaveDate = "nf.lastSaveDate"
        static let dailyStreak = "nf.dailyStreak"
        static let lastDailyClaim = "nf.lastDailyClaim"
        static let surgeEndsAt = "nf.surgeEndsAt"
        static let firstPurchase = "nf.hasMadeFirstPurchase"
        static let ownedThemes = "nf.ownedThemes"
        static let selectedTheme = "nf.selectedTheme"
    }

    init() {
        setupIdleCollection()
        let hadLocalSave = loadGameState()
        if !hadLocalSave {
            initializeBoard()
        }

        // A fresh install takes whatever iCloud has; an existing one only takes
        // it if it's strictly newer.
        if let cloud = CloudSaveManager.shared.load() {
            restore(from: cloud, force: !hadLocalSave)
        }
        refreshDailyReward()
        rollQuestDayIfNeeded()

        // Another device saving while this one is open.
        CloudSaveManager.shared.onRemoteSave = { [weak self] snapshot in
            self?.restore(from: snapshot)
        }
    }

    /// How often a comet can appear, and how long it sticks around once it does.
    static let cometInterval: TimeInterval = 180
    static let cometLifetime: TimeInterval = 20

    func setupIdleCollection() {
        idleEngine.onTick = { [weak self] produced in
            guard let self = self else { return }
            self.stardust += produced
            self.tickComet()
            self.tickSurge()
        }
        idleEngine.start()
    }

    /// Drops production back when a Stellar Surge runs out. Guarded so the
    /// resync happens once rather than on every tick.
    private func tickSurge() {
        let active = surgeMultiplier > 1
        guard surgeWasActive, !active else {
            surgeWasActive = active
            return
        }
        surgeWasActive = false
        surgeEndsAt = nil
        syncUpgradeEffects()
    }

    /// Spawns and expires the comet off the existing idle tick, so there's no
    /// second timer to keep in sync.
    private func tickComet() {
        if let active = comet {
            let tileTaken = gridTiles.indices.contains(active.row)
                && gridTiles[active.row].indices.contains(active.col)
                && gridTiles[active.row][active.col].placedItem != nil
            if active.isExpired || tileTaken {
                comet = nil
            }
            return
        }

        guard Date().timeIntervalSince(lastCometSpawn) >= Self.cometInterval,
              let tile = freeUnlockedTiles.randomElement() else { return }

        lastCometSpawn = Date()
        // Worth about ninety seconds of current output, with a floor so it
        // still means something in the first few minutes of a run.
        let payout = max(25, idleEngine.totalProductionPerSec * 90)
        comet = Comet(row: tile.row, col: tile.col, spawnedAt: Date(),
                      lifetime: Self.cometLifetime, stardust: payout, shards: 3)
        Feedback.place()
    }

    @discardableResult
    func collectComet() -> Bool {
        guard let active = comet, !active.isExpired else { return false }
        stardust += active.stardust
        starlightShards += active.shards
        cometsCaught += 1
        todayComets += 1
        comet = nil
        announceMerge("Comet caught   +\(abbreviatedNumber(active.stardust))")
        Feedback.comet()
        saveGameState()
        return true
    }

    func isCometTile(_ tile: GridTile) -> Bool {
        guard let comet else { return false }
        return comet.row == tile.row && comet.col == tile.col
    }

    // MARK: Daily reward

    /// Decides whether today's reward is waiting and what it's worth. The
    /// streak is the only thing in the game that rewards *when* you play.
    private func refreshDailyReward() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let last = lastDailyClaim else {
            pendingDailyReward = DailyReward.forStreak(1)
            return
        }

        let lastDay = calendar.startOfDay(for: last)
        guard lastDay < today else {
            // Already collected today.
            pendingDailyReward = nil
            return
        }

        // Missing a day resets the run — the streak is meant to reward actually
        // coming back, not merely coming back eventually.
        let gap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        pendingDailyReward = DailyReward.forStreak(gap == 1 ? dailyStreak + 1 : 1)
    }

    @discardableResult
    func claimDailyReward() -> Bool {
        guard let reward = pendingDailyReward else { return false }
        starlightShards += reward.shards
        nebulaGems += reward.gems
        dailyStreak = reward.day
        lastDailyClaim = Date()
        pendingDailyReward = nil
        GameCenterManager.shared.report(self)
        Feedback.goal()
        saveGameState()
        return true
    }

    /// Lays out a fresh 5x5 hex grid and seeds it. The unlocked region is a
    /// parameter because a post-Supernova galaxy starts wider than a first run.
    func initializeBoard(unlockedRows: Int = 3, unlockedCols: Int = 3) {
        // Grid first: starting items are placed straight onto it, so it has to
        // exist before they're spawned.
        gridTiles = (0..<5).map { row in
            (0..<5).map { col in
                GridTile(row: row, col: col,
                         isUnlocked: row < unlockedRows && col < unlockedCols,
                         placedItem: nil)
            }
        }
        boardItems = []
        comet = nil

        // Start with matched pairs so the first merge is immediately possible,
        // and leave free tiles so the player can still forge.
        var starters = ["fire_basic", "fire_basic", "ice_basic",
                        "ice_basic", "void_basic", "void_basic"]
            .compactMap { ItemCatalog.makeItem(chainID: $0) }
        for _ in 0..<bonusStartingItems {
            starters.append(randomStarterItem())
        }
        for item in starters {
            spawnOnBoard(item)
        }

        idleEngine.recalculate(from: gridTiles)
    }

    /// Combines the item at `from` into the tile at `to`. The result lands on
    /// `to`, so the player chooses where the power ends up — which is the whole
    /// point of merging on the board instead of in a list.
    @discardableResult
    func mergeOnGrid(from: (row: Int, col: Int), to: (row: Int, col: Int)) -> Bool {
        guard gridTiles.indices.contains(from.row),
              gridTiles[from.row].indices.contains(from.col),
              gridTiles.indices.contains(to.row),
              gridTiles[to.row].indices.contains(to.col),
              let source = gridTiles[from.row][from.col].placedItem,
              let target = gridTiles[to.row][to.col].placedItem,
              let merged = CelestialItem.merge(item1: source, item2: target) else {
            Feedback.denied()
            return false
        }

        var placed = merged
        placed.position = (to.row, to.col)
        gridTiles[to.row][to.col].placedItem = placed
        gridTiles[from.row][from.col].placedItem = nil

        awardMerge(merged, isFusion: source.chainID != target.chainID)
        idleEngine.recalculate(from: gridTiles)
        GameCenterManager.shared.submitScore(clampedScore(stardust))
        saveGameState()
        return true
    }

    /// Merges two items in the overflow tray, which only fills up when the grid
    /// has no room left.
    @discardableResult
    func attemptMerge(_ item1: CelestialItem, _ item2: CelestialItem) -> Bool {
        guard let merged = CelestialItem.merge(item1: item1, item2: item2) else {
            Feedback.denied()
            return false
        }

        boardItems.removeAll { $0.id == item1.id || $0.id == item2.id }
        boardItems.append(merged)

        awardMerge(merged, isFusion: item1.chainID != item2.chainID)
        saveGameState()
        return true
    }

    /// Shared payout for any combine. Merging is the main source of Starlight
    /// Shards; higher tiers pay more and fusions pay a premium on top, since
    /// they cost you a tier-up to set up.
    private func awardMerge(_ merged: CelestialItem, isFusion: Bool) {
        let fusionBonus = isFusion ? 3 : 1
        let shardsGained = max(1, merged.tier * 2) * shardYieldMultiplier * fusionBonus
        starlightShards += shardsGained
        totalMerges += 1
        todayMerges += 1
        if isFusion {
            totalFusions += 1
            todayFusions += 1
        }
        if ItemCatalog.chain(for: merged.chainID)?.isHybrid == true {
            discoveredHybridIDs.insert(merged.chainID)
        }
        highestTierReached = max(highestTierReached, merged.tier)

        announceMerge("\(isFusion ? "FUSION · " : "")\(merged.name)   +\(shardsGained)")
        celestialRank = 1 + totalMerges / 10

        Feedback.merge(isFusion: isFusion)
        GameCenterManager.shared.report(self)
    }

    /// Unlocks the nearest locked tile. False when the grid is fully open.
    @discardableResult
    private func unlockFirstLockedTile() -> Bool {
        for row in gridTiles.indices {
            for col in gridTiles[row].indices where !gridTiles[row][col].isUnlocked {
                gridTiles[row][col].isUnlocked = true
                todayTilesUnlocked += 1
                return true
            }
        }
        return false
    }

    /// Spends Starlight Shards to unlock the next locked tile, nearest first.
    @discardableResult
    func unlockNextTile() -> Bool {
        guard starlightShards >= tileUnlockCost, unlockFirstLockedTile() else { return false }
        starlightShards -= tileUnlockCost
        Feedback.place()
        saveGameState()
        return true
    }

    /// A fresh tier-0 item. Common chains are weighted higher so early boards
    /// tend to contain matching pairs the player can actually merge.
    private func randomStarterItem() -> CelestialItem {
        let weighted = ["fire_basic", "fire_basic", "ice_basic", "ice_basic",
                        "void_basic", "radiant_basic"]
        let chainID = weighted.randomElement()!
        return ItemCatalog.makeItem(chainID: chainID) ?? ItemCatalog.makeItem(chainID: "fire_basic")!
    }

    /// Drops a new item straight onto the board. There is no separate staging
    /// area any more — items land where they'll produce. The tray is only a
    /// fallback for when every unlocked tile is taken.
    @discardableResult
    private func spawnOnBoard(_ item: CelestialItem) -> Bool {
        // Don't bury a live comet under a newly forged item.
        let candidates = freeUnlockedTiles
        guard let target = candidates.first(where: { !isCometTile($0) }) ?? candidates.first else {
            boardItems.append(item)
            return false
        }
        var placed = item
        placed.position = (target.row, target.col)
        gridTiles[target.row][target.col].placedItem = placed
        idleEngine.recalculate(from: gridTiles)
        return true
    }

    /// Spends Stardust to forge a new item — the main progression loop.
    @discardableResult
    func forgeItem() -> Bool {
        guard stardust >= forgeItemCost else { return false }
        stardust -= forgeItemCost
        itemsForged += 1
        lifetimeForged += 1
        todayForged += 1
        spawnOnBoard(randomStarterItem())
        Feedback.forge()
        saveGameState()
        return true
    }

    /// Spends Nebula Gems to add a random tier-0 item to the board.
    @discardableResult
    func summonItem() -> Bool {
        guard nebulaGems >= itemSummonCost else { return false }
        nebulaGems -= itemSummonCost
        spawnOnBoard(randomStarterItem())
        Feedback.place()
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
        baseOfflineHours + 2 * Double(upgradeLevel("offline")) + purchaseOfflineHours
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
        Feedback.purchase()
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

    /// Pushes every non-prestige multiplier into the idle engine and recomputes
    /// output. Must run after any change to `upgradeLevels`, purchases, or the
    /// surge — including on load.
    func syncUpgradeEffects() {
        idleEngine.upgradeMultiplier =
            upgradeProductionMultiplier * purchaseMultiplier * surgeMultiplier
        idleEngine.recalculate(from: gridTiles)
    }

    // MARK: Purchases

    /// Hands over what a real-money product bought. Called once per transaction
    /// by `IAPManager`, which owns the exactly-once bookkeeping.
    func applyStoreGrant(_ grant: StoreGrant, productID: String) {
        // First real purchase pays double gems. Advertised up front rather than
        // sprung afterwards — it's the offer, not a surprise.
        let doubled = !hasMadeFirstPurchase && grant.gems > 0
        let gems = doubled ? grant.gems * 2 : grant.gems

        nebulaGems += gems
        starlightShards += grant.shards
        if grant.gems > 0 || grant.shards > 0 {
            hasMadeFirstPurchase = true
            announceMerge("\(doubled ? "DOUBLED · " : "")+\(gems) Gems")
        }
        Feedback.purchase()
        saveGameState()
        // Anything they paid for goes up immediately. Consumable gems are the
        // one thing StoreKit can't restore, so losing them is losing money.
        flushToCloud()
    }

    /// True until the player's first paid purchase lands.
    var firstPurchaseBonusAvailable: Bool { !hasMadeFirstPurchase }

    /// Applies whatever the best currently-valid entitlement gives. Rebuilt
    /// wholesale on every refresh rather than accumulated, so losing a
    /// subscription actually takes its perks back.
    func applyEntitlements(multiplier: Double, offlineHours: Double, themeIDs: Set<String>) {
        let changed = multiplier != purchaseMultiplier
            || offlineHours != purchaseOfflineHours
            || themeIDs != entitlementThemeIDs

        purchaseMultiplier = multiplier
        purchaseOfflineHours = offlineHours
        entitlementThemeIDs = themeIDs

        // Don't strand the player looking at a theme they no longer have.
        if !owns(CosmeticCatalog.theme(for: selectedThemeID)) {
            selectedThemeID = CosmeticCatalog.defaultID
        }
        if changed { syncUpgradeEffects() }
    }

    // MARK: Gem shop

    /// The deal currently running, or nil once it lapses.
    var currentOffer: TimedOffer? {
        guard let offer = OfferCatalog.current(), !offer.isExpired else { return nil }
        return offer
    }

    /// Buys the running deal at its sale price.
    @discardableResult
    func buyOffer(_ timed: TimedOffer) -> Bool {
        guard let offer = GemShopCatalog.all.first(where: { $0.id == timed.id }),
              !timed.isExpired else { return false }
        return buy(offer, price: timed.salePrice)
    }

    @discardableResult
    func buy(_ offer: GemOffer, price: Int? = nil) -> Bool {
        let cost = price ?? offer.gemCost
        guard nebulaGems >= cost else { return false }

        // Anything that can't be delivered mustn't take the gems.
        switch offer.id {
        case "forge_bundle":
            guard !freeUnlockedTiles.isEmpty else { return false }
            for _ in 0..<5 { spawnOnBoard(randomStarterItem()) }
        case "unlock_tile":
            guard unlockFirstLockedTile() else { return false }
        case "call_comet":
            guard comet == nil, let tile = freeUnlockedTiles.randomElement() else { return false }
            let payout = max(25, idleEngine.totalProductionPerSec * 90)
            comet = Comet(row: tile.row, col: tile.col, spawnedAt: Date(),
                          lifetime: Self.cometLifetime, stardust: payout, shards: 3)
        case "surge":
            // Extends rather than replaces, so buying two isn't a waste.
            extendSurge(minutes: 30)
        case "surge_long":
            extendSurge(minutes: 240)
        case "shard_cache":
            starlightShards += 250
        case "forge_reset":
            guard itemsForged > 0 else { return false }
            itemsForged = 0
        case "tier_jump":
            // Upgrade the single strongest placed item one tier.
            guard let best = placedEntries
                    .filter({ !$0.item.isMaxTier })
                    .max(by: { $0.item.baseProduction < $1.item.baseProduction }),
                  let upgraded = ItemCatalog.makeItem(chainID: best.item.chainID,
                                                      tier: best.item.tier + 1)
            else { return false }
            var placed = upgraded
            placed.position = (best.tile.row, best.tile.col)
            gridTiles[best.tile.row][best.tile.col].placedItem = placed
            highestTierReached = max(highestTierReached, upgraded.tier)
            announceMerge("\(upgraded.name)")
        case "open_board":
            var opened = false
            while unlockFirstLockedTile() { opened = true }
            guard opened else { return false }
        default:
            return false
        }

        nebulaGems -= cost
        syncUpgradeEffects()
        Feedback.purchase()
        saveGameState()
        return true
    }

    /// Surges extend rather than replace, so buying a second one isn't wasted.
    private func extendSurge(minutes: Double) {
        let base = max(Date(), surgeEndsAt ?? Date())
        surgeEndsAt = base.addingTimeInterval(minutes * 60)
        surgeWasActive = true
    }

    // MARK: Cosmetics

    func owns(_ theme: CosmeticTheme) -> Bool {
        theme.gemCost == 0
            || ownedThemeIDs.contains(theme.id)
            || entitlementThemeIDs.contains(theme.id)
    }

    /// True when the theme is available because of an active purchase rather
    /// than having been bought with gems — it goes away if a subscription does.
    func isEntitlementTheme(_ theme: CosmeticTheme) -> Bool {
        !ownedThemeIDs.contains(theme.id) && entitlementThemeIDs.contains(theme.id)
    }

    @discardableResult
    func purchaseTheme(_ theme: CosmeticTheme) -> Bool {
        guard !owns(theme), nebulaGems >= theme.gemCost else { return false }
        nebulaGems -= theme.gemCost
        ownedThemeIDs.insert(theme.id)
        selectedThemeID = theme.id
        Feedback.purchase()
        saveGameState()
        return true
    }

    @discardableResult
    func selectTheme(_ theme: CosmeticTheme) -> Bool {
        guard owns(theme) else { return false }
        selectedThemeID = theme.id
        Feedback.place()
        saveGameState()
        return true
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
        Feedback.goal()
        saveGameState()
        return true
    }

    /// Every item sitting on the grid, with the tile it occupies.
    var placedEntries: [(tile: GridTile, item: CelestialItem)] {
        gridTiles.flatMap { $0 }.compactMap { tile in
            tile.placedItem.map { (tile, $0) }
        }
    }

    var placedCount: Int { placedEntries.count }

    var unlockedTileCount: Int {
        gridTiles.flatMap { $0 }.filter(\.isUnlocked).count
    }

    /// Today's three quests, with the ones already collected still listed so the
    /// player can see they finished them.
    var todayQuests: [DailyQuest] { DailyQuestCatalog.today() }

    var claimableQuests: [DailyQuest] {
        todayQuests.filter { $0.isComplete(self) && !claimedQuestIDs.contains($0.id) }
    }

    @discardableResult
    func claimQuest(_ quest: DailyQuest) -> Bool {
        guard quest.isComplete(self), !claimedQuestIDs.contains(quest.id) else { return false }
        claimedQuestIDs.insert(quest.id)
        nebulaGems += quest.gemReward
        announceMerge("Quest complete   +\(quest.gemReward) Gems")
        Feedback.goal()
        saveGameState()
        return true
    }

    /// Re-evaluates everything that turns over at midnight. Called on launch
    /// and whenever the app comes back to the foreground, since a session can
    /// easily straddle a day boundary.
    func refreshDailyState() {
        refreshDailyReward()
        rollQuestDayIfNeeded()
    }

    /// Zeroes the daily counters when the calendar day turns over.
    private func rollQuestDayIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard questDay != today else { return }
        questDay = today
        todayMerges = 0
        todayFusions = 0
        todayForged = 0
        todayComets = 0
        todayPrestiges = 0
        todayTilesUnlocked = 0
        claimedQuestIDs = []
    }

    var freeUnlockedTiles: [GridTile] {
        gridTiles.flatMap { $0 }.filter { $0.isUnlocked && $0.placedItem == nil }
    }

    /// Items on the grid that could combine with `item` — a tier-up or a fusion.
    func mergePartners(for item: CelestialItem) -> Set<UUID> {
        Set(
            placedEntries
                .filter { $0.item.id != item.id }
                .filter { CelestialItem.merge(item1: item, item2: $0.item) != nil }
                .map { $0.item.id }
        )
    }

    /// Whether any pair on the board can currently be combined.
    var hasAvailableMerge: Bool {
        placedEntries.contains { !mergePartners(for: $0.item).isEmpty }
    }

    /// Whether any pair on the board can specifically *fuse* into a hybrid.
    var hasAvailableFusion: Bool {
        placedEntries.contains { entry in
            placedEntries.contains { other in
                other.item.id != entry.item.id
                    && other.item.chainID != entry.item.chainID
                    && CelestialItem.merge(item1: entry.item, item2: other.item) != nil
            }
        }
    }

    /// The single most useful next action, surfaced as a hint in the UI.
    var nextStepHint: String {
        if placedCount == 0 && boardItems.isEmpty {
            return "Forge your first item to begin."
        }
        if !boardItems.isEmpty {
            return "Tap a held item to drop it on a free tile."
        }
        if hasAvailableFusion {
            return "Two different elements at the same tier can fuse into a hybrid."
        }
        if hasAvailableMerge {
            return "Tap one item, then a matching one, to combine them."
        }
        if canPrestige {
            return "You can trigger a Supernova on the Nova tab."
        }
        if freeUnlockedTiles.isEmpty {
            return "Board is full — merge to make room, or unlock a tile."
        }
        return "Forge more items to fill your galaxy."
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
        guard canPrestige else { return false }

        let earnedMarks = potentialMarks
        galaxyMarks += earnedMarks
        prestigeCount += 1
        todayPrestiges += 1

        // Forge price is per-run. Leaving this as a lifetime counter meant a
        // Supernova reset the board but kept the exponential price, so each
        // prestige started strictly poorer than the last.
        itemsForged = 0
        // Prestiging is the only source of Nebula Gems.
        nebulaGems += earnedMarks * 2
        hasPrestiged = true

        // Apply permanent boost
        let multiplier = 1.0 + (Double(earnedMarks) * 0.1)
        idleEngine.applyPermanentMultiplier(multiplier)

        // Start a new cycle on the wider post-prestige grid. The unlock pattern
        // is passed in rather than applied afterwards — rebuilding gridTiles
        // after seeding would wipe the items just placed.
        initializeBoard(unlockedRows: 3, unlockedCols: 4)

        GameCenterManager.shared.submitScore(Int64(galaxyMarks), leaderboardID: "nebulaforge.prestige")
        GameCenterManager.shared.report(self)

        Feedback.supernova()

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
        defaults.set(totalFusions, forKey: DefaultsKey.totalFusions)
        defaults.set(lifetimeForged, forKey: DefaultsKey.lifetimeForged)
        defaults.set(cometsCaught, forKey: DefaultsKey.cometsCaught)
        defaults.set(prestigeCount, forKey: DefaultsKey.prestigeCount)
        defaults.set(Array(discoveredHybridIDs), forKey: DefaultsKey.discoveredHybrids)
        defaults.set(Array(claimedQuestIDs), forKey: DefaultsKey.claimedQuests)
        if let questDay {
            defaults.set(questDay, forKey: DefaultsKey.questDay)
        }
        // One dictionary rather than six keys — they're written and cleared
        // together, so they may as well travel together.
        defaults.set([
            "merges": todayMerges, "fusions": todayFusions, "forged": todayForged,
            "comets": todayComets, "prestiges": todayPrestiges,
            "tiles": todayTilesUnlocked,
        ], forKey: DefaultsKey.todayCounters)
        defaults.set(itemsForged, forKey: DefaultsKey.itemsForged)
        defaults.set(highestTierReached, forKey: DefaultsKey.highestTierReached)
        defaults.set(Array(claimedGoalIDs), forKey: DefaultsKey.claimedGoalIDs)
        defaults.set(upgradeLevels, forKey: DefaultsKey.upgradeLevels)
        defaults.set(Date(), forKey: DefaultsKey.lastSaveDate)
        defaults.set(dailyStreak, forKey: DefaultsKey.dailyStreak)
        if let lastDailyClaim {
            defaults.set(lastDailyClaim, forKey: DefaultsKey.lastDailyClaim)
        }
        defaults.set(hasMadeFirstPurchase, forKey: DefaultsKey.firstPurchase)
        defaults.set(Array(ownedThemeIDs), forKey: DefaultsKey.ownedThemes)
        defaults.set(selectedThemeID, forKey: DefaultsKey.selectedTheme)
        // A surge is wall-clock time the player paid for, so it keeps running
        // while the app is closed rather than pausing.
        if let surgeEndsAt {
            defaults.set(surgeEndsAt, forKey: DefaultsKey.surgeEndsAt)
        } else {
            defaults.removeObject(forKey: DefaultsKey.surgeEndsAt)
        }

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
        pushToCloudIfDue()
    }

    /// Mirrors the save to iCloud, at most once a minute.
    ///
    /// `saveGameState` runs after every merge, so pushing on each one would
    /// hammer a store meant for occasional writes.
    private func pushToCloudIfDue(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastCloudPush) > 60 else { return }
        lastCloudPush = Date()
        CloudSaveManager.shared.save(snapshot())
    }

    /// Pushes immediately, for moments worth not losing — backgrounding, and
    /// anything the player paid for.
    func flushToCloud() {
        pushToCloudIfDue(force: true)
    }

    /// Adopts a cloud save if it's newer than what's on this device.
    @discardableResult
    func adoptCloudSaveIfNewer() -> Bool {
        guard let snapshot = CloudSaveManager.shared.load() else { return false }
        return restore(from: snapshot)
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

    // MARK: Cloud save

    /// Everything worth carrying to another device.
    func snapshot() -> SaveSnapshot {
        var items: [SaveSnapshot.Item] = boardItems.map {
            SaveSnapshot.Item(chainID: $0.chainID, tier: $0.tier, row: nil, col: nil)
        }
        for entry in placedEntries {
            items.append(SaveSnapshot.Item(chainID: entry.item.chainID,
                                           tier: entry.item.tier,
                                           row: entry.tile.row,
                                           col: entry.tile.col))
        }

        return SaveSnapshot(
            savedAt: Date(),
            stardust: stardust,
            starlightShards: starlightShards,
            nebulaGems: nebulaGems,
            galaxyMarks: galaxyMarks,
            celestialRank: celestialRank,
            permanentMultiplier: idleEngine.permanentMultiplier,
            hasPrestiged: hasPrestiged,
            totalMerges: totalMerges,
            totalFusions: totalFusions,
            itemsForged: itemsForged,
            highestTierReached: highestTierReached,
            claimedGoalIDs: Array(claimedGoalIDs),
            upgradeLevels: upgradeLevels,
            unlockedTiles: gridTiles.flatMap { $0 }.filter(\.isUnlocked).map { "\($0.row),\($0.col)" },
            dailyStreak: dailyStreak,
            lastDailyClaim: lastDailyClaim,
            hasMadeFirstPurchase: hasMadeFirstPurchase,
            ownedThemeIDs: Array(ownedThemeIDs),
            selectedThemeID: selectedThemeID,
            items: items)
    }

    /// Replaces local state with a snapshot from another device.
    ///
    /// Newest wins, and only strictly newer: a device being actively played
    /// saves constantly, so it always holds the latest timestamp and can't be
    /// overwritten by a stale one sitting in iCloud.
    @discardableResult
    func restore(from snapshot: SaveSnapshot, force: Bool = false) -> Bool {
        let localTime = UserDefaults.standard.object(forKey: DefaultsKey.lastSaveDate) as? Date
        if !force, let localTime, snapshot.savedAt <= localTime { return false }

        stardust = snapshot.stardust
        starlightShards = snapshot.starlightShards
        nebulaGems = snapshot.nebulaGems
        galaxyMarks = snapshot.galaxyMarks
        celestialRank = max(1, snapshot.celestialRank)
        idleEngine.permanentMultiplier = snapshot.permanentMultiplier
        hasPrestiged = snapshot.hasPrestiged
        totalMerges = snapshot.totalMerges
        totalFusions = snapshot.totalFusions
        itemsForged = snapshot.itemsForged
        highestTierReached = snapshot.highestTierReached
        claimedGoalIDs = Set(snapshot.claimedGoalIDs)
        upgradeLevels = snapshot.upgradeLevels
        dailyStreak = snapshot.dailyStreak
        lastDailyClaim = snapshot.lastDailyClaim
        hasMadeFirstPurchase = snapshot.hasMadeFirstPurchase
        ownedThemeIDs = Set(snapshot.ownedThemeIDs).union([CosmeticCatalog.defaultID])
        selectedThemeID = ownedThemeIDs.contains(snapshot.selectedThemeID)
            ? snapshot.selectedThemeID : CosmeticCatalog.defaultID

        let unlocked = Set(snapshot.unlockedTiles)
        gridTiles = (0..<5).map { row in
            (0..<5).map { col in
                GridTile(row: row, col: col,
                         isUnlocked: unlocked.contains("\(row),\(col)"),
                         placedItem: nil)
            }
        }

        boardItems = []
        comet = nil
        for stored in snapshot.items {
            guard var item = ItemCatalog.makeItem(chainID: stored.chainID, tier: stored.tier)
            else { continue }
            if let row = stored.row, let col = stored.col,
               gridTiles.indices.contains(row), gridTiles[row].indices.contains(col),
               gridTiles[row][col].placedItem == nil {
                item.position = (row, col)
                gridTiles[row][col].placedItem = item
            } else {
                spawnOnBoard(item)
            }
        }

        syncUpgradeEffects()
        refreshDailyReward()
        // Suppressed so writing the restored state doesn't push it straight
        // back to iCloud and race the device it came from.
        CloudSaveManager.shared.withRestoreSuppressed { saveGameState() }
        return true
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
        totalFusions = defaults.integer(forKey: DefaultsKey.totalFusions)
        cometsCaught = defaults.integer(forKey: DefaultsKey.cometsCaught)
        prestigeCount = defaults.integer(forKey: DefaultsKey.prestigeCount)
        discoveredHybridIDs = Set(defaults.stringArray(forKey: DefaultsKey.discoveredHybrids) ?? [])
        claimedQuestIDs = Set(defaults.stringArray(forKey: DefaultsKey.claimedQuests) ?? [])
        questDay = defaults.object(forKey: DefaultsKey.questDay) as? Date
        // Saves written before lifetime forging was tracked separately fall back
        // to the per-run count, which is the closest honest answer.
        let storedLifetime = defaults.integer(forKey: DefaultsKey.lifetimeForged)
        lifetimeForged = max(storedLifetime, defaults.integer(forKey: DefaultsKey.itemsForged))

        if let counters = defaults.dictionary(forKey: DefaultsKey.todayCounters) as? [String: Int] {
            todayMerges = counters["merges"] ?? 0
            todayFusions = counters["fusions"] ?? 0
            todayForged = counters["forged"] ?? 0
            todayComets = counters["comets"] ?? 0
            todayPrestiges = counters["prestiges"] ?? 0
            todayTilesUnlocked = counters["tiles"] ?? 0
        }
        itemsForged = defaults.integer(forKey: DefaultsKey.itemsForged)
        highestTierReached = defaults.integer(forKey: DefaultsKey.highestTierReached)
        claimedGoalIDs = Set(defaults.stringArray(forKey: DefaultsKey.claimedGoalIDs) ?? [])
        upgradeLevels = defaults.dictionary(forKey: DefaultsKey.upgradeLevels) as? [String: Int] ?? [:]
        idleEngine.permanentMultiplier = defaults.object(forKey: DefaultsKey.permanentMultiplier) as? Double ?? 1.0
        dailyStreak = defaults.integer(forKey: DefaultsKey.dailyStreak)
        lastDailyClaim = defaults.object(forKey: DefaultsKey.lastDailyClaim) as? Date

        hasMadeFirstPurchase = defaults.bool(forKey: DefaultsKey.firstPurchase)
        let saved = Set(defaults.stringArray(forKey: DefaultsKey.ownedThemes) ?? [])
        ownedThemeIDs = saved.union([CosmeticCatalog.defaultID])
        let savedTheme = defaults.string(forKey: DefaultsKey.selectedTheme) ?? CosmeticCatalog.defaultID
        // Don't leave the board wearing a theme the player doesn't own.
        selectedThemeID = ownedThemeIDs.contains(savedTheme) ? savedTheme : CosmeticCatalog.defaultID

        if let end = defaults.object(forKey: DefaultsKey.surgeEndsAt) as? Date, end > Date() {
            surgeEndsAt = end
            surgeWasActive = true
        }

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

            // Saves written before the board was unified kept most items in a
            // separate staging tray, where they produced nothing. Move them onto
            // free tiles; whatever doesn't fit stays in the tray.
            boardItems = []
            for item in loadedBoardItems {
                spawnOnBoard(item)
            }
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
    @State private var showDailyReward = false
    @Environment(\.scenePhase) private var scenePhase

    // Merging and producing now happen on the same board, so the old separate
    // Merge tab is gone — placement decisions and their payoff are visible
    // together instead of on two screens that never showed each other.
    var body: some View {
        TabView(selection: $selectedTab) {
            GalacticCanvasView()
                .tabItem {
                    Label("Galaxy", systemImage: "sparkles")
                }
                .tag(0)

            PrestigeView()
                .tabItem {
                    Label("Nova", systemImage: "burst.fill")
                }
                .tag(1)

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }
                .badge(gameVM.claimableGoals.count + gameVM.claimableQuests.count)
                .tag(2)

            ShopView()
                .tabItem {
                    Label("Shop", systemImage: "cart.fill")
                }
                .tag(3)
        }
        .tint(.purple)
        .sheet(isPresented: $showTutorial, onDismiss: {
            gameVM.hasSeenTutorial = true
            showNextPrompt()
        }) {
            TutorialView()
        }
        .sheet(isPresented: $showOfflineEarnings, onDismiss: {
            gameVM.pendingOfflineEarnings = 0
            showNextPrompt()
        }) {
            OfflineEarningsView(amount: gameVM.pendingOfflineEarnings)
        }
        .sheet(isPresented: $showDailyReward) {
            DailyRewardView()
        }
        .onAppear {
            // Wire the store to the game here rather than in ShopView, so
            // subscription multipliers apply even if the player never opens it.
            IAPManager.shared.attach(gameVM)
            NotificationManager.shared.refreshStatus()
            NotificationManager.shared.clearBadge()
            showNextPrompt()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Rebuilt on the way out so a stale reminder can't fire after
                // the player has already been back.
                NotificationManager.shared.rescheduleStreakReminder(
                    streak: gameVM.dailyStreak,
                    claimedToday: gameVM.pendingDailyReward == nil)
                gameVM.saveGameState()
                // Backgrounding is the last reliable moment before the app can
                // be killed, so this one bypasses the rate limit.
                gameVM.flushToCloud()
            case .active:
                NotificationManager.shared.clearBadge()
                // Catches someone who signed into Game Center while away, and
                // rolls the daily quests over if midnight passed.
                GameCenterManager.shared.retryAuthentication()
                gameVM.refreshDailyState()
                Task { await IAPManager.shared.refreshEntitlements() }
            default:
                break
            }
        }
    }

    /// A launch can have three things to say at once. Show them one at a time,
    /// most contextual first. The delay is what makes presenting the next sheet
    /// from a previous sheet's `onDismiss` reliable.
    private func showNextPrompt() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !gameVM.hasSeenTutorial {
                showTutorial = true
            } else if gameVM.pendingOfflineEarnings > 0 {
                showOfflineEarnings = true
            } else if gameVM.pendingDailyReward != nil {
                showDailyReward = true
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
                CosmicBackground(theme: gameVM.theme)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        dailySection

                        ForEach(Goal.Category.allCases) { category in
                            let goals = GoalCatalog.inCategory(category)
                            if !goals.isEmpty {
                                sectionHeader(category.rawValue,
                                              done: goals.filter { gameVM.claimedGoalIDs.contains($0.id) }.count,
                                              total: goals.count)
                                ForEach(goals) { GoalRow(goal: $0) }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Goals")
        }
    }

    private func sectionHeader(_ title: String, done: Int, total: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Text("\(done)/\(total)")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.top, 8)
    }

    /// Daily quests sit above the permanent goals because they're the thing
    /// that's gone tomorrow.
    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("resets at midnight")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }

            ForEach(gameVM.todayQuests) { quest in
                QuestRow(quest: quest)
            }
        }
    }
}

struct QuestRow: View {
    @EnvironmentObject var gameVM: GameViewModel
    let quest: DailyQuest

    private var claimed: Bool { gameVM.claimedQuestIDs.contains(quest.id) }
    private var complete: Bool { quest.isComplete(gameVM) }
    private var progress: Int { quest.currentProgress(gameVM) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: claimed ? "checkmark.seal.fill" : quest.icon)
                .font(.title3)
                .foregroundColor(claimed ? .green : .yellow)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                if !claimed {
                    ProgressView(value: Double(progress), total: Double(quest.target))
                        .tint(complete ? .yellow : .blue)
                    Text("\(progress) / \(quest.target)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            if claimed {
                Text("Done")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
            } else if complete {
                Button {
                    gameVM.claimQuest(quest)
                } label: {
                    Label("\(quest.gemReward)", systemImage: "diamond.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else {
                Label("\(quest.gemReward)", systemImage: "diamond.fill")
                    .font(.caption)
                    .foregroundColor(.purple.opacity(0.8))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(complete && !claimed ? Color.yellow.opacity(0.7) : Color.clear, lineWidth: 1.5))
        .cornerRadius(14)
        .opacity(claimed ? 0.6 : 1)
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

// MARK: - Settings
struct SettingsView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var audio = AudioManager.shared
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @ObservedObject private var notifications = NotificationManager.shared
    @ObservedObject private var cloud = CloudSaveManager.shared
    @StateObject private var iapManager = IAPManager.shared
    @State private var restoring = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground(theme: gameVM.theme)

                ScrollView {
                    VStack(spacing: 14) {
                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle(isOn: Binding(
                                    get: { !audio.isMuted },
                                    set: { audio.isMuted = !$0 }
                                )) {
                                    Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                                        .foregroundColor(.white)
                                }
                                .tint(.purple)

                                Divider().background(Color.white.opacity(0.2))

                                HStack {
                                    Label("Daily Reminder", systemImage: "bell.fill")
                                        .foregroundColor(.white)
                                    Spacer()
                                    if notifications.isAuthorized {
                                        Text("On").font(.caption).foregroundColor(.green)
                                    } else if notifications.hasAsked {
                                        Link("Enable in Settings",
                                             destination: URL(string: UIApplication.openSettingsURLString)!)
                                            .font(.caption)
                                    } else {
                                        Button("Turn On") { notifications.requestPermission() }
                                            .font(.caption)
                                            .buttonStyle(.bordered)
                                            .tint(.purple)
                                    }
                                }
                            }
                        }

                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    restoring = true
                                    Task {
                                        await iapManager.restorePurchases()
                                        restoring = false
                                    }
                                } label: {
                                    HStack {
                                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                                        Spacer()
                                        if restoring { ProgressView().tint(.white) }
                                    }
                                    .foregroundColor(.white)
                                }

                                Divider().background(Color.white.opacity(0.2))

                                HStack {
                                    Label("Game Center", systemImage: "trophy.fill")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(gameCenter.isAuthenticated ? "Signed in" : "Not signed in")
                                        .font(.caption)
                                        .foregroundColor(gameCenter.isAuthenticated ? .green : .white.opacity(0.5))
                                }

                                Divider().background(Color.white.opacity(0.2))

                                HStack {
                                    Label("iCloud Save", systemImage: "icloud.fill")
                                        .foregroundColor(.white)
                                    Spacer()
                                    if let error = cloud.lastError {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    } else if let synced = cloud.lastSyncedAt {
                                        Text(synced, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Not synced yet")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }

                                Button {
                                    gameVM.flushToCloud()
                                } label: {
                                    Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }

                        card {
                            VStack(alignment: .leading, spacing: 8) {
                                statRow("Total merges", "\(gameVM.totalMerges)")
                                statRow("Fusions", "\(gameVM.totalFusions)")
                                statRow("Highest tier", "\(gameVM.highestTierReached)")
                                statRow("Galaxy Marks", "\(gameVM.galaxyMarks)")
                                statRow("Daily streak", "\(gameVM.dailyStreak)")
                            }
                        }

                        card {
                            VStack(alignment: .leading, spacing: 8) {
                                Link(destination: URL(string: "https://ema19rivas99-max.github.io/nebula-forge/privacy")!) {
                                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                                }
                                Link(destination: URL(string: "https://ema19rivas99-max.github.io/nebula-forge/support")!) {
                                    Label("Support", systemImage: "questionmark.circle.fill")
                                }
                                Divider().background(Color.white.opacity(0.2))
                                statRow("Version", version)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.white.opacity(0.75))
            Spacer()
            Text(value).foregroundColor(.white).bold()
        }
        .font(.subheadline)
    }
}

// MARK: - Daily Reward
/// The only thing in the game that rewards *when* you play. Everything else
/// pays the same whenever you get to it, which gave the player no reason to
/// open the app on any particular day.
struct DailyRewardView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            CosmicBackground()

            VStack(spacing: 18) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 56))
                    .foregroundStyle(.yellow, .orange)

                Text("Daily Alignment")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                if let reward = gameVM.pendingDailyReward {
                    Text("Day \(reward.day) of \(DailyReward.maxStreakDay)")
                        .font(.headline)
                        .foregroundColor(.yellow)

                    HStack(spacing: 8) {
                        ForEach(1...DailyReward.maxStreakDay, id: \.self) { day in
                            Circle()
                                .fill(day <= reward.day ? Color.yellow : Color.white.opacity(0.2))
                                .frame(width: 12, height: 12)
                        }
                    }

                    HStack(spacing: 24) {
                        Label("\(reward.shards)", systemImage: "sparkle")
                            .foregroundColor(.blue)
                        Label("\(reward.gems)", systemImage: "diamond.fill")
                            .foregroundColor(.purple)
                    }
                    .font(.title3.bold())
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)

                    Text("Miss a day and the streak resets to one.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Button {
                        gameVM.claimDailyReward()
                        // Best possible moment to ask: they've just been handed
                        // something and the streak is the thing at stake. iOS
                        // only lets you ask once, so a cold launch prompt would
                        // waste it.
                        if !NotificationManager.shared.hasAsked {
                            NotificationManager.shared.requestPermission()
                        }
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
                } else {
                    Text("Already collected today. Come back tomorrow.")
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)

                    Button("Close") { dismiss() }
                        .foregroundColor(.blue)
                }
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
         "Spend Stardust to forge new items. They land straight on the board and start producing immediately."),
        ("circle.grid.cross.fill", "Merge In Place",
         "Tap one item, then a matching one. They combine into a stronger item worth triple the production — and it lands on the second tile, so you choose where the power ends up."),
        ("link", "Position Is Everything",
         "Every element earns its output differently and changes its neighbours. The number under each item is what that tile actually produces — watch it move as you rearrange."),
        ("wand.and.stars", "Fuse Opposites",
         "Two *different* elements at the same tier can fuse into a hybrid instead of tiering up. Hybrids produce far more, and pay triple Shards."),
        ("sparkles", "Catch Comets",
         "A comet lands on a free tile every few minutes and fades after about twenty seconds. Tap it before it goes for a burst of Stardust."),
        ("burst.fill", "Go Supernova",
         "Once your board has enough Power, trigger a Supernova. You lose the galaxy but keep a permanent multiplier and earn Gems. Marks scale with how deep you merged, not how many items you crammed in.")
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

                        Divider().background(Color.white.opacity(0.3))

                        Text("The Four Elements")
                            .font(.headline)
                            .foregroundColor(.white)

                        ForEach(Element.allCases, id: \.self) { element in
                            HStack(alignment: .top, spacing: 14) {
                                Circle()
                                    .fill(element.tint)
                                    .frame(width: 12, height: 12)
                                    .padding(.top, 4)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(element.displayName) — \(element.roleName)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(element.tint)
                                    Text(element.roleDetail)
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
/// Position of a tile, as a value the view can hold in `@State` and compare.
struct GridPosition: Hashable {
    let row: Int
    let col: Int
}

/// The whole game happens here now. Items are forged straight onto the board,
/// merged in place, and produce from wherever they sit — so a placement and its
/// payoff are visible at the same moment, instead of on two screens that never
/// showed each other.
struct GalacticCanvasView: View {
    @EnvironmentObject var gameVM: GameViewModel
    /// Drives the trophy button's enabled state — tapping it before Game Center
    /// authenticates was presenting an inescapable blank modal.
    @ObservedObject private var gameCenter = GameCenterManager.shared

    // Tap-to-select rather than drag-and-drop: drag gestures fight the
    // enclosing ScrollView on iPhone and were effectively unusable.
    @State private var selectedPosition: GridPosition?
    @State private var selectedTrayItemID: UUID?
    @State private var blockReason: String?
    @State private var showTutorial = false
    @State private var showSettings = false
    @State private var showGameCenterHelp = false

    private var selectedItem: CelestialItem? {
        selectedPosition.flatMap { item(at: $0) }
    }

    private var selectedTrayItem: CelestialItem? {
        gameVM.boardItems.first { $0.id == selectedTrayItemID }
    }

    /// Items already on the board that the current selection could combine with.
    private var mergeableIDs: Set<UUID> {
        guard let selectedItem else { return [] }
        return gameVM.mergePartners(for: selectedItem)
    }

    private func tile(at position: GridPosition) -> GridTile? {
        guard gameVM.gridTiles.indices.contains(position.row),
              gameVM.gridTiles[position.row].indices.contains(position.col) else { return nil }
        return gameVM.gridTiles[position.row][position.col]
    }

    private func item(at position: GridPosition) -> CelestialItem? {
        tile(at: position)?.placedItem
    }

    private func handleTap(row: Int, col: Int) {
        let position = GridPosition(row: row, col: col)
        guard let tapped = tile(at: position) else { return }
        blockReason = nil

        // The comet is the only time-critical thing on the board, so it wins
        // the tap regardless of what's selected.
        if gameVM.isCometTile(tapped), gameVM.comet != nil {
            gameVM.collectComet()
            return
        }

        guard tapped.isUnlocked else { return }

        // Dropping a held overflow item onto a free tile.
        if let trayItem = selectedTrayItem, tapped.placedItem == nil {
            _ = gameVM.placeItemOnGrid(trayItem, row: row, col: col)
            selectedTrayItemID = nil
            return
        }

        guard tapped.placedItem != nil else {
            selectedPosition = nil
            return
        }

        guard let current = selectedPosition else {
            selectedPosition = position
            return
        }

        if current == position {
            selectedPosition = nil
            return
        }

        if gameVM.mergeOnGrid(from: (current.row, current.col), to: (row, col)) {
            selectedPosition = nil
            return
        }

        // Say why it didn't combine rather than failing silently, then treat
        // the tap as picking a new item.
        if let a = item(at: current), let b = item(at: position) {
            blockReason = CelestialItem.mergeBlockReason(item1: a, item2: b)
        }
        selectedPosition = position
    }

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground(theme: gameVM.theme)

                VStack(spacing: 8) {
                    resourceBar
                    surgeBanner
                    actionBar
                    hintLine

                    ScrollView([.horizontal, .vertical]) {
                        hexGrid.padding()
                    }

                    selectionPanel

                    if !gameVM.boardItems.isEmpty {
                        overflowTray
                    }
                }
            }
            .overlay(alignment: .top) { mergeBanner }
            .animation(.spring(response: 0.35), value: gameVM.lastMergeSummary)
            .navigationTitle("Nebula Forge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        Button {
                            showTutorial = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.white)
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // Always does something. Disabling it entirely meant a
                        // player who wasn't signed in just had a dead button
                        // and no idea why.
                        if gameCenter.isAuthenticated {
                            GameCenterManager.shared.showLeaderboard()
                        } else {
                            gameCenter.retryAuthentication()
                            showGameCenterHelp = true
                        }
                    } label: {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(gameCenter.isAuthenticated ? .yellow : .gray)
                    }
                }
            }
            .sheet(isPresented: $showTutorial) {
                TutorialView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(gameVM)
            }
            .alert("Leaderboards need Game Center", isPresented: $showGameCenterHelp) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("Sign in to Game Center to see how your galaxy ranks. Your scores are already being recorded and will appear once you do.")
            }
        }
    }

    // MARK: Pieces
    // Split out so the type-checker isn't handed one enormous body expression.

    private var resourceBar: some View {
        HStack {
            ResourceBadge(icon: "star.fill", value: gameVM.stardust, color: .yellow)
            Spacer()
            ResourceBadge(icon: "sparkle", value: gameVM.starlightShards, color: .blue)
            Spacer()
            ResourceBadge(icon: "diamond.fill", value: gameVM.nebulaGems, color: .purple)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text("\(abbreviatedNumber(gameVM.idleEngine.totalProductionPerSec))/sec")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Button {
                _ = gameVM.unlockNextTile()
            } label: {
                Label("\(gameVM.tileUnlockCost)", systemImage: "lock.open.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(gameVM.starlightShards < gameVM.tileUnlockCost)

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
                Label(abbreviatedNumber(gameVM.forgeItemCost), systemImage: "hammer.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(gameVM.stardust < gameVM.forgeItemCost)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var surgeBanner: some View {
        if gameVM.surgeMultiplier > 1 {
            let secs = gameVM.surgeSecondsRemaining
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                Text("Stellar Surge ×2 — \(secs / 60)m \(secs % 60)s")
                    .font(.caption.bold())
            }
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.yellow))
        }
    }

    private var hintLine: some View {
        Text(blockReason ?? gameVM.nextStepHint)
            .font(.caption)
            .foregroundColor(blockReason == nil ? .yellow.opacity(0.9) : .red.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var hexGrid: some View {
        VStack(spacing: -10) {
            ForEach(0..<gameVM.gridTiles.count, id: \.self) { row in
                HStack(spacing: -5) {
                    ForEach(0..<gameVM.gridTiles[row].count, id: \.self) { col in
                        hexTile(row: row, col: col)
                            .offset(x: row % 2 == 0 ? 25 : 0)
                    }
                }
            }
        }
    }

    private func hexTile(row: Int, col: Int) -> some View {
        let tile = gameVM.gridTiles[row][col]
        let position = GridPosition(row: row, col: col)
        let output = tile.placedItem == nil
            ? 0
            : gameVM.idleEngine.production(for: tile, in: gameVM.gridTiles).total

        return HexTileView(
            tile: tile,
            isSelected: selectedPosition == position,
            isMergeCandidate: tile.placedItem.map { mergeableIDs.contains($0.id) } ?? false,
            isPlacementTarget: selectedTrayItemID != nil && tile.isUnlocked && tile.placedItem == nil,
            comet: gameVM.isCometTile(tile) ? gameVM.comet : nil,
            output: output,
            tileFill: gameVM.theme.tileFill,
            onTap: { handleTap(row: row, col: col) }
        )
    }

    /// The number the board used to hide. Shows what the selected tile actually
    /// produces and which neighbours are changing it.
    @ViewBuilder
    private var selectionPanel: some View {
        if let position = selectedPosition,
           let item = selectedItem,
           let tile = tile(at: position) {
            let breakdown = gameVM.idleEngine.production(for: tile, in: gameVM.gridTiles)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("T\(item.tier)")
                        .font(.caption2.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(item.element.tint))
                    Spacer()
                    Text("\(abbreviatedNumber(breakdown.total))/sec")
                        .font(.caption.bold())
                        .foregroundColor(.yellow)
                }

                Text("\(item.element.roleName) — \(item.element.roleDetail)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))

                if breakdown.isModified {
                    HStack(spacing: 8) {
                        ForEach(breakdown.notes, id: \.self) { note in
                            Text(note)
                                .font(.caption2.bold())
                                .foregroundColor(note.hasPrefix("-") ? .red : .green)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    /// Only appears when every unlocked tile is taken — forged items normally
    /// land straight on the board.
    private var overflowTray: some View {
        VStack(spacing: 2) {
            Text("Overflow — no free tiles")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(gameVM.boardItems) { item in
                        Button {
                            selectedTrayItemID = (selectedTrayItemID == item.id) ? nil : item.id
                            selectedPosition = nil
                        } label: {
                            ItemCard(item: item)
                                .scaleEffect(0.75)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedTrayItemID == item.id ? Color.yellow : Color.clear,
                                                lineWidth: 3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 90)
        }
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var mergeBanner: some View {
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
}

// MARK: - Celestial Item Sprite
struct CelestialItemSprite: View {
    let item: CelestialItem
    let size: CGFloat
    @State private var pulse = false

    private var baseColor: Color { item.element.tint }

    /// Asset name for this chain and tier, e.g. `item_fire_t3`, `item_eclipse_t5`.
    private var assetName: String {
        guard let chain = ItemCatalog.chain(for: item.chainID) else {
            return "item_\(item.element.rawValue)_t\(min(item.tier, 7))"
        }
        return chain.assetName(forTier: item.tier)
    }

    /// Hybrids now have their own artwork, but the ring still marks them out as
    /// the rarer thing on a crowded board.
    private var isHybrid: Bool {
        ItemCatalog.chain(for: item.chainID)?.isHybrid ?? false
    }

    var body: some View {
        ZStack {
            // Every item gets a lit backing, not just high tiers. The artwork is
            // dark-on-dark against the cosmic background — Void and tier-0 items
            // were close to invisible without something behind them.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [baseColor.opacity(0.42), baseColor.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: (size + 14) / 2
                    )
                )
                .frame(width: size + 14, height: size + 14)

            // A thin rim gives a hard edge the background can't swallow.
            Circle()
                .strokeBorder(baseColor.opacity(0.55), lineWidth: 1)
                .frame(width: size + 14, height: size + 14)

            if item.tier >= 3 {
                Circle()
                    .fill(baseColor.opacity(0.35))
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

            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size + 12, height: size + 12)
                .shadow(color: baseColor.opacity(0.5), radius: item.tier >= 5 ? 10 : 4)

            if isHybrid {
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [.white, baseColor, .white, baseColor, .white],
                                        center: .center),
                        lineWidth: 2
                    )
                    .frame(width: size + 16, height: size + 16)
            }
        }
        .frame(width: size + 20, height: size + 20)
    }

    private var glowRadius: CGFloat { min(2 + CGFloat(item.tier) * 1.5, 15) }
}

struct HexTileView: View {
    let tile: GridTile
    let isSelected: Bool
    let isMergeCandidate: Bool
    let isPlacementTarget: Bool
    let comet: Comet?
    let output: Double
    var tileFill: [Color] = [Color.blue.opacity(0.15), Color.purple.opacity(0.10)]
    let onTap: () -> Void

    private var strokeColor: Color {
        if isSelected { return .yellow }
        if isMergeCandidate { return .green }
        if isPlacementTarget { return .yellow.opacity(0.7) }
        if !tile.isUnlocked { return .gray.opacity(0.3) }
        return .white.opacity(0.4)
    }

    private var strokeWidth: CGFloat {
        if isSelected { return 3 }
        if isMergeCandidate || isPlacementTarget { return 2.5 }
        return 1.5
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                HexagonShape()
                    .fill(
                        tile.isUnlocked
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: tileFill,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(Color.gray.opacity(0.1))
                    )
                    .overlay(
                        HexagonShape()
                            .stroke(strokeColor, lineWidth: strokeWidth)
                    )
                    .frame(width: 65, height: 75)

                if let item = tile.placedItem {
                    VStack(spacing: 0) {
                        CelestialItemSprite(item: item, size: 32)
                        // The per-tile number is the point of merging the two
                        // boards: adjacency effects are now readable in place.
                        Text(abbreviatedNumber(output))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                if let comet {
                    CometBadge(comet: comet)
                }

                if !tile.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

/// A comet sitting on a tile, wrapped in a ring that drains as its window
/// closes. Redraws come free — the idle tick already republishes ten times a
/// second, so there's no separate animation timer.
struct CometBadge: View {
    let comet: Comet

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
                .frame(width: 46, height: 46)

            Circle()
                .trim(from: 0, to: CGFloat(comet.remainingFraction))
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 46, height: 46)

            Image(systemName: "sparkles")
                .font(.title3.bold())
                .foregroundStyle(.white, .cyan)
                .shadow(color: .cyan, radius: 6)
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
    /// Optional so sheets and previews that have no view model still render.
    var theme: CosmeticTheme = CosmeticCatalog.theme(for: CosmeticCatalog.defaultID)

    // Generated once so the starfield doesn't reshuffle every frame.
    private let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, opacity: Double)] = (0..<80).map { _ in
        (
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            r: CGFloat.random(in: 0.5...2.5),
            opacity: Double.random(in: 0.3...1)
        )
    }

    /// Fixed cloud placement, so the nebula doesn't crawl around the screen on
    /// every redraw (this view repaints ten times a second).
    private let clouds: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.22, 0.18, 0.42), (0.78, 0.30, 0.36), (0.50, 0.62, 0.48),
        (0.14, 0.80, 0.32), (0.86, 0.86, 0.38),
    ]

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: theme.background),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            // Soft coloured clouds under the starfield. Without these every
            // theme reads as the same screen in a slightly different blue.
            if !theme.nebula.isEmpty {
                let span = max(size.width, size.height)
                for (i, cloud) in clouds.enumerated() {
                    let tint = theme.nebula[i % theme.nebula.count]
                    let radius = cloud.r * span
                    let centre = CGPoint(x: cloud.x * size.width, y: cloud.y * size.height)
                    let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [tint, tint.opacity(0)]),
                            center: centre,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }

            for star in stars {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: star.x * size.width,
                        y: star.y * size.height,
                        width: star.r,
                        height: star.r
                    )),
                    with: .color(theme.starTint.opacity(star.opacity))
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

    private var potentialMarks: Int { gameVM.potentialMarks }
    private var power: Double { gameVM.prestigePower }
    private var ready: Bool { gameVM.canPrestige }

    /// How far along the power requirement the player is, for the bar.
    private var readiness: Double {
        min(1, power / GameViewModel.prestigePowerRequirement)
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
                        Text(ready ? "Supernova Ready" : "Supernova Locked")
                            .font(.title.bold())
                            .foregroundColor(.white)

                        VStack(spacing: 6) {
                            Text("Galaxy Power \(abbreviatedNumber(power))")
                                .foregroundColor(.white.opacity(0.85))

                            ProgressView(value: readiness)
                                .tint(ready ? .yellow : .blue)
                                .frame(maxWidth: 220)

                            Text("Potential Galaxy Marks: \(potentialMarks)")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            Text("Celestial Rank: \(gameVM.celestialRank)")
                                .foregroundColor(.purple)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(15)

                        // Worth spelling out, because the rule changed: Marks
                        // used to be a flat count of placed items, which made
                        // merging deep strictly worse than forging junk.
                        Text("Power is the sum of everything on your board, and each tier is worth triple the last. Merge deep before you burn it down.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal)

                        Text("Resetting destroys this galaxy, but Galaxy Marks are permanent — spend them below.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.55))
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
                        .disabled(!ready)
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

// MARK: - Shop View
/// Three shelves: Gems for money, boosts for Gems, and cosmetics for Gems. The
/// last two work with no App Store Connect products at all, so the tab is never
/// empty while real-money products are still in review.
struct ShopView: View {
    @EnvironmentObject var gameVM: GameViewModel
    @StateObject private var iapManager = IAPManager.shared
    @State private var shelf: Shelf = .boosts

    /// Named `Shelf` rather than `Section` so it doesn't shadow SwiftUI's own
    /// `Section` inside this view.
    enum Shelf: String, CaseIterable, Identifiable {
        case boosts = "Boosts"
        case cosmetics = "Themes"
        case gems = "Gems"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            ZStack {
                CosmicBackground(theme: gameVM.theme)

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "diamond.fill")
                            .foregroundColor(.purple)
                        Text("\(gameVM.nebulaGems) Gems")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)

                    Picker("Shelf", selection: $shelf) {
                        ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 12) {
                            offerBanner
                            firstPurchaseBanner
                            switch shelf {
                            case .boosts: boostShelf
                            case .cosmetics: cosmeticShelf
                            case .gems: gemShelf
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Nebula Store")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            IAPManager.shared.attach(gameVM)
            await iapManager.loadProducts()
        }
    }

    /// The rotating deal. Shown on every shelf, because the point of a deadline
    /// is that you see it.
    @ViewBuilder
    private var offerBanner: some View {
        if let offer = gameVM.currentOffer {
            let affordable = gameVM.nebulaGems >= offer.salePrice
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Limited Time", systemImage: "clock.fill")
                        .font(.caption.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.yellow))
                    Spacer()
                    Text(offer.countdown)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundColor(.yellow)
                }

                HStack(spacing: 12) {
                    Image(systemName: offer.icon)
                        .font(.title2)
                        .foregroundColor(.yellow)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(offer.title)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text(offer.detail)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    Button {
                        if affordable {
                            gameVM.buyOffer(offer)
                        } else {
                            shelf = .gems
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text("\(offer.fullPrice)")
                                .font(.caption2)
                                .strikethrough()
                                .foregroundColor(.white.opacity(0.6))
                            Label("\(offer.salePrice)", systemImage: "diamond.fill")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(affordable ? .green : .purple)
                }

                if !affordable {
                    Text("Not enough Gems — tap to top up")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.6), lineWidth: 1.5))
            .cornerRadius(14)
        }
    }

    /// Shown until the first paid purchase lands.
    @ViewBuilder
    private var firstPurchaseBanner: some View {
        if gameVM.firstPurchaseBonusAvailable {
            Button {
                shelf = .gems
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gift.fill")
                        .font(.title2)
                        .foregroundColor(.pink)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("First Purchase: Double Gems")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text("Your first gem pack pays twice. Once only.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding()
                .background(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.pink.opacity(0.6), lineWidth: 1.5))
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
    }

    private var boostShelf: some View {
        ForEach(GemShopCatalog.all) { offer in
            GemOfferRow(offer: offer, onNeedGems: { shelf = .gems })
        }
    }

    private var cosmeticShelf: some View {
        ForEach(CosmeticCatalog.all) { theme in
            ThemeRow(theme: theme)
        }
    }

    @ViewBuilder
    private var gemShelf: some View {
        if iapManager.products.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.purple.opacity(0.7))
                Text("No products available")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("These appear once the in-app purchases are created in App Store Connect. Gems can already be earned free by triggering a Supernova.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 40)
        } else {
            ForEach(iapManager.products, id: \.id) { product in
                ShopProductRow(product: product, iapManager: iapManager)
            }
        }

        // App Review requires a restore path for anything non-consumable.
        Button {
            Task { await iapManager.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.caption)
                .underline()
                .foregroundColor(.blue)
        }
        .padding(.top, 8)
    }
}

struct GemOfferRow: View {
    @EnvironmentObject var gameVM: GameViewModel
    let offer: GemOffer
    /// Tapping an unaffordable item should go somewhere, not just be dead.
    var onNeedGems: () -> Void = {}

    private var affordable: Bool { gameVM.nebulaGems >= offer.gemCost }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: offer.icon)
                .font(.title2)
                .foregroundColor(.yellow)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(offer.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(offer.detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Button {
                if affordable {
                    gameVM.buy(offer)
                } else {
                    onNeedGems()
                }
            } label: {
                Label("\(offer.gemCost)", systemImage: "diamond.fill")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            // Deliberately not disabled: an unaffordable price is the moment to
            // offer gems, not a dead end.
            .tint(affordable ? .purple : .gray)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }
}

/// A miniature of the real board in a given palette — background, nebula,
/// starfield and three tiles. Buying a theme should never be a guess about what
/// it looks like.
struct ThemePreview: View {
    let theme: CosmeticTheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let hex = w * 0.34
            ZStack {
                CosmicBackground(theme: theme)

                HexagonShape()
                    .fill(LinearGradient(colors: theme.tileFill,
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(HexagonShape().stroke(theme.accent.opacity(0.6), lineWidth: 1))
                    .frame(width: hex, height: hex * 1.15)
                    .offset(x: -hex * 0.52, y: -hex * 0.3)

                HexagonShape()
                    .fill(LinearGradient(colors: theme.tileFill,
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(HexagonShape().stroke(theme.accent.opacity(0.6), lineWidth: 1))
                    .frame(width: hex, height: hex * 1.15)
                    .offset(x: hex * 0.52, y: -hex * 0.3)

                HexagonShape()
                    .fill(LinearGradient(colors: theme.tileFill,
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(HexagonShape().stroke(theme.accent, lineWidth: 1.5))
                    .frame(width: hex, height: hex * 1.15)
                    .offset(y: hex * 0.68)

                Circle()
                    .fill(theme.accent)
                    .frame(width: hex * 0.34, height: hex * 0.34)
                    .blur(radius: 1)
                    .offset(y: hex * 0.68)
            }
        }
    }
}

struct ThemeRow: View {
    @EnvironmentObject var gameVM: GameViewModel
    let theme: CosmeticTheme

    private var owned: Bool { gameVM.owns(theme) }
    private var selected: Bool { gameVM.selectedThemeID == theme.id }

    var body: some View {
        HStack(spacing: 14) {
            ThemePreview(theme: theme)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.yellow : Color.white.opacity(0.2),
                                lineWidth: selected ? 2.5 : 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(theme.detail)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            if selected {
                VStack(spacing: 2) {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                    if gameVM.isEntitlementTheme(theme) {
                        Text("included")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            } else if owned {
                VStack(spacing: 2) {
                    Button("Use") { gameVM.selectTheme(theme) }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .font(.caption)
                    if gameVM.isEntitlementTheme(theme) {
                        Text("included")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            } else {
                Button {
                    gameVM.purchaseTheme(theme)
                } label: {
                    Label("\(theme.gemCost)", systemImage: "diamond.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(gameVM.nebulaGems < theme.gemCost)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }
}

struct ShopProductRow: View {
    let product: Product
    @ObservedObject var iapManager: IAPManager

    private var owned: Bool { iapManager.purchasedProductIDs.contains(product.id) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                // What the game actually hands over, which the App Store
                // description can drift away from.
                if let summary = StoreCatalog.summary(for: product.id) {
                    Text(summary)
                        .font(.caption2.bold())
                        .foregroundColor(.yellow)
                }
            }

            Spacer()

            if owned {
                Text("Owned")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            } else {
                Button {
                    Task { try? await iapManager.purchase(product) }
                } label: {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.purple)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
}

// MARK: - Cloud save
/// The whole save, in one Codable value.
///
/// Consumable gem purchases are the reason this exists: StoreKit restores
/// subscriptions and non-consumables on a new device, but gems bought and not
/// yet spent live nowhere but the device that bought them.
struct SaveSnapshot: Codable {
    struct Item: Codable {
        let chainID: String
        let tier: Int
        /// nil for items sitting in the overflow tray.
        let row: Int?
        let col: Int?
    }

    var savedAt: Date
    var stardust: Double
    var starlightShards: Int
    var nebulaGems: Int
    var galaxyMarks: Int
    var celestialRank: Int
    var permanentMultiplier: Double
    var hasPrestiged: Bool
    var totalMerges: Int
    var totalFusions: Int
    var itemsForged: Int
    var highestTierReached: Int
    var claimedGoalIDs: [String]
    var upgradeLevels: [String: Int]
    var unlockedTiles: [String]
    var dailyStreak: Int
    var lastDailyClaim: Date?
    var hasMadeFirstPurchase: Bool
    var ownedThemeIDs: [String]
    var selectedThemeID: String
    var items: [Item]
}

/// Mirrors the save into iCloud key-value storage.
///
/// Deliberately not CloudKit. `NSPersistentCloudKitContainer` is what crashed
/// this app on launch every build; this is a different API with no schema, no
/// container setup and no migration, and the save is a few kilobytes against a
/// 1MB limit. If iCloud is unavailable it simply does nothing.
final class CloudSaveManager: ObservableObject {
    static let shared = CloudSaveManager()

    private let store = NSUbiquitousKeyValueStore.default
    private static let key = "nf.save.v1"

    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    /// Set while a restore is being applied, so the resulting local saves don't
    /// immediately push the same data back up.
    private var isRestoring = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudChangedExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store)
        store.synchronize()
    }

    /// Called when another device writes a newer save.
    var onRemoteSave: ((SaveSnapshot) -> Void)?

    @objc private func cloudChangedExternally(_ note: Notification) {
        guard let snapshot = load() else { return }
        DispatchQueue.main.async {
            self.onRemoteSave?(snapshot)
        }
    }

    func save(_ snapshot: SaveSnapshot) {
        guard !isRestoring else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            // Well under the 1MB per-key limit, but a corrupt oversized write
            // would silently fail, so it's worth refusing loudly.
            guard data.count < 900_000 else {
                lastError = "Save too large to sync"
                return
            }
            store.set(data, forKey: Self.key)
            store.synchronize()
            lastSyncedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func load() -> SaveSnapshot? {
        guard let data = store.data(forKey: Self.key) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SaveSnapshot.self, from: data)
        } catch {
            // A save written by a newer version we can't read is not a reason
            // to lose the local one.
            lastError = "Could not read cloud save"
            return nil
        }
    }

    func withRestoreSuppressed(_ body: () -> Void) {
        isRestoring = true
        body()
        isRestoring = false
    }
}

// MARK: - Notifications
/// Local reminders only — nothing leaves the device and there's no push server.
///
/// Permission is deliberately not requested at launch. A cold prompt before the
/// player knows what the game is gets denied, and iOS only asks once.
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @Published var hasAsked: Bool {
        didSet { UserDefaults.standard.set(hasAsked, forKey: "nf.askedNotifications") }
    }

    private init() {
        hasAsked = UserDefaults.standard.bool(forKey: "nf.askedNotifications")
        refreshStatus()
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func requestPermission() {
        hasAsked = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                }
            }
    }

    /// Rescheduled from scratch on every app background, so a stale reminder
    /// can't fire after the player has already come back.
    func rescheduleStreakReminder(streak: Int, claimedToday: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["nf.streak"])
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        if claimedToday {
            content.title = "Your galaxy is still turning"
            content.body = streak > 1
                ? "Day \(streak + 1) of your streak is ready. Don't drop it now."
                : "Come back tomorrow to start a streak."
        } else {
            content.title = "Today's reward is waiting"
            content.body = streak > 1
                ? "Collect it to keep your \(streak)-day streak alive."
                : "Collect your daily Gems and Shards."
        }
        content.sound = .default

        // Early evening the following day: late enough to be a real reminder,
        // not so late that it lands while they're asleep.
        var when = DateComponents()
        when.hour = 19
        when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: "nf.streak",
                                         content: content, trigger: trigger))
    }

    /// Cleared whenever the app opens, so the badge always means something.
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - Audio
/// Plays the game's sound effects.
///
/// Each effect keeps a small pool of players because merges can overlap, and a
/// single `AVAudioPlayer` restarting mid-sound clips the previous one off.
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: "nf.muted") }
    }

    private var pools: [String: [AVAudioPlayer]] = [:]
    private var next: [String: Int] = [:]
    private let poolSize = 3

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: "nf.muted")
        configureSession()
    }

    /// `.ambient` so the game mixes with whatever the player is already
    /// listening to instead of stopping it.
    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default,
                                                            options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    private func pool(for name: String) -> [AVAudioPlayer] {
        if let existing = pools[name] { return existing }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            pools[name] = []
            return []
        }
        var made: [AVAudioPlayer] = []
        for _ in 0..<poolSize {
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                made.append(player)
            }
        }
        pools[name] = made
        return made
    }

    func play(_ name: String, volume: Float = 1.0) {
        guard !isMuted else { return }
        let players = pool(for: name)
        guard !players.isEmpty else { return }
        let index = (next[name] ?? 0) % players.count
        next[name] = index + 1
        let player = players[index]
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// Warms the players for the effects that fire soonest, so the first merge
    /// of a session isn't the one that stutters.
    func preload() {
        for name in ["tap", "merge", "forge", "denied"] { _ = pool(for: name) }
    }
}

// MARK: - Feedback
/// One call site for "something happened", so haptics and audio can't drift
/// apart.
enum Feedback {
    static func merge(isFusion: Bool) {
        HapticManager.shared.mergeSuccess()
        AudioManager.shared.play(isFusion ? "fusion" : "merge")
    }

    static func denied() {
        HapticManager.shared.mergeFail()
        AudioManager.shared.play("denied", volume: 0.7)
    }

    static func place() {
        HapticManager.shared.itemPlace()
        AudioManager.shared.play("tap", volume: 0.8)
    }

    static func forge() {
        HapticManager.shared.itemPlace()
        AudioManager.shared.play("forge")
    }

    static func supernova() {
        HapticManager.shared.supernova()
        AudioManager.shared.play("supernova")
    }

    static func comet() {
        HapticManager.shared.supernova()
        AudioManager.shared.play("comet")
    }

    static func purchase() {
        HapticManager.shared.supernova()
        AudioManager.shared.play("purchase")
    }

    static func goal() {
        HapticManager.shared.mergeSuccess()
        AudioManager.shared.play("goal")
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
