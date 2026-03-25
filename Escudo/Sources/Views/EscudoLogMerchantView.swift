//
//  EscudoLogMerchantView.swift
//  Escudo — Log variant: 30-day income / expense summary with period-over-period delta
//

import CoreData
import SwiftUI

struct EscudoLogMerchantView: View {
    var bottomEdge: CGFloat
    @Binding var categoryFilters: [Category]
    @Binding var logViewMode: Int
    @Binding var filter: FilterType
    @Binding var categoryStartDate: Date?

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
    var currency: String = Locale.current.currencyCode ?? "EUR"
    var sym: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    @FetchRequest private var transactions: FetchedResults<Transaction>

    init(bottomEdge: CGFloat,
         categoryFilters: Binding<[Category]>,
         logViewMode: Binding<Int>,
         filter: Binding<FilterType>,
         categoryStartDate: Binding<Date?>) {
        self._categoryFilters   = categoryFilters
        self._logViewMode       = logViewMode
        self._filter            = filter
        self._categoryStartDate = categoryStartDate
        self.bottomEdge         = bottomEdge
        let start60 = Calendar.current.date(byAdding: .day, value: -60, to: Date.now) ?? Date.now
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "date >= %@ AND date <= %@",
                                    start60 as CVarArg, Date.now as CVarArg)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        _transactions = FetchRequest(fetchRequest: req)
    }

    // MARK: - Period splits

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.now
    }
    private var current: [Transaction] { transactions.filter { ($0.date ?? .distantPast) >= cutoff } }
    private var previous: [Transaction] { transactions.filter { ($0.date ?? .distantPast) < cutoff } }

    private var curIncome:   Double { current.filter  {  $0.income }.reduce(0) { $0 + $1.amount } }
    private var curExpenses: Double { current.filter  { !$0.income }.reduce(0) { $0 + $1.amount } }
    private var prevIncome:  Double { previous.filter {  $0.income }.reduce(0) { $0 + $1.amount } }
    private var prevExpenses:Double { previous.filter { !$0.income }.reduce(0) { $0 + $1.amount } }

    private var incomeDelta:   Double { curIncome - prevIncome }
    private var expensesDelta: Double { curExpenses - prevExpenses }
    private var net:           Double { curIncome - curExpenses }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // Section label
            HStack {
                Text("LAST 30 DAYS")
                    .font(.escudo(9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.escudoTextMuted)
                Rectangle()
                    .fill(Color.escudoLine)
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Income + Expenses cards
            HStack(spacing: 12) {
                SummaryCard(
                    label: "INCOME",
                    amount: curIncome,
                    delta: incomeDelta,
                    isIncome: true,
                    sym: sym
                )
                SummaryCard(
                    label: "EXPENSES",
                    amount: curExpenses,
                    delta: expensesDelta,
                    isIncome: false,
                    sym: sym
                )
            }
            .padding(.horizontal, 20)

            // Net row
            HStack {
                Text("NET")
                    .font(.escudo(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.escudoTextMuted)
                Spacer()
                Text("\(net >= 0 ? "+" : "-")\(sym)\(abs(net), specifier: "%.2f")")
                    .font(.escudo(15, weight: .semibold))
                    .foregroundStyle(net >= 0 ? Color.escudoPos : Color.escudoNeg)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)

            Spacer(minLength: bottomEdge + 60)
        }
    }
}

// MARK: - Summary card

private struct SummaryCard: View {
    let label: String
    let amount: Double
    let delta: Double
    let isIncome: Bool
    let sym: String

    var accentColor: Color { isIncome ? Color.escudoPos : Color.escudoNeg }
    var sign: String { isIncome ? "+" : "-" }
    var deltaSign: String { delta >= 0 ? "+" : "-" }
    var deltaColor: Color {
        if delta == 0 { return Color.escudoTextMuted }
        let better = isIncome ? delta > 0 : delta < 0
        return better ? Color.escudoPos : Color.escudoNeg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.escudo(9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.escudoTextMuted)

            Text("\(sign)\(sym)\(amount, specifier: "%.2f")")
                .font(.escudo(18, weight: .semibold))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 3) {
                Image(systemName: delta == 0 ? "minus" : (delta > 0 ? "arrow.up" : "arrow.down"))
                    .font(.system(size: 9, weight: .semibold))
                Text("\(deltaSign)\(sym)\(abs(delta), specifier: "%.2f")")
                    .font(.escudo(10, weight: .medium))
            }
            .foregroundStyle(deltaColor)

            Text("vs prior 30d")
                .font(.escudo(9))
                .foregroundStyle(Color.escudoTextMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.SecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
