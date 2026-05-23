import Foundation

/// Human-friendly relative date helpers ("2 days ago"), used by Home cards
/// and Project detail headers.
enum RelativeDateFormatting {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func relative(from date: Date, to reference: Date = .now) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: reference)
    }

    static func short(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }
}
