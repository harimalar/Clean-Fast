import SwiftUI
import Combine
import UserNotifications
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - App

@main
struct FastingTrackerApp: App {
    @StateObject private var vm = FastingViewModel()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var themeManager = ThemeManager()

    init() {}

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(vm)
                .environmentObject(subscription)
                .environmentObject(themeManager)
                .onAppear {
                    vm.normalizeGoal(for: subscription.isPro)
                    applyGlobalAppearance(for: themeManager.selectedTheme)
                }
                .onChange(of: subscription.tier) { _ in
                    vm.normalizeGoal(for: subscription.isPro)
                }
                .onChange(of: themeManager.selectedTheme) { newTheme in
                    applyGlobalAppearance(for: newTheme)
                }
                .preferredColorScheme(themeManager.selectedTheme.preferredColorScheme)
        }
    }

    private func applyGlobalAppearance(for theme: AppTheme) {
        let textColor = theme.isLight
        ? UIColor(red: 0.11, green: 0.15, blue: 0.24, alpha: 1)
        : UIColor.white

        let secondaryColor = theme.isLight
        ? UIColor(red: 0.31, green: 0.36, blue: 0.46, alpha: 1)
        : UIColor(white: 0.72, alpha: 1)

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.titleTextAttributes = [.foregroundColor: textColor]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: textColor]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = textColor

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = theme.isLight
        ? UIColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1)
        : UIColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1)
        tabAppearance.stackedLayoutAppearance.normal.iconColor = secondaryColor
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: secondaryColor]
        tabAppearance.stackedLayoutAppearance.selected.iconColor = textColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: textColor]
        tabAppearance.inlineLayoutAppearance.normal.iconColor = secondaryColor
        tabAppearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: secondaryColor]
        tabAppearance.inlineLayoutAppearance.selected.iconColor = textColor
        tabAppearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: textColor]
        tabAppearance.compactInlineLayoutAppearance.normal.iconColor = secondaryColor
        tabAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: secondaryColor]
        tabAppearance.compactInlineLayoutAppearance.selected.iconColor = textColor
        tabAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: textColor]
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = textColor
        UITabBar.appearance().unselectedItemTintColor = secondaryColor
    }
}

// MARK: - Models

enum FastingGoal: Int, CaseIterable, Identifiable, Codable {
    case h12 = 12
    case h14 = 14
    case h16 = 16
    case h18 = 18
    case h20 = 20
    case h24 = 24
    case h36 = 36

    var id: Int { rawValue }
    var title: String { "\(rawValue)h" }
    var seconds: TimeInterval { TimeInterval(rawValue * 3600) }
}

struct FastEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let goalHours: Int

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
    var durationHours: Double { duration / 3600.0 }
    var metGoal: Bool { duration >= TimeInterval(goalHours * 3600) }
}

enum AppTier: String {
    case free
    case pro

    var title: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }
}

enum ProPlan: String, CaseIterable, Identifiable {
    case oneTime

    var id: String { rawValue }

    var title: String { "Pro Unlock" }
    var priceText: String { "$4.99 one-time" }
    var badge: String? { "Lifetime Access" }
}

// MARK: - Utilities

extension Date {
    func dayKey() -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func shortDate() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    func timeOnly() -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: self)
    }
}

enum CSVExporter {
    static func export(entries: [FastEntry]) -> URL? {
        let header = "Start Date,Start Time,End Date,End Time,Goal (h),Duration (h),Met Goal\n"
        let rows = entries.map { e in
            let dur = String(format: "%.2f", e.durationHours)
            return "\(e.startDate.shortDate()),\(e.startDate.timeOnly()),\(e.endDate.shortDate()),\(e.endDate.timeOnly()),\(e.goalHours),\(dur),\(e.metGoal)"
        }.joined(separator: "\n")

        let csv = header + rows + "\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fasting-history.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Storage

final class FastStore {
    static let shared = FastStore()

    private let localKeyEntries = "fasting_entries_v1"
    private let localKeyGoal = "fasting_goal_v1"
    private let localKeyCurrentStart = "current_fast_start_v1"
    private let localKeyHydrationCups = "hydration_cups_v1"
    private let localKeyHydrationDay = "hydration_day_v1"

    private let iCloudKeyEntries = "icloud_fasting_entries_v1"
    private let iCloudKeyGoal = "icloud_fasting_goal_v1"

    private let kvs = NSUbiquitousKeyValueStore.default

    private init() {}

    func startListeningForCloudChanges(onChange: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { _ in onChange() }
        kvs.synchronize()
    }

    func loadGoal() -> FastingGoal {
        if let raw = kvs.object(forKey: iCloudKeyGoal) as? Int,
           let g = FastingGoal(rawValue: raw) {
            return g
        }
        let localRaw = UserDefaults.standard.integer(forKey: localKeyGoal)
        return FastingGoal(rawValue: localRaw) ?? .h18
    }

    func saveGoal(_ goal: FastingGoal) {
        UserDefaults.standard.set(goal.rawValue, forKey: localKeyGoal)
        kvs.set(goal.rawValue, forKey: iCloudKeyGoal)
        kvs.synchronize()
    }

    func loadCurrentStart() -> Date? {
        UserDefaults.standard.object(forKey: localKeyCurrentStart) as? Date
    }

    func saveCurrentStart(_ start: Date?) {
        if let start {
            UserDefaults.standard.set(start, forKey: localKeyCurrentStart)
        } else {
            UserDefaults.standard.removeObject(forKey: localKeyCurrentStart)
        }
    }

    func loadHydrationCupsForToday() -> Int {
        let today = Date().dayKey()
        guard UserDefaults.standard.string(forKey: localKeyHydrationDay) == today else { return 0 }
        return max(0, UserDefaults.standard.integer(forKey: localKeyHydrationCups))
    }

    func saveHydrationCupsForToday(_ cups: Int) {
        UserDefaults.standard.set(max(0, cups), forKey: localKeyHydrationCups)
        UserDefaults.standard.set(Date().dayKey(), forKey: localKeyHydrationDay)
    }

    func loadEntries() -> [FastEntry] {
        let local = loadLocalEntries()
        let cloud = loadCloudEntries()

        var map: [UUID: FastEntry] = [:]
        for e in local { map[e.id] = e }
        for e in cloud { map[e.id] = e }

        return map.values.sorted(by: { $0.endDate > $1.endDate })
    }

    func saveEntries(_ entries: [FastEntry]) {
        saveLocalEntries(entries)
        saveCloudEntries(entries)
    }

    private func loadLocalEntries() -> [FastEntry] {
        guard let data = UserDefaults.standard.data(forKey: localKeyEntries),
              let decoded = try? JSONDecoder().decode([FastEntry].self, from: data) else { return [] }
        return decoded
    }

    private func saveLocalEntries(_ entries: [FastEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: localKeyEntries)
    }

    private func loadCloudEntries() -> [FastEntry] {
        guard let data = kvs.data(forKey: iCloudKeyEntries),
              let decoded = try? JSONDecoder().decode([FastEntry].self, from: data) else { return [] }
        return decoded
    }

    private func saveCloudEntries(_ entries: [FastEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        kvs.set(data, forKey: iCloudKeyEntries)
        kvs.synchronize()
    }
}
// MARK: - Notifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let completeID = "fast_complete_notification"

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleFastComplete(at date: Date, goalTitle: String) {
        cancelFastComplete()

        let content = UNMutableNotificationContent()
        content.title = "Fast complete"
        content.body = "Nice work - you reached your \(goalTitle) goal."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )

        let request = UNNotificationRequest(identifier: completeID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelFastComplete() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [completeID])
    }
}

// MARK: - Subscription

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var tier: AppTier = .free
    @Published var selectedPlan: ProPlan = .oneTime

    private let tierKey = "clearfast_tier_v1"
    private let planKey = "clearfast_plan_v1"

    var isPro: Bool { tier == .pro }

    init() {
        load()
    }

    func purchaseSelectedPlan() {
        tier = .free
        save()
    }

    func restorePurchases() {
        tier = .free
        save()
    }

    func setPlan(_ plan: ProPlan) {
        selectedPlan = plan
        save()
    }

    func enableProForTesting() {
        tier = .pro
        save()
    }

    func resetToFreeForTesting() {
        tier = .free
        save()
    }

    private func load() {
        if let rawTier = UserDefaults.standard.string(forKey: tierKey),
           let persistedTier = AppTier(rawValue: rawTier) {
            tier = persistedTier
        }

        tier = .free

        if let rawPlan = UserDefaults.standard.string(forKey: planKey),
           let persistedPlan = ProPlan(rawValue: rawPlan) {
            selectedPlan = persistedPlan
        }
    }

    private func save() {
        UserDefaults.standard.set(tier.rawValue, forKey: tierKey)
        UserDefaults.standard.set(selectedPlan.rawValue, forKey: planKey)
    }
}

// MARK: - ViewModel

enum WidgetSyncBridge {
    private static let appGroupID = "group.com.hari.clearfast"
    private static let keyGoalHours = "widget_goal_hours_v1"
    private static let keyFastStartEpoch = "widget_fast_start_epoch_v1"
    private static let keyFastIsActive = "widget_fast_is_active_v1"
    private static let keyHydrationCups = "widget_hydration_cups_v1"
    private static let keyHistoryCount = "widget_history_count_v1"

    static func push(goalHours: Int, fastStart: Date?, hydrationCups: Int, historyCount: Int) {
        write(to: .standard, goalHours: goalHours, fastStart: fastStart, hydrationCups: hydrationCups, historyCount: historyCount)
        if let shared = UserDefaults(suiteName: appGroupID) {
            write(to: shared, goalHours: goalHours, fastStart: fastStart, hydrationCups: hydrationCups, historyCount: historyCount)
        }
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "ClearFastWidget")
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }

    private static func write(
        to defaults: UserDefaults,
        goalHours: Int,
        fastStart: Date?,
        hydrationCups: Int,
        historyCount: Int
    ) {
        defaults.set(goalHours, forKey: keyGoalHours)
        defaults.set(hydrationCups, forKey: keyHydrationCups)
        defaults.set(historyCount, forKey: keyHistoryCount)

        if let fastStart {
            defaults.set(true, forKey: keyFastIsActive)
            defaults.set(fastStart.timeIntervalSince1970, forKey: keyFastStartEpoch)
        } else {
            defaults.set(false, forKey: keyFastIsActive)
            defaults.removeObject(forKey: keyFastStartEpoch)
        }
    }
}

@MainActor
final class FastingViewModel: ObservableObject {
    @Published var goal: FastingGoal = .h18 {
        didSet {
            FastStore.shared.saveGoal(goal)
            syncWidgetBridge()
        }
    }

    @Published var currentFastStart: Date? {
        didSet {
            FastStore.shared.saveCurrentStart(currentFastStart)
            syncWidgetBridge()
        }
    }

    @Published var history: [FastEntry] = [] {
        didSet { syncWidgetBridge() }
    }
    @Published var notificationsEnabled: Bool = false
    @Published var hydrationCups: Int = 0 {
        didSet {
            store.saveHydrationCupsForToday(hydrationCups)
            syncWidgetBridge()
        }
    }

    private let store = FastStore.shared
    private var hydrationDayKey = Date().dayKey()

    init() {
        goal = store.loadGoal()
        history = store.loadEntries()
        currentFastStart = store.loadCurrentStart()
        hydrationDayKey = Date().dayKey()
        hydrationCups = store.loadHydrationCupsForToday()

        store.startListeningForCloudChanges { [weak self] in
            guard let self else { return }
            self.goal = self.store.loadGoal()
            self.history = self.store.loadEntries()
        }

        syncWidgetBridge()
    }

    func availableGoals(isPro: Bool) -> [FastingGoal] {
        isPro ? FastingGoal.allCases : [.h16, .h18]
    }

    func isGoalLocked(_ candidate: FastingGoal, isPro: Bool) -> Bool {
        !availableGoals(isPro: isPro).contains(candidate)
    }

    func selectGoal(_ candidate: FastingGoal, isPro: Bool) {
        guard !isGoalLocked(candidate, isPro: isPro) else { return }
        goal = candidate
    }

    func normalizeGoal(for isPro: Bool) {
        if isGoalLocked(goal, isPro: isPro) {
            goal = .h18
        }
    }

    func startFast(at requestedStart: Date = Date()) {
        let start = min(requestedStart, Date())
        currentFastStart = start
        NotificationManager.shared.scheduleFastComplete(at: start.addingTimeInterval(goal.seconds), goalTitle: goal.title)
    }

    func updateFastStart(to requestedStart: Date) {
        guard currentFastStart != nil else { return }
        let start = min(requestedStart, Date())
        currentFastStart = start
        NotificationManager.shared.scheduleFastComplete(at: start.addingTimeInterval(goal.seconds), goalTitle: goal.title)
    }

    func endFast() {
        guard let start = currentFastStart else { return }
        let end = Date()

        let entry = FastEntry(id: UUID(), startDate: start, endDate: end, goalHours: goal.rawValue)
        history.insert(entry, at: 0)
        store.saveEntries(history)

        currentFastStart = nil
        NotificationManager.shared.cancelFastComplete()
    }

    func cancelFast() {
        currentFastStart = nil
        NotificationManager.shared.cancelFastComplete()
    }

    func delete(_ entry: FastEntry) {
        history.removeAll(where: { $0.id == entry.id })
        store.saveEntries(history)
    }

    func clearAll() {
        history = []
        store.saveEntries(history)
        currentFastStart = nil
        NotificationManager.shared.cancelFastComplete()
    }

    func elapsedSeconds(now: Date) -> TimeInterval {
        guard let start = currentFastStart else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    func progress(now: Date) -> Double {
        let e = elapsedSeconds(now: now)
        return min(1.0, e / goal.seconds)
    }

    func elapsedText(now: Date) -> String {
        let total = Int(elapsedSeconds(now: now))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    func remainingText(now: Date) -> String {
        let remaining = max(0, Int(goal.seconds - elapsedSeconds(now: now)))
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        return "\(h)h \(m)m left"
    }

    func refreshHydrationDayIfNeeded() {
        let today = Date().dayKey()
        guard hydrationDayKey != today else { return }
        hydrationDayKey = today
        hydrationCups = 0
    }

    func hydrationTargetCups(now: Date, goalHours: Int? = nil) -> Int {
        refreshHydrationDayIfNeeded()
        let sessionHours = elapsedSeconds(now: now) / 3600
        let protocolHours = max(sessionHours, Double(goalHours ?? goal.rawValue))

        if protocolHours >= 36 { return 14 }
        if protocolHours >= 24 { return 12 }
        if protocolHours >= 16 { return 10 }
        return 8
    }

    func addHydrationCup() {
        refreshHydrationDayIfNeeded()
        hydrationCups += 1
    }

    func removeHydrationCup() {
        refreshHydrationDayIfNeeded()
        hydrationCups = max(0, hydrationCups - 1)
    }

    func setHydrationCups(_ value: Int) {
        refreshHydrationDayIfNeeded()
        hydrationCups = max(0, value)
    }

    private func syncWidgetBridge() {
        WidgetSyncBridge.push(
            goalHours: goal.rawValue,
            fastStart: currentFastStart,
            hydrationCups: hydrationCups,
            historyCount: history.count
        )
    }

    func enableNotificationsIfNeeded() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        notificationsEnabled = granted
        if !granted { NotificationManager.shared.cancelFastComplete() }
    }

    struct Stats {
        let total: Int
        let successes: Int
        let successRate: Int
        let averageHours: Double
        let longestHours: Double
        let currentStreak: Int
        let longestStreak: Int
    }

    func stats() -> Stats {
        let total = history.count
        let successes = history.filter { $0.metGoal }.count
        let successRate = total == 0 ? 0 : Int(round((Double(successes) / Double(total)) * 100.0))

        let avg = total == 0 ? 0 : history.map(\.durationHours).reduce(0, +) / Double(total)
        let longest = history.map(\.durationHours).max() ?? 0
        let streaks = computeStreaks()

        return Stats(
            total: total,
            successes: successes,
            successRate: successRate,
            averageHours: avg,
            longestHours: longest,
            currentStreak: streaks.current,
            longestStreak: streaks.longest
        )
    }

    private func computeStreaks() -> (current: Int, longest: Int) {
        let successful = history.filter { $0.metGoal }
        guard !successful.isEmpty else { return (0, 0) }

        var days = Set<String>()
        successful.forEach { days.insert($0.endDate.dayKey()) }
        let sortedKeysDesc = days.sorted(by: >)

        func keyToDate(_ key: String) -> Date? {
            let p = key.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            var comps = DateComponents()
            comps.year = p[0]; comps.month = p[1]; comps.day = p[2]
            return Calendar.current.date(from: comps)
        }

        let cal = Calendar.current
        let datesDesc = sortedKeysDesc.compactMap(keyToDate)

        let datesAsc = datesDesc.sorted()
        var longest = 1
        var run = 1
        if datesAsc.count >= 2 {
            for i in 1..<datesAsc.count {
                let prev = datesAsc[i - 1]
                let cur = datesAsc[i]
                if let next = cal.date(byAdding: .day, value: 1, to: prev), next == cur {
                    run += 1
                    longest = max(longest, run)
                } else if prev == cur {
                    continue
                } else {
                    run = 1
                }
            }
        }

        guard let mostRecent = datesDesc.first else { return (0, longest) }
        let today = Date().dayKey()
        let yesterday = (cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()).dayKey()
        let mostKey = mostRecent.dayKey()
        if mostKey != today && mostKey != yesterday { return (0, longest) }

        var current = 1
        if datesDesc.count >= 2 {
            for i in 0..<(datesDesc.count - 1) {
                let d0 = datesDesc[i]
                let d1 = datesDesc[i + 1]
                let diff = cal.dateComponents([.day], from: d1, to: d0).day ?? 999
                if diff == 1 { current += 1 } else { break }
            }
        }

        return (current, longest)
    }
}
// MARK: - Design

enum AppTheme: String, CaseIterable, Identifiable {
    case lite
    case midnight
    case obsidian
    case aurora
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lite: return "Lite"
        case .midnight: return "Midnight Blue"
        case .obsidian: return "Obsidian Black"
        case .aurora: return "Aurora Green"
        case .ember: return "Ember Night"
        }
    }

    var subtitle: String {
        switch self {
        case .lite: return "Full light mode"
        case .midnight: return "Classic CleanFast Pro look"
        case .obsidian: return "High-contrast premium dark"
        case .aurora: return "Cool, calm, modern gradient"
        case .ember: return "Warm elite performance vibe"
        }
    }

    var isLight: Bool {
        self == .lite
    }

    var preferredColorScheme: ColorScheme {
        isLight ? .light : .dark
    }

    var backgroundTop: Color {
        switch self {
        case .lite: return Color(red: 0.93, green: 0.95, blue: 0.99)
        case .midnight: return Color(red: 0.05, green: 0.08, blue: 0.16)
        case .obsidian: return Color(red: 0.03, green: 0.04, blue: 0.08)
        case .aurora: return Color(red: 0.04, green: 0.10, blue: 0.16)
        case .ember: return Color(red: 0.10, green: 0.06, blue: 0.13)
        }
    }

    var backgroundBottom: Color {
        switch self {
        case .lite: return Color(red: 0.85, green: 0.90, blue: 0.97)
        case .midnight: return Color(red: 0.02, green: 0.03, blue: 0.08)
        case .obsidian: return Color(red: 0.01, green: 0.02, blue: 0.05)
        case .aurora: return Color(red: 0.01, green: 0.05, blue: 0.09)
        case .ember: return Color(red: 0.06, green: 0.02, blue: 0.05)
        }
    }

    var glowA: Color {
        switch self {
        case .lite: return Color(red: 0.45, green: 0.63, blue: 0.96)
        case .midnight: return Color(red: 0.27, green: 0.56, blue: 0.96)
        case .obsidian: return Color(red: 0.44, green: 0.52, blue: 0.70)
        case .aurora: return Color(red: 0.15, green: 0.78, blue: 0.62)
        case .ember: return Color(red: 0.92, green: 0.48, blue: 0.33)
        }
    }

    var glowB: Color {
        switch self {
        case .lite: return Color(red: 0.31, green: 0.77, blue: 0.86)
        case .midnight: return Color(red: 0.18, green: 0.72, blue: 0.92)
        case .obsidian: return Color(red: 0.16, green: 0.28, blue: 0.46)
        case .aurora: return Color(red: 0.26, green: 0.63, blue: 0.89)
        case .ember: return Color(red: 0.88, green: 0.62, blue: 0.24)
        }
    }

    var glowC: Color {
        switch self {
        case .lite: return Color(red: 0.97, green: 0.81, blue: 0.46)
        case .midnight: return Color(red: 0.98, green: 0.78, blue: 0.30)
        case .obsidian: return Color(red: 0.62, green: 0.64, blue: 0.74)
        case .aurora: return Color(red: 0.96, green: 0.88, blue: 0.42)
        case .ember: return Color(red: 0.98, green: 0.74, blue: 0.42)
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var selectedTheme: AppTheme = .midnight

    private let themeKey = "clearfast_theme_v1"

    init() {
        load()
        ThemeRuntime.current = selectedTheme
    }

    func select(_ theme: AppTheme) {
        guard selectedTheme != theme else { return }
        selectedTheme = theme
        ThemeRuntime.current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
    }

    private func load() {
        guard let raw = UserDefaults.standard.string(forKey: themeKey),
              let theme = AppTheme(rawValue: raw) else { return }
        selectedTheme = theme
    }
}

enum ThemeRuntime {
    static var current: AppTheme = .midnight
}

enum AppColors {
    static var theme: AppTheme { ThemeRuntime.current }
    static var isLight: Bool { theme.isLight }

    static var bgTop: Color { theme.backgroundTop }
    static var bgBottom: Color { theme.backgroundBottom }

    static var card: Color {
        isLight ? Color.white.opacity(0.76) : Color.white.opacity(0.12)
    }
    static var cardStrong: Color {
        isLight ? Color.white.opacity(0.88) : Color.white.opacity(0.14)
    }
    static var stroke: Color {
        isLight ? Color.black.opacity(0.09) : Color.white.opacity(0.16)
    }
    static var surfaceSoft: Color {
        isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08)
    }
    static var surfaceStrong: Color {
        isLight ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
    }
    static var surfaceSelected: Color {
        isLight ? Color.black.opacity(0.14) : Color.white.opacity(0.22)
    }

    static var textPrimary: Color {
        isLight ? Color(red: 0.10, green: 0.14, blue: 0.22) : Color.white
    }
    static var textSecondary: Color {
        isLight ? Color(red: 0.28, green: 0.33, blue: 0.43) : Color.white.opacity(0.82)
    }

    static let accentA = Color(red: 0.27, green: 0.56, blue: 0.96)
    static let accentB = Color(red: 0.18, green: 0.72, blue: 0.92)

    static let proGold = Color(red: 0.98, green: 0.78, blue: 0.30)
    static let success = Color(red: 0.23, green: 0.84, blue: 0.56)
    static let danger = Color(red: 0.95, green: 0.41, blue: 0.42)
}

struct AppBackground: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        let theme = themeManager.selectedTheme

        ZStack {
            LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            Circle()
                .fill(theme.glowA.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: -120, y: -310)

            Circle()
                .fill(theme.glowB.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 150, y: 280)

            Circle()
                .fill(theme.glowC.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 55)
                .offset(x: 120, y: -260)
        }
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppColors.stroke, lineWidth: 1)
            )
            .shadow(
                color: AppColors.isLight ? Color.black.opacity(0.06) : Color.clear,
                radius: AppColors.isLight ? 10 : 0,
                x: 0,
                y: AppColors.isLight ? 4 : 0
            )
    }
}

enum ButtonTone {
    case accent
    case pro
    case neutral
    case danger
}

struct PrimaryButton: View {
    let title: String
    var tone: ButtonTone = .accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.stroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tone {
        case .pro:
            return .black
        case .neutral where AppColors.isLight:
            return AppColors.textPrimary
        default:
            return .white
        }
    }

    private var background: some View {
        Group {
            switch tone {
            case .accent:
                AppColors.accentA
            case .pro:
                AppColors.proGold
            case .neutral:
                AppColors.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12)
            case .danger:
                AppColors.danger
            }
        }
    }
}

struct TierPill: View {
    let tier: AppTier

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tier == .pro ? "crown.fill" : "bolt.fill")
            Text(tier.title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tier == .pro ? Color.black : AppColors.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tier == .pro ? AppColors.proGold : AppColors.surfaceStrong)
        .clipShape(Capsule())
    }
}

struct LockedTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
            Text("Pro")
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(Color.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColors.proGold)
        .clipShape(Capsule())
    }
}

struct GoalPicker: View {
    let selected: FastingGoal
    let isPro: Bool
    let disabled: Bool
    let onSelect: (FastingGoal) -> Void
    let onLockedTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FastingGoal.allCases) { candidate in
                goalChip(for: candidate)
            }
        }
        .padding(.horizontal, 2)
    }

    private func isLocked(_ candidate: FastingGoal) -> Bool {
        !isPro && ![FastingGoal.h16, FastingGoal.h18].contains(candidate)
    }

    private func chipForeground(locked: Bool, selected: Bool) -> Color {
        if selected { return AppColors.textPrimary }
        if locked {
            return AppColors.isLight ? AppColors.textSecondary : Color.white.opacity(0.72)
        }
        return AppColors.isLight ? AppColors.textPrimary : Color.white.opacity(0.90)
    }

    private func chipBackground(selected: Bool) -> Color {
        if selected { return AppColors.surfaceSelected }
        return AppColors.isLight ? AppColors.surfaceSoft : Color.white.opacity(0.11)
    }

    @ViewBuilder
    private func goalChip(for candidate: FastingGoal) -> some View {
        let locked = isLocked(candidate)
        let isSelected = selected == candidate && !locked

        Button {
            guard !disabled else { return }
            if locked {
                onLockedTap()
            } else {
                onSelect(candidate)
            }
        } label: {
            VStack(spacing: 2) {
                Text(candidate.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(chipForeground(locked: locked, selected: isSelected))
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(chipBackground(selected: isSelected))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppColors.accentB.opacity(0.8) : Color.clear, lineWidth: 1.2)
            )
            .opacity(disabled && !isSelected ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

struct ProgressRingView: View {
    let progress: Double
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.stroke, lineWidth: 16)

            Circle()
                .trim(from: 0, to: max(0.002, min(1.0, progress)))
                .stroke(
                    AngularGradient(colors: [AppColors.accentA, AppColors.proGold, AppColors.accentB, AppColors.accentA], center: .center),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: AppColors.accentA.opacity(0.4), radius: 7, x: 0, y: 3)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(width: 208, height: 208)
    }
}

struct MetricTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ProTeaserCard: View {
    let action: () -> Void

    var body: some View {
        return GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 36, height: 36)
                    .background(AppColors.proGold)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("CleanFast Pro")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("One-time $4.99 unlock for advanced goals and export")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 8)

                Button("Get $4.99") { action() }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.proGold)
                    .foregroundStyle(Color.black)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Root

struct RootTabView: View {
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        let isLight = themeManager.selectedTheme.isLight

        TabView {
            DashboardView()
                .tabItem { Label("Fast", systemImage: "timer") }

            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            CoachView()
                .tabItem { Label("Coach", systemImage: "waveform.path.ecg") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView(showsDoneButton: false)
                .tabItem {
                    Label("Settings", systemImage: subscription.isPro ? "crown.fill" : "gearshape.fill")
                }
        }
        .id(themeManager.selectedTheme.rawValue)
        .tint(isLight ? AppColors.textPrimary : .white)
        .toolbarBackground(isLight ? Color.white : Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(isLight ? .light : .dark, for: .tabBar)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var vm: FastingViewModel
    @EnvironmentObject private var subscription: SubscriptionManager

    @State private var now = Date()
    @State private var selectedStartDate = Date()
    @State private var showPaywall = false
    @State private var showFinishConfirmation = false
    @State private var showHydrationSheet = false
    @State private var showStartInfoSheet = false
    @State private var hydrationPulse = false
    @State private var showHydrationPlusOne = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header

                        if !subscription.isPro {
                            ProTeaserCard {
                                showPaywall = true
                            }
                        }
                        mainTracker
                        dailyMomentumCard
                        quickStats

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .onReceive(tick) {
                    now = $0
                    vm.refreshHydrationDayIfNeeded()
                }
                .onAppear {
                    selectedStartDate = vm.currentFastStart ?? Date()
                    vm.refreshHydrationDayIfNeeded()
                }
                .onChange(of: vm.currentFastStart) { newValue in
                    selectedStartDate = newValue ?? Date()
                }
                .onChange(of: selectedStartDate) { newValue in
                    guard let currentStart = vm.currentFastStart else { return }
                    if abs(currentStart.timeIntervalSince(newValue)) >= 30 {
                        vm.updateFastStart(to: newValue)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showHydrationSheet) {
                NavigationStack {
                    HydrationElectrolytesView(
                        currentHours: vm.elapsedSeconds(now: now) / 3600,
                        goalHours: vm.goal.rawValue,
                        showsDoneButton: true
                    )
                }
            }
            .sheet(isPresented: $showStartInfoSheet) {
                startInfoSheet
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog("Finish this fast?", isPresented: $showFinishConfirmation, titleVisibility: .visible) {
                Button("Complete Fast") {
                    vm.endFast()
                }
                Button("Mark as Ended Early", role: .destructive) {
                    vm.endFast()
                }
                Button("Keep Fasting", role: .cancel) {}
            } message: {
                Text("Choose how to end this session. Either option saves your fast to history.")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CleanFast Pro")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subscription.isPro ? "Elite fasting mode active" : "Build your daily fasting momentum")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            TierPill(tier: subscription.tier)
        }
    }

    private var mainTracker: some View {
        GlassCard {
            VStack(spacing: 14) {
                GoalPicker(
                    selected: vm.goal,
                    isPro: subscription.isPro,
                    disabled: vm.currentFastStart != nil,
                    onSelect: { vm.selectGoal($0, isPro: subscription.isPro) },
                    onLockedTap: { showPaywall = true }
                )

                statusRow
                startTimeEditorRow

                ProgressRingView(
                    progress: vm.progress(now: now),
                    title: vm.elapsedText(now: now),
                    subtitle: vm.currentFastStart == nil ? "Not started" : vm.remainingText(now: now)
                )
                .padding(.top, 4)

                hydrationQuickRow

                if vm.currentFastStart == nil {
                    PrimaryButton(title: "Start Fast", tone: .accent) {
                        vm.startFast(at: selectedStartDate)
                    }
                } else {
                    Button {
                        showFinishConfirmation = true
                    } label: {
                        Label("Finish Fast", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.proGold)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hydrationQuickRow: some View {
        let cups = vm.hydrationCups
        let target = vm.hydrationTargetCups(now: now, goalHours: vm.goal.rawValue)
        let sessionHours = vm.elapsedSeconds(now: now) / 3600
        let hasFast = vm.currentFastStart != nil
        let needsElectrolytes = hasFast && sessionHours >= 16
        let highPriority = hasFast && sessionHours >= 24

        return HStack(spacing: 10) {
            Button {
                showHydrationSheet = true
            } label: {
                HStack(spacing: 9) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "drop.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppColors.accentB)

                        if highPriority {
                            Circle()
                                .fill(AppColors.proGold)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hydration")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("\(cups) / \(target) cups")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(showHydrationPlusOne ? AppColors.accentB : AppColors.textSecondary)
                            .animation(.easeInOut(duration: 0.2), value: showHydrationPlusOne)
                    }

                    if needsElectrolytes {
                        Text("Electrolytes recommended")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.proGold)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button {
                quickAddHydrationCup()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.accentB)
                        .padding(2)
                        .scaleEffect(hydrationPulse ? 1.16 : 1.0)
                        .animation(.spring(response: 0.26, dampingFraction: 0.56), value: hydrationPulse)

                    if showHydrationPlusOne {
                        Text("+1")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppColors.accentA)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -18)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func quickAddHydrationCup() {
        vm.addHydrationCup()

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        withAnimation(.spring(response: 0.26, dampingFraction: 0.56)) {
            hydrationPulse = true
            showHydrationPlusOne = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.easeOut(duration: 0.18)) {
                hydrationPulse = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeInOut(duration: 0.22)) {
                showHydrationPlusOne = false
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.currentFastStart == nil ? "calendar.badge.clock" : "clock.badge.checkmark")
                .font(.system(size: 12, weight: .semibold))
            Text(statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if vm.currentFastStart != nil {
                Button {
                    showStartInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, 2)
    }

    private var startTimeEditorRow: some View {
        HStack(spacing: 7) {
            DatePicker(
                "",
                selection: $selectedStartDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(AppColors.textPrimary)

            DatePicker(
                "",
                selection: $selectedStartDate,
                in: ...Date(),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(AppColors.textPrimary)
        }
        .padding(.horizontal, 2)
    }

    private var statusText: String {
        guard let start = vm.currentFastStart else {
            return "Pick start date & time, then tap Start Fast."
        }
        return "Started \(start.timeOnly())"
    }

    private var startInfoSheet: some View {
        let started = vm.currentFastStart ?? selectedStartDate

        return NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Started")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(started.shortDate())
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(started.timeOnly())
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Text("You can adjust start date and time anytime from the pickers on the Fast tab.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Session Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var quickStats: some View {
        let s = vm.stats()
        return GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(s.successRate)% success")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack(spacing: 8) {
                    quickStatTile(label: "Streak", value: "\(s.currentStreak)d")
                    quickStatTile(label: "Average", value: String(format: "%.1fh", s.averageHours))
                    quickStatTile(label: "Best", value: String(format: "%.1fh", s.longestHours))
                }
            }
        }
    }

    private func quickStatTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var dailyMomentumCard: some View {
        let progress = max(0, min(1, vm.progress(now: now)))
        let milestones = [25, 50, 75, 100]

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Milestones", systemImage: "flag.checkered.2.crossed")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(vm.currentFastStart == nil ? "Ready" : "\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack(spacing: 8) {
                    ForEach(milestones, id: \.self) { percent in
                        milestoneChip(percent: percent, reached: progress >= (Double(percent) / 100.0))
                    }
                }

                if let nextMilestone = nextMilestoneText(progress: progress) {
                    Text(nextMilestone)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.accentB)
                }

                Text(milestoneHint(progress: progress))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func milestoneChip(percent: Int, reached: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(reached ? AppColors.success : AppColors.textSecondary)
            Text("\(percent)%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(reached ? AppColors.textPrimary : AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(reached ? AppColors.surfaceStrong : AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func nextMilestoneText(progress: Double) -> String? {
        guard vm.currentFastStart != nil else { return nil }
        guard progress < 1 else { return "All milestones reached." }

        let milestoneSteps: [Double] = [0.25, 0.5, 0.75, 1.0]
        guard let nextStep = milestoneSteps.first(where: { progress < $0 }) else { return nil }

        let elapsed = vm.elapsedSeconds(now: now)
        let targetAtStep = vm.goal.seconds * nextStep
        let remaining = max(0, targetAtStep - elapsed)
        let percent = Int(nextStep * 100)

        return "Next milestone: \(percent)% in \(shortDurationText(remaining))"
    }

    private func shortDurationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }

    private func milestoneHint(progress: Double) -> String {
        if vm.currentFastStart == nil { return "Start a fast to unlock milestone guidance." }
        switch progress {
        case ..<0.25:
            return "Early phase: hydrate and keep activity light."
        case ..<0.5:
            return "Momentum phase: keep electrolytes steady."
        case ..<0.75:
            return "Focus phase: avoid heavy meal planning right now."
        case ..<1.0:
            return "Final phase: prepare a balanced meal to break your fast."
        default:
            return "Goal reached. Finish when you're ready."
        }
    }
}
// MARK: - Coach

struct CoachView: View {
    @EnvironmentObject private var vm: FastingViewModel
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var now = Date()
    @State private var showPaywall = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let bodyAccent = Color(red: 0.63, green: 0.58, blue: 0.95)
    private let coachAccent = Color(red: 0.22, green: 0.78, blue: 0.74)
    private let hydrationAccent = Color(red: 0.18, green: 0.80, blue: 0.82)
    private let refeedAccent = Color(red: 0.94, green: 0.59, blue: 0.29)

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        coachHeader

                        sectionHeader("Core")
                        benefitsEntryCard
                        safetyGuidanceEntryCard
                        metabolicEntryCard

                        sectionHeader("Advanced")
                        extendedProtocolsEntryCard
                        bodySignalsEntryCard
                        hydrationEntryCard
                        refeedEntryCard

                        coachQuickActionButton

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
                .safeAreaPadding(.top, 6)
                .onReceive(tick) { now = $0 }
            }
            .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var coachHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Coach")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
            Text(subscription.isPro ? "Guidance, signals, hydration, and protocols." : "Safety Guidance is free. Unlock Pro for full coaching tools.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.surfaceSoft)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var coachQuickActionButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            PrimaryButton(
                title: vm.currentFastStart == nil ? "Start Fast" : "Resume Fast",
                tone: .accent
            ) {
                switchToFastTab()
            }

            Text(vm.currentFastStart == nil ? "Jump to Fast tab and begin your session." : "Jump to Fast tab to view your live timer.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 2)
        }
    }

    private var benefitsEntryCard: some View {
        coachEntryTile(
            title: "Fasting Benefits",
            subtitle: "Full timeline, simple language.",
            icon: "sparkles.rectangle.stack",
            accent: AppColors.accentB,
            requiresPro: true
        ) {
            FastingBenefitsTimelineView(currentHours: vm.elapsedSeconds(now: now) / 3600)
        }
    }

    private var safetyGuidanceEntryCard: some View {
        coachEntryTile(
            title: "Safety Guidance",
            subtitle: "Risk groups and stop rules.",
            icon: "cross.case.fill",
            accent: AppColors.danger
        ) {
            SafetyGuidanceView()
        }
    }

    private var metabolicEntryCard: some View {
        let progress = Int(vm.progress(now: now) * 100)
        let hours = vm.elapsedSeconds(now: now) / 3600

        return coachEntryTile(
            title: "Metabolic Coach",
            subtitle: metabolicPhaseText(for: hours),
            icon: "waveform.path.ecg",
            accent: coachAccent,
            badgeText: "\(progress)%",
            metaText: vm.currentFastStart == nil ? nil : "Updated \(coachUpdatedText())",
            highlight: vm.currentFastStart != nil,
            requiresPro: true
        ) {
            MetabolicCoachDetailView(
                currentHours: hours,
                progressPercent: progress,
                hasActiveFast: vm.currentFastStart != nil
            )
        }
    }

    private var extendedProtocolsEntryCard: some View {
        coachEntryTile(
            title: "Extended Protocols",
            subtitle: "36h, 48h, 72h playbooks.",
            icon: "clock.badge.exclamationmark",
            accent: AppColors.proGold,
            badgeText: subscription.isPro ? "READY" : "PRO",
            requiresPro: true
        ) {
            ExtendedProtocolsDetailView()
        }
    }

    private var bodySignalsEntryCard: some View {
        coachEntryTile(
            title: "Body Signals",
            subtitle: "Log symptoms and get smart guidance.",
            icon: "figure.walk.motion",
            accent: bodyAccent,
            requiresPro: true
        ) {
            BodySignalsView(
                currentHours: vm.elapsedSeconds(now: now) / 3600,
                hasActiveFast: vm.currentFastStart != nil
            )
        }
    }

    private var hydrationEntryCard: some View {
        coachEntryTile(
            title: "Hydration & Electrolytes",
            subtitle: "Water and mineral support plan.",
            icon: "drop.circle.fill",
            accent: hydrationAccent,
            requiresPro: true
        ) {
            HydrationElectrolytesView(
                currentHours: vm.elapsedSeconds(now: now) / 3600,
                goalHours: vm.goal.rawValue
            )
        }
    }

    private var refeedEntryCard: some View {
        coachEntryTile(
            title: "Refeed Guide",
            subtitle: "Break your fast safely.",
            icon: "fork.knife.circle.fill",
            accent: refeedAccent,
            requiresPro: true
        ) {
            RefeedGuideView(
                currentHours: vm.elapsedSeconds(now: now) / 3600,
                goalHours: vm.goal.rawValue
            )
        }
    }

    private func switchToFastTab() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController,
              let tab = findTabBarController(in: root) else {
            return
        }
        tab.selectedIndex = 0
    }

    private func findTabBarController(in viewController: UIViewController) -> UITabBarController? {
        if let tab = viewController as? UITabBarController {
            return tab
        }

        if let presented = viewController.presentedViewController,
           let found = findTabBarController(in: presented) {
            return found
        }

        for child in viewController.children {
            if let found = findTabBarController(in: child) {
                return found
            }
        }

        return nil
    }

    private func coachUpdatedText() -> String {
        guard let start = vm.currentFastStart else { return "now" }
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        if elapsed < 60 { return "just now" }

        let minutes = elapsed / 60
        if minutes < 60 {
            return minutes == 1 ? "1m ago" : "\(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "1h ago" : "\(hours)h ago"
        }

        let days = hours / 24
        return days == 1 ? "1d ago" : "\(days)d ago"
    }

    private func metabolicPhaseText(for hours: Double) -> String {
        if vm.currentFastStart == nil {
            return "Start a fast to unlock live coaching."
        }
        switch hours {
        case ..<12:
            return "Early phase: hydrate and stay light."
        case ..<14:
            return "Transition phase: keep electrolytes steady."
        case ..<16:
            return "Fat-adaptation phase: protect sleep."
        case ..<20:
            return "Focus phase: stay consistent."
        case ..<24:
            return "Advanced window: prep your refeed."
        default:
            return "Extended fast zone: use safety checks."
        }
    }

    private func coachEntryTile<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        badgeText: String? = nil,
        metaText: String? = nil,
        highlight: Bool = false,
        requiresPro: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        let locked = requiresPro && !subscription.isPro
        let effectiveBadge = locked ? "PRO" : badgeText

        return GlassCard {
            Group {
                if locked {
                    Button {
                        showPaywall = true
                    } label: {
                        coachTileLabel(
                            title: title,
                            subtitle: subtitle,
                            icon: icon,
                            accent: accent,
                            badgeText: effectiveBadge,
                            metaText: metaText,
                            locked: true
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        destination()
                    } label: {
                        coachTileLabel(
                            title: title,
                            subtitle: subtitle,
                            icon: icon,
                            accent: accent,
                            badgeText: effectiveBadge,
                            metaText: metaText,
                            locked: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke((highlight && !locked) ? accent.opacity(0.40) : Color.clear, lineWidth: 1)
        )
        .opacity(locked ? 0.92 : 1)
    }

    private func coachTileLabel(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        badgeText: String?,
        metaText: String?,
        locked: Bool
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .bold))
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let metaText {
                    Text(metaText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.surfaceStrong)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(locked ? AppColors.textSecondary : accent)
            }
        }
    }
}

struct SafetyGuidanceView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Safety Guidance")
                                .font(.system(size: 23, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("CleanFast Pro is an educational wellness app. It does not diagnose, treat, or replace professional care.")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("If symptoms feel unsafe, stop fasting and seek urgent medical care.")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.danger)
                        }
                    }

                    safetyTile(
                        title: "Who Should Check With A Doctor First",
                        body: "People with diabetes, blood pressure disorders, kidney or heart conditions, pregnancy, breastfeeding, medication use, age under 18, or eating-disorder history."
                    )
                    safetyTile(
                        title: "When To Stop Immediately",
                        body: "Fainting, severe dizziness, confusion, chest pain, persistent vomiting, or severe weakness are stop signs."
                    )
                    safetyTile(
                        title: "Before You Start Any Fast",
                        body: "Plan hydration, electrolyte intake, sleep, and your refeed meal. Start with shorter windows and build gradually."
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Safety Guidance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func safetyTile(title: String, body: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(body)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

struct MetabolicCoachDetailView: View {
    let currentHours: Double
    let progressPercent: Int
    let hasActiveFast: Bool

    private struct Phase {
        let range: String
        let title: String
        let cue: String
        let action: String
    }

    private let phases: [Phase] = [
        .init(range: "0-12h", title: "Foundation", cue: "Hunger waves can be inconsistent.", action: "Hydrate and keep movement easy."),
        .init(range: "12-16h", title: "Transition", cue: "Fuel switching begins for many users.", action: "Use electrolytes and avoid high intensity."),
        .init(range: "16-20h", title: "Focus Window", cue: "Energy can feel steadier.", action: "Stay consistent with sleep and hydration."),
        .init(range: "20-24h", title: "Advanced Window", cue: "Longer-fasting stress can rise.", action: "Prepare a clean refeed strategy."),
        .init(range: "24h+", title: "Extended Territory", cue: "Risk profile is higher for most users.", action: "Use structured safety checks and doctor guidance.")
    ]

    private var currentPhaseIndex: Int {
        if !hasActiveFast { return 0 }
        switch currentHours {
        case ..<12: return 0
        case ..<16: return 1
        case ..<20: return 2
        case ..<24: return 3
        default: return 4
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Live Metabolic Snapshot")
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                Text("\(progressPercent)%")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)
                            }

                            Text(hasActiveFast ? "Current elapsed: \(String(format: "%.1f", currentHours))h" : "No active fast. Start a session to unlock live coaching context.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                        phaseTile(phase, active: index == currentPhaseIndex && hasActiveFast)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Metabolic Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func phaseTile(_ phase: Phase, active: Bool) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(phase.range)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.proGold)
                        .clipShape(Capsule())
                    Spacer()
                    if active {
                        Text("CURRENT")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.success)
                    }
                }
                Text(phase.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(phase.cue)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Action: \(phase.action)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(active ? AppColors.success.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }
}

struct ExtendedProtocolsDetailView: View {
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var showPaywall = false

    private struct ProtocolTile: Identifiable {
        let hours: String
        let title: String
        let details: String
        let refeed: String
        var id: String { hours }
    }

    private let protocols: [ProtocolTile] = [
        .init(hours: "36h", title: "Bridge Protocol", details: "Good transition step after consistent 16h-24h routines.", refeed: "Break with protein, mineral-rich fluids, and moderate carbs."),
        .init(hours: "48h", title: "Deep Reset Protocol", details: "Advanced range with stronger hydration and electrolyte needs.", refeed: "Two-step refeed: light first meal, balanced meal 2-3 hours later."),
        .init(hours: "72h", title: "Prolonged Protocol", details: "High-stress fasting range. Only for experienced users with medical supervision.", refeed: "Structured refeed over 24 hours. Avoid aggressive overeating.")
    ]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Extended Protocols")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if !subscription.isPro { LockedTag() }
                            }
                            Text("Educational playbooks for 36h to 72h fasts. Safety checkpoints are mandatory.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Seek doctor guidance before prolonged fasting.")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.danger)
                        }
                    }

                    ForEach(protocols) { protocolTile in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(protocolTile.hours)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.proGold)
                                    .clipShape(Capsule())
                                Text(protocolTile.title)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(protocolTile.details)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppColors.textSecondary)
                                Text("Refeed: \(protocolTile.refeed)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                        }
                    }

                    if !subscription.isPro {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Unlock Pro To Save Advanced Templates")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("One-time $4.99 unlock for full advanced protocol tools and exports.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppColors.textSecondary)
                                PrimaryButton(title: "Unlock Pro - $4.99", tone: .pro) {
                                    showPaywall = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Extended Protocols")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

struct BodySignalsView: View {
    let currentHours: Double
    let hasActiveFast: Bool

    private enum Symptom: String, CaseIterable, Hashable, Identifiable {
        case headache = "Headache"
        case dizziness = "Dizziness"
        case cold = "Cold feeling"
        case cramps = "Muscle cramps"
        case nausea = "Nausea"
        case weakness = "Weakness"

        var id: String { rawValue }
    }

    @State private var selectedSymptoms: Set<Symptom> = []
    @State private var energy = 3
    @State private var hunger = 3

    private var riskTone: Color {
        if selectedSymptoms.contains(.dizziness) || selectedSymptoms.contains(.weakness) {
            return AppColors.danger
        }
        if selectedSymptoms.contains(.cramps) || selectedSymptoms.contains(.headache) || selectedSymptoms.contains(.nausea) {
            return AppColors.proGold
        }
        return AppColors.success
    }

    private var recommendation: String {
        if selectedSymptoms.contains(.dizziness) || selectedSymptoms.contains(.weakness) {
            return "Red flag: break fast now and seek medical support if symptoms persist."
        }

        if selectedSymptoms.contains(.nausea) {
            return "Pause intensity, hydrate slowly, and consider ending this fast early."
        }

        if selectedSymptoms.contains(.cramps) || selectedSymptoms.contains(.headache) {
            return "Likely low electrolytes. Add sodium + fluids and reassess in 30 minutes."
        }

        if hunger >= 4 && energy <= 2 {
            return "High strain signal. Shorten today and rebuild with a smaller target tomorrow."
        }

        if hasActiveFast {
            return "Status looks stable. Continue hydration and light activity."
        }

        return "No active fast. Start one to unlock real-time symptom context."
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Body Signals Check-In")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text(hasActiveFast ? "Current fast: \(String(format: "%.1f", currentHours))h elapsed" : "No active fast")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)

                            Text("Log symptoms to get immediate, plain-English guidance.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Symptoms")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(Symptom.allCases) { symptom in
                                    let selected = selectedSymptoms.contains(symptom)
                                    Button {
                                        if selected {
                                            selectedSymptoms.remove(symptom)
                                        } else {
                                            selectedSymptoms.insert(symptom)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            Text(symptom.rawValue)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.85)
                                            Spacer(minLength: 0)
                                        }
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(selected ? AppColors.textPrimary : AppColors.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 9)
                                        .background(selected ? AppColors.surfaceSelected : AppColors.surfaceSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How You Feel")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            signalPicker(title: "Energy", value: $energy)
                            signalPicker(title: "Hunger", value: $hunger)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested Action")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(recommendation)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(riskTone.opacity(0.45), lineWidth: 1)
                    )

                    GlassCard {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Medical Disclaimer")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Body Signals is educational guidance only and not medical advice. If symptoms feel unsafe, stop fasting and seek medical care.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.danger)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Body Signals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func signalPicker(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)

            Picker(title, selection: value) {
                ForEach(1...5, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
struct HydrationElectrolytesView: View {
    let currentHours: Double
    let goalHours: Int
    var showsDoneButton: Bool = false

    @EnvironmentObject private var vm: FastingViewModel
    @Environment(\.dismiss) private var dismiss

    private var targetCups: Int {
        vm.hydrationTargetCups(now: Date(), goalHours: goalHours)
    }

    private var hydrationProgress: Double {
        min(1.0, Double(vm.hydrationCups) / Double(max(1, targetCups)))
    }

    private var electrolyteReminder: String? {
        if currentHours >= 24 { return "Electrolytes are strongly recommended in this window." }
        if currentHours >= 16 { return "Electrolytes recommended from this stage onward." }
        return nil
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Hydration & Electrolytes")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Goal: \(targetCups) cups for this fasting window")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)

                            ProgressView(value: hydrationProgress)
                                .tint(AppColors.accentB)

                            HStack(spacing: 12) {
                                Button {
                                    vm.removeHydrationCup()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .buttonStyle(.plain)

                                Text("\(vm.hydrationCups) / \(targetCups) cups")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)

                                Button {
                                    vm.addHydrationCup()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(AppColors.accentB)
                                }
                                .buttonStyle(.plain)
                            }

                            if let electrolyteReminder {
                                Text(electrolyteReminder)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.proGold)
                            }
                        }
                    }

                    mineralTile(
                        title: "Sodium",
                        range: "2-3 g/day (general fasting range)",
                        clue: "Low sodium can feel like headache, fatigue, or dizziness."
                    )
                    mineralTile(
                        title: "Potassium",
                        range: "Food-first approach after fasting",
                        clue: "Focus on balanced refeed foods unless clinician advises supplements."
                    )
                    mineralTile(
                        title: "Magnesium",
                        range: "Evening support may help cramps/sleep",
                        clue: "Use only if appropriate for your health profile."
                    )

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Important")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("This is educational guidance. If symptoms are severe, stop fasting and seek medical care.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.danger)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Hydration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private func mineralTile(title: String, range: String, clue: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(range)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(clue)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
struct RefeedGuideView: View {
    let currentHours: Double
    let goalHours: Int

    private var protocolHours: Double {
        max(currentHours, Double(goalHours))
    }

    private var profileTitle: String {
        switch protocolHours {
        case ..<20: return "Standard Refeed"
        case ..<36: return "Extended Refeed"
        default: return "Prolonged Refeed"
        }
    }

    private var firstStep: String {
        switch protocolHours {
        case ..<20: return "Start with water + a light protein-focused meal."
        case ..<36: return "Start with broth or easy-to-digest protein + vegetables."
        default: return "Break gently: fluids first, then small food portions over several hours."
        }
    }

    private var avoidStep: String {
        switch protocolHours {
        case ..<20: return "Avoid high-sugar foods as first meal."
        case ..<36: return "Avoid heavy fat+sugar combos in first 2-3 hours."
        default: return "Avoid aggressive refeed and large carb load at once."
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Refeed Guide")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Current profile: \(profileTitle)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("How you break a fast is as important as how you run it.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    refeedStep(
                        title: "Step 1 (0-30 min)",
                        text: firstStep,
                        icon: "1.circle.fill"
                    )
                    refeedStep(
                        title: "Step 2 (30-180 min)",
                        text: "Eat a balanced meal with protein, fiber, and steady carbs.",
                        icon: "2.circle.fill"
                    )
                    refeedStep(
                        title: "What to avoid first",
                        text: avoidStep,
                        icon: "exclamationmark.triangle.fill"
                    )

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recovery Check")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("If you feel dizzy, nauseated, or shaky after refeed, slow intake and consider medical guidance.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Refeed Guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func refeedStep(title: String, text: String, icon: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.proGold)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}
struct FastingBenefitsTimelineView: View {
    let currentHours: Double

    private struct BenefitMilestone: Identifiable {
        let hour: Int
        let headline: String
        let plainEnglish: String

        var id: Int { hour }
        var label: String { "\(hour)h" }
    }

    private let milestones: [BenefitMilestone] = [
        .init(hour: 8, headline: "Glucose swings may settle", plainEnglish: "Many people notice fewer random hunger spikes."),
        .init(hour: 12, headline: "Insulin may start to decrease", plainEnglish: "Your body may begin switching from recent food to stored fuel."),
        .init(hour: 14, headline: "Fat oxidation often increases", plainEnglish: "You may rely more on body fat for energy."),
        .init(hour: 16, headline: "Ketone production may rise", plainEnglish: "Some people feel steadier focus as ketones increase."),
        .init(hour: 18, headline: "Autophagy-related cleanup may increase", plainEnglish: "Cell cleanup signals may rise for some people; timing varies."),
        .init(hour: 20, headline: "Metabolic flexibility can deepen", plainEnglish: "Your body may get better at switching between fuel sources."),
        .init(hour: 24, headline: "Repair signaling may become stronger", plainEnglish: "Recovery and refeed quality become more important here."),
        .init(hour: 36, headline: "Extended adaptation phase", plainEnglish: "Energy may dip; hydration and electrolytes matter more."),
        .init(hour: 48, headline: "Deeper ketosis (advanced users)", plainEnglish: "Long fast territory; use structured guidance."),
        .init(hour: 72, headline: "Prolonged fast range", plainEnglish: "Medical supervision is strongly advised.")
    ]

    private var nextMilestone: BenefitMilestone? {
        milestones.first(where: { currentHours < Double($0.hour) })
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Estimated timeline only")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            HStack(spacing: 8) {
                                timelineBadge(title: "Now", value: String(format: "%.1fh", currentHours))
                                if let next = nextMilestone {
                                    timelineBadge(title: "Next", value: next.label)
                                } else {
                                    timelineBadge(title: "Status", value: "72h+")
                                }
                            }

                            Text("Benefits vary by person, sleep, stress, and health status. This is educational, not medical advice.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                        }
                    }

                    ForEach(milestones) { milestone in
                        benefitTile(for: milestone)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Fasting Benefits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func benefitTile(for milestone: BenefitMilestone) -> some View {
        let reached = currentHours >= Double(milestone.hour)
        let isNext = !reached && (nextMilestone?.hour == milestone.hour)

        return HStack(alignment: .top, spacing: 12) {
            Text(milestone.label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppColors.proGold)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.headline)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)

                Text(milestone.plainEnglish)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 4)

            if reached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.success)
                    .padding(.top, 1)
            } else if isNext {
                Image(systemName: "clock.badge")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.accentB)
                    .padding(.top, 1)
            }
        }
        .padding(12)
        .background(reached ? AppColors.surfaceStrong : AppColors.surfaceSoft)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(reached ? AppColors.success.opacity(0.45) : AppColors.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func timelineBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppColors.surfaceSoft)
        .clipShape(Capsule())
    }
}





// MARK: - Progress

struct StatsView: View {
    @EnvironmentObject private var vm: FastingViewModel
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        summaryCard
                        consistencyCard

                        if subscription.isPro {
                            proLabCard
                        } else {
                            lockedInsightsCard
                        }

                        streakRoadmapCard

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
            }
            .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var summaryCard: some View {
        let s = vm.stats()
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Performance Snapshot")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Last 7 days")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(s.successRate)%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("SUCCESS")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    MetricTile(label: "Completed", value: "\(s.successes)")
                    MetricTile(label: "Total", value: "\(s.total)")
                }

                HStack(spacing: 10) {
                    MetricTile(label: "Current streak", value: "\(s.currentStreak)d")
                    MetricTile(label: "Longest streak", value: "\(s.longestStreak)d")
                }
            }
        }
    }

    private var consistencyCard: some View {
        let days = recentSevenDays
        let values = days.map(dayCompletion)
        let consistency = consistencyScore(values: values)

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("7-Day Consistency")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(consistency)%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let value = dayCompletion(for: day)
                        let percent = Int(round(value * 100.0))

                        VStack(spacing: 6) {
                            Text("\(percent)%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)

                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(AppColors.surfaceStrong)
                                    .frame(width: 20, height: 66)

                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppColors.accentB, AppColors.accentA],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 20, height: 66 * max(0.08, value))
                            }

                            Text(weekdaySymbol(for: day))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Text(consistencyHint(score: consistency))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var proLabCard: some View {
        let s = vm.stats()
        let best = vm.history.map(\.durationHours).max() ?? 0
        let avg = s.averageHours
        let preferredStart = preferredStartWindow()
        let thisWeek = consistencyScore(for: recentSevenDays)
        let lastWeek = consistencyScore(for: previousSevenDays)
        let delta = thisWeek - lastWeek
        let monthBest = bestStreakThisMonth()

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Pro Performance Lab")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    TierPill(tier: .pro)
                }

                HStack(spacing: 8) {
                    proTrendChip(
                        title: "Weekly Trend",
                        value: delta == 0 ? "No change" : "\(delta > 0 ? "+" : "")\(delta)% vs last week",
                        positive: delta >= 0
                    )
                    proTrendChip(
                        title: "Best This Month",
                        value: "\(monthBest)d streak",
                        positive: monthBest > 0
                    )
                }

                HStack(spacing: 10) {
                    labTile(label: "Best Fast", value: String(format: "%.1fh", best))
                    labTile(label: "Average", value: String(format: "%.1fh", avg))
                }

                HStack(spacing: 10) {
                    labTile(label: "Preferred Start", value: preferredStart)
                    labTile(label: "Goal Hit Rate", value: "\(s.successRate)%")
                }

                Text(proInsightText(stats: s, weeklyDelta: delta, monthBestStreak: monthBest))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var lockedInsightsCard: some View {
        GlassCard {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppColors.proGold)
                        .frame(width: 36, height: 36)
                        .background(AppColors.surfaceStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Pro Insights")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Heatmaps, trends, and predictive coaching")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: 8)

                    LockedTag()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var streakRoadmapCard: some View {
        let s = vm.stats()
        let target = nextStreakTarget(after: s.currentStreak)
        let progress = min(1.0, Double(s.currentStreak) / Double(max(1, target)))

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Streak Roadmap")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(s.currentStreak)d / \(target)d")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                ProgressView(value: progress)
                    .tint(AppColors.accentB)

                Text(streakHint(current: s.currentStreak, target: target))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func proTrendChip(title: String, value: String, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(positive ? AppColors.success : AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func labTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var recentSevenDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private var previousSevenDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (7..<14).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private func dayCompletion(for day: Date) -> Double {
        let cal = Calendar.current
        let entries = vm.history.filter { cal.isDate($0.endDate, inSameDayAs: day) }
        guard !entries.isEmpty else { return 0 }

        return entries.map { entry in
            let target = Double(max(1, entry.goalHours))
            return min(1.0, entry.durationHours / target)
        }.max() ?? 0
    }

    private func consistencyScore(values: [Double]) -> Int {
        Int(round((values.reduce(0, +) / Double(max(1, values.count))) * 100.0))
    }

    private func consistencyScore(for days: [Date]) -> Int {
        consistencyScore(values: days.map(dayCompletion))
    }

    private func weekdaySymbol(for date: Date) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let idx = max(0, min(symbols.count - 1, Calendar.current.component(.weekday, from: date) - 1))
        return String(symbols[idx].prefix(1))
    }

    private func consistencyHint(score: Int) -> String {
        switch score {
        case ..<25:
            return "Low consistency this week. A shorter target can rebuild momentum quickly."
        case ..<50:
            return "Foundation is forming. Keep your start time stable for 3 days in a row."
        case ..<75:
            return "Solid rhythm. Small evening routine tweaks can push you above 75%."
        default:
            return "Excellent consistency. You are operating at an advanced adherence level."
        }
    }

    private func preferredStartWindow() -> String {
        let cal = Calendar.current
        let hours = vm.history.map { cal.component(.hour, from: $0.startDate) }
        guard !hours.isEmpty else { return "Not enough data" }

        let average = Int(round(Double(hours.reduce(0, +)) / Double(hours.count)))
        let next = (average + 1) % 24
        return "\(hourLabel(average)) - \(hourLabel(next))"
    }

    private func hourLabel(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        let date = Calendar.current.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    private func bestStreakThisMonth() -> Int {
        let cal = Calendar.current
        let now = Date()
        let monthEntries = vm.history.filter {
            $0.metGoal && cal.isDate($0.endDate, equalTo: now, toGranularity: .month)
        }

        let daySet = Set(monthEntries.map { cal.startOfDay(for: $0.endDate) })
        let sortedDays = daySet.sorted()
        guard !sortedDays.isEmpty else { return 0 }

        var best = 1
        var run = 1

        for idx in 1..<sortedDays.count {
            let delta = cal.dateComponents([.day], from: sortedDays[idx - 1], to: sortedDays[idx]).day ?? 0
            if delta == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }

        return best
    }

    private func proInsightText(stats: FastingViewModel.Stats, weeklyDelta: Int, monthBestStreak: Int) -> String {
        if stats.total < 3 {
            return "Complete at least 3 sessions to unlock stronger performance predictions."
        }

        if weeklyDelta < 0 {
            return "Consistency dipped \(abs(weeklyDelta))% vs last week. Use a shorter target for 2-3 sessions to recover momentum."
        }

        if monthBestStreak >= 7 {
            return "Strong month. Your best streak is \(monthBestStreak)d. Keep start time stable to compound results."
        }

        return "Consistency is stable. Push one extra successful day this week to raise your trend line."
    }

    private func nextStreakTarget(after current: Int) -> Int {
        let milestones = [3, 7, 14, 30]
        return milestones.first(where: { current < $0 }) ?? 30
    }

    private func streakHint(current: Int, target: Int) -> String {
        let remaining = max(0, target - current)
        if remaining == 0 {
            return "Milestone reached. Keep going to establish a 30-day elite streak."
        }
        return "\(remaining) more successful day\(remaining == 1 ? "" : "s") to hit your next streak milestone."
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject private var vm: FastingViewModel
    @EnvironmentObject private var subscription: SubscriptionManager

    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showPaywall = false
    @State private var filter: HistoryFilter = .all

    private enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case achieved = "Achieved"
        case endedEarly = "Ended Early"

        var id: String { rawValue }

        func matches(_ entry: FastEntry) -> Bool {
            switch self {
            case .all: return true
            case .achieved: return entry.metGoal
            case .endedEarly: return !entry.metGoal
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        historyCard

                        if !subscription.isPro {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("CSV Export")
                                            .font(.system(.headline, design: .rounded))
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        LockedTag()
                                    }

                                    Text("Export your complete fasting history to CSV for spreadsheet analysis.")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppColors.textSecondary)

                                    PrimaryButton(title: "Unlock Pro - $4.99", tone: .pro) {
                                        showPaywall = true
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
            }
            .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showShare) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var historyCard: some View {
        let allEntries = subscription.isPro ? vm.history : Array(vm.history.prefix(10))
        let displayedEntries = allEntries.filter { filter.matches($0) }
        let stats = vm.stats()

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Fasting Sessions")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    if subscription.isPro {
                        Button {
                            exportURL = CSVExporter.export(entries: vm.history)
                            if exportURL != nil { showShare = true }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(9)
                                .background(AppColors.surfaceStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !vm.history.isEmpty {
                    HStack(spacing: 8) {
                        historyStatTile(label: "Completed", value: "\(stats.successes)")
                        historyStatTile(label: "Success", value: "\(stats.successRate)%")
                        historyStatTile(label: "Avg", value: String(format: "%.1fh", stats.averageHours))
                        historyStatTile(label: "Best", value: String(format: "%.1fh", stats.longestHours))
                    }
                    .padding(.bottom, 2)
                }

                if !allEntries.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(HistoryFilter.allCases) { candidate in
                            Button {
                                filter = candidate
                            } label: {
                                Text(candidate.rawValue)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(filter == candidate ? AppColors.textPrimary : AppColors.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(filter == candidate ? AppColors.surfaceStrong : AppColors.surfaceSoft)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 2)
                }

                if displayedEntries.isEmpty {
                    Text(filter == .all ? "No entries yet. Complete your first fast to start building history." : "No \(filter.rawValue.lowercased()) sessions yet.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(displayedEntries) { entry in
                            HistoryRow(entry: entry) {
                                vm.delete(entry)
                            }
                        }
                    }
                }

                if !subscription.isPro && vm.history.count > allEntries.count {
                    Text("Free plan shows your latest 10 entries.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func historyStatTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}


struct HistoryRow: View {
    let entry: FastEntry
    let onDelete: () -> Void

    private var rawCompletion: Double {
        guard entry.goalHours > 0 else { return 0 }
        return entry.durationHours / Double(entry.goalHours)
    }

    private var progressValue: Double {
        min(1.0, max(0, rawCompletion))
    }

    private var durationText: String {
        durationText(from: entry.duration)
    }

    private var statusTitle: String {
        entry.metGoal ? "Achieved" : "Ended Early"
    }

    private var statusColor: Color {
        entry.metGoal ? AppColors.success : AppColors.danger
    }

    private var goalGapText: String {
        let goalSeconds = TimeInterval(entry.goalHours * 3600)
        let delta = entry.duration - goalSeconds

        if abs(delta) < 60 {
            return "On target."
        }

        let gap = durationText(from: abs(delta))
        return delta >= 0 ? "\(gap) over goal" : "\(gap) short of goal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.endDate.shortDate())
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("\(entry.startDate.timeOnly()) - \(entry.endDate.timeOnly())")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(statusTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                    Text(durationText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(10)
                        .background(AppColors.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                historyPill("Goal \(entry.goalHours)h")
                historyPill("Duration \(durationText)")
            }

            ProgressView(value: progressValue)
                .tint(statusColor)

            Text(goalGapText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(statusColor)

            Text(entry.metGoal ? "Goal achieved. Strong consistency." : "Session ended early. Keep building momentum.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(12)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func historyPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.surfaceStrong)
            .clipShape(Capsule())
    }

    private func durationText(from seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60

        if h == 0 {
            return "\(m)m"
        }
        return "\(h)h \(m)m"
    }
}

// MARK: - Settings & Paywall

struct SettingsView: View {
    let showsDoneButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var vm: FastingViewModel
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var showPaywall = false

    init(showsDoneButton: Bool = true) {
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        settingsSectionHeader("Membership")
                        proAccessTile

                        settingsSectionHeader("App Preferences")
                        settingsTile(
                            title: "Themes",
                            subtitle: "Current: \(themeManager.selectedTheme.title)",
                            icon: "paintpalette.fill",
                            badgeText: themeManager.selectedTheme.title,
                            requiresPro: true,
                            accent: AppColors.accentB
                        ) {
                            ThemeStudioView()
                        }

                        settingsTile(
                            title: "Notifications",
                            subtitle: vm.notificationsEnabled ? "Fast alerts are enabled" : "Fast alerts are disabled",
                            icon: "bell.badge.fill",
                            badgeText: vm.notificationsEnabled ? "ON" : "OFF",
                            accent: vm.notificationsEnabled ? AppColors.success : AppColors.textSecondary
                        ) {
                            NotificationPreferencesView()
                        }

                        settingsTile(
                            title: "Sync & Backup",
                            subtitle: subscription.isPro ? "iCloud sync active" : "Pro feature",
                            icon: "arrow.triangle.2.circlepath.circle.fill",
                            badgeText: subscription.isPro ? "ACTIVE" : "PRO",
                            requiresPro: true,
                            accent: subscription.isPro ? AppColors.success : AppColors.textSecondary
                        ) {
                            SyncBackupView()
                        }

                        settingsSectionHeader("Safety & Data")
                        settingsTile(
                            title: "Legal & Safety",
                            subtitle: "Privacy policy, terms, safety",
                            icon: "doc.text.fill",
                            accent: AppColors.textSecondary
                        ) {
                            LegalCenterView()
                        }

                        settingsTile(
                            title: "Danger Zone",
                            subtitle: "Reset local app data",
                            icon: "exclamationmark.triangle.fill",
                            accent: AppColors.danger,
                            isDestructive: true
                        ) {
                            DangerZoneView()
                        }

                        settingsMetadataCard

                        settingsSectionHeader("Support")
                        supportTile
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.surfaceSoft)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var proAccessTile: some View {
        settingsTile(
            title: "Pro Access",
            subtitle: subscription.isPro ? "One-time purchase active" : "One-time purchase unlock - $4.99",
            icon: "crown.fill",
            badgeText: subscription.isPro ? "ACTIVE" : "$4.99",
            accent: AppColors.proGold
        ) {
            ProAccessView()
        }
    }

    private var settingsMetadataCard: some View {
        GlassCard {
            HStack(spacing: 10) {
                metadataPill(label: "Version", value: appVersion)
                metadataPill(label: "Build", value: appBuild)
                metadataPill(label: "Last Sync", value: lastSyncLabel)
            }
        }
    }

    private var supportTile: some View {
        GlassCard {
            Button {
                if let url = URL(string: "mailto:rajhari@gmail.com?subject=CleanFast%20Support") {
                    openURL(url)
                }
            } label: {
                settingsTileLabel(
                    title: "Contact Support",
                    subtitle: "rajhari@gmail.com",
                    icon: "envelope.fill",
                    badgeText: nil,
                    accent: AppColors.accentB,
                    locked: false,
                    isDestructive: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func metadataPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(AppColors.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var lastSyncLabel: String {
        subscription.isPro ? "Active" : "Local"
    }

    private func settingsTile<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        badgeText: String? = nil,
        requiresPro: Bool = false,
        accent: Color,
        isDestructive: Bool = false,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        let locked = requiresPro && !subscription.isPro

        return GlassCard {
            if locked {
                Button {
                    showPaywall = true
                } label: {
                    settingsTileLabel(
                        title: title,
                        subtitle: subtitle,
                        icon: icon,
                        badgeText: "PRO",
                        accent: accent,
                        locked: true,
                        isDestructive: isDestructive
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    destination()
                } label: {
                    settingsTileLabel(
                        title: title,
                        subtitle: subtitle,
                        icon: icon,
                        badgeText: badgeText,
                        accent: accent,
                        locked: false,
                        isDestructive: isDestructive
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func settingsTileLabel(
        title: String,
        subtitle: String,
        icon: String,
        badgeText: String?,
        accent: Color,
        locked: Bool,
        isDestructive: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(AppColors.surfaceStrong)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isDestructive ? AppColors.danger : AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(isDestructive ? AppColors.danger.opacity(0.85) : AppColors.textSecondary)
            }

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isDestructive ? AppColors.danger : AppColors.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppColors.surfaceStrong)
                    .clipShape(Capsule())
            }

            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isDestructive ? AppColors.danger : AppColors.textSecondary)
        }
    }
}

struct ProAccessView: View {
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pro Access")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("CleanFast Pro is a one-time purchase.")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(subscription.isPro ? "Pro is active on this device." : "Unlock once for $4.99 to enable advanced coaching, goals, and export tools.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    PrimaryButton(title: subscription.isPro ? "Manage Pro" : "Unlock Pro - $4.99", tone: subscription.isPro ? .neutral : .pro) {
                        showPaywall = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Pro Access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

struct NotificationPreferencesView: View {
    @EnvironmentObject private var vm: FastingViewModel
    @State private var requesting = false

    private enum Choice {
        case on
        case off
    }

    private var selected: Choice {
        vm.notificationsEnabled ? .on : .off
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Choose how fasting alerts work.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    GlassCard {
                        VStack(spacing: 8) {
                            radioRow(
                                title: "On",
                                subtitle: "Send fast completion alerts",
                                isSelected: selected == .on
                            ) {
                                guard !requesting else { return }
                                requesting = true
                                Task {
                                    await vm.enableNotificationsIfNeeded()
                                    requesting = false
                                }
                            }

                            radioRow(
                                title: "Off",
                                subtitle: "Disable in-app notification scheduling",
                                isSelected: selected == .off
                            ) {
                                vm.notificationsEnabled = false
                                NotificationManager.shared.cancelFastComplete()
                            }
                        }
                    }

                    if requesting {
                        GlassCard {
                            Text("Requesting permission...")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func radioRow(title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? AppColors.accentB : AppColors.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(AppColors.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SyncBackupView: View {
    @EnvironmentObject private var subscription: SubscriptionManager

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sync & Backup")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(subscription.isPro ? "iCloud sync is active for goals and history." : "Cross-device sync and advanced backup are part of Pro.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Backup")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(subscription.isPro ? "JSON backup export is available in the next update path." : "Unlock Pro to enable full backup/export features.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Sync & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct DangerZoneView: View {
    @EnvironmentObject private var vm: FastingViewModel

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Danger Zone")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Permanent actions. Use with caution.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                            PrimaryButton(title: "Clear All Data", tone: .danger) {
                                vm.clearAll()
                            }
                        }
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Danger Zone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
struct ThemeStudioView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Theme Studio")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Pick the style that fits your fasting routine. Selection applies instantly.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    ForEach(AppTheme.allCases) { theme in
                        themeCard(theme)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let selected = themeManager.selectedTheme == theme

        return Button {
            themeManager.select(theme)
        } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(theme.title)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(theme.subtitle)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.seal.fill" : "circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(selected ? AppColors.success : AppColors.textSecondary)
                    }

                    HStack(spacing: 10) {
                        themeSwatch(theme.backgroundTop)
                        themeSwatch(theme.backgroundBottom)
                        themeSwatch(theme.glowA)
                        themeSwatch(theme.glowB)
                        themeSwatch(theme.glowC)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func themeSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color)
            .frame(height: 28)
    }
}

struct LegalCenterView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Legal & Safety Center")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Review CleanFast Pro medical safety guidance, privacy policy, and terms before using advanced fasting protocols.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)

                            Text("Seek doctor advice before starting prolonged fasts.")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.danger)
                        }
                    }

                    GlassCard {
                        VStack(spacing: 0) {
                            legalLinkRow(title: "Medical Safety", subtitle: "Who should consult a doctor and when to stop fasting", icon: "cross.case.fill") {
                                MedicalSafetyDetailView()
                            }
                            Divider().background(AppColors.stroke)
                            legalLinkRow(title: "Privacy Policy", subtitle: "How CleanFast Pro stores and handles your data", icon: "lock.doc.fill") {
                                PrivacyPolicyView()
                            }
                            Divider().background(AppColors.stroke)
                            legalLinkRow(title: "Terms & Conditions", subtitle: "Rules, limitations, and user responsibilities", icon: "doc.text.fill") {
                                TermsConditionsView()
                            }
                            Divider().background(AppColors.stroke)
                            legalLinkRow(title: "About CleanFast Pro", subtitle: "Developer, mission, privacy model, and copyright", icon: "info.circle.fill") {
                                AboutClearFastView()
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Legal & Safety")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func legalLinkRow<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(AppColors.surfaceStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

struct MedicalSafetyDetailView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Medical Safety Notice")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("CleanFast Pro is an educational wellness app. It is not a medical device and does not provide diagnosis or treatment.")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Always consult a licensed physician before changing your fasting routine.")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.danger)
                        }
                    }

                    legalParagraphCard(
                        title: "Consult A Doctor Before Fasting If You Have",
                        bodyText: "Diabetes, blood pressure disorders, heart disease, kidney disease, eating-disorder history, medication use, pregnancy, breastfeeding, or if you are under 18."
                    )

                    legalParagraphCard(
                        title: "Stop Fasting Immediately If",
                        bodyText: "You experience dizziness, confusion, fainting, persistent vomiting, chest pain, severe weakness, or any symptom that feels unsafe."
                    )

                    legalParagraphCard(
                        title: "Advanced Fasts (36h-72h)",
                        bodyText: "Use advanced protocols only with medical supervision and a structured refeed plan. Do not attempt prolonged fasting without doctor guidance."
                    )
                }
                .padding(16)
            }
        }
        .navigationTitle("Medical Safety")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func legalParagraphCard(title: String, bodyText: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(bodyText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(2)
            }
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Privacy Policy")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Effective date: March 4, 2026")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    legalSection(title: "Data We Store", bodyText: "Fasting goals, start times, completed sessions, and app preferences are stored on your device. If sync is enabled, this data may be mirrored through your iCloud account.")
                    legalSection(title: "No Health Diagnosis", bodyText: "CleanFast Pro does not diagnose, treat, or monitor disease. Your data is used to power charts, reminders, and progress features.")
                    legalSection(title: "Data Sharing", bodyText: "CleanFast Pro does not sell your personal data. CSV exports are created only when you request them and are shared by you.")
                    legalSection(title: "Your Control", bodyText: "You can delete all local data at any time from Settings > Danger Zone > Clear All Data.")
                }
                .padding(16)
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func legalSection(title: String, bodyText: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(bodyText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(2)
            }
        }
    }
}

struct TermsConditionsView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Terms & Conditions")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Effective date: March 4, 2026")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    legalSection(title: "Educational Use Only", bodyText: "CleanFast Pro provides educational wellness guidance. It is not a substitute for professional medical advice.")
                    legalSection(title: "User Responsibility", bodyText: "You are responsible for your fasting decisions, hydration, nutrition, and medical safety. Use the app only in ways appropriate for your health status.")
                    legalSection(title: "Pro Access", bodyText: "Pro unlock is a one-time purchase of $4.99 for eligible premium features on supported versions.")
                    legalSection(title: "Liability Limitation", bodyText: "To the maximum extent permitted by law, CleanFast Pro is not liable for outcomes resulting from misuse, unsafe fasting, or ignoring medical guidance.")
                }
                .padding(16)
            }
        }
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func legalSection(title: String, bodyText: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(bodyText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(2)
            }
        }
    }
}

struct AboutClearFastView: View {
    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About CleanFast Pro")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Independent fasting app by Malar Hari.")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Premium experience, simple guidance, and long-term trust.")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    aboutSection(title: "Developer", bodyText: "CleanFast Pro is created by independent app developer Malar Hari.")

                    aboutSection(title: "Mission", bodyText: "Build a premium fasting app that is practical, safe, and easy to use every day.")

                    aboutSection(title: "Business Model", bodyText: "CleanFast Pro is a one-time payment. No subscriptions. No ads, ever.")

                    aboutSection(title: "Data & Privacy", bodyText: "Your fasting data is stored on your phone by default. If iCloud sync is enabled, data is mirrored through your own Apple account. CleanFast Pro does not sell your personal data.")

                    aboutSection(title: "Copyright", bodyText: "(c) \(currentYear) Malar Hari. All rights reserved.")
                }
                .padding(16)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private func aboutSection(title: String, bodyText: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text(bodyText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(2)
            }
        }
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscription: SubscriptionManager

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        hero

                        featureCard(
                            icon: "flame.fill",
                            title: "Advanced Goals",
                            subtitle: "Unlock 12h to 36h fasting protocols"
                        )

                        featureCard(
                            icon: "square.and.arrow.up",
                            title: "Complete Export",
                            subtitle: "Full CSV export for all your fasting sessions"
                        )

                        featureCard(
                            icon: "chart.bar.xaxis",
                            title: "Behavior Analytics",
                            subtitle: "Adherence insights and trend guidance"
                        )

                        planSelector
                        PrimaryButton(title: "Unlock Pro - $4.99", tone: .pro) { }
                            .disabled(true)
                            .opacity(0.7)

                        Text("Pro purchase activation is pending App Store Connect IAP setup.")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.9))
                            .padding(.top, 4)
                    }
                    .padding(16)
                }
            }
            .toolbarColorScheme(AppColors.isLight ? .light : .dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }

    private var hero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 42, height: 42)
                        .background(AppColors.proGold)
                        .clipShape(Circle())
                    Spacer()
                    TierPill(tier: subscription.tier)
                }

                Text("Train like an athlete. Track like an analyst.")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Pro is built for users who want discipline, precision, and long-term fasting consistency.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func featureCard(icon: String, title: String, subtitle: String) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 34, height: 34)
                    .background(AppColors.proGold)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }
        }
    }

    private var planSelector: some View {
        GlassCard {
            VStack(spacing: 8) {
                ForEach(ProPlan.allCases) { plan in
                    let selected = subscription.selectedPlan == plan
                    Button {
                        subscription.setPlan(plan)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(plan.title)
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(AppColors.textPrimary)
                                    if let badge = plan.badge {
                                        Text(badge)
                                            .font(.system(size: 10, weight: .black, design: .rounded))
                                            .foregroundStyle(Color.black)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(AppColors.proGold)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(plan.priceText)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(selected ? AppColors.accentB : AppColors.textSecondary)
                        }
                        .padding(12)
                        .background(selected ? AppColors.surfaceStrong : AppColors.surfaceSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
