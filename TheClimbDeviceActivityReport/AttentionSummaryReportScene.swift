import DeviceActivity
import Foundation
import SwiftUI

extension DeviceActivityReport.Context {
    static let theClimbAttentionSummary = Self("the-climb.attention-summary")
}

struct AttentionSummaryReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .theClimbAttentionSummary
    let content: (AttentionSummaryReportView.State) -> AttentionSummaryReportView

    init(
        content: @escaping (AttentionSummaryReportView.State) -> AttentionSummaryReportView = {
            AttentionSummaryReportView(state: $0)
        }
    ) {
        self.content = content
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> AttentionSummaryReportView.State {
        let summary = await AttentionSummaryAggregator().makeSummary(from: data)
        AttentionSummaryStore().save(summary)
        return summary.isEmpty ? .empty : .loaded(summary)
    }
}

private struct AttentionSummaryAggregator {
    private enum Resolution {
        case hourly
        case daily
        case weekly

        var supportsDailyBreakdown: Bool {
            self != .weekly
        }
    }

    private struct SegmentAggregate {
        let interval: DateInterval
        let resolution: Resolution
        let screenTime: TimeInterval
        let pickupCount: Int
        let applicationDuration: TimeInterval
        let categoryDuration: TimeInterval
    }

    private struct DayAggregate {
        var screenTime: TimeInterval = 0
        var pickupCount = 0
    }

    private let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func makeSummary(
        from results: DeviceActivityResults<DeviceActivityData>
    ) async -> AttentionSummary {
        var segments: [SegmentAggregate] = []

        for await activityData in results {
            let resolution = resolution(for: activityData.segmentInterval)

            for await segment in activityData.activitySegments {
                var applicationDuration: TimeInterval = 0
                var categoryDuration: TimeInterval = 0
                var pickupCount = segment.totalPickupsWithoutApplicationActivity

                for await category in segment.categories {
                    categoryDuration += category.totalActivityDuration

                    for await application in category.applications {
                        applicationDuration += application.totalActivityDuration
                        pickupCount += application.numberOfPickups
                    }
                }

                segments.append(
                    SegmentAggregate(
                        interval: segment.dateInterval,
                        resolution: resolution,
                        screenTime: max(0, segment.totalActivityDuration),
                        pickupCount: max(0, pickupCount),
                        applicationDuration: max(0, applicationDuration),
                        categoryDuration: max(0, categoryDuration)
                    )
                )
            }
        }

        return makeSummary(from: segments)
    }

    private func makeSummary(from allSegments: [SegmentAggregate]) -> AttentionSummary {
        guard
            let intervalStart = allSegments.map(\.interval.start).min(),
            let intervalEnd = allSegments.map(\.interval.end).max()
        else {
            return .empty()
        }

        let anchorDay = calendar.startOfDay(for: intervalEnd.addingTimeInterval(-1))
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: anchorDay) ?? anchorDay
        let sevenDayEnd = calendar.date(byAdding: .day, value: 1, to: anchorDay) ?? intervalEnd
        let reportingInterval = DateInterval(start: sevenDayStart, end: sevenDayEnd)
        let segments = allSegments.filter { $0.interval.intersects(reportingInterval) }

        var days: [Date: DayAggregate] = [:]
        var hours: [Date: TimeInterval] = [:]
        var supportsDailyBreakdown = true

        for segment in segments {
            supportsDailyBreakdown = supportsDailyBreakdown
                && segment.resolution.supportsDailyBreakdown

            if segment.resolution.supportsDailyBreakdown {
                let day = calendar.startOfDay(for: segment.interval.start)
                var aggregate = days[day, default: DayAggregate()]
                aggregate.screenTime += segment.screenTime
                aggregate.pickupCount += segment.pickupCount
                days[day] = aggregate
            }

            if segment.resolution == .hourly {
                let hour = calendar.dateInterval(
                    of: .hour,
                    for: segment.interval.start
                )?.start ?? segment.interval.start
                hours[hour, default: 0] += segment.screenTime
            }
        }

        let coveredDayCount = max(
            1,
            min(
                7,
                (calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: intervalStart),
                    to: anchorDay
                ).day ?? 0) + 1
            )
        )

        let orderedDays: [AttentionSummary.Day]
        if supportsDailyBreakdown {
            orderedDays = (0..<coveredDayCount).compactMap { offset in
                guard
                    let date = calendar.date(
                        byAdding: .day,
                        value: offset - coveredDayCount + 1,
                        to: anchorDay
                    )
                else {
                    return nil
                }

                let aggregate = days[date, default: DayAggregate()]
                return AttentionSummary.Day(
                    date: date,
                    screenTime: aggregate.screenTime,
                    pickupCount: aggregate.pickupCount
                )
            }
        } else {
            orderedDays = []
        }

        let totalScreenTime = segments.reduce(0) { $0 + $1.screenTime }
        let totalPickupCount = segments.reduce(0) { $0 + $1.pickupCount }
        let selectedApplicationDuration = segments.reduce(0) {
            $0 + $1.applicationDuration
        }
        let selectedCategoryDuration = segments.reduce(0) {
            $0 + $1.categoryDuration
        }
        let mostDistractingHour = hours.max { lhs, rhs in
            lhs.value < rhs.value
        }.map {
            AttentionSummary.DistractingHour(start: $0.key, screenTime: $0.value)
        }

        return AttentionSummary(
            version: AttentionSummary.schemaVersion,
            generatedAt: .now,
            intervalStart: max(intervalStart, reportingInterval.start),
            intervalEnd: min(intervalEnd, reportingInterval.end),
            days: orderedDays,
            totalScreenTime: totalScreenTime,
            averageDailyScreenTime: totalScreenTime / Double(coveredDayCount),
            totalPickupCount: totalPickupCount,
            selectedApplicationDuration: selectedApplicationDuration,
            selectedCategoryDuration: selectedCategoryDuration,
            mostDistractingHour: mostDistractingHour,
            supportsDailyBreakdown: supportsDailyBreakdown
        )
    }

    private func resolution(
        for segmentInterval: DeviceActivityFilter.SegmentInterval
    ) -> Resolution {
        switch segmentInterval {
        case .hourly:
            return .hourly
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        @unknown default:
            return .weekly
        }
    }
}
