#if os(iOS)
import SwiftUI
import WidgetKit

private enum WidgetStorage {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let storageKey = "the-climb.snapshot.v1"
}

struct ClimbWidgetEntry: TimelineEntry {
    let date: Date
    let missionTitle: String
    let missionSummary: String
    let missionStatus: String
    let durationMinutes: Int
    let streak: Int
    let streakGoal: Int
    let ovr: Int
    let isConfigured: Bool

    static let placeholder = ClimbWidgetEntry(
        date: Date(),
        missionTitle: "No phone for 1 hour after waking",
        missionSummary: "Start clean. Win the first hour.",
        missionStatus: "Pending",
        durationMinutes: 60,
        streak: 14,
        streakGoal: 30,
        ovr: 78,
        isConfigured: true
    )

    static let empty = ClimbWidgetEntry(
        date: Date(),
        missionTitle: "Build your climb",
        missionSummary: "Open The Climb to create today’s mission.",
        missionStatus: "Ready",
        durationMinutes: 0,
        streak: 0,
        streakGoal: 7,
        ovr: 50,
        isConfigured: false
    )
}

struct ClimbWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClimbWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ClimbWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClimbWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(60 * 20)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> ClimbWidgetEntry {
        guard let defaults = UserDefaults(suiteName: WidgetStorage.appGroupID),
              let data = defaults.data(forKey: WidgetStorage.storageKey) else {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let snapshot = try? decoder.decode(WidgetAppStateSnapshot.self, from: data),
              let profile = snapshot.profile else {
            return .empty
        }

        let mission = snapshot.missions.first { Calendar.current.isDateInToday($0.date) }
            ?? snapshot.missions.sorted { $0.date > $1.date }.first

        return ClimbWidgetEntry(
            date: Date(),
            missionTitle: mission?.title ?? "Today’s mission is ready",
            missionSummary: mission?.summary ?? "Open The Climb to start your discipline rhythm.",
            missionStatus: mission?.status.capitalized ?? "Ready",
            durationMinutes: mission?.durationMinutes ?? 0,
            streak: profile.currentStreak,
            streakGoal: profile.streakGoal,
            ovr: profile.ovrScore,
            isConfigured: true
        )
    }
}

struct TheClimbWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ClimbWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidget
        case .accessoryCircular:
            circularWidget
        case .accessoryRectangular:
            rectangularWidget
        case .accessoryInline:
            inlineWidget
        default:
            smallWidget
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader
            Spacer(minLength: 0)
            Text(entry.missionTitle)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
            ProgressBar(value: streakProgress)
                .frame(height: 5)
            HStack {
                Label("\(entry.streak)", systemImage: "flame.fill")
                Spacer()
                Label("\(entry.ovr)", systemImage: "gauge.with.dots.needle.67percent")
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white.opacity(0.78))
        }
        .padding(16)
        .widgetBackground()
    }

    private var mediumWidget: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                widgetHeader
                Text(entry.missionTitle)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(entry.missionSummary)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    WidgetBadge(text: entry.missionStatus, symbol: "flag.fill", tint: .green)
                    if entry.durationMinutes > 0 {
                        WidgetBadge(text: "\(entry.durationMinutes)m", symbol: "timer", tint: .white.opacity(0.72))
                    }
                }
            }

            VStack(spacing: 12) {
                ScoreRing(value: Double(entry.ovr) / 100, label: "\(entry.ovr)", caption: "OVR")
                    .frame(width: 76, height: 76)
                VStack(spacing: 5) {
                    ProgressBar(value: streakProgress)
                        .frame(width: 82, height: 5)
                    Text("\(entry.streak)/\(max(entry.streakGoal, 1)) streak")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .padding(16)
        .widgetBackground()
    }

    private var circularWidget: some View {
        Gauge(value: Double(entry.ovr), in: 0...100) {
            Image(systemName: "mountain.2.fill")
        } currentValueLabel: {
            Text("\(entry.ovr)")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.green)
        .containerBackground(.black, for: .widget)
    }

    private var rectangularWidget: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("The Climb")
                .font(.caption2.weight(.semibold))
            Text(entry.missionTitle)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Text("\(entry.streak) day streak · \(entry.ovr) OVR")
                .font(.caption2)
        }
        .containerBackground(.black, for: .widget)
    }

    private var inlineWidget: some View {
        Text("The Climb: \(entry.streak) streak · \(entry.ovr) OVR")
    }

    private var widgetHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "mountain.2.fill")
                .foregroundStyle(.green)
            Text("The Climb")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 0)
            if !entry.isConfigured {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var streakProgress: Double {
        guard entry.streakGoal > 0 else { return 0 }
        return min(Double(entry.streak) / Double(entry.streakGoal), 1)
    }
}

struct TheClimbWidget: Widget {
    let kind = "TheClimbWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClimbWidgetProvider()) { entry in
            TheClimbWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("The Climb")
        .description("Today’s mission, streak, and OVR.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct WidgetAppStateSnapshot: Decodable {
    let profile: WidgetProfile?
    let missions: [WidgetMission]
}

private struct WidgetProfile: Decodable {
    let streakGoal: Int
    let ovrScore: Int
    let currentStreak: Int
}

private struct WidgetMission: Decodable {
    let date: Date
    let title: String
    let summary: String
    let durationMinutes: Int
    let status: String
}

private struct WidgetBadge: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(.green)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
    }
}

private struct ScoreRing: View {
    let value: Double
    let label: String
    let caption: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(caption)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }
}

private extension View {
    func widgetBackground() -> some View {
        containerBackground(for: .widget) {
            ZStack {
                Color.black
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.11, blue: 0.14),
                        Color.black,
                        Color.green.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}
#endif
