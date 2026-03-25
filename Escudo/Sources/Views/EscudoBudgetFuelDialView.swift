//
//  EscudoBudgetFuelDialView.swift
//  Escudo — Budget screen: fuel-gauge metaphor (design spec, screen 08, RECOMMENDED)
//

import CoreData
import SwiftUI

// MARK: - Top-level wrapper used from ActualBudgetView

struct EscudoBudgetFuelSection: View {
    let budget: MainBudget
    @FetchRequest<Transaction> private var transactions: FetchedResults<Transaction>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.dateCreated)]) private var budgets: FetchedResults<Budget>
    @EnvironmentObject var dataController: DataController

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var currency: String = Locale.current.currencyCode ?? "EUR"
    var currencySymbol: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    init(budget: MainBudget) {
        self.budget = budget
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let start = budget.wrappedDate
        req.predicate = NSPredicate(format: "date >= %@ AND income == false AND date <= %@",
                                    start as CVarArg, Date.now as CVarArg)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        _transactions = FetchRequest(fetchRequest: req)
    }

    var totalSpent: Double { transactions.reduce(0) { $0 + $1.amount } }

    var pacePercent: Double {
        let cal = Calendar.current
        let start = budget.wrappedDate
        let end   = budget.endDate
        let total   = cal.dateComponents([.day], from: start, to: end).day ?? 1
        let elapsed = cal.dateComponents([.day], from: start, to: Date.now).day ?? 0
        return Double(elapsed) / Double(max(total, 1))
    }

    var daysLeft: Int {
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: Date.now, to: budget.endDate).day ?? 0)
    }

    var daysElapsed: Int {
        let cal = Calendar.current
        let start = budget.wrappedDate
        return max(1, cal.dateComponents([.day], from: start, to: Date.now).day ?? 1)
    }

    var dailyAvg: Double { totalSpent / Double(daysElapsed) }

    var body: some View {
        VStack(spacing: 0) {
            EscudoBudgetFuelDialView(
                totalSpent: totalSpent,
                budgetAmount: budget.amount,
                pacePercent: pacePercent,
                currencySymbol: currencySymbol
            )

            // Verdict strip
            let pctUsed = budget.amount > 0 ? totalSpent / budget.amount : 0
            let onTrack = pctUsed <= pacePercent + 0.05
            VerdictStrip(onTrack: onTrack, pacePercent: pacePercent, pctUsed: pctUsed)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            // Daily avg tile
            DailyAvgTile(dailyAvg: dailyAvg, daysLeft: daysLeft, currencySymbol: currencySymbol)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // Sub-tanks
            if !budgets.isEmpty {
                EscudoSectionHead(label: "SUB-TANKS")
                ForEach(budgets, id: \.self) { b in
                    SubTankRow(budget: b, currencySymbol: currencySymbol)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Dial graphic

struct EscudoBudgetFuelDialView: View {
    let totalSpent:    Double
    let budgetAmount:  Double
    let pacePercent:   Double
    let currencySymbol: String

    private var pctUsed: Double { budgetAmount > 0 ? min(totalSpent / budgetAmount, 1.0) : 0 }
    private var onTrack: Bool   { pctUsed <= pacePercent + 0.05 }
    private var remaining: Double { max(0, budgetAmount - totalSpent) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w * 0.5
            let cy = h * 0.82
            let r  = w * 0.382          // 130/340 of viewBox width

            ZStack(alignment: .bottom) {
                // Canvas: ticks, danger arc, pace marker, needle, hub
                Canvas { ctx, size in
                    drawDial(ctx: ctx, cx: cx, cy: cy, r: r, pct: pctUsed, pace: pacePercent, onTrack: onTrack)
                }
                .frame(width: w, height: h)

                // E / F labels via Text overlays (easier to style)
                // E on the left
                Text("E")
                    .font(.escudo(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.escudoTextMuted)
                    .position(x: cx - r - 12, y: cy + 14)

                // F on the right (red — danger end)
                Text("F")
                    .font(.escudo(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.escudoNeg)
                    .position(x: cx + r + 12, y: cy + 14)

                // ½ label at top
                Text("½")
                    .font(.escudo(9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.escudoTextMuted)
                    .position(x: cx, y: 24)

                // Center readout — positioned below the hub
                VStack(spacing: 4) {
                    Text("\(currencySymbol)\(amountString(remaining))")
                        .font(.escudo(36, weight: .semibold))
                        .foregroundStyle(Color.escudoText)
                        .monospacedDigit()
                        .tracking(-1.0)

                    Text("LEFT IN TANK · \(Int(round(pctUsed * 100)))% USED")
                        .font(.escudo(9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.escudoTextMuted)
                }
                .position(x: cx, y: cy + 40)
            }
        }
        .aspectRatio(340.0 / 200.0, contentMode: .fit)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 56)   // room for the center readout that extends below
    }

    // MARK: - Canvas draw

    private func drawDial(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, pct: Double, pace: Double, onTrack: Bool) {
        let π = Double.pi

        // 1. Background arc track (light gray)
        var trackPath = Path()
        trackPath.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(trackPath, with: .color(Color.escudoLine), lineWidth: 3)

        // 2. Danger zone arc (last 10%, from 162/180*π offset)
        let dangerStart = 180.0 + 162.0  // degrees
        let dangerEnd   = 360.0
        var dangerPath = Path()
        dangerPath.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                          startAngle: .degrees(dangerStart), endAngle: .degrees(dangerEnd), clockwise: false)
        ctx.stroke(dangerPath, with: .color(Color.escudoNeg), lineWidth: 3)

        // 3. Tick marks (11 ticks: i=0..10)
        for i in 0...10 {
            let angleDeg = 180.0 + Double(i) / 10.0 * 180.0
            let rad = angleDeg * π / 180.0
            let major = i % 5 == 0
            let innerR = r - (major ? 10 : 7)
            let outerR = r + 2
            let x1 = cx + innerR * cos(rad)
            let y1 = cy + innerR * sin(rad)
            let x2 = cx + outerR * cos(rad)
            let y2 = cy + outerR * sin(rad)
            var tick = Path()
            tick.move(to: CGPoint(x: x1, y: y1))
            tick.addLine(to: CGPoint(x: x2, y: y2))
            ctx.stroke(tick, with: .color(major ? Color.escudoText : Color.escudoTextMuted),
                       style: StrokeStyle(lineWidth: major ? 2 : 1))
        }

        // 4. Pace marker (dashed line)
        let paceAngleDeg = 180.0 + pace * 180.0
        let paceRad = paceAngleDeg * π / 180.0
        let pmX1 = cx + (r - 18) * cos(paceRad)
        let pmY1 = cy + (r - 18) * sin(paceRad)
        let pmX2 = cx + (r + 4)  * cos(paceRad)
        let pmY2 = cy + (r + 4)  * sin(paceRad)
        var pacePath = Path()
        pacePath.move(to: CGPoint(x: pmX1, y: pmY1))
        pacePath.addLine(to: CGPoint(x: pmX2, y: pmY2))
        ctx.stroke(pacePath, with: .color(Color.escudoAccent),
                   style: StrokeStyle(lineWidth: 2, dash: [3, 2]))

        // 5. Needle
        let needleAngleDeg = 180.0 + pct * 180.0
        let needleRad = needleAngleDeg * π / 180.0
        let nx = cx + r * cos(needleRad)
        let ny = cy + r * sin(needleRad)
        var needle = Path()
        needle.move(to: CGPoint(x: cx, y: cy))
        needle.addLine(to: CGPoint(x: nx, y: ny))
        let needleColor = onTrack ? Color.escudoAccent : Color.escudoWarn
        ctx.stroke(needle, with: .color(needleColor),
                   style: StrokeStyle(lineWidth: 3, lineCap: .round))

        // 6. Hub: outer ring (bg) + inner dot
        let hubOuter = Path(ellipseIn: CGRect(x: cx - 8, y: cy - 8, width: 16, height: 16))
        ctx.fill(hubOuter, with: .color(Color.escudoBg))
        ctx.stroke(hubOuter, with: .color(Color.escudoText), style: StrokeStyle(lineWidth: 2))
        let hubInner = Path(ellipseIn: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4))
        ctx.fill(hubInner, with: .color(Color.escudoText))
    }

    private func amountString(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }
}

// MARK: - Verdict strip

private struct VerdictStrip: View {
    let onTrack: Bool
    let pacePercent: Double
    let pctUsed: Double

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(onTrack ? Color.escudoAccent : Color.escudoWarn)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(onTrack ? "on track." : "burning hot.")
                    .font(.escudo(13, weight: .semibold))
                    .foregroundStyle(Color.escudoText)
                Text("pace at \(Int(round(pacePercent * 100)))% · you're at \(Int(round(pctUsed * 100)))%")
                    .font(.escudo(11))
                    .foregroundStyle(Color.escudoTextDim)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.escudoSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(onTrack ? Color.escudoAccent : Color.escudoWarn, lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

// MARK: - Daily avg tile

private struct DailyAvgTile: View {
    let dailyAvg: Double
    let daysLeft: Int
    let currencySymbol: String

    private var monthShort: String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        return fmt.string(from: Date.now).uppercased()
    }

    private func amountString(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY AVG · \(monthShort)")
                    .font(.escudo(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.escudoTextMuted)
                Text("\(currencySymbol)\(amountString(dailyAvg))")
                    .font(.escudo(22, weight: .semibold))
                    .foregroundStyle(Color.escudoText)
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                // Days left counter
                Text("\(daysLeft)D LEFT")
                    .font(.escudo(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.escudoTextMuted)
            }
        }
        .padding(14)
        .background(Color.escudoSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.escudoLine, lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

// MARK: - Sub-tank row (per-category budget)

struct SubTankRow: View {
    let budget: Budget
    let currencySymbol: String

    @EnvironmentObject var dataController: DataController

    private var spent: Double {
        let cap = budget.amount
        let left = dataController.getBudgetLeftover(budget: budget)
        return cap - left
    }

    private var cap: Double { budget.amount }
    private var pct: Double { cap > 0 ? min(spent / cap, 1.0) : 0 }
    private var over: Bool   { spent > cap }
    private var overBy: Double { max(0, spent - cap) }

    private let badgeColors: [String] = [
        "#b4b85a", "#c46a4a", "#d9a441", "#9a7a52",
        "#7a8a9a", "#a87a9a", "#8fae6b", "#7f7f7a"
    ]

    private var barColor: Color {
        if over { return Color.escudoNeg }
        return Color(hex: budget.wrappedColour)
    }

    private func amtStr(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                // Name + overspend amount
                HStack(spacing: 6) {
                    Text(budget.wrappedName)
                        .font(.escudo(11, weight: .medium))
                        .foregroundStyle(Color.escudoText)
                        .lineLimit(1)
                    if over {
                        Text("+\(currencySymbol)\(amtStr(overBy))")
                            .font(.escudo(10, weight: .bold))
                            .foregroundStyle(Color.escudoNeg)
                    }
                }
                .frame(width: 110, alignment: .leading)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.escudoSurface2)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor)
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 10)

                // Amount / cap
                HStack(spacing: 0) {
                    Text("\(currencySymbol)\(amtStr(spent))")
                        .font(.escudo(10, weight: over ? .bold : .regular))
                        .foregroundStyle(over ? Color.escudoNeg : Color.escudoTextDim)
                    Text("/\(amtStr(cap))")
                        .font(.escudo(10))
                        .foregroundStyle(Color.escudoTextMuted)
                }
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.escudoLine).frame(height: 1)
        }
    }
}
