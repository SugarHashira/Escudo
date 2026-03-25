import SwiftUI
import CoreData

struct CategorizationQueueView: View {
    @Environment(\.managedObjectContext) private var moc

    @FetchRequest(fetchRequest: CategorizationQueueView.unknownFetchRequest)
    private var transactions: FetchedResults<Transaction>

    private static var unknownFetchRequest: NSFetchRequest<Transaction> = {
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
        let p1 = NSPredicate(format: "category.name == %@", "Unknown")
        let p2 = NSPredicate(format: "sourceID != nil AND sourceID != ''")
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [p1, p2])
        return req
    }()

    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
    var currency: String = Locale.current.currencyCode ?? "EUR"
    var sym: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    @State private var selectedTransaction: Transaction? = nil
    @State private var pickedCategory: Category? = nil
    @State private var showPicker = false
    @State private var showingCategoryView = false

    @State private var pendingSimilarCount = 0
    @State private var pendingCategory: Category? = nil
    @State private var pendingTransaction: Transaction? = nil
    @State private var showSimilarConfirm = false

    var body: some View {
        mainContent
            .navigationTitle("Categorize (\(transactions.count))")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showPicker, content: pickerSheet)
            .confirmationDialog(
                similarDialogTitle,
                isPresented: $showSimilarConfirm,
                titleVisibility: .visible,
                actions: similarDialogActions,
                message: similarDialogMessage
            )
    }

    private var similarDialogTitle: String {
        let n = pendingSimilarCount
        return "Apply to \(n) similar transaction\(n == 1 ? "" : "s")?"
    }

    @ViewBuilder
    private var mainContent: some View {
        if transactions.isEmpty {
            emptyState
        } else {
            transactionList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("✅").font(.system(size: 48))
            Text("All caught up")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text("No uncategorized transactions")
                .font(.system(.body, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transactionList: some View {
        List {
            ForEach(transactions) { tx in
                Button {
                    selectedTransaction = tx
                    pickedCategory = nil
                    showPicker = true
                } label: {
                    TransactionQueueRow(tx: tx, sym: sym)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func pickerSheet() -> some View {
        NavigationView {
            NewCategoryPickerView(
                category: $pickedCategory,
                showPicker: $showPicker,
                showSheet: $showingCategoryView,
                income: selectedTransaction?.income ?? false
            )
            .navigationTitle("Pick Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPicker = false }
                }
            }
        }
        .onChange(of: pickedCategory) { cat in
            guard let cat = cat, let tx = selectedTransaction else { return }
            assignCategory(cat, to: tx)
            showPicker = false
        }
    }

    @ViewBuilder
    private func similarDialogActions() -> some View {
        Button("Apply to All Similar") {
            if let cat = pendingCategory, let tx = pendingTransaction, let note = tx.note {
                AutoCategoriser.applyToSimilar(note: note, income: tx.income, category: cat, moc: moc)
                DataController.shared.save()
            }
        }
        Button("Skip", role: .cancel) {}
    }

    @ViewBuilder
    private func similarDialogMessage() -> some View {
        Text("Transactions with similar descriptions will be categorized as \"\(pendingCategory?.wrappedName ?? "")\"")
    }

    private func assignCategory(_ cat: Category, to tx: Transaction) {
        tx.category = cat
        DataController.shared.save()

        let note = tx.note ?? ""
        let noteWords = AutoCategoriser.words(in: note)
        guard !noteWords.isEmpty else { return }

        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        let p1 = NSPredicate(format: "category.name == %@", "Unknown")
        let p2 = NSPredicate(format: "note != nil AND note != ''")
        let p3 = NSPredicate(format: "income == %d", tx.income)
        let p4 = NSPredicate(format: "self != %@", tx)
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [p1, p2, p3, p4])

        let candidates = (try? moc.fetch(req)) ?? []
        let similarCount = candidates.filter { candidate in
            guard let n = candidate.note else { return false }
            return !AutoCategoriser.words(in: n).intersection(noteWords).isEmpty
        }.count

        if similarCount > 0 {
            pendingSimilarCount = similarCount
            pendingCategory = cat
            pendingTransaction = tx
            showSimilarConfirm = true
        }
    }
}

private struct TransactionQueueRow: View {
    let tx: Transaction
    let sym: String

    var formattedDate: String {
        guard let d = tx.date else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.note ?? "Transaction")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .lineLimit(2)
                Text(formattedDate)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(tx.income ? "+" : "-")\(sym)\(String(format: "%.2f", tx.amount))")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(tx.income ? .green : .primary)
        }
        .padding(.vertical, 2)
    }
}
