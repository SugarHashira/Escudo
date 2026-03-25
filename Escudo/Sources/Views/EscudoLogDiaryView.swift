//
//  EscudoLogDiaryView.swift
//  Escudo — Log variant: money diary / narrative feed (design spec, screen 03)
//

import CoreData
import SwiftUI

struct EscudoLogDiaryView: View {
    var bottomEdge: CGFloat

    @EnvironmentObject var dataController: DataController
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var currency: String = Locale.current.currencyCode ?? "EUR"
    var sym: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    // Last 14 days of transactions
    @FetchRequest private var transactions: FetchedResults<Transaction>

    init(bottomEdge: CGFloat) {
        self.bottomEdge = bottomEdge
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: Date.now)) ?? Date.now
        req.predicate = NSPredicate(format: "date >= %@", cutoff as CVarArg)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        _transactions = FetchRequest(fetchRequest: req)
    }

    // Group by day, compute narrative
    struct DiaryEntry: Identifiable {
        let id: Date
        let date: Date
        let label: String          // TODAY / YESTERDAY / MON
        let dayLabel: String       // Tue 21
        let tone: String           // steady / heavy / light / quiet
        let headline: String
        let body: String
        let tags: [String]
        let netDelta: Double       // + = net positive (income > expense)
        let totalSpent: Double
    }

    private var weekSummary: String {
        let cal = Calendar(identifier: .gregorian)
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date.now)) else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return "week of \(fmt.string(from: weekStart))"
    }

    private var weekUnderBudget: Bool {
        // Simplified: just check if expenses are low
        let weekExpenses = transactions.filter { !$0.income }.reduce(0) { $0 + $1.amount }
        return weekExpenses < 300
    }

    private var entries: [DiaryEntry] {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date.now)

        // Group by day
        var byDay: [Date: [Transaction]] = [:]
        for tx in transactions {
            guard let d = tx.date else { continue }
            let day = cal.startOfDay(for: d)
            byDay[day, default: []].append(tx)
        }

        return byDay.keys.sorted(by: >).prefix(10).compactMap { day -> DiaryEntry? in
            guard let txns = byDay[day], !txns.isEmpty else { return nil }
            let expense = txns.filter { !$0.income }.reduce(0) { $0 + $1.amount }
            let income  = txns.filter {  $0.income }.reduce(0) { $0 + $1.amount }
            let net     = income - expense

            // Day label
            let dayLabel: String
            if cal.isDate(day, inSameDayAs: today) {
                dayLabel = "TODAY"
            } else if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                      cal.isDate(day, inSameDayAs: yesterday) {
                dayLabel = "YESTERDAY"
            } else {
                let fmt = DateFormatter(); fmt.dateFormat = "EEE"
                dayLabel = fmt.string(from: day).uppercased()
            }

            let fmt2 = DateFormatter(); fmt2.dateFormat = "EEE d"
            let shortDay = fmt2.string(from: day)

            // Tone based on net
            let tone: String
            if income > 0 && expense < income * 0.5 { tone = "heavy" }  // income day
            else if expense > 150 { tone = "heavy" }
            else if expense < 20  { tone = "quiet" }
            else { tone = "steady" }

            // Headline
            let headline: String
            if income > 200 {
                headline = "Payday. \(sym)\(amtInt(income)) in."
            } else if expense > 150 {
                headline = "Heavy spending day."
            } else if expense < 5 && income == 0 {
                headline = "A quiet day."
            } else {
                headline = "A steady day."
            }

            // Body
            let topExpense = txns.filter { !$0.income }.sorted { $0.amount > $1.amount }.first
            let body: String
            if income > 0 && expense == 0 {
                body = "\(sym)\(amtInt(income)) arrived — \(txns.first?.category?.wrappedName ?? "income")."
            } else if let top = topExpense {
                let others = txns.filter { !$0.income }.count - 1
                let othersStr = others > 0 ? " and \(others) other\(others > 1 ? "s" : "")" : ""
                body = "Spent \(sym)\(amtStr(expense)) — \(top.wrappedNote)\(othersStr)."
            } else {
                body = "No expenses recorded."
            }

            // Tags from category names
            let tags = Array(Set(txns.compactMap { $0.category?.wrappedName })).prefix(3).map { $0.lowercased() }

            return DiaryEntry(
                id: day, date: day,
                label: dayLabel, dayLabel: shortDay,
                tone: tone, headline: headline, body: body,
                tags: Array(tags), netDelta: net, totalSpent: expense
            )
        }
    }

    private func amtInt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(Int(v))
    }

    private func amtStr(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("MONEY DIARY")
                    .font(.escudo(10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.escudoTextMuted)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(weekSummary)
                        .font(.escudo(20, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.escudoText)
                    Text("·")
                        .foregroundStyle(Color.escudoTextMuted)
                    Text(weekUnderBudget ? "you're under." : "watch spending.")
                        .font(.escudo(20, weight: .semibold))
                        .foregroundStyle(weekUnderBudget ? Color.escudoAccent : Color.escudoWarn)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Diary entries with timeline rail
            ZStack(alignment: .topLeading) {
                // Rail line
                Rectangle()
                    .fill(Color.escudoLine)
                    .frame(width: 1)
                    .padding(.leading, 23)

                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        DiaryCard(entry: entry, sym: sym)
                    }
                    Spacer(minLength: bottomEdge + 80)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Diary entry card

private struct DiaryCard: View {
    let entry: EscudoLogDiaryView.DiaryEntry
    let sym: String

    private func amtStr(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: abs(v))) ?? String(format: "%.2f", abs(v))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline dot
            VStack(spacing: 0) {
                Circle()
                    .fill(entry.tone == "heavy" ? Color.escudoAccent : Color.escudoTextDim)
                    .frame(width: 7, height: 7)
                    .padding(.top, 14)
                    .padding(.leading, 0.5)
            }
            .frame(width: 16)

            // Card content
            VStack(alignment: .leading, spacing: 6) {
                // Day label + delta
                HStack {
                    Text("\(entry.label) · \(entry.dayLabel)")
                        .font(.escudo(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.escudoTextMuted)
                    Spacer()
                    Text("\(entry.netDelta >= 0 ? "+" : "−")\(sym)\(amtStr(entry.netDelta))")
                        .font(.escudo(10, weight: .semibold))
                        .foregroundStyle(entry.netDelta >= 0 ? Color.escudoPos : Color.escudoText)
                        .monospacedDigit()
                }

                // Headline
                Text(entry.headline)
                    .font(.escudo(17, weight: .semibold))
                    .foregroundStyle(Color.escudoText)
                    .fixedSize(horizontal: false, vertical: true)

                // Body narrative
                Text(entry.body)
                    .font(.escudo(13))
                    .foregroundStyle(Color.escudoTextDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                // Tags
                if !entry.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.escudo(10))
                                .foregroundStyle(Color.escudoTextDim)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.escudoLine, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}
