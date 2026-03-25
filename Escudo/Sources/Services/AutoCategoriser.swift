import CoreData
import Foundation

/// Learns category patterns from existing manually-categorised transactions.
/// On new imported transactions: significant-word overlap against known patterns → best category.
final class AutoCategoriser {
    private static let stopwords: Set<String> = [
        "the","and","for","with","from","that","this","have","will","your","more",
        "uma","para","com","dos","das","por","que","nao","mais","como","mas","sem",
        "compra","pagamento","payment","transfer","purchase","debit","credit","card",
        "ref","num","via","gon"
    ]

    /// Significant words: lowercase, no diacritics, alpha only, >3 chars, not stopword
    static func words(in text: String) -> Set<String> {
        let normalized = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let tokens = normalized.components(separatedBy: CharacterSet.letters.inverted)
        return Set(tokens.filter { $0.count > 3 && !stopwords.contains($0) })
    }

    /// Returns best matching Category from existing transactions, or nil if no confident match.
    /// Only looks at transactions with real categories (not "Unknown").
    static func bestCategory(for note: String, income: Bool, moc: NSManagedObjectContext) -> Category? {
        let noteWords = words(in: note)
        guard !noteWords.isEmpty else { return nil }

        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "category != nil"),
            NSPredicate(format: "NOT (category.name IN %@)", ["Unknown", "Revolut", "Bankinter", "Trading 212"]),
            NSPredicate(format: "note != nil AND note != ''"),
            NSPredicate(format: "income == %d", income)
        ])
        guard let transactions = try? moc.fetch(req), !transactions.isEmpty else { return nil }

        var scores: [NSManagedObjectID: (Category, Int)] = [:]
        for tx in transactions {
            guard let cat = tx.category, let txNote = tx.note else { continue }
            let txWords = words(in: txNote)
            let overlap = noteWords.intersection(txWords).count
            guard overlap > 0 else { continue }
            let oid = cat.objectID
            scores[oid] = (cat, (scores[oid]?.1 ?? 0) + overlap)
        }
        return scores.values.max(by: { $0.1 < $1.1 })?.0
    }

    /// Apply category to all existing "Unknown" transactions whose note is similar to the given note.
    /// Returns count of transactions updated.
    @discardableResult
    static func applyToSimilar(note: String, income: Bool, category: Category, moc: NSManagedObjectContext) -> Int {
        let noteWords = words(in: note)
        guard !noteWords.isEmpty else { return 0 }

        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "category.name == %@", "Unknown"),
            NSPredicate(format: "note != nil AND note != ''"),
            NSPredicate(format: "income == %d", income)
        ])
        guard let candidates = try? moc.fetch(req) else { return 0 }
        var count = 0
        for tx in candidates {
            guard let txNote = tx.note else { continue }
            let txWords = AutoCategoriser.words(in: txNote)
            if !noteWords.intersection(txWords).isEmpty {
                tx.category = category
                count += 1
            }
        }
        return count
    }
}
