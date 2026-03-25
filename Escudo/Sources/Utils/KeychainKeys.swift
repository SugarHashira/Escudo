enum KeychainKeys {
    // Trading 212
    static let trading212          = "escudo.trading212.apiKey"
    static let trading212AppKeyID  = "escudo.trading212.appKeyID"

    // Enable Banking
    static let ebAppID             = "escudo.enablebanking.appID"
    static let ebPrivateKey        = "escudo.enablebanking.privateKey"

    // Per-bank session IDs + account ID lists (comma-separated)
    static let ebSessionRevolut    = "escudo.enablebanking.session.revolut"
    static let ebAccountsRevolut   = "escudo.enablebanking.accounts.revolut"
    static let ebSessionBankinter  = "escudo.enablebanking.session.bankinter"
    static let ebAccountsBankinter = "escudo.enablebanking.accounts.bankinter"

    // SIBS Open Banking (Berlin Group / PSD2)
    static let sibsClientID        = "escudo.sibs.clientID"
    static let sibsClientSecret    = "escudo.sibs.clientSecret"
    static let sibsAccessToken     = "escudo.sibs.accessToken"
    static let sibsRefreshToken    = "escudo.sibs.refreshToken"
    static let sibsConsentID       = "escudo.sibs.consentID"
}
