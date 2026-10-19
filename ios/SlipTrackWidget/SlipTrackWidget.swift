import SwiftUI
import WidgetKit

/// Snapshot the app writes into the shared App Group after every change.
struct BudgetSnapshot {
  var remaining = "—"
  var spent = "—"
  var income = "—"
  var percent = 0.0
  var mood = "happy"
  var period = ""
  var hidden = false
  var empty = true

  static func load() -> BudgetSnapshot {
    guard let d = UserDefaults(suiteName: "group.app.sliptrack.sliptrack"),
      let raw = d.dictionary(forKey: "widget.snapshot")
    else { return BudgetSnapshot() }
    return BudgetSnapshot(
      remaining: raw["remaining"] as? String ?? "—",
      spent: raw["spent"] as? String ?? "—",
      income: raw["income"] as? String ?? "—",
      percent: raw["percent"] as? Double ?? 0,
      mood: raw["mood"] as? String ?? "happy",
      period: raw["period"] as? String ?? "",
      hidden: raw["hidden"] as? Bool ?? false,
      empty: raw["empty"] as? Bool ?? true)
  }
}

struct Entry: TimelineEntry {
  let date: Date
  let snapshot: BudgetSnapshot
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Entry {
    Entry(date: .now, snapshot: BudgetSnapshot(
      remaining: "≈ 12,480 THB", spent: "7,520 THB", income: "20,000 THB",
      percent: 0.62, period: "Pay cycle", empty: false))
  }
  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : Entry(date: .now, snapshot: .load()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    // The app reloads timelines on change; refresh hourly as a fallback.
    completion(Timeline(entries: [Entry(date: .now, snapshot: .load())],
      policy: .after(.now.addingTimeInterval(3600))))
  }
}

private let brand = Color(red: 0.118, green: 0.294, blue: 0.227)
private let brandDeep = Color(red: 0.078, green: 0.208, blue: 0.157)
private let mint = Color(red: 0.839, green: 0.922, blue: 0.875)

struct SlipTrackWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: Entry

  var body: some View {
    let s = entry.snapshot
    Group {
      if s.hidden {
        VStack(spacing: 8) {
          Image(systemName: "lock.fill").font(.title2)
          Text("SlipTrack").font(.caption.bold())
        }
        .foregroundStyle(.white)
      } else if family == .systemSmall {
        small(s)
      } else {
        medium(s)
      }
    }
    .containerBackground(for: .widget) {
      LinearGradient(colors: [brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  func small(_ s: BudgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image("cat_\(s.mood)").resizable().scaledToFit().frame(width: 40, height: 40)
        Spacer()
      }
      Spacer(minLength: 0)
      Text("Available").font(.caption2).foregroundStyle(.white.opacity(0.7))
      Text(s.empty ? "Add income" : s.remaining)
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
      bar(s.percent)
    }
  }

  func medium(_ s: BudgetSnapshot) -> some View {
    HStack(spacing: 14) {
      Image("cat_\(s.mood)").resizable().scaledToFit().frame(width: 92, height: 92)
      VStack(alignment: .leading, spacing: 4) {
        Text(s.period).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
        Text(s.empty ? "Add income to start" : s.remaining)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .minimumScaleFactor(0.5).lineLimit(1).foregroundStyle(.white)
        bar(s.percent)
        HStack {
          label("arrow.down.left", s.income)
          Spacer()
          label("arrow.up.right", s.spent)
        }
      }
    }
  }

  func bar(_ value: Double) -> some View {
    GeometryReader { g in
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.18))
        Capsule().fill(mint).frame(width: g.size.width * max(0, min(1, value)))
      }
    }
    .frame(height: 6)
  }

  func label(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 3) {
      Image(systemName: icon).font(.system(size: 9, weight: .bold))
      Text(text).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
    }
    .foregroundStyle(.white.opacity(0.85))
  }
}

@main
struct SlipTrackWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "SlipTrackWidget", provider: Provider()) { entry in
      SlipTrackWidgetView(entry: entry)
    }
    .configurationDisplayName("SlipTrack")
    .description("Money left in this pay cycle, with your cat.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
