//
//  EscudoInsightsBloombergView.swift
//  Escudo — Insights screen: category breakdown
//

import CoreData
import SwiftUI

struct EscudoInsightsBloombergView: View {
    @EnvironmentObject var dataController: DataController

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var currency: String = Locale.current.currencyCode ?? "EUR"
    var sym: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    // Selected period: 0=1W 1=1M 2=3M 3=1Y 4=ALL
    @State private var period: Int = 1

    private let periodLabels = ["1W", "1M", "3M", "1Y", "ALL"]

    private var periodRange: (start: Date, end: Date) {
        let cal = Calendar(identifier: .gregorian)
        let now = Date.now
        let end = cal.date(byAdding: .second, value: 1, to: now) ?? now
        switch period {
        case 0:
            let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now
            return (start, end)
        case 1:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let mEnd  = cal.date(byAdding: .month, value: 1, to: start) ?? end
            return (start, min(mEnd, end))
        case 2:
            let start = cal.date(byAdding: .month, value: -3, to: cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now) ?? now
            return (start, end)
        case 3:
            let start = cal.date(byAdding: .year, value: -1, to: cal.startOfDay(for: now)) ?? now
            return (start, end)
        default:
            return (Date.distantPast, end)
        }
    }

    private var periodLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "d MMM"
        let r = periodRange
        if period == 4 { return "All time" }
        return "\(fmt.string(from: r.start)) – \(fmt.string(from: Date.now))"
    }

    private var categoryRows: [DataController.CategoryInsightRow] {
        let r = periodRange
        return dataController.getCategoryInsights(start: r.start, end: r.end)
    }

    private var currentTotal: Double {
        let r = periodRange
        return dataController.getSpentInRange(start: r.start, end: r.end)
    }
    private var prevTotal: Double { dataController.getCalendarMonthSpent(offset: -1) }
    private var delta: Double     { currentTotal - prevTotal }

    private var prevMonthShort: String {
        let cal = Calendar(identifier: .gregorian)
        let prev = cal.date(byAdding: .month, value: -1, to: Date.now) ?? Date.now
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        return fmt.string(from: prev).lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("INSIGHTS")
                    .font(.escudo(10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.escudoTextMuted)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<periodLabels.count, id: \.self) { i in
                        Button { period = i } label: {
                            EscudoChip(title: periodLabels[i], active: period == i)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            // Hero amount + delta
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(sym)
                        .font(.escudo(13))
                        .foregroundStyle(Color.escudoTextDim)
                    Text(amtInt(currentTotal))
                        .font(.escudo(44, weight: .semibold))
                        .tracking(-1.5)
                        .foregroundStyle(Color.escudoText)
                        .monospacedDigit()
                    Text(".\(centsPart(currentTotal))")
                        .font(.escudo(18))
                        .foregroundStyle(Color.escudoTextDim)
                        .monospacedDigit()

                    Spacer()

                    if period == 1 && prevTotal > 0 {
                        let arrow  = delta <= 0 ? "↘" : "↗"
                        let colour = delta <= 0 ? Color.escudoPos : Color.escudoNeg
                        let pctDelta = abs(delta) / prevTotal * 100
                        Text("\(arrow) \(String(format: "%.1f", pctDelta))% vs \(prevMonthShort)")
                            .font(.escudo(12, weight: .semibold))
                            .foregroundStyle(colour)
                    }
                }
                Text(periodLabel)
                    .font(.escudo(10))
                    .tracking(0.8)
                    .foregroundStyle(Color.escudoTextMuted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // Category rows
            Rectangle()
                .fill(Color.escudoLine)
                .frame(height: 1)

            ForEach(categoryRows, id: \.category.objectID) { row in
                CategoryInsightRow(row: row, sym: sym, totalSpent: currentTotal) {
                    NotificationCenter.default.post(
                        name: .openCategoryLog,
                        object: nil,
                        userInfo: [
                            "categoryURI": row.category.objectID.uriRepresentation().absoluteString,
                            "startDate": periodRange.start as NSDate,
                            "endDate": periodRange.end as NSDate
                        ]
                    )
                }
            }
        }
    }

    private func amtInt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(Int(v))
    }

    private func centsPart(_ v: Double) -> String {
        let cents = Int((v.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d", cents)
    }
}

// MARK: - Category row

private struct CategoryInsightRow: View {
    let row: DataController.CategoryInsightRow
    let sym: String
    let totalSpent: Double
    let onTap: () -> Void

    private var pct: Int { totalSpent > 0 ? Int(round(row.mtdTotal / totalSpent * 100)) : 0 }

    private func amtStr(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: row.category.wrappedColour))
                    .frame(width: 10, height: 10)

                Text(row.category.wrappedName)
                    .font(.escudo(14, weight: .medium))
                    .foregroundStyle(Color.escudoText)
                    .lineLimit(1)

                Spacer()

                Text("\(pct)%")
                    .font(.escudo(11))
                    .foregroundStyle(Color.escudoTextMuted)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)

                Text("\(sym)\(amtStr(row.mtdTotal))")
                    .font(.escudo(14, weight: .semibold))
                    .foregroundStyle(Color.escudoText)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.escudo(11))
                    .foregroundStyle(Color.escudoTextMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.escudoLine).frame(height: 1)
        }
    }
}

// MARK: - Mini sparkline (kept for potential reuse)

struct MiniSparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let max = data.max() ?? 1
            let min = data.min() ?? 0
            let range = max - min

            if data.count >= 2 && range > 0 {
                Path { path in
                    for (i, val) in data.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(data.count - 1)
                        let y = h - h * CGFloat((val - min) / range)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else       { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h / 2))
                    path.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(color.opacity(0.4), lineWidth: 1)
            }
        }
    }
}
