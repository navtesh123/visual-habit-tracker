// PRD §3.7 / M9 — Home-screen widget. Medium family only in v1 (the size
// that fits a horizontal "photo + meta" layout cleanly). Tapping the photo
// region deep-links into the app's camera for the pinned project.

import WidgetKit
import SwiftUI
import UIKit

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedConstants.widgetKind,
            provider: ProgressTimelineProvider()
        ) { entry in
            ProgressWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetNeon.midnightAbyss
                }
        }
        .configurationDisplayName("Progress")
        .description("Your latest progress photo, at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Timeline provider

struct ProgressTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressWidgetEntry {
        ProgressWidgetEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressWidgetEntry) -> Void) {
        completion(ProgressWidgetEntry.load() ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressWidgetEntry>) -> Void) {
        let entry = ProgressWidgetEntry.load() ?? .placeholder
        // Refresh every 30 minutes — main app also kicks
        // `WidgetCenter.shared.reloadTimelines` on every photo save.
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Entry

struct ProgressWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let image: UIImage?

    static let placeholder = ProgressWidgetEntry(
        date: .now,
        snapshot: WidgetSnapshot(
            schema: WidgetSnapshot.currentSchema,
            projectID: nil,
            projectName: "Your project",
            accentTokenRaw: "amethystGlow",
            photoCount: 0,
            lastCaptureAt: nil,
            cumulativeThisMonth: 0,
            latestPhotoJPEGRelativePath: nil
        ),
        image: nil
    )

    static func load() -> ProgressWidgetEntry? {
        guard let containerURL = WidgetSharedConstants.appGroupContainerURL() else { return nil }
        let snapshotURL = containerURL.appendingPathComponent(WidgetSharedConstants.snapshotFilename)
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        var image: UIImage?
        if let path = snapshot.latestPhotoJPEGRelativePath {
            let imageURL = containerURL.appendingPathComponent(path)
            if let imageData = try? Data(contentsOf: imageURL) {
                image = UIImage(data: imageData)
            }
        }
        return ProgressWidgetEntry(date: .now, snapshot: snapshot, image: image)
    }
}

// MARK: - View

struct ProgressWidgetView: View {
    let entry: ProgressWidgetEntry

    var body: some View {
        // Tap on the whole widget routes to capture for the pinned project.
        Link(destination: WidgetSharedConstants.captureURL(for: entry.snapshot.projectID)) {
            HStack(spacing: 12) {
                photoBlock
                metaBlock
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var photoBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = entry.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                WidgetNeon.accent(forTokenRaw: entry.snapshot.accentTokenRaw).opacity(0.4)
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(WidgetNeon.ghostWhite)
            }
        }
        .frame(width: 110, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    WidgetNeon.accent(forTokenRaw: entry.snapshot.accentTokenRaw),
                    lineWidth: 2
                )
        )
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.projectName)
                .font(.system(.title3, design: .default, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(WidgetNeon.ghostWhite)

            if entry.snapshot.cumulativeThisMonth > 0 {
                Text("\(entry.snapshot.cumulativeThisMonth) photos this month")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(WidgetNeon.ghostWhite.opacity(0.7))
            } else if let date = entry.snapshot.lastCaptureAt {
                Text("Last shot \(relative(date))")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(WidgetNeon.ghostWhite.opacity(0.7))
            } else {
                Text("No photos yet")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(WidgetNeon.ghostWhite.opacity(0.7))
            }

            Spacer(minLength: 0)

            // Visual CTA. The Link covers the whole widget so this is purely
            // an affordance, not a separate tap target (static widgets only
            // get one Link in iOS 17+/26).
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                Text("Tap to capture")
            }
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(WidgetNeon.midnightAbyss)
            .background(WidgetNeon.limeSqueeze, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
