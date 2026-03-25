import Foundation
import Security
import UIKit

// MARK: - Bank enum

enum EBBank: CaseIterable {
    case revolut, bankinter

    var aspspNameKey:    String { "eb_aspsp_name_\(udKey)" }
    var aspspCountryKey: String { "eb_aspsp_country_\(udKey)" }
    private var udKey: String {
        switch self { case .revolut: "revolut"; case .bankinter: "bankinter" }
    }

    var aspspName: String {
        get { UserDefaults.standard.string(forKey: aspspNameKey) ?? defaultASPSPName }
        set { UserDefaults.standard.set(newValue, forKey: aspspNameKey) }
    }
    var aspspCountry: String {
        get { UserDefaults.standard.string(forKey: aspspCountryKey) ?? defaultASPSPCountry }
        set { UserDefaults.standard.set(newValue, forKey: aspspCountryKey) }
    }
    private var defaultASPSPName: String {
        switch self { case .revolut: "Revolut"; case .bankinter: "Bankinter" }
    }
    private var defaultASPSPCountry: String {
        switch self { case .revolut: "PT"; case .bankinter: "ES" }
    }
    var sessionKey: String {
        switch self { case .revolut: KeychainKeys.ebSessionRevolut; case .bankinter: KeychainKeys.ebSessionBankinter }
    }
    var accountsKey: String {
        switch self { case .revolut: KeychainKeys.ebAccountsRevolut; case .bankinter: KeychainKeys.ebAccountsBankinter }
    }
    var displayName: String {
        switch self { case .revolut: "Revolut"; case .bankinter: "Bankinter" }
    }
    var categoryEmoji: String {
        switch self { case .revolut: "💳"; case .bankinter: "🏦" }
    }
}

enum EBConnectionState: Equatable {
    case notConnected
    case connected(sessionID: String)
}

// MARK: - Service

@MainActor
final class EnableBankingService {
    private let baseURL = "https://api.enablebanking.com"
    let appID: String
    let privateKeyPEM: String

    /// HTTPS redirect URL registered in Enable Banking dashboard.
    /// Must point to a page that JS-redirects to escudo://callback?code=...
    static var redirectURL: String {
        get { UserDefaults.standard.string(forKey: "ebRedirectURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ebRedirectURL") }
    }

    /// Last raw response logged for debugging — exposed to BankSyncCoordinator.
    var debugLog: String?

    /// Pending OAuth continuation — resumed by handleCallback(url:) from AppDelegate.
    nonisolated(unsafe) static var pendingContinuation: CheckedContinuation<String, Error>?

    init(appID: String, privateKeyPEM: String) {
        self.appID = appID
        self.privateKeyPEM = privateKeyPEM
    }

    /// Called by AppDelegate / onOpenURL when escudo:// URL arrives from Safari.
    @MainActor
    static func handleCallback(url: URL) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value
        else {
            pendingContinuation?.resume(throwing: EBError.noCallbackCode)
            pendingContinuation = nil
            return
        }
        pendingContinuation?.resume(returning: code)
        pendingContinuation = nil
    }

    // MARK: - JWT

    func makeJWT() throws -> String {
        let header: [String: Any] = ["typ": "JWT", "alg": "RS256", "kid": appID]
        let now = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": "enablebanking.com",
            "aud": "api.enablebanking.com",
            "iat": now,
            "exp": now + 3600
        ]
        let headerB64  = try JSONSerialization.data(withJSONObject: header).base64URLEncoded()
        let payloadB64 = try JSONSerialization.data(withJSONObject: payload).base64URLEncoded()
        let message    = "\(headerB64).\(payloadB64)"
        let sig        = try rsaSign(message: message)
        return "\(message).\(sig)"
    }

    private func rsaSign(message: String) throws -> String {
        let secKey = try loadPrivateKey()
        let msgData = Data(message.utf8)
        var cfError: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(
            secKey, .rsaSignatureMessagePKCS1v15SHA256, msgData as CFData, &cfError
        ) else {
            throw EBError.signingFailed
        }
        return (sig as Data).base64URLEncoded()
    }

    private func loadPrivateKey() throws -> SecKey {
        let isPKCS8 = privateKeyPEM.contains("BEGIN PRIVATE KEY")

        var pem = privateKeyPEM
        for h in ["-----BEGIN RSA PRIVATE KEY-----", "-----BEGIN PRIVATE KEY-----",
                   "-----END RSA PRIVATE KEY-----",  "-----END PRIVATE KEY-----"] {
            pem = pem.replacingOccurrences(of: h, with: "")
        }
        pem = pem.replacingOccurrences(of: "\n", with: "")
                 .replacingOccurrences(of: "\r", with: "")
                 .replacingOccurrences(of: " ",  with: "")

        guard var keyData = Data(base64Encoded: pem) else { throw EBError.invalidPrivateKey }

        // PKCS#8 wraps the PKCS#1 key inside an ASN.1 OCTET STRING.
        // SecKeyCreateWithData only accepts raw PKCS#1 DER on iOS — unwrap it.
        if isPKCS8 {
            guard let pkcs1 = extractPKCS1fromPKCS8(keyData) else { throw EBError.invalidPrivateKey }
            keyData = pkcs1
        }

        let attrs: [CFString: Any] = [
            kSecAttrKeyType:  kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        var cfError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &cfError) else {
            throw EBError.invalidPrivateKey
        }
        return secKey
    }

    /// Parses PKCS#8 DER and extracts the inner PKCS#1 RSA key.
    /// Structure: SEQUENCE { INTEGER(0), SEQUENCE(AlgoID), OCTET STRING { <pkcs1> } }
    private func extractPKCS1fromPKCS8(_ data: Data) -> Data? {
        var bytes = [UInt8](data)
        var i = 0

        func readLen() -> Int? {
            guard i < bytes.count else { return nil }
            let b = Int(bytes[i]); i += 1
            if b < 0x80 { return b }
            let n = b & 0x7F
            guard i + n <= bytes.count else { return nil }
            var len = 0
            for _ in 0..<n { len = (len << 8) | Int(bytes[i]); i += 1 }
            return len
        }

        func skip(tag: UInt8) -> Int? {
            guard i < bytes.count, bytes[i] == tag else { return nil }
            i += 1; return readLen()
        }

        guard skip(tag: 0x30) != nil else { return nil }  // outer SEQUENCE
        guard let vLen = skip(tag: 0x02) else { return nil }; i += vLen  // version INTEGER
        guard let aLen = skip(tag: 0x30) else { return nil }; i += aLen  // AlgorithmIdentifier
        guard let kLen = skip(tag: 0x04), i + kLen <= bytes.count else { return nil }  // OCTET STRING

        return Data(bytes[i ..< (i + kLen)])
    }

    // MARK: - Connection state

    func connectionState(for bank: EBBank) -> EBConnectionState {
        guard let sid = try? KeychainHelper.load(key: bank.sessionKey) else { return .notConnected }
        return .connected(sessionID: sid)
    }

    // MARK: - Connect

    func connect(bank: EBBank) async throws {
        let jwt = try makeJWT()

        let validUntil = ISO8601DateFormatter().string(from: Date().addingTimeInterval(90 * 24 * 3600))
        let body: [String: Any] = [
            "access":       ["valid_until": validUntil],
            "aspsp":        ["name": bank.aspspName, "country": bank.aspspCountry],
            "state":        UUID().uuidString,
            "redirect_url": EnableBankingService.redirectURL,
            "psu_type":     "personal"
        ]

        let authResp = try await post(path: "/auth", body: body, jwt: jwt, as: EBAuthResponse.self)
        guard let redirectURL = URL(string: authResp.url) else { throw EBError.noCallbackCode }

        let code = try await openBankLink(url: redirectURL)

        let sessionResp = try await post(
            path: "/sessions", body: ["code": code], jwt: jwt, as: EBSessionResponse.self
        )

        try KeychainHelper.save(key: bank.sessionKey,  value: sessionResp.session_id)
        try KeychainHelper.save(key: bank.accountsKey, value: sessionResp.accounts.map { $0.uid }.joined(separator: ","))
    }

    private func openBankLink(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            EnableBankingService.pendingContinuation = continuation
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    // MARK: - ASPSP discovery

    func listASPSPs(country: String) async throws -> [EBASPSPInfo] {
        let jwt = try makeJWT()
        let resp = try await get(path: "/aspsps?country=\(country)", jwt: jwt, as: EBASPSPListResponse.self)
        return resp.aspsps
    }

    // MARK: - Fetch

    func fetchAccounts(for bank: EBBank) async throws -> [EBAccountDetail] {
        let jwt = try makeJWT()
        guard let raw = try? KeychainHelper.load(key: bank.accountsKey) else { throw EBError.notConnected }
        let ids = raw.split(separator: ",").map(String.init)

        // Debug dump — written to Documents/eb-debug-<bank>.json, pulled via devicectl
        var debugDump: [[String: Any]] = []

        var results: [EBAccountDetail] = []
        for id in ids {
            let detailsRaw = try await getRaw(path: "/accounts/\(id)/details",      jwt: jwt)
            let balsRaw    = try await getRaw(path: "/accounts/\(id)/balances",     jwt: jwt)
            let txnsRaw    = try await getRaw(path: "/accounts/\(id)/transactions", jwt: jwt)

            debugLog = String(data: txnsRaw, encoding: .utf8).map { "RAW /transactions: \($0)" }

            // Accumulate all raw responses for file dump
            let detailsJSON = (try? JSONSerialization.jsonObject(with: detailsRaw)) ?? String(data: detailsRaw, encoding: .utf8) ?? ""
            let balsJSON    = (try? JSONSerialization.jsonObject(with: balsRaw))    ?? String(data: balsRaw,    encoding: .utf8) ?? ""
            let txnsJSON    = (try? JSONSerialization.jsonObject(with: txnsRaw))    ?? String(data: txnsRaw,    encoding: .utf8) ?? ""
            debugDump.append(["accountID": id, "details": detailsJSON, "balances": balsJSON, "transactions": txnsJSON])

            let details = try JSONDecoder().decode(EBAccountInfo.self,          from: detailsRaw)
            let bals    = try JSONDecoder().decode(EBBalancesResponse.self,     from: balsRaw)
            let txns    = try JSONDecoder().decode(EBTransactionsResponse.self, from: txnsRaw)

            let balance = bals.balances.first(where: { $0.balance_type == "CLAV" })?.balance_amount.amount
                       ?? bals.balances.first(where: { $0.balance_type == "ITAV" })?.balance_amount.amount
                       ?? bals.balances.first?.balance_amount.amount ?? "0"

            // IBAN from /details (top-level or nested account_id), or extracted from transactions as last resort
            let resolvedIBAN: String? = details.resolvedIBAN
                ?? txns.transactions.lazy.compactMap { $0.ownAccountIBAN }.first

            // Build a useful account name: prefer product, else use IBAN suffix to distinguish accounts,
            // falling back to owner name only if nothing else is available
            let accountName: String = {
                if let product = details.product, !product.isEmpty { return product }
                if let iban = resolvedIBAN, iban.count >= 4 {
                    return "\(bank.displayName) ···\(iban.suffix(4))"
                }
                return details.name ?? details.owner_name ?? bank.displayName
            }()

            results.append(EBAccountDetail(
                accountID:    id,
                iban:         resolvedIBAN,
                name:         accountName,
                currency:     details.currency ?? "EUR",
                balance:      Double(balance) ?? 0,
                transactions: txns.transactions
            ))
        }

        // Write full raw dump to Documents for devicectl extraction
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let dumpData = try? JSONSerialization.data(withJSONObject: debugDump, options: .prettyPrinted) {
            let fileURL = docsURL.appendingPathComponent("eb-debug-\(bank.displayName.lowercased()).json")
            try? dumpData.write(to: fileURL)
        }

        return results
    }

    // MARK: - HTTP helpers

    private func getRaw(path: String, jwt: String) async throws -> Data {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, data: data)
        return data
    }

    private func get<T: Decodable>(path: String, jwt: String, as type: T.Type) async throws -> T {
        let data = try await getRaw(path: path, jwt: jwt)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw EBError.httpError(-2, "Decode failed for \(path): \(error)\nRaw: \(raw.prefix(500))")
        }
    }

    private func post<T: Decodable>(path: String, body: [String: Any], jwt: String, as type: T.Type) async throws -> T {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)",     forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw EBError.httpError(-2, "Decode failed for \(path): \(error)\nRaw: \(raw.prefix(500))")
        }
    }

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw EBError.httpError(code, body)
        }
    }
}


// MARK: - Public composite

struct EBAccountDetail {
    let accountID:    String
    let iban:         String?
    let name:         String
    let currency:     String
    let balance:      Double
    let transactions: [EBTransaction]
}

// MARK: - DTOs

private struct EBASPSPListResponse: Decodable {
    let aspsps: [EBASPSPInfo]
}

struct EBASPSPInfo: Decodable, Identifiable {
    var id: String { name + country }
    let name:    String
    let country: String
    let bic:     String?
}

private struct EBAuthResponse: Decodable {
    let url: String
}

private struct EBSessionResponse: Decodable {
    let session_id: String
    let accounts:   [EBSessionAccount]
}

private struct EBSessionAccount: Decodable {
    let uid: String
}

private struct EBAccountDetailsWrapper: Decodable {
    let account: EBAccountInfo
}

struct EBAccountInfo: Decodable {
    let name:       String?
    let currency:   String?
    let owner_name: String?
    let product:    String?
    let iban:       String?          // top-level (Revolut)
    let account_id: EBAccountID?    // nested (Bankinter PT)

    /// Resolves IBAN from either top-level field or nested account_id (Bankinter PT style)
    var resolvedIBAN: String? { iban ?? account_id?.iban }
}

struct EBAccountID: Decodable {
    let iban: String?
}

private struct EBBalancesResponse: Decodable {
    let balances: [EBBalance]
}

struct EBBalance: Decodable {
    let balance_type:   String
    let balance_amount: EBAmount
}

struct EBAmount: Decodable {
    let amount:   String
    let currency: String
}

private struct EBTransactionsResponse: Decodable {
    let transactions: [EBTransaction]
}

struct EBParty: Decodable {
    let name: String?
}

struct EBAccountRef: Decodable {
    let iban: String?
}

struct EBTransaction: Decodable {
    // IDs — actual API uses entry_reference + transaction_id
    let entry_reference:         String?
    let transaction_id:          String?
    let internal_transaction_id: String?
    // Amount
    let transaction_amount: EBAmount?
    // Credit/Debit indicator — "CRDT" = income, "DBIT" = expense
    let credit_debit_indicator: String?
    // Dates
    let booking_date: String?
    let value_date:   String?
    // Counterparty — objects, not flat strings
    let creditor: EBParty?
    let debtor:   EBParty?
    // Account references — used to extract own IBAN when /details doesn't provide it
    let debtor_account:   EBAccountRef?
    let creditor_account: EBAccountRef?
    // Remittance — actual field name per API logs
    let remittance_information: [String]?

    /// For DBIT (expense): debtor_account is OUR account. For CRDT (income): creditor_account is OUR account.
    var ownAccountIBAN: String? {
        if credit_debit_indicator?.uppercased() == "DBIT" { return debtor_account?.iban }
        if credit_debit_indicator?.uppercased() == "CRDT" { return creditor_account?.iban }
        return debtor_account?.iban ?? creditor_account?.iban
    }

    var effectiveAmount: EBAmount {
        transaction_amount ?? EBAmount(amount: "0", currency: "EUR")
    }
    var effectiveDate: String? {
        booking_date ?? value_date
    }
    var effectiveID: String {
        entry_reference
            ?? transaction_id
            ?? internal_transaction_id
            ?? "\(effectiveDate ?? "")_\(effectiveAmount.amount)_\(effectiveAmount.currency)"
    }
    var isIncome: Bool {
        if let ind = credit_debit_indicator { return ind.uppercased() == "CRDT" }
        return (Double(effectiveAmount.amount) ?? 0) >= 0
    }
    var effectiveDescription: String {
        // Remittance first — most descriptive (e.g. "COMPRA 2811591 Gamestate Eindhoven")
        if let rem = remittance_information?.joined(separator: " "),
           !rem.isEmpty, rem.lowercased() != "payment" {
            // Append counterparty name if remittance is short/generic
            if rem.count < 20, let party = creditor?.name ?? debtor?.name {
                return "\(rem) · \(party)"
            }
            return rem
        }
        // Fallback: counterparty name
        if let party = creditor?.name ?? debtor?.name { return party }
        // Last resort: remittance even if generic
        if let rem = remittance_information?.joined(separator: " "), !rem.isEmpty { return rem }
        return "Transaction"
    }
}

// MARK: - Errors

enum EBError: LocalizedError {
    case invalidPrivateKey
    case signingFailed
    case notConnected
    case noCallbackCode
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: return "Invalid RSA private key — check the PEM format"
        case .signingFailed:     return "JWT signing failed"
        case .notConnected:      return "Bank not connected"
        case .noCallbackCode:    return "No authorization code in callback URL"
        case .httpError(let code, let body):
            return "Enable Banking HTTP \(code): \(body.prefix(200))"
        }
    }
}

// MARK: - Data base64url

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
