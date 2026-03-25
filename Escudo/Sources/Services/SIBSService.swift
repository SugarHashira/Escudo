import Foundation
import UIKit

// MARK: - Connection state

enum SIBSConnectionState: Equatable {
    case notConnected
    case consentPending(consentID: String)
    case connected(consentID: String)
}

// MARK: - Service

/// SIBS API Market — Account Information Service (PSD2 / Berlin Group NextGenPSD2 \(SIBSService.apiVersion))
///
/// Base URL (sandbox):  https://site2.sibsapimarket.com:8445/sibs/apimarket-sb
/// Base URL (prod):     https://site1.sibsapimarket.com:8445/sibs/apimarket-sb
///
/// Authentication: X-IBM-Client-Id header (your client_id from the portal).
/// URL pattern:    /{aspspCode}/\(SIBSService.apiVersion)/{resource}
///
/// Required headers per request:
///   X-IBM-Client-Id, X-Request-ID, Date, Consent-ID (after consent created)
///   Signature (mandated in production — skip in sandbox unless enforced)
///
/// Credentials to store in Keychain before use:
///   sibsClientID     — client_id from SIBS API Market portal
///   sibsClientSecret — client_secret (used for consent OAuth2 SCA redirect)
///
/// ASPSP code to set in UserDefaults "sibsAspspCode":
///   e.g. "BPIPPT" for BPI Portugal, "CGDPPT" for CGD, etc.
@MainActor
final class SIBSService {

    // Sandbox (default) — change to site1 for production.
    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: "sibsBaseURL")
              ?? "https://site1.sibsapimarket.com:8445/sibs/apimarket-sb" }
        set { UserDefaults.standard.set(newValue, forKey: "sibsBaseURL") }
    }

    /// ASPSP code of the bank to connect (e.g. "BNKI" for Bankinter PT).
    static var aspspCode: String {
        get { UserDefaults.standard.string(forKey: "sibsAspspCode") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "sibsAspspCode") }
    }

    /// API version for payment accounts — check developer.sibsapimarket.com → Information Product → available-aspsp.
    /// Most banks: "v1-0-3". Default: "v1-0-3".
    static var apiVersion: String {
        get { UserDefaults.standard.string(forKey: "sibsApiVersion") ?? "v1-0-3" }
        set { UserDefaults.standard.set(newValue, forKey: "sibsApiVersion") }
    }

    /// API version for card accounts — Card Accounts OpenAPI spec uses v1-0-4 paths. Default: "v1-0-4".
    static var cardApiVersion: String {
        get { UserDefaults.standard.string(forKey: "sibsCardApiVersion") ?? "v1-0-4" }
        set { UserDefaults.standard.set(newValue, forKey: "sibsCardApiVersion") }
    }

    let clientID:     String
    let clientSecret: String
    var debugLog: String?

    /// Pending OAuth/SCA continuation — resumed by SIBSService.handleCallback(url:).
    nonisolated(unsafe) static var pendingContinuation: CheckedContinuation<URL, Error>?

    init(clientID: String, clientSecret: String) {
        self.clientID     = clientID
        self.clientSecret = clientSecret
    }

    // MARK: - Callback

    /// Called from AppDelegate when escudo:// URL arrives from Safari after SCA.
    @MainActor
    static func handleCallback(url: URL) {
        pendingContinuation?.resume(returning: url)
        pendingContinuation = nil
    }

    // MARK: - Connection state

    var connectionState: SIBSConnectionState {
        guard let cid = try? KeychainHelper.load(key: KeychainKeys.sibsConsentID)
        else { return .notConnected }
        // If we have an access token as well, consent is fully authorized
        let hasToken = (try? KeychainHelper.load(key: KeychainKeys.sibsAccessToken)) != nil
        return hasToken
            ? .connected(consentID: cid)
            : .consentPending(consentID: cid)
    }

    // MARK: - Connect (consent creation + SCA)

    /// Full PSD2 consent flow:
    /// 1. POST /{aspsp}/\(SIBSService.apiVersion)/consents  → consentId + SCA redirect URL
    /// 2. Open redirect in Safari → PSU authenticates at bank
    /// 3. Bank redirects to GitHub Pages callback → JS-redirects to escudo://callback
    /// 4. App receives callback → mark consent as authorized
    func connect() async throws {
        let aspsp = SIBSService.aspspCode
        guard !aspsp.isEmpty else { throw SIBSError.missingAspspCode }

        let consentResp = try await createConsent(aspsp: aspsp)
        try KeychainHelper.save(key: KeychainKeys.sibsConsentID, value: consentResp.consentId)

        guard let scaURL = URL(string: consentResp.scaRedirect) else {
            throw SIBSError.noSCARedirect
        }

        // Open SCA page; wait for escudo://callback
        let callbackURL = try await openSCA(url: scaURL)

        // The callback URL may carry an OAuth code or just signal consent authorized.
        // Store the access token if present (some ASPSPs send code → exchange for token).
        if let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
           let code = items.first(where: { $0.name == "code" })?.value {
            // Try OAuth2 code exchange — not all ASPSPs require this step
            if let tokenResp = try? await exchangeCode(code: code, aspsp: aspsp) {
                try? KeychainHelper.save(key: KeychainKeys.sibsAccessToken, value: tokenResp.access_token)
                if let rt = tokenResp.refresh_token {
                    try? KeychainHelper.save(key: KeychainKeys.sibsRefreshToken, value: rt)
                }
            }
        }

        // Mark consent as active (use consentId as the "session" marker)
        // We use sibsAccessToken as a "consent activated" flag if no code was exchanged.
        if (try? KeychainHelper.load(key: KeychainKeys.sibsAccessToken)) == nil {
            try KeychainHelper.save(key: KeychainKeys.sibsAccessToken, value: consentResp.consentId)
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        KeychainHelper.delete(key: KeychainKeys.sibsConsentID)
        KeychainHelper.delete(key: KeychainKeys.sibsAccessToken)
        KeychainHelper.delete(key: KeychainKeys.sibsRefreshToken)
    }

    // MARK: - Fetch accounts + transactions

    func fetchAccounts() async throws -> [SIBSAccountDetail] {
        let aspsp   = SIBSService.aspspCode
        guard !aspsp.isEmpty else { throw SIBSError.missingAspspCode }
        let consentID = try loadConsentID()

        var results: [SIBSAccountDetail] = []

        // --- Payment accounts ---
        let accountsRaw  = try await getRaw(path: "/\(aspsp)/\(SIBSService.apiVersion)/accounts", consentID: consentID)
        debugLog = String(data: accountsRaw, encoding: .utf8).map { "RAW /accounts: \($0.prefix(300))" }
        let accountsResp = try decode(SIBSAccountsResponse.self, from: accountsRaw, path: "/accounts")

        for acc in accountsResp.accounts ?? [] {
            let balancesRaw  = try await getRaw(
                path: "/\(aspsp)/\(SIBSService.apiVersion)/accounts/\(acc.resourceId)/balances",
                consentID: consentID
            )
            let txnsRaw = try await getRaw(
                path: "/\(aspsp)/\(SIBSService.apiVersion)/accounts/\(acc.resourceId)/transactions?dateFrom=\(dateFrom())&bookingStatus=both",
                consentID: consentID
            )

            let balsResp = try decode(SIBSAccountBalancesResponse.self, from: balancesRaw, path: "/balances")
            let txnsResp = try decode(SIBSAccountTransactionResponse.self, from: txnsRaw, path: "/transactions")

            let balance = balsResp.balances?.first(where: { $0.balanceType == "closingBooked" })?.balanceAmount.amount
                       ?? balsResp.balances?.first?.balanceAmount.amount ?? "0"

            let txns = (txnsResp.transactions?.booked ?? []) + (txnsResp.transactions?.pending ?? [])

            results.append(SIBSAccountDetail(
                resourceID:   acc.resourceId,
                iban:         acc.iban,
                maskedPan:    nil,
                name:         acc.displayName ?? acc.name ?? acc.product ?? iban4(acc.iban),
                currency:     acc.currency ?? "EUR",
                balance:      Double(balance) ?? 0,
                accountType:  .payment,
                transactions: txns.map { $0.toUnified() }
            ))
        }

        // --- Card accounts (v1-0-4 per Card Accounts OpenAPI spec) ---
        do {
            let cardVer = SIBSService.cardApiVersion
            let cardsRaw  = try await getRaw(path: "/\(aspsp)/\(cardVer)/card-accounts", consentID: consentID)
            debugLog = String(data: cardsRaw, encoding: .utf8).map { "RAW /card-accounts: \($0.prefix(300))" }
            let cardsResp = try decode(SIBSCardAccountsResponse.self, from: cardsRaw, path: "/card-accounts")

            for card in cardsResp.cardAccounts ?? [] {
                let txnsRaw = try await getRaw(
                    path: "/\(aspsp)/\(cardVer)/card-accounts/\(card.resourceId)/transactions?dateFrom=\(dateFrom())&bookingStatus=both",
                    consentID: consentID
                )
                let txnsResp = try decode(SIBSCardTransactionResponse.self, from: txnsRaw, path: "/card-transactions")
                let txns = (txnsResp.cardTransactions?.booked ?? []) + (txnsResp.cardTransactions?.pending ?? [])

                let balance = card.balances?.first(where: { $0.balanceType == "closingBooked" })?.balanceAmount.amount
                           ?? card.balances?.first?.balanceAmount.amount ?? "0"

                let displayName: String = {
                    if let m = card.maskedPan, !m.isEmpty { return "Card ···\(m.suffix(4))" }
                    if let n = card.name,     !n.isEmpty  { return n }
                    return "Credit Card"
                }()

                results.append(SIBSAccountDetail(
                    resourceID:   card.resourceId,
                    iban:         nil,
                    maskedPan:    card.maskedPan,
                    name:         displayName,
                    currency:     card.currency ?? "EUR",
                    balance:      Double(balance) ?? 0,
                    accountType:  .card,
                    transactions: txns.map { $0.toUnified() }
                ))
            }
        } catch SIBSError.httpError(404, _) {
            debugLog = "ℹ️ /card-accounts → 404 (not exposed by this ASPSP)"
        } catch SIBSError.httpError(405, _) {
            debugLog = "ℹ️ /card-accounts → 405 (PIIS not supported)"
        }

        return results
    }

    // MARK: - Consent creation

    private func createConsent(aspsp: String) async throws -> SIBSConsentResponse {
        let validUntil = iso8601DateOnly(daysFromNow: 89)
        let body: [String: Any] = [
            "access": ["allAccounts": "allAccountsWithBalances"],
            "recurringIndicator":        true,
            "validUntil":                validUntil,
            "frequencyPerDay":           4,
            "combinedServiceIndicator":  false
        ]
        return try await postJSON(
            path:      "/\(aspsp)/\(SIBSService.apiVersion)/consents",
            body:      body,
            consentID: nil,
            as:        SIBSConsentResponse.self
        )
    }

    private func openSCA(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            SIBSService.pendingContinuation = continuation
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    // MARK: - Optional OAuth2 code exchange (some ASPSPs only)

    private func exchangeCode(code: String, aspsp: String) async throws -> SIBSTokenResponse {
        var req = URLRequest(url: URL(string: SIBSService.baseURL + "/\(aspsp)/\(SIBSService.apiVersion)/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(clientID, forHTTPHeaderField: "X-IBM-Client-Id")
        let body = "grant_type=authorization_code&code=\(code)&client_id=\(clientID)&client_secret=\(clientSecret)&redirect_uri=escudo://callback"
        req.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, data: data)
        return try decode(SIBSTokenResponse.self, from: data, path: "/token")
    }

    // MARK: - Keychain helpers

    private func loadConsentID() throws -> String {
        guard let cid = try? KeychainHelper.load(key: KeychainKeys.sibsConsentID) else {
            throw SIBSError.notConnected
        }
        return cid
    }

    // MARK: - HTTP helpers

    private func getRaw(path: String, consentID: String) async throws -> Data {
        var req = URLRequest(url: URL(string: SIBSService.baseURL + path)!)
        req.setValue(clientID,               forHTTPHeaderField: "X-IBM-Client-Id")
        req.setValue(UUID().uuidString,      forHTTPHeaderField: "X-Request-ID")
        req.setValue(httpDate(),             forHTTPHeaderField: "Date")
        req.setValue(consentID,              forHTTPHeaderField: "Consent-ID")
        req.setValue("application/json",     forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, data: data)
        return data
    }

    private func postJSON<T: Decodable>(
        path: String, body: [String: Any], consentID: String?, as type: T.Type
    ) async throws -> T {
        var req = URLRequest(url: URL(string: SIBSService.baseURL + path)!)
        req.httpMethod = "POST"
        req.setValue(clientID,             forHTTPHeaderField: "X-IBM-Client-Id")
        req.setValue(UUID().uuidString,    forHTTPHeaderField: "X-Request-ID")
        req.setValue(httpDate(),           forHTTPHeaderField: "Date")
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue("application/json",   forHTTPHeaderField: "Accept")
        if let cid = consentID { req.setValue(cid, forHTTPHeaderField: "Consent-ID") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, data: data)
        return try decode(T.self, from: data, path: path)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, path: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw SIBSError.httpError(-2, "Decode failed [\(path)]: \(error)\nRaw: \(raw.prefix(400))")
        }
    }

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SIBSError.httpError(code, body)
        }
    }

    // MARK: - Date helpers

    private func httpDate() -> String {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        f.timeZone   = TimeZone(abbreviation: "GMT")
        return f.string(from: Date())
    }

    private func iso8601DateOnly(daysFromNow: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func dateFrom() -> String {
        iso8601DateOnly(daysFromNow: -90)   // last 90 days
    }

    private func iban4(_ iban: String?) -> String {
        guard let iban, iban.count >= 4 else { return "Account" }
        return "···\(iban.suffix(4))"
    }
}

// MARK: - Public composite

enum SIBSAccountType { case payment, card }

struct SIBSAccountDetail {
    let resourceID:   String
    let iban:         String?
    let maskedPan:    String?
    let name:         String
    let currency:     String
    let balance:      Double
    let accountType:  SIBSAccountType
    let transactions: [SIBSUnifiedTransaction]
}

struct SIBSUnifiedTransaction {
    let id:          String
    let amount:      String
    let currency:    String
    let isIncome:    Bool
    let date:        String?
    let description: String
}

// MARK: - Consent DTOs

private struct SIBSConsentResponse: Decodable {
    let consentId:     String
    let consentStatus: String?
    let _links: SIBSConsentLinks?

    var scaRedirect: String {
        _links?.scaOAuth?.href
        ?? _links?.scaRedirect?.href
        ?? _links?.startAuthorisationWithPsuAuthentication?.href
        ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case consentId, consentStatus, _links
    }
}

private struct SIBSConsentLinks: Decodable {
    let scaOAuth:                                SIBSHref?
    let scaRedirect:                             SIBSHref?
    let startAuthorisationWithPsuAuthentication: SIBSHref?
}

private struct SIBSHref: Decodable { let href: String }

// MARK: - Token DTO

private struct SIBSTokenResponse: Decodable {
    let access_token:  String
    let refresh_token: String?
    let token_type:    String?
    let expires_in:    Int?
}

// MARK: - Account DTOs (Berlin Group \(SIBSService.apiVersion))

private struct SIBSAccountsResponse: Decodable {
    let accounts: [SIBSAccount]?
}

private struct SIBSAccount: Decodable {
    let resourceId:  String
    let iban:        String?
    let currency:    String?
    let name:        String?
    let displayName: String?
    let product:     String?
    let status:      String?
}

private struct SIBSAccountBalancesResponse: Decodable {
    let balances: [SIBSBalance]?
}

struct SIBSBalance: Decodable {
    let balanceType:   String?
    let balanceAmount: SIBSAmount
}

struct SIBSAmount: Decodable {
    let amount:   String
    let currency: String
}

private struct SIBSAccountTransactionResponse: Decodable {
    let transactions: SIBSTransactionReport?
}

private struct SIBSTransactionReport: Decodable {
    let booked:  [SIBSTransaction]?
    let pending: [SIBSTransaction]?
}

private struct SIBSTransaction: Decodable {
    let entryReference:                    String?
    let transactionAmount:                 SIBSAmount
    let bookingDate:                       String?
    let valueDate:                         String?
    let creditorName:                      String?
    let debtorName:                        String?
    let remittanceInformationUnstructured: String?

    func toUnified() -> SIBSUnifiedTransaction {
        let amount = Double(transactionAmount.amount) ?? 0
        let isIncome = amount >= 0
        let id = entryReference
            ?? "\(bookingDate ?? valueDate ?? "")_\(transactionAmount.amount)"
        let desc = remittanceInformationUnstructured?.isEmpty == false
            ? remittanceInformationUnstructured!
            : creditorName ?? debtorName ?? "Transaction"
        return SIBSUnifiedTransaction(
            id:          id,
            amount:      String(abs(amount)),
            currency:    transactionAmount.currency,
            isIncome:    isIncome,
            date:        bookingDate ?? valueDate,
            description: desc
        )
    }
}

// MARK: - Card Account DTOs
// Matches Card Accounts OpenAPI spec v4.0.1 (/{aspsp-cde}/v1-0-4/card-accounts)

private struct SIBSCardAccountsResponse: Decodable {
    let cardAccounts: [SIBSCardAccount]?
}

/// CardAccountDetail from spec — only required fields are maskedPan + currency; rest optional.
private struct SIBSCardAccount: Decodable {
    let resourceId:  String
    let maskedPan:   String?
    let currency:    String?
    let ownerName:   String?
    let name:        String?
    let displayName: String?
    let product:     String?
    let status:      String?
    let usage:       String?
    let details:     String?
    let creditLimit: SIBSAmount?
    let balances:    [SIBSBalance]?
}

/// CardAccountTransactionResponse from spec.
private struct SIBSCardTransactionResponse: Decodable {
    let cardAccount:      SIBSAccountReference?
    let cardTransactions: SIBSCardAccountReport?
    let balances:         [SIBSBalance]?
}

/// AccountReference — identifies the addressed card account in the response.
private struct SIBSAccountReference: Decodable {
    let iban:      String?
    let bban:      String?
    let pan:       String?
    let maskedPan: String?
    let msisdn:    String?
    let currency:  String?
}

/// CardAccountReport — booked + pending arrays of Transaction.
private struct SIBSCardAccountReport: Decodable {
    let booked:  [SIBSCardTransaction]?
    let pending: [SIBSCardTransaction]?
}

/// Address — used for cardAcceptorAddress.
private struct SIBSAddress: Decodable {
    let street:         String?
    let buildingNumber: String?
    let city:           String?
    let postalCode:     String?
    let country:        String?
}

/// Transaction object from Card Accounts spec — all fields except transactionAmount are optional.
private struct SIBSCardTransaction: Decodable {
    // Identity
    let cardTransactionId:              String?
    let terminalId:                     String?
    // Dates
    let transactionDate:                String?
    let acceptorTransactionDateTime:    String?
    // Amounts
    let transactionAmount:              SIBSAmount         // required
    let originalAmount:                 SIBSAmount?
    let markupFee:                      SIBSAmount?
    let markupFeePercentage:            String?
    // Merchant / acceptor
    let cardAcceptorId:                 String?
    let cardAcceptorAddress:            SIBSAddress?
    let cardAcceptorPhone:              String?
    let merchantCategoryCode:           String?
    // Card
    let maskedPan:                      String?
    // Details
    let transactionDetails:             String?
    let invoiced:                       Bool?
    let proprietaryBankTransactionCode: String?

    func toUnified() -> SIBSUnifiedTransaction {
        let amount = Double(transactionAmount.amount) ?? 0
        // Best stable ID: cardTransactionId → date+amount fallback
        let id = cardTransactionId
            ?? "\(transactionDate ?? acceptorTransactionDateTime ?? "")_\(transactionAmount.amount)"
        // Best description: details → merchant ID → fallback
        let desc = (transactionDetails?.isEmpty == false ? transactionDetails : nil)
            ?? (cardAcceptorId?.isEmpty == false ? cardAcceptorId : nil)
            ?? "Card Transaction"
        return SIBSUnifiedTransaction(
            id:          id,
            amount:      String(abs(amount)),
            currency:    transactionAmount.currency,
            isIncome:    amount >= 0,
            date:        transactionDate,
            description: desc
        )
    }
}

// MARK: - Errors

enum SIBSError: LocalizedError {
    case notConnected
    case missingAspspCode
    case noCallbackCode
    case noSCARedirect
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConnected:     return "SIBS not connected — run connect() first"
        case .missingAspspCode: return "ASPSP code not set — enter your bank code in Settings (e.g. BPIPPT)"
        case .noCallbackCode:   return "No authorization code in SIBS callback"
        case .noSCARedirect:    return "SIBS consent response missing SCA redirect URL"
        case .httpError(let code, let body):
            return "SIBS HTTP \(code): \(body.prefix(200))"
        }
    }
}
