import WidgetKit
import SwiftUI

struct ClearFastWidgetEntry: TimelineEntry {
    let date: Date
    let isActive: Bool
    let goalHours: Int
    let elapsedSeconds: TimeInterval
    let remainingSeconds: TimeInterval
    let hydrationCups: Int
    let historyCount: Int

    var progress: Double {
        let goalSeconds = max(1, goalHours * 3600)
        return min(1, max(0, elapsedSeconds / Double(goalSeconds)))
    }

    var progressPercent: Int {
        Int((progress * 100).rounded())
    }
}

struct ClearFastSnapshot {
    private static let appGroupID = "group.com.hari.clearfast"
    private static let keyGoalHours = "widget_goal_hours_v1"
    private static let keyFastStartEpoch = "widget_fast_start_epoch_v1"
    private static let keyFastIsActive = "widget_fast_is_active_v1"
    private static let keyHydrationCups = "widget_hydration_cups_v1"
    private static let keyHistoryCount = "widget_history_count_v1"

    static func load(now: Date = Date()) -> ClearFastWidgetEntry {
        let sharedDefaults = UserDefaults(suiteName: appGroupID)
        let defaults = sharedDefaults ?? .standard

        let goalRaw = defaults.integer(forKey: keyGoalHours)
        let goal = max(1, goalRaw == 0 ? 18 : goalRaw)
        let active = defaults.bool(forKey: keyFastIsActive)
        let hydration = max(0, defaults.integer(forKey: keyHydrationCups))
        let historyCount = max(0, defaults.integer(forKey: keyHistoryCount))

        if active {
            let epoch = defaults.double(forKey: keyFastStartEpoch)
            let start = Date(timeIntervalSince1970: epoch)
            let elapsed = max(0, now.timeIntervalSince(start))
            let remaining = max(0, Double(goal * 3600) - elapsed)

            return ClearFastWidgetEntry(
                date: now,
                isActive: true,
                goalHours: goal,
                elapsedSeconds: elapsed,
                remainingSeconds: remaining,
                hydrationCups: hydration,
                historyCount: historyCount
            )
        }

        return ClearFastWidgetEntry(
            date: now,
            isActive: false,
            goalHours: goal,
            elapsedSeconds: 0,
            remainingSeconds: Double(goal * 3600),
            hydrationCups: hydration,
            historyCount: historyCount
        )
    }
}

struct ClearFastWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClearFastWidgetEntry {
        ClearFastWidgetEntry(
            date: Date(),
            isActive: true,
            goalHours: 18,
            elapsedSeconds: 6_000,
            remainingSeconds: 58_800,
            hydrationCups: 4,
            historyCount: 12
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ClearFastWidgetEntry) -> Void) {
        completion(ClearFastSnapshot.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClearFastWidgetEntry>) -> Void) {
        let entry = ClearFastSnapshot.load()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct ClearFastWidget: Widget {
    let kind: String = "ClearFastWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClearFastWidgetProvider()) { entry in
            ClearFastWidgetView(entry: entry)
        }
        .configurationDisplayName("CleanFast Pro")
        .description("Track your fasting progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClearFastWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClearFastWidgetEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                smallContent
            } else {
                mediumContent
            }
        }
        .padding(14)
        .widgetURL(URL(string: "clearfast://fast"))
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.16, blue: 0.33),
                    Color(red: 0.08, green: 0.10, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var smallContent: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                progressRing(progress: entry.isActive ? entry.progress : 0, size: 100, lineWidth: 8)

                Text(entry.isActive ? "LIVE" : "READY")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(entry.isActive ? Color.cyan.opacity(0.24) : Color.white.opacity(0.16))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                    .offset(x: 6, y: 6)

                VStack(spacing: 2) {
                    Text(entry.isActive ? shortTimeText(entry.elapsedSeconds) : "00:00")
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(entry.isActive ? "elapsed" : "ready")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)

            Text(entry.isActive ? "\(remainingText(entry.remainingSeconds)) left" : "Tap to start fast")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CleanFast Pro")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .foregroundStyle(.white)
                Spacer()
                Text(entry.isActive ? "LIVE" : "READY")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(entry.isActive ? Color.cyan.opacity(0.24) : Color.white.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            if entry.isActive {
                Text(timeText(entry.elapsedSeconds))
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)

                Text("\(remainingText(entry.remainingSeconds)) left • Ends \(endTimeText(entry.date.addingTimeInterval(entry.remainingSeconds)))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white.opacity(0.85))

                ProgressView(value: entry.progress)
                    .tint(.cyan)
            } else {
                Text("Start your next fast")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Goal \(entry.goalHours)h")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Open CleanFast Pro to begin")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private func progressRing(progress: Double, size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.27, green: 0.78, blue: 1.0),
                            Color(red: 0.39, green: 0.58, blue: 1.0),
                            Color(red: 0.98, green: 0.82, blue: 0.34)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private func shortTimeText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func remainingText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        return "\(h)h \(m)m"
    }

    private func endTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
