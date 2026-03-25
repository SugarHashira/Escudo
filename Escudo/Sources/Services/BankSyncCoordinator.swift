import Foundation
import CoreData
import UserNotifications
import BackgroundTasks

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Maps bank API data (Enable Banking + Trading 212) into Escudo's Core Data store.
@MainActor
final class BankSyncCoordinator: ObservableObject {
    static let shared = BankSyncCoordinator()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var syncLogs: [String] = []

    private var ebService:   EnableBankingService?
    private var t212Service: Trading212Service?
    private var sibsService: SIBSService?

    private init() { buildServices() }

    func buildServices() {
        if let appID = try? KeychainHelper.load(key: KeychainKeys.ebAppID),
           let key   = try? KeychainHelper.load(key: KeychainKeys.ebPrivateKey) {
            ebService = EnableBankingService(appID: appID, privateKeyPEM: key)
        }
        if let key = try? KeychainHelper.load(key: KeychainKeys.trading212) {
            let appKeyID = try? KeychainHelper.load(key: KeychainKeys.trading212AppKeyID)
            t212Service = Trading212Service(apiKey: key, appKeyID: appKeyID, environment: .stored)
        }
        if let clientID     = try? KeychainHelper.load(key: KeychainKeys.sibsClientID),
           let clientSecret = try? KeychainHelper.load(key: KeychainKeys.sibsClientSecret) {
            sibsService = SIBSService(clientID: clientID, clientSecret: clientSecret)
        }
    }

    // MARK: - Public

    func manualSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        syncLogs = []
        defer { isSyncing = false }

        log("⏳ Sync started \(dateStr())")
        let moc = DataController.shared.container.viewContext

        await syncEnableBanking(bank: .revolut,   moc: moc)
        await syncEnableBanking(bank: .bankinter, moc: moc)
        await syncTrading212(moc: moc)
        await syncSIBS(moc: moc)

        log("✅ Sync finished \(dateStr())")
    }

    static func scheduleBackgroundSync() {
        let store = UserDefaults(suiteName: "group.com.sugarhashira.Escudo") ?? .standard
        let hour   = store.object(forKey: "syncHour")   as? Int ?? 8
        let minute = store.object(forKey: "syncMinute") as? Int ?? 0
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        var nextRun = Calendar.current.date(from: comps) ?? Date()
        if nextRun <= Date() {
            nextRun = Calendar.current.date(byAdding: .day, value: 1, to: nextRun) ?? nextRun
        }
        let req = BGProcessingTaskRequest(identifier: "com.sugarhashira.Escudo.sync")
        req.earliestBeginDate = nextRun
        req.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(req)
    }

    var isConfigured: Bool {
        ebService != nil || t212Service != nil || sibsService != nil
    }

    var sibsConnectionState: SIBSConnectionState {
        sibsService?.connectionState ?? .notConnected
    }

    func backgroundSyncAndNotify() async {
        let defaults = UserDefaults(suiteName: "group.com.sugarhashira.Escudo") ?? .standard
        let hour   = defaults.object(forKey: "syncHour")   as? Int ?? 8
        let minute = defaults.object(forKey: "syncMinute") as? Int ?? 0
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour; comps.minute = minute; comps.second = 0
        let scheduledToday = Calendar.current.date(from: comps) ?? Date()
        // last window = most recent past occurrence of the configured time
        let lastWindow = scheduledToday > Date()
            ? Calendar.current.date(byAdding: .day, value: -1, to: scheduledToday) ?? scheduledToday
            : scheduledToday
        if let last = defaults.object(forKey: "lastAutoSyncDate") as? Date, last >= lastWindow {
            return
        }
        await manualSync()
        defaults.set(Date(), forKey: "lastAutoSyncDate")
        let count = unknownCount()
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Transactions to Review"
        content.body = count == 1
            ? "1 transaction needs categorising"
            : "\(count) transactions need categorising"
        content.sound = .default
        content.userInfo = ["action": "reviewUnknown"]
        let req = UNNotificationRequest(identifier: "escudo.review", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    private func unknownCount() -> Int {
        let moc = DataController.shared.container.viewContext
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "category.name == %@", "Unknown")
        return (try? moc.count(for: req)) ?? 0
    }

    // MARK: - Enable Banking

    private func syncEnableBanking(bank: EBBank, moc: NSManagedObjectContext) async {
        guard let service = ebService,
              case .connected = service.connectionState(for: bank) else {
            log("⏭️ \(bank.displayName): skipped (not connected)")
            return
        }
        do {
            log("🔄 \(bank.displayName): fetching accounts…")
            let details = try await service.fetchAccounts(for: bank)
            var total = 0
            for detail in details {
                // Use IBAN as stable source key — falls back to EB account UUID
                let sourceKey = detail.iban.map { "iban_\($0)" } ?? "eb_\(detail.accountID)"
                let account = fetchOrCreateAccount(
                    source:   sourceKey,
                    name:     detail.name,
                    emoji:    bank.categoryEmoji,
                    colour:   bank == .revolut ? "c46a4a" : "d9a441",
                    currency: detail.currency,
                    moc:      moc
                )
                // Store IBAN + bank name separately — accessible regardless of source key format
                if let iban = detail.iban { account.storedIBAN = iban }
                account.storedBankName = bank.displayName
                        if let dbg = service.debugLog { log("  🔍 \(dbg)") }
                let added = insertEBTransactions(detail.transactions, account: account, moc: moc)
                total += added
                log("  📄 \(detail.name): \(added) new tx")

                // Anchor balance: set adjustment so computedBalance == API balance
                let txSum = (account.transactions as? Set<Transaction>)?
                    .reduce(0.0) { $0 + ($1.income ? $1.amount : -$1.amount) } ?? 0
                account.balanceAdjustment = detail.balance - txSum
                log("  💰 \(detail.name): balance anchored to \(String(format: "%.2f", detail.balance))")
            }
            // Remove stale accounts created before IBAN-keying (old source patterns)
            let staleReq: NSFetchRequest<Account> = Account.fetchRequest()
            let bankName = bank.displayName.lowercased()
            staleReq.predicate = NSPredicate(
                format: "source == %@ OR source BEGINSWITH %@",
                bankName, "eb_"
            )
            if let stale = try? moc.fetch(staleReq) {
                for acc in stale {
                    // Only delete if we have an IBAN-keyed replacement
                    let ibanReq: NSFetchRequest<Account> = Account.fetchRequest()
                    ibanReq.predicate = NSPredicate(format: "source BEGINSWITH 'iban_'")
                    let hasIban = ((try? moc.count(for: ibanReq)) ?? 0) > 0
                    if hasIban { moc.delete(acc) }
                }
            }

            DataController.shared.save()
            log("✅ \(bank.displayName): \(total) new transactions saved")
        } catch {
            lastError = "\(bank.displayName): \(error.localizedDescription)"
            log("❌ \(bank.displayName): \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func insertEBTransactions(
        _ txns: [EBTransaction],
        account: Account,
        moc: NSManagedObjectContext
    ) -> Int {
        // Dedup against ALL existing sourceIDs (global — catches any prior naming scheme)
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "sourceID != nil AND sourceID != ''")
        let existingIDs = Set((try? moc.fetch(req))?.compactMap { $0.sourceID } ?? [])

        // Also dedup by (account + date + amount) to catch transactions saved under old composite IDs
        let acctReq: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        acctReq.predicate = NSPredicate(format: "account == %@", account)
        let acctTxns = (try? moc.fetch(acctReq)) ?? []
        // key: "date_amount_income"
        let existingComposite = Set(acctTxns.compactMap { tx -> String? in
            guard let d = tx.day else { return nil }
            return "\(Int(d.timeIntervalSince1970))_\(tx.amount)_\(tx.income)"
        })

        let calendar = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var added = 0

        for ebTx in txns {
            let sid = ebTx.effectiveID
            guard !existingIDs.contains(sid) else { continue }

            let amount = Double(ebTx.effectiveAmount.amount) ?? 0
            let income = ebTx.isIncome
            let date   = fmt.date(from: ebTx.effectiveDate ?? "") ?? Date()
            let day    = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? date
            let compositeKey = "\(Int(day.timeIntervalSince1970))_\(abs(amount))_\(income)"
            guard !existingComposite.contains(compositeKey) else { continue }

            let tx = Transaction(context: moc)
            tx.id       = UUID()
            tx.sourceID = sid
            tx.amount   = abs(amount)
            tx.income   = income
            tx.note     = ebTx.effectiveDescription
            tx.currency = ebTx.effectiveAmount.currency

            let autoCatEnabled = UserDefaults.standard.object(forKey: "autoCategorizerEnabled") as? Bool ?? true
            if autoCatEnabled,
               let matched = AutoCategoriser.bestCategory(for: ebTx.effectiveDescription, income: income, moc: moc) {
                tx.category = matched
            } else {
                tx.category = unknownCategory(income: income, moc: moc)
            }

            tx.account  = account
            tx.recurringType = 0
            tx.date  = date
            tx.day   = day
            let comps = calendar.dateComponents([.month, .year], from: date)
            tx.month = calendar.date(from: comps) ?? date
            added += 1
        }
        return added
    }

    // MARK: - Trading 212

    private func syncTrading212(moc: NSManagedObjectContext) async {
        guard let service = t212Service else {
            log("⏭️ Trading 212: skipped (no credentials)")
            return
        }
        log("🔄 Trading 212: fetching data…")

        // Per-currency account lookup — created lazily on first transaction in that currency
        func t212Account(for currency: String) -> Account {
            let ccy = currency.uppercased()
            return fetchOrCreateAccount(
                source:   "trading212_\(ccy.lowercased())",
                name:     "Trading 212 \(ccy)",
                emoji:    "📈",
                colour:   ccy == "GBP" ? "34C759" : "007AFF",
                currency: ccy,
                moc:      moc
            )
        }

        // Per-type category map — created lazily so unused types don't pollute the category list
        func cat(name: String, emoji: String, income: Bool) -> Category {
            fetchOrCreateCategory(name: name, emoji: emoji, income: income, moc: moc)
        }
        func categoryFor(t212Type: T212TxType, rawDesc: String) -> Category {
            switch t212Type {
            case .dividend:
                return cat(name: "Dividends",     emoji: "💰", income: true)
            case .buy:
                return cat(name: "Investments",   emoji: "📈", income: false)
            case .sell:
                return cat(name: "Investments",   emoji: "📈", income: true)
            }
        }
        func cashCategoryFor(rawDesc: String, isIncome: Bool) -> Category {
            // rawDesc format is "[TYPE] optionalTicker" — extract the type token
            let typeToken = rawDesc
                .drop(while: { $0 == "[" })
                .prefix(while: { $0 != "]" && $0 != " " })
                .uppercased()
            switch typeToken {
            case "DEPOSIT":
                return cat(name: "Deposits",        emoji: "🏦", income: true)
            case "WITHDRAWAL":
                return cat(name: "Withdrawals",     emoji: "💸", income: false)
            case "INTEREST":
                return cat(name: "Interest",        emoji: "📊", income: true)
            case "LENDING_INTEREST":
                return cat(name: "Stock Lending",   emoji: "🤝", income: true)
            case "CASHBACK", "CARD_CASHBACK", "SPENDING_CASHBACK":
                return cat(name: "Cashback",        emoji: "🎁", income: true)
            case "REFERRAL_BONUS":
                return cat(name: "Referral Bonus",  emoji: "🎉", income: true)
            case "TRANSFER_IN":
                return cat(name: "Transfers",       emoji: "↩️", income: true)
            case "TRANSFER_OUT":
                return cat(name: "Transfers",       emoji: "↩️", income: false)
            case "FX_FEE":
                return cat(name: "FX Fees",         emoji: "💱", income: false)
            case "NRA_TAX":
                return cat(name: "Withholding Tax", emoji: "🏛️", income: false)
            case "STAMP_DUTY_RESERVE_TAX":
                return cat(name: "Stamp Duty",      emoji: "🏛️", income: false)
            default:
                return cat(name: isIncome ? "T212 Income" : "T212 Fees",
                           emoji: isIncome ? "💵" : "📉", income: isIncome)
            }
        }

        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "sourceID != nil AND sourceID != ''")
        let existingIDs = Set((try? moc.fetch(req))?.compactMap { $0.sourceID } ?? [])

        let raw = UserDefaults.standard.integer(forKey: "syncDaysBack")
        let daysBack = raw <= 0 ? 30 : raw.clamped(to: 1...365)
        log("📅 Fetching last \(daysBack) days via CSV export")

        var newTxs: [T212RawTransaction] = []
        do {
            newTxs = try await service.fetchCSV(daysBack: daysBack)
            log("✅ CSV: \(newTxs.count) rows")
        } catch ServiceError.httpError(429, _) {
            log("⏳ Rate-limited (429) — waiting 2 minutes then retrying…")
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            do {
                newTxs = try await service.fetchCSV(daysBack: daysBack)
                log("✅ CSV (retry): \(newTxs.count) rows")
            } catch {
                log("❌ Retry failed: \(error.localizedDescription)")
                lastError = "Trading 212: \(error.localizedDescription)"
                return
            }
        } catch {
            log("❌ \(error.localizedDescription)")
            lastError = "Trading 212: \(error.localizedDescription)"
            return
        }

        let calendar = Calendar(identifier: .gregorian)
        var added = 0

        for tx in newTxs {
            guard !existingIDs.contains(tx.sourceID) else { continue }

            let entry = Transaction(context: moc)
            entry.id       = UUID()
            entry.sourceID = tx.sourceID
            entry.amount   = abs(tx.amount)
            entry.income   = tx.amount >= 0
            entry.currency = tx.currency
            // Card debit: store merchant name only, drop the [CARD_DEBIT] tag
            if tx.rawDescription.hasPrefix("[CARD_DEBIT] ") {
                entry.note = String(tx.rawDescription.dropFirst("[CARD_DEBIT] ".count))
            } else {
                entry.note = tx.rawDescription
            }
            entry.account  = t212Account(for: tx.currency)
            entry.recurringType = 0

            // Category: per-type mapping
            if tx.rawDescription.hasPrefix("[") {
                // Cash transaction — use type-specific category
                entry.category = cashCategoryFor(rawDesc: tx.rawDescription, isIncome: tx.amount >= 0)
            } else {
                // Order or dividend — use type-based category
                entry.category = categoryFor(t212Type: tx.type, rawDesc: tx.rawDescription)
            }

            entry.date  = tx.date
            entry.day   = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tx.date) ?? tx.date
            let comps   = calendar.dateComponents([.month, .year], from: tx.date)
            entry.month = calendar.date(from: comps) ?? tx.date
            added += 1
        }

        DataController.shared.save()
        log("✅ Trading 212: \(added) new transactions saved")
    }

    // MARK: - SIBS

    private func syncSIBS(moc: NSManagedObjectContext) async {
        guard let service = sibsService else {
            log("⏭️ SIBS: skipped (no credentials)")
            return
        }
        guard case .connected = service.connectionState else {
            log("⏭️ SIBS: skipped (not connected — run connect() from Settings)")
            return
        }

        do {
            log("🔄 SIBS: fetching accounts…")

            let details = try await service.fetchAccounts()
            var total = 0

            for detail in details {
                let emoji  = detail.accountType == .card ? "💳" : "🏦"
                let colour = detail.accountType == .card ? "1A73E8" : "2D9CDB"
                let source = detail.iban.map { "iban_\($0)" } ?? "sibs_\(detail.resourceID)"

                let account = fetchOrCreateAccount(
                    source:   source,
                    name:     detail.name,
                    emoji:    emoji,
                    colour:   colour,
                    currency: detail.currency,
                    moc:      moc
                )
                account.storedBankName = "SIBS"
                if let iban = detail.iban { account.storedIBAN = iban }

                if let dbg = service.debugLog { log("  🔍 \(dbg)") }

                let added = insertSIBSTransactions(detail.transactions, account: account, moc: moc)
                total += added
                log("  📄 \(detail.name): \(added) new tx\(detail.accountType == .card ? " [card]" : "")")

                // Anchor balance
                let txSum = (account.transactions as? Set<Transaction>)?
                    .reduce(0.0) { $0 + ($1.income ? $1.amount : -$1.amount) } ?? 0
                account.balanceAdjustment = detail.balance - txSum
            }

            DataController.shared.save()
            log("✅ SIBS: \(total) new transactions saved")
        } catch {
            lastError = "SIBS: \(error.localizedDescription)"
            log("❌ SIBS: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func insertSIBSTransactions(
        _ txns: [SIBSUnifiedTransaction],
        account: Account,
        moc: NSManagedObjectContext
    ) -> Int {
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "sourceID != nil AND sourceID != ''")
        let existingIDs = Set((try? moc.fetch(req))?.compactMap { $0.sourceID } ?? [])

        let calendar = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var added = 0

        for sibsTx in txns {
            let sid = "sibs_\(sibsTx.id)"
            guard !existingIDs.contains(sid) else { continue }

            let amount = Double(sibsTx.amount) ?? 0
            let date   = fmt.date(from: sibsTx.date ?? "") ?? Date()
            let day    = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? date

            let tx = Transaction(context: moc)
            tx.id       = UUID()
            tx.sourceID = sid
            tx.amount   = abs(amount)
            tx.income   = sibsTx.isIncome
            tx.note     = sibsTx.description
            tx.currency = sibsTx.currency
            tx.account  = account
            tx.recurringType = 0
            tx.date  = date
            tx.day   = day
            let comps = calendar.dateComponents([.month, .year], from: date)
            tx.month = calendar.date(from: comps) ?? date

            let autoCatEnabled = UserDefaults.standard.object(forKey: "autoCategorizerEnabled") as? Bool ?? true
            if autoCatEnabled,
               let matched = AutoCategoriser.bestCategory(for: sibsTx.description, income: sibsTx.isIncome, moc: moc) {
                tx.category = matched
            } else {
                tx.category = unknownCategory(income: sibsTx.isIncome, moc: moc)
            }

            added += 1
        }
        return added
    }

    // MARK: - Helpers

    private func fetchOrCreateAccount(
        source: String, name: String, emoji: String, colour: String,
        currency: String? = nil, moc: NSManagedObjectContext
    ) -> Account {
        let req: NSFetchRequest<Account> = Account.fetchRequest()
        req.predicate = NSPredicate(format: "source == %@", source)
        if let existing = (try? moc.fetch(req))?.first {
            if let c = currency { existing.currency = c }
            return existing
        }

        // Migration: if we now have an IBAN key but the account was created with an eb_ key,
        // find it by stored IBAN and migrate its source key in-place (avoids duplicate accounts)
        if source.hasPrefix("iban_") {
            let ibanValue = String(source.dropFirst(5))
            let all: NSFetchRequest<Account> = Account.fetchRequest()
            all.predicate = NSPredicate(format: "source BEGINSWITH 'eb_'")
            if let stale = (try? moc.fetch(all))?.first(where: { acc in
                acc.storedIBAN == ibanValue || acc.colour == colour
            }) {
                stale.source = source   // migrate to IBAN-keyed source
                if let c = currency { stale.currency = c }
                return stale
            }
        }

        let acc = Account(context: moc)
        acc.id          = UUID()
        acc.name        = name
        acc.emoji       = emoji
        acc.colour      = colour
        acc.source      = source
        acc.dateCreated = Date()
        if let c = currency { acc.currency = c }
        let countReq: NSFetchRequest<Account> = Account.fetchRequest()
        acc.order = Int64((try? moc.count(for: countReq)) ?? 0)
        return acc
    }

    private func unknownCategory(income: Bool, moc: NSManagedObjectContext) -> Category {
        fetchOrCreateCategory(name: "Unknown", emoji: "❓", income: income, colour: "8E8E93", moc: moc)
    }

    private func fetchOrCreateCategory(
        name: String, emoji: String, income: Bool, colour: String? = nil, moc: NSManagedObjectContext
    ) -> Category {
        let req: NSFetchRequest<Category> = Category.fetchRequest()
        req.predicate = NSPredicate(format: "name == %@", name)
        if let existing = (try? moc.fetch(req))?.first { return existing }

        let cat = Category(context: moc)
        cat.id          = UUID()
        cat.name        = name
        cat.emoji       = emoji
        cat.income      = income
        cat.colour      = colour ?? (income ? "34C759" : "007AFF")
        cat.dateCreated = Date()
        let countReq: NSFetchRequest<Category> = Category.fetchRequest()
        cat.order = Int64((try? moc.count(for: countReq)) ?? 0)
        return cat
    }

    private func log(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        syncLogs.append("[\(ts)] \(msg)")
    }

    private func dateStr() -> String {
        let f = DateFormatter()
        f.dateStyle = .none; f.timeStyle = .medium
        return f.string(from: Date())
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
