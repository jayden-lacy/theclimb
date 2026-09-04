import SwiftUI

struct AttentionSummaryReportView: View {
    enum State: Equatable {
        case loading
        case empty
        case loaded(AttentionSummary)
    }

    let state: State

    var body: some View {
        Group {
            switch state {
            case .loading:
                loadingView
            case .empty:
                emptyView
            case .loaded(let summary):
                summaryView(summary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Palette.primaryText)
        .background(Palette.background)
        .preferredColorScheme(.dark)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Palette.accent)

            Text("Building your attention summary")
                .font(.headline)

            Text("Screen Time stays private on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading attention summary")
        .accessibilityHint("Screen Time data stays private on this device.")
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Screen Time Yet", systemImage: "hourglass")
        } description: {
            Text("Use your device normally, then return to see your attention summary.")
        }
        .symbolRenderingMode(.hierarchical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No Screen Time data is available yet.")
        .accessibilityHint("Use your device normally, then return to see your attention summary.")
    }

    private func summaryView(_ summary: AttentionSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(summary)
                weeklyChart(summary)
                metrics(summary)

                if let hour = summary.mostDistractingHour {
                    distractingHour(hour)
                }

                privacyFooter
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func header(_ summary: AttentionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ATTENTION SUMMARY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityAddTraits(.isHeader)

            Text(DurationText.compact(summary.totalScreenTime))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .contentTransition(.numericText())

            Text("Total screen time across the reporting period")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Attention summary. \(DurationText.accessible(summary.totalScreenTime)) total screen time across the reporting period."
        )
    }

    @ViewBuilder
    private func weeklyChart(_ summary: AttentionSummary) -> some View {
        if summary.supportsDailyBreakdown, !summary.days.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last \(summary.days.count) days")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .bottom, spacing: 8) {
                    let maximum = max(
                        summary.days.map(\.screenTime).max() ?? 0,
                        60
                    )

                    ForEach(summary.days) { day in
                        DayBar(day: day, maximum: maximum)
                    }
                }
                .frame(height: 132)
            }
        } else {
            Text("Daily detail needs a daily or hourly Screen Time report.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .accessibilityLabel(
                    "Daily detail is unavailable because this report did not request daily or hourly segments."
                )
        }
    }

    private func metrics(_ summary: AttentionSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 0) {
                    Metric(
                        title: "Daily average",
                        value: DurationText.compact(summary.averageDailyScreenTime),
                        accessibilityValue: DurationText.accessible(summary.averageDailyScreenTime)
                    )

                    divider

                    Metric(
                        title: "Pickups",
                        value: summary.totalPickupCount.formatted(),
                        accessibilityValue: "\(summary.totalPickupCount) pickups"
                    )
                }

                Divider()

                HStack(alignment: .top, spacing: 0) {
                    Metric(
                        title: "Selected apps",
                        value: DurationText.compact(summary.selectedApplicationDuration),
                        accessibilityValue: DurationText.accessible(summary.selectedApplicationDuration)
                    )

                    divider

                    Metric(
                        title: "Selected categories",
                        value: DurationText.compact(summary.selectedCategoryDuration),
                        accessibilityValue: DurationText.accessible(summary.selectedCategoryDuration)
                    )
                }
            }

            VStack(spacing: 16) {
                Metric(
                    title: "Daily average",
                    value: DurationText.compact(summary.averageDailyScreenTime),
                    accessibilityValue: DurationText.accessible(summary.averageDailyScreenTime)
                )
                Metric(
                    title: "Pickups",
                    value: summary.totalPickupCount.formatted(),
                    accessibilityValue: "\(summary.totalPickupCount) pickups"
                )
                Metric(
                    title: "Selected apps",
                    value: DurationText.compact(summary.selectedApplicationDuration),
                    accessibilityValue: DurationText.accessible(summary.selectedApplicationDuration)
                )
                Metric(
                    title: "Selected categories",
                    value: DurationText.compact(summary.selectedCategoryDuration),
                    accessibilityValue: DurationText.accessible(summary.selectedCategoryDuration)
                )
            }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var divider: some View {
        Divider()
            .frame(height: 48)
            .padding(.horizontal, 12)
    }

    private func distractingHour(_ hour: AttentionSummary.DistractingHour) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 38, height: 38)
                .background(Palette.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Most distracting hour")
                    .font(.headline)

                Text(
                    "\(hour.start.formatted(date: .omitted, time: .shortened)) · \(DurationText.compact(hour.screenTime)) active"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Most distracting hour started at \(hour.start.formatted(date: .omitted, time: .shortened)), with \(DurationText.accessible(hour.screenTime)) of screen time."
        )
    }

    private var privacyFooter: some View {
        Label(
            "Only anonymous totals are shared with The Climb.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(
            "Privacy. Only anonymous Screen Time totals are shared with The Climb."
        )
    }
}

private struct DayBar: View {
    let day: AttentionSummary.Day
    let maximum: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let fraction = day.screenTime / maximum

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.accent)
                            .frame(
                                height: max(
                                    day.screenTime > 0 ? 4 : 0,
                                    proxy.size.height * fraction
                                )
                            )
                    }
            }
            .frame(height: 96)

            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(day.date.formatted(.dateTime.weekday(.wide))), \(DurationText.accessible(day.screenTime)) screen time and \(day.pickupCount) pickups."
        )
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let accessibilityValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(accessibilityValue)")
    }
}

private enum DurationText {
    static func compact(_ duration: TimeInterval) -> String {
        formatter(unitsStyle: .abbreviated).string(from: max(0, duration)) ?? "0m"
    }

    static func accessible(_ duration: TimeInterval) -> String {
        formatter(unitsStyle: .full).string(from: max(0, duration)) ?? "0 minutes"
    }

    private static func formatter(
        unitsStyle: DateComponentsFormatter.UnitsStyle
    ) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = unitsStyle
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }
}

private enum Palette {
    static let background = Color(red: 7 / 255, green: 11 / 255, blue: 22 / 255)
    static let primaryText = Color(red: 247 / 255, green: 247 / 255, blue: 245 / 255)
    static let accent = Color(red: 169 / 255, green: 203 / 255, blue: 255 / 255)
}
