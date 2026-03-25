import SwiftUI
import CoreData

struct AccountsView: View {
    @Environment(\.managedObjectContext) private var moc
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Account.order, ascending: true)],
        animation: .default
    ) private var accounts: FetchedResults<Account>

    @State private var showAdd = false
    @State private var editingAccount: Account? = nil

    var body: some View {
        List {
            ForEach(accounts) { account in
                AccountRow(account: account)
                    .contentShape(Rectangle())
                    .onTapGesture { editingAccount = account }
            }
            .onDelete(perform: deleteAccounts)
            .onMove(perform: moveAccounts)
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    EditButton()
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AccountEditSheet(account: nil) { name, emoji, colour, cur, excl, adj in
                addAccount(name: name, emoji: emoji, colour: colour, currency: cur, excludeFromTotal: excl, adjustment: adj)
            }
        }
        .sheet(item: $editingAccount) { acct in
            AccountEditSheet(account: acct) { name, emoji, colour, cur, excl, adj in
                acct.name           = name
                acct.emoji          = emoji
                acct.colour         = colour
                acct.currency       = cur
                acct.excludeFromTotal = excl
                applyAdjustment(adj, to: acct)
                DataController.shared.save()
            }
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        for i in offsets { moc.delete(accounts[i]) }
        DataController.shared.save()
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var reordered = Array(accounts)
        reordered.move(fromOffsets: source, toOffset: destination)
        for (i, acc) in reordered.enumerated() { acc.order = Int64(i) }
        DataController.shared.save()
    }

    private func addAccount(name: String, emoji: String, colour: String, currency: String, excludeFromTotal: Bool, adjustment: Double) {
        let acc = Account(context: moc)
        acc.id          = UUID()
        acc.name        = name
        acc.emoji       = emoji
        acc.colour      = colour
        acc.currency    = currency
        acc.excludeFromTotal = excludeFromTotal
        acc.source      = "manual"
        acc.dateCreated = Date()
        acc.order       = Int64(accounts.count)
        DataController.shared.save()
        // Create opening balance correction transaction if adjustment set
        if adjustment != 0 { applyAdjustment(adjustment, to: acc) }
        DataController.shared.save()
    }

    /// Converts a manual balance adjustment into a visible "Balance correction" transaction.
    /// Creates the tx for the delta vs current adjustment, then zeroes out the stored adjustment
    /// so computedBalance = txSum (correction tx included) without any hidden offset.
    private func applyAdjustment(_ newAdj: Double, to account: Account) {
        let oldAdj = account.balanceAdjustment
        let delta  = newAdj - oldAdj
        guard abs(delta) > 0.001 else { return }   // no meaningful change

        // Fetch or create "Balance Correction" category
        let catReq: NSFetchRequest<Category> = Category.fetchRequest()
        catReq.predicate = NSPredicate(format: "name == %@", "Balance correction")
        let corrCat: Category
        if let existing = (try? moc.fetch(catReq))?.first {
            corrCat = existing
        } else {
            let cat       = Category(context: moc)
            cat.id        = UUID()
            cat.name      = "Balance correction"
            cat.emoji     = "⚖️"
            cat.colour    = "8E8E93"
            cat.income    = delta > 0
            cat.dateCreated = Date()
            cat.order     = Int64.max
            corrCat       = cat
        }

        let tx              = Transaction(context: moc)
        tx.id               = UUID()
        tx.sourceID         = "correction_\(UUID().uuidString)"
        tx.amount           = abs(delta)
        tx.income           = delta > 0
        tx.note             = "Balance correction"
        tx.category         = corrCat
        tx.account          = account
        tx.recurringType    = 0
        let now             = Date()
        let cal             = Calendar(identifier: .gregorian)
        tx.date             = now
        tx.day              = cal.date(bySettingHour: 0, minute: 0, second: 0, of: now) ?? now
        let comps           = cal.dateComponents([.month, .year], from: now)
        tx.month            = cal.date(from: comps) ?? now

        // Zero out stored adjustment — tx now carries the offset
        account.balanceAdjustment = 0
    }
}

// MARK: - Balance adjustment helpers

extension Account {
    static func balanceAdjKey(for id: UUID) -> String { "balAdj_\(id.uuidString)" }
    static func ibanKey(for id: UUID) -> String { "acct_iban_\(id.uuidString)" }

    var balanceAdjustment: Double {
        get {
            guard let id = id else { return 0 }
            return UserDefaults.standard.double(forKey: Account.balanceAdjKey(for: id))
        }
        set {
            guard let id = id else { return }
            UserDefaults.standard.set(newValue, forKey: Account.balanceAdjKey(for: id))
        }
    }

    var storedIBAN: String? {
        get {
            guard let id = id else { return nil }
            return UserDefaults.standard.string(forKey: Account.ibanKey(for: id))
        }
        set {
            guard let id = id else { return }
            if let v = newValue { UserDefaults.standard.set(v, forKey: Account.ibanKey(for: id)) }
            else { UserDefaults.standard.removeObject(forKey: Account.ibanKey(for: id)) }
        }
    }

    static func excludeFromTotalKey(for id: UUID) -> String { "acct_excludeTotal_\(id.uuidString)" }

    var excludeFromTotal: Bool {
        get {
            guard let id = id else { return false }
            return UserDefaults.standard.bool(forKey: Account.excludeFromTotalKey(for: id))
        }
        set {
            guard let id = id else { return }
            UserDefaults.standard.set(newValue, forKey: Account.excludeFromTotalKey(for: id))
        }
    }

    static func bankNameKey(for id: UUID) -> String { "acct_bank_\(id.uuidString)" }

    var storedBankName: String? {
        get {
            guard let id = id else { return nil }
            return UserDefaults.standard.string(forKey: Account.bankNameKey(for: id))
        }
        set {
            guard let id = id else { return }
            if let v = newValue { UserDefaults.standard.set(v, forKey: Account.bankNameKey(for: id)) }
            else { UserDefaults.standard.removeObject(forKey: Account.bankNameKey(for: id)) }
        }
    }

    /// Computed balance from transactions + manual adjustment
    var computedBalance: Double {
        let txBal = (transactions as? Set<Transaction>)?
            .reduce(0.0) { $0 + ($1.income ? $1.amount : -$1.amount) } ?? 0
        return txBal + balanceAdjustment
    }

    /// Effective currency code — CoreData field, falls back to "EUR"
    var effectiveCurrency: String { currency ?? "EUR" }

    /// Currency symbol for this account
    var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: effectiveCurrency) ?? effectiveCurrency
    }
}

// MARK: - Transaction currency

extension Transaction {
    /// Effective currency — CoreData field → account field → "EUR"
    var effectiveCurrency: String {
        if let c = currency, !c.isEmpty { return c }
        if let c = account?.currency, !c.isEmpty { return c }
        return "EUR"
    }

    /// Currency symbol for this transaction
    var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: effectiveCurrency) ?? effectiveCurrency
    }
}

// MARK: - Row

struct AccountRow: View {
    @ObservedObject var account: Account

    var sym: String { account.currencySymbol }

    var txCount: Int { (account.transactions as? Set<Transaction>)?.count ?? 0 }
    var balance: Double { account.computedBalance }

    /// IBAN: storedIBAN first, then extracted from source key "iban_PT50..."
    var iban: String? {
        let raw: String
        if let stored = account.storedIBAN, !stored.isEmpty {
            raw = stored
        } else if let src = account.source, src.hasPrefix("iban_") {
            raw = String(src.dropFirst(5))
        } else {
            return nil
        }
        let compact = raw.replacingOccurrences(of: " ", with: "")
        guard compact.count > 4 else { return compact }
        let prefix = String(compact.prefix(4))
        let suffix = String(compact.suffix(4))
        return "\(prefix) •••• \(suffix)"
    }

    /// Source badge label
    var sourceBadge: String? {
        guard let src = account.source, src != "manual" else { return nil }
        // Prefer stored bank name (Revolut, Bankinter, etc.)
        if let bankName = account.storedBankName { return bankName }
        // Infer from colour for existing accounts before first sync
        if src.hasPrefix("iban_") || src.hasPrefix("eb_") {
            switch account.colour {
            case "c46a4a": return "Revolut"
            case "d9a441": return "Bankinter"
            default:       return "Enable Banking"
            }
        }
        if src.hasPrefix("trading212") { return "Trading 212" }
        return src.capitalized
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: account.colour ?? "007AFF").opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(account.emoji ?? "💳")
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name ?? "Account")
                        .font(.system(.body, design: .rounded).weight(.medium))
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                HStack(spacing: 4) {
                    if let badge = sourceBadge {
                        Text(badge)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    if let iban = iban {
                        Text(iban)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text("\(txCount) tx")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("\(balance >= 0 ? "" : "-")\(sym)\(String(format: "%.2f", abs(balance)))")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(balance >= 0 ? .primary : .red)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit sheet

struct AccountEditSheet: View {
    let account: Account?
    let onSave: (String, String, String, String, Bool, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var colour: String
    @State private var currencyCode: String
    @State private var excludeFromTotal: Bool
    @State private var adjustmentText: String

    private var displayIBAN: String? {
        if let stored = account?.storedIBAN, !stored.isEmpty { return stored }
        if let src = account?.source, src.hasPrefix("iban_") { return String(src.dropFirst(5)) }
        return nil
    }

    private let presetColours = [
        "007AFF", "34C759", "FF3B30", "FF9500",
        "AF52DE", "5856D6", "FF2D55", "00C7BE"
    ]

    init(account: Account?, onSave: @escaping (String, String, String, String, Bool, Double) -> Void) {
        self.account = account
        self.onSave  = onSave
        _name             = State(initialValue: account?.name   ?? "")
        _emoji            = State(initialValue: account?.emoji  ?? "💳")
        _colour           = State(initialValue: account?.colour ?? "007AFF")
        _currencyCode     = State(initialValue: account?.currency ?? "EUR")
        _excludeFromTotal = State(initialValue: account?.excludeFromTotal ?? false)
        let adj = account?.balanceAdjustment ?? 0
        _adjustmentText = State(initialValue: adj == 0 ? "" : String(format: "%.2f", adj))
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Display Name") {
                    HStack {
                        TextField("e.g. 💳", text: $emoji)
                            .frame(width: 40)
                            .multilineTextAlignment(.center)
                        TextField("Account name", text: $name)
                    }
                }
                Section("Currency") {
                    TextField("e.g. EUR, GBP, USD", text: $currencyCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: currencyCode) { _, v in
                            currencyCode = String(v.prefix(3).uppercased())
                        }
                }
                if let iban = displayIBAN {
                    Section("IBAN") {
                        Text(iban)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Section {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 12) {
                        ForEach(presetColours, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if hex == colour {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                }
                                .onTapGesture { colour = hex }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Colour")
                }
                Section {
                    HStack {
                        TextField("0.00", text: $adjustmentText)
                            .keyboardType(.decimalPad)
                        Text("manual offset")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Balance Adjustment")
                } footer: {
                    Text("Added to the transaction total. Use negative to subtract. Useful for opening balances or accounts not fully imported.")
                        .font(.caption)
                }
                Section {
                    Toggle("Exclude from Total Balance", isOn: $excludeFromTotal)
                } footer: {
                    Text("When on, this account is hidden from the combined Total Balance displayed in the log.")
                        .font(.caption)
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !name.isEmpty else { return }
                        let adj = Double(adjustmentText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let cur = currencyCode.isEmpty ? "EUR" : currencyCode
                        onSave(name, emoji, colour, cur, excludeFromTotal, adj)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

