import Foundation

// MARK: - Plain DTOs (no SwiftData dependency)

struct T212RawTransaction {
    let sourceID: String
    let date: Date
    let amount: Double       // positive = income, negative = expense
    let currency: String     // ISO 4217 from "Currency (Total)" column
    let rawDescription: String
    let type: T212TxType
}

enum T212TxType { case buy, sell, dividend }

struct T212RawHolding {
    let ticker: String
    let name: String
    let quantity: Double
    let averageCost: Double
    let currentPrice: Double
}

// MARK: - Service

enum T212Environment: String, CaseIterable {
    case live     = "live"
    case practice = "practice"

    var baseURL: URL {
        switch self {
        case .live:     URL(string: "https://live.trading212.com/api/v0")!
        case .practice: URL(string: "https://demo.trading212.com/api/v0")!
        }
    }

    var displayName: String {
        switch self { case .live: "Live"; case .practice: "Practice" }
    }

    static var stored: T212Environment {
        let raw = UserDefaults.standard.string(forKey: "t212Environment") ?? "live"
        return T212Environment(rawValue: raw) ?? .live
    }

    func store() {
        UserDefaults.standard.set(rawValue, forKey: "t212Environment")
    }
}

/// Wraps the Trading 212 REST API (v0).
/// Docs: https://t212public-api-docs.redoc.ly/
@MainActor
final class Trading212Service {
    private var baseURL: URL
    private var apiKey: String
    private var appKeyID: String?

    init(apiKey: String, appKeyID: String? = nil, environment: T212Environment = .stored) {
        self.apiKey   = apiKey
        self.appKeyID = appKeyID
        self.baseURL  = environment.baseURL
    }

    // MARK: - Shared decoder (T212 uses snake_case keys)

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    // MARK: - Portfolio

    func fetchPortfolio() async throws -> [T212RawHolding] {
        let data = try await get(path: "/equity/portfolio")
        let positions = try decoder().decode([T212Position].self, from: data)
        return positions.map(\.rawHolding)
    }

    // MARK: - Account info

    func fetchAccountInfo() async throws -> T212AccountInfo {
        let data = try await get(path: "/equity/account/info")
        return try decoder().decode(T212AccountInfo.self, from: data)
    }

    // MARK: - Cash balance

    func fetchCashBalance() async throws -> T212CashBalance {
        let data = try await get(path: "/equity/account/cash")
        return try decoder().decode(T212CashBalance.self, from: data)
    }

    // MARK: - CSV Export

    // UserDefaults keys for cached S3 download URL
    /// T212 returns ISO8601 dates with fractional seconds ("2026-04-23T15:35:03.000Z").
    /// Standard `.withInternetDateTime` can't parse those — try both.
    private static func parseISO(_ s: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: s) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: s)
    }

    /// GET exports list → if most recent Finished report is < 24h old, download it.
    /// Otherwise POST a new export, poll until Finished, then download.
    /// Either way: parse the CSV and return raw transactions.
    func fetchCSV(daysBack: Int = 30) async throws -> [T212RawTransaction] {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        let now      = Date()
        let fromDate = now.addingTimeInterval(-Double(daysBack) * 86400)

        // 1. GET exports list
        let listData = try await get(path: "/equity/history/exports")
        let reports  = try decoder().decode([T212ExportStatus].self, from: listData)

        // 2. Most recent Finished report — reuse if < 24h old
        let latest = reports
            .filter { ($0.status ?? "") == "Finished" && $0.downloadLink != nil }
            .max(by: { $0.reportId < $1.reportId })

        let downloadURL: URL
        if let r      = latest,
           let toStr  = r.timeTo,
           let toDate = Trading212Service.parseISO(toStr),
           now.timeIntervalSince(toDate) < 86400,
           let link   = r.downloadLink,
           let url    = URL(string: link) {
            downloadURL = url
        } else {
            // 3. No recent report — POST new export
            let body: [String: Any] = [
                "dataIncluded": [
                    "includeDividends":    true,
                    "includeInterest":     true,
                    "includeOrders":       true,
                    "includeTransactions": true
                ],
                "timeFrom": isoFmt.string(from: fromDate),
                "timeTo":   isoFmt.string(from: now)
            ]
            let createData = try await post(path: "/equity/history/exports", body: body)
            let reportId   = try decoder().decode(T212ExportCreateResponse.self, from: createData).reportId

            // Poll until Finished — 10 s head start, then every 5 s, 2 min max
            try await Task.sleep(nanoseconds: 10_000_000_000)
            var polledURL: URL?
            for attempt in 0..<24 {
                if attempt > 0 { try await Task.sleep(nanoseconds: 5_000_000_000) }
                let pollData = try await get(path: "/equity/history/exports")
                let pollList = try decoder().decode([T212ExportStatus].self, from: pollData)
                if let match = pollList.first(where: { $0.reportId == reportId }) {
                    switch match.status ?? "" {
                    case "Finished":
                        guard let link = match.downloadLink, let url = URL(string: link) else {
                            throw ServiceError.parseError("Export finished but no download link")
                        }
                        polledURL = url
                    case "Failed":
                        throw ServiceError.parseError("T212 export failed (reportId \(reportId))")
                    default: break
                    }
                }
                if polledURL != nil { break }
            }
            guard let url = polledURL else {
                throw ServiceError.parseError("CSV export timed out after 2 min")
            }
            downloadURL = url
        }

        // 4. Download CSV from pre-signed S3 URL (no auth header needed)
        let (csvData, response) = try await URLSession.shared.data(from: downloadURL)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else {
            throw ServiceError.httpError(code, "CSV download failed")
        }
        guard let text = String(data: csvData, encoding: .utf8) else {
            throw ServiceError.parseError("CSV not valid UTF-8")
        }

        // 5. Parse and return
        return parseCSV(text)
    }

    // MARK: - CSV parser

    private static let csvDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        // T212 uses "2024-01-15 10:30:00" or "2024-01-15 10:30:00.123"
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func parseCSV(_ text: String) -> [T212RawTransaction] {
        var lines = csvLines(text)
        guard !lines.isEmpty else { return [] }

        let headers = csvRow(lines.removeFirst())
        // Build column-index dictionary
        let idx = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1.trimmingCharacters(in: .whitespaces), $0) })

        func col(_ row: [String], _ name: String) -> String {
            guard let i = idx[name], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }

        var results: [T212RawTransaction] = []

        for line in lines {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let cols = csvRow(line)

            let action       = col(cols, "Action")
            let timeStr      = col(cols, "Time")
            let ticker       = col(cols, "Ticker")
            let name         = col(cols, "Name")
            let totalStr     = col(cols, "Total")
            let id           = col(cols, "ID")
            let ccyTotal     = col(cols, "Currency (Total)")
            let qtyStr       = col(cols, "No. of shares")
            let priceStr     = col(cols, "Price / share")
            let ccyPrice     = col(cols, "Currency (Price / share)")
            let merchantName = col(cols, "Merchant name")

            guard !id.isEmpty, !action.isEmpty else { continue }

            let total = Double(totalStr) ?? 0
            // Parse date — try with and without milliseconds
            let date: Date = {
                let s = timeStr
                if let d = Trading212Service.csvDateFmt.date(from: s) { return d }
                // Trim milliseconds ("2024-01-15 10:30:00.123" → "2024-01-15 10:30:00")
                let trimmed = String(s.prefix(19))
                return Trading212Service.csvDateFmt.date(from: trimmed) ?? Date()
            }()

            let al = action.lowercased()
            let txType: T212TxType
            let desc: String

            if al == "market buy" || (al.contains("buy") && !al.contains("card")) {
                txType = .buy
                desc   = "Buy \(qtyStr) \(ticker) @ \(priceStr) \(ccyPrice)"
            } else if al.contains("sell") {
                txType = .sell
                desc   = "Sell \(qtyStr) \(ticker) @ \(priceStr) \(ccyPrice)"
            } else if al.contains("dividend") {
                txType = .dividend
                desc   = "Dividend \(ticker.isEmpty ? name : ticker)\(ccyTotal.isEmpty ? "" : " · \(ccyTotal)")"
            } else if al.contains("card debit") {
                txType = .buy
                let merchant = merchantName.isEmpty ? "Card Payment" : merchantName
                desc   = "[CARD_DEBIT] \(merchant)"
            } else if al.contains("spending cashback") {
                txType = .dividend
                desc   = "[SPENDING_CASHBACK] Cashback\(ccyTotal.isEmpty ? "" : " · \(ccyTotal)")"
            } else if al.contains("deposit") {
                txType = .buy
                desc   = "[DEPOSIT] Deposit\(ccyTotal.isEmpty ? "" : " · \(ccyTotal)")"
            } else if al.contains("withdrawal") {
                txType = .buy
                desc   = "[WITHDRAWAL] Withdrawal\(ccyTotal.isEmpty ? "" : " · \(ccyTotal)")"
            } else if al.contains("interest on cash") {
                txType = .buy
                desc   = "[INTEREST] Interest\(ccyTotal.isEmpty ? "" : " · \(ccyTotal)")"
            } else if al.contains("lending interest") {
                txType = .buy
                desc   = "[LENDING_INTEREST] Stock Lending Interest\(ccyTotal.isEmpty ? "" : " · \(ccyTotal)")"
            } else if al.contains("stamp duty") {
                txType = .buy
                desc   = "[STAMP_DUTY_RESERVE_TAX] Stamp Duty\(ticker.isEmpty ? "" : " · \(ticker)")"
            } else if al.contains("currency conversion") {
                txType = .buy
                desc   = "[FX_FEE] FX Fee\(ccyTotal.isEmpty ? "" : " · \(ccyTotal)")"
            } else {
                // Generic fallback — wrap action as tag
                let tag = action.uppercased().replacingOccurrences(of: " ", with: "_")
                txType = total >= 0 ? .dividend : .buy
                desc   = "[\(tag)] \(action)"
            }

            guard total != 0 else { continue }

            results.append(T212RawTransaction(
                sourceID:       id,
                date:           date,
                amount:         total,
                currency:       ccyTotal.isEmpty ? "EUR" : ccyTotal,
                rawDescription: desc,
                type:           txType
            ))
        }
        return results
    }

    /// Split CSV text into lines, respecting quoted newlines.
    private func csvLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var inQuote = false
        for ch in text {
            if ch == "\"" { inQuote.toggle() }
            else if (ch == "\n" || ch == "\r") && !inQuote {
                if !current.isEmpty { lines.append(current); current = "" }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// Parse a single CSV row into fields, handling quoted commas and escaped quotes ("").
    private func csvRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuote = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                let next = line.index(after: i)
                if inQuote && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuote.toggle()
            } else if ch == "," && !inQuote {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    // MARK: - Helpers

    private func get(path: String) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw ServiceError.parseError("Invalid URL: \(path)")
        }
        var request = URLRequest(url: url)
        if let kid = appKeyID, !kid.isEmpty {
            let combined = "\(kid):\(apiKey)"
            let b64 = Data(combined.utf8).base64EncodedString()
            request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(code, body)
        }
        return data
    }

    private func post(path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw ServiceError.parseError("Invalid URL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let kid = appKeyID, !kid.isEmpty {
            let combined = "\(kid):\(apiKey)"
            let b64 = Data(combined.utf8).base64EncodedString()
            request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(code, body)
        }
        return data
    }
}

enum ServiceError: LocalizedError {
    case httpError(Int, String)
    case parseError(String)
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            let snippet = body.prefix(120)
            return "Trading 212 HTTP \(code)\(snippet.isEmpty ? "" : ": \(snippet)")"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .missingCredentials:  return "Missing API credentials"
        }
    }
}

// MARK: - Private DTOs

private struct T212Position: Decodable {
    let ticker: String
    let fullName: String
    let quantity: Double
    let averagePrice: Double
    let currentPrice: Double
    let ppl: Double

    var rawHolding: T212RawHolding {
        T212RawHolding(
            ticker: ticker,
            name: fullName,
            quantity: quantity,
            averageCost: averagePrice,
            currentPrice: currentPrice
        )
    }
}

// MARK: - CSV export DTOs

private struct T212ExportCreateResponse: Decodable {
    let reportId: Int64
}

struct T212ExportStatus: Decodable {
    let reportId: Int64
    let status: String?        // "Finished" | "Running" | "Failed"
    let downloadLink: String?
    let timeFrom: String?
    let timeTo: String?
}

// MARK: - Account info DTO

struct T212AccountInfo: Decodable {
    let id: Int64?
    let currencyCode: String?
    let type: String?        // "LIVE" or "PRACTICE"
}

// MARK: - Cash balance DTO

struct T212CashBalance: Decodable {
    let free: Double?
    let invested: Double?
    let total: Double?
    let result: Double?
    let ppl: Double?
}

