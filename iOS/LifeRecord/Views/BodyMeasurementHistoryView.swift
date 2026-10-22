import SwiftUI

/// Uses the parent's live, demo-aware query, like the body dashboard destination.
struct BodyMeasurementHistoryView: View {
    let metrics: [BodyMetric]

    var body: some View {
        List {
            if metrics.isEmpty {
                ContentUnavailableView("还没有身体测量", systemImage: AppSymbol.weight,
                                       description: Text("在今日页添加体重、体脂率或腰围记录。"))
            }
            ForEach(metrics.sorted { $0.date > $1.date }) { metric in
                NavigationLink { BodyMetricDetailView(entry: metric) } label: {
                    BodyMeasurementRow(metric: metric, showsDate: true)
                }
            }
        }
        .navigationTitle("身体测量记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BodyMeasurementRow: View {
    let metric: BodyMetric
    var showsDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(showsDate
                     ? metric.date.formatted(date: .abbreviated, time: .shortened)
                     : metric.date.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(metric.weight.formatted(.number.precision(.fractionLength(1)))) kg")
                    .font(.headline).monospacedDigit()
            }
            if metric.bodyFat != nil || metric.waist != nil {
                Text([
                    metric.bodyFat.map { "体脂 \($0.formatted(.number.precision(.fractionLength(1)))) %" },
                    metric.waist.map { "腰围 \($0.formatted(.number.precision(.fractionLength(1)))) cm" }
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !metric.note.isEmpty {
                Text(metric.note).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if metric.isDemo {
                Text("示例").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
