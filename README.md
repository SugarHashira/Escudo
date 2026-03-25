<p align="center">
  <img src="https://raw.githubusercontent.com/SugarHashira/Escudo/master/docs/icon.png" width="120" alt="Escudo app icon" />
</p>

# Escudo

A privacy-first personal finance aggregator for iOS. Pulls data from multiple banks and investment accounts into one unified dashboard — entirely on-device, no backend, no account required.

Built out of two frustrations: every decent finance app costs a monthly subscription, and none of them support Trading 212.

> iOS 17+ · SwiftUI · Core Data

---

## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/SugarHashira/Escudo/master/docs/screen-log.png" width="180" alt="Log screen" />
  &nbsp;
  <img src="https://raw.githubusercontent.com/SugarHashira/Escudo/master/docs/screen-settings.png" width="180" alt="Settings screen" />
  &nbsp;
  <img src="https://raw.githubusercontent.com/SugarHashira/Escudo/master/docs/screen-transaction.jpeg" width="180" alt="Transaction entry" />
  &nbsp;
  <img src="https://raw.githubusercontent.com/SugarHashira/Escudo/master/docs/screen-insights.jpeg" width="180" alt="Insights screen" />
  &nbsp;
  <img src="https://raw.githubusercontent.com/SugarHashira/Escudo/master/docs/screen-budget.jpeg" width="180" alt="Budget screen" />
</p>

---

## What it does

Most people have money spread across a brokerage, a neobank, and a traditional bank. Escudo connects them all and gives you a single view of your net worth, spending, and investments — without your data ever leaving your phone.

| Screen | What you get |
|--------|-------------|
| **Log** | Net worth card + all accounts at a glance |
| **Transactions** | Unified transaction history, auto-categorised |
| **Insights** | Spending breakdown by category, trends over time |
| **Budget** | Budget targets with a visual fuel-gauge dial |
| **Settings** | Connect/disconnect integrations, manage credentials |

---

## Integrations

| Source | How | Data fetched |
|--------|-----|-------------|
| **Trading 212** | REST API (API key) | Portfolio positions, orders, dividends |
| **Revolut** | Enable Banking OAuth 2.0 | Accounts, transactions |
| **Bankinter PT** | Enable Banking OAuth 2.0 | Accounts, transactions |
| **SIBS** | SIBS Open Banking API | Card + account data (PT market) |
| **CSV import** | Manual file import | Revolut & Bankinter statements |

Credentials are stored exclusively in the iOS Keychain — never in UserDefaults, never in iCloud, never on a server.

---

## Features

- **Automatic sync** — background fetch on app launch and via BGTaskScheduler
- **Auto-categorisation** — rule-based keyword matching (Transport, Groceries, Subscriptions, Dining, etc.)
- **Recurring transactions** — template-based recurring transaction engine
- **Budget tracking** — per-category budgets with visual progress dials
- **Multi-currency** — accounts in EUR, GBP, USD handled via stored exchange rates
- **Net worth** — aggregated balance across all accounts + investment portfolio P&L
- **Deep linking** — `escudo://` URL scheme for shortcuts and automation

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI |
| Persistence | SwiftData (Core Data underneath, 5 schema versions) |
| Concurrency | Swift async/await · `@MainActor` throughout |
| Credentials | Security framework (Keychain) |
| Networking | URLSession (no Alamofire) |
| Background | BGTaskScheduler |
| Auth | ASWebAuthenticationSession (OAuth 2.0) |
| Build | XcodeGen (`project.yml`) |
| Min target | iOS 17.0 |

---

## Architecture

```
Trading 212 REST API    → Trading212Service     ┐
Enable Banking OAuth    → EnableBankingService  ├─→ BankSyncCoordinator → SwiftData (local)
SIBS Open Banking       → SIBSService           ┘
CSV (manual import)     → RevolutService / BankinterService ↗
```

**`BankSyncCoordinator`** is the `@MainActor` orchestration singleton. It:
1. Reads credentials from Keychain
2. Instantiates all service clients
3. Runs syncs in parallel
4. Deduplicates and persists transactions via `DataController`
5. Schedules the next background refresh

All services are `@MainActor` because SwiftData `@Model` types are main-actor-bound. No manual thread management needed.

**DTO pattern** — each service uses private `Decodable` structs for API responses, then maps to `@Model` types before persistence. The view layer never touches raw API shapes.

---

## Build

Requires Xcode 15+ and a device or simulator running iOS 17+.

```bash
# Clone
git clone https://github.com/SugarHashira/Escudo.git
cd Escudo

# (Optional) regenerate Xcode project from project.yml
brew install xcodegen
xcodegen generate

# Open and run
open Escudo.xcodeproj
# Cmd+B to build · Cmd+R to run · Cmd+U to test
```

---

## Setup

### Trading 212

1. Go to Trading 212 → Settings → API
2. Generate an API key
3. In Escudo → Settings → Trading 212, paste the key

### Enable Banking (Revolut / Bankinter PT)

Enable Banking is a free Open Banking gateway that connects to Portuguese banks via PSD2. Escudo uses it to fetch Revolut and Bankinter PT accounts and transactions.

1. Create a free account at [enablebanking.com](https://enablebanking.com)
2. Go to **Applications** → **Create application**
3. Set the redirect URI to `escudo://callback`
4. Copy your `clientId` and `clientSecret`
5. In Escudo → Settings → Banks, enter the credentials and tap **Connect**
6. An in-app browser sheet opens — log in to your bank and authorise the connection
7. Escudo stores the access and refresh tokens in the iOS Keychain

> **Note:** Enable Banking has a free tier that covers a limited number of live bank connections. Sufficient for personal use.

### SIBS

1. Register at [developer.sibsgateway.com](https://developer.sibsgateway.com)
2. Obtain API credentials
3. Enter them in Escudo → Settings → SIBS

---

## Project structure

```
Escudo/Sources/
├── EscudoApp.swift              # @main entry, SwiftData container
├── AppDelegate.swift           # Background sync, deep links, notifications
├── Models/                     # Currency, TimeFrame, FilterType, etc.
├── Data/
│   ├── DataController.swift    # Core Data stack, batch ops
│   └── MainModel.xcdatamodeld  # Schema (5 versions)
├── Services/
│   ├── BankSyncCoordinator.swift   # Orchestration hub
│   ├── Trading212Service.swift     # T212 REST client
│   ├── EnableBankingService.swift  # OAuth + banking API
│   ├── SIBSService.swift           # SIBS API client
│   ├── RevolutService.swift        # CSV importer
│   └── BankinterService.swift      # CSV importer
├── Views/                      # 27 SwiftUI screens + components
└── Utils/
    ├── AutoCategoriser.swift   # Keyword-based categorisation
    ├── KeychainHelper.swift    # Keychain CRUD
    ├── KeychainKeys.swift      # Key name constants
    └── EscudoColors.swift      # Theme
```

---

## Known limitations

- **Enable Banking does not expose credit card accounts** — only bank accounts and transactions are available through the PSD2 API; credit card balances and transactions are not accessible
- No token auto-refresh for Enable Banking — manual re-auth needed when tokens expire
- No sync retry — failed syncs log the error and stop
- Categorisation rules are hardcoded (no custom rule UI yet)
- Trading 212 holdings fully replace on each sync (no incremental update)

---

## Contributing

Bug reports and PRs welcome. A few ground rules:

- All new services must follow the `@MainActor` + DTO pattern (see `Trading212Service` as the reference)
- Credentials go in Keychain, never UserDefaults
- Run `xcodebuild -scheme EscudoTests test` before submitting a PR

---

## Acknowledgements

[Dime](https://github.com/rafsoh/dimeApp) — a beautifully designed open-source iOS finance tracker that was a direct inspiration for Escudo. If you want iCloud sync, widgets, and a more polished out-of-the-box experience, check it out.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE) for details.
