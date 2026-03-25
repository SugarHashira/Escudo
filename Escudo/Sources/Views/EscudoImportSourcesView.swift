//
//  EscudoImportSourcesView.swift
//  Escudo — Import sources management
//

import CoreData
import Foundation
import SwiftUI

struct EscudoImportSourcesView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataController: DataController
    @StateObject private var syncCoordinator = BankSyncCoordinator.shared

    // MARK: - T212 state
    @State private var t212ApiKey: String = ""
    @State private var t212AppKeyID: String = ""
    @State private var t212Editing: Bool = false
    @State private var t212Expanded: Bool = false
    @State private var t212Environment: T212Environment = .stored
    @AppStorage("syncDaysBack") private var syncDaysBack: Int = 30
    @State private var showSyncLogs: Bool = false

    // MARK: - Enable Banking state
    @State private var ebAppID: String = ""
    @State private var ebPrivateKey: String = ""
    @State private var ebRedirectURL: String = EnableBankingService.redirectURL
    @State private var ebCredentialsSaved: Bool = false
    @State private var ebExpanded: Bool = false
    @State private var showKeyFilePicker: Bool = false

    // MARK: - Revolut state
    @State private var revolutState: EBConnectionState = .notConnected
    @State private var connectingRevolut: Bool = false
    @State private var revolutExpanded: Bool = false
    @State private var revolutASPSPName: String = EBBank.revolut.aspspName
    @State private var revolutASPSPCountry: String = EBBank.revolut.aspspCountry

    // MARK: - Bankinter state
    @State private var bankinterState: EBConnectionState = .notConnected
    @State private var connectingBankinter: Bool = false
    @State private var bankinterExpanded: Bool = false
    @State private var bankinterASPSPName: String = EBBank.bankinter.aspspName
    @State private var bankinterASPSPCountry: String = EBBank.bankinter.aspspCountry

    // MARK: - SIBS state
    @State private var sibsClientID: String = ""
    @State private var sibsClientSecret: String = ""
    @State private var sibsBaseURL: String = SIBSService.baseURL
    @State private var sibsAspspCode: String = SIBSService.aspspCode
    @State private var sibsApiVersion: String = SIBSService.apiVersion
    @State private var sibsCredentialsSaved: Bool = false
    @State private var sibsExpanded: Bool = false
    @State private var sibsState: SIBSConnectionState = .notConnected
    @State private var connectingSIBS: Bool = false

    @State private var showImportPicker: Bool = false
    @State private var syncError: String? = nil

    // MARK: - Derived

    private var t212Connected: Bool { !t212ApiKey.isEmpty }

    private var lastSyncString: String {
        if let ts = UserDefaults.standard.object(forKey: "lastT212Sync") as? Date {
            let diff = Date.now.timeIntervalSince(ts)
            if diff < 60 { return "just now" }
            if diff < 3600 { return "\(Int(diff / 60)) min ago" }
            let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
            return fmt.string(from: ts)
        }
        return "never"
    }

    private var t212TxCount: Int {
        let req: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        req.predicate = NSPredicate(format: "account.source == %@", "trading212")
        return (try? dataController.container.viewContext.fetch(req))?.count ?? 0
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero
                    VStack(alignment: .leading, spacing: 4) {
                        Text("4 sources.")
                            .font(.escudo(28, weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(Color.escudoText)
                        Text("connect or import data from your banks")
                            .font(.escudo(13))
                            .foregroundStyle(Color.escudoTextDim)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                    VStack(spacing: 10) {
                        // Trading 212
                        t212Card

                        // Enable Banking credentials (shared for Revolut + Bankinter)
                        ebCredentialsCard

                        // Revolut
                        bankCard(
                            badge: "RV", badgeColor: Color(hex: "#c46a4a"),
                            name: "Revolut", bank: .revolut,
                            state: revolutState, connecting: connectingRevolut,
                            expanded: $revolutExpanded,
                            aspspName: $revolutASPSPName, aspspCountry: $revolutASPSPCountry,
                            onConnect: { Task { await connectBank(.revolut) } }
                        )

                        // Bankinter PT
                        bankCard(
                            badge: "BK", badgeColor: Color(hex: "#d9a441"),
                            name: "Bankinter PT", bank: .bankinter,
                            state: bankinterState, connecting: connectingBankinter,
                            expanded: $bankinterExpanded,
                            aspspName: $bankinterASPSPName, aspspCountry: $bankinterASPSPCountry,
                            onConnect: { Task { await connectBank(.bankinter) } }
                        )

                        // SIBS Open Banking
                        sibsCard
                    }
                    .padding(.horizontal, 20)

                    // CSV / file drop zone
                    VStack(spacing: 6) {
                        Text("DROP CSV / OFX / PDF")
                            .font(.escudo(11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Color.escudoTextMuted)
                        Text("we'll auto-detect the format")
                            .font(.escudo(10))
                            .foregroundStyle(Color.escudoTextDim)
                        Button { showImportPicker = true } label: {
                            Text("CHOOSE FILE")
                                .font(.escudo(10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(Color.escudoAccent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .overlay(Capsule().stroke(Color.escudoAccent, lineWidth: 1))
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(Color.escudoLine)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 80)
                }
            }
            .background(Color.PrimaryBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Text("BACK")
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoTextDim)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("IMPORT · SOURCES")
                        .font(.escudo(10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Color.escudoTextMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if syncCoordinator.isSyncing {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .sheet(isPresented: $showSyncLogs) {
                NavigationView {
                    ScrollView {
                        Text(syncCoordinator.syncLogs.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                    .navigationTitle("Sync Logs")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSyncLogs = false }
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { loadKeys() }
    }

    // MARK: - Trading 212 card

    private var t212Card: some View {
        VStack(spacing: 0) {
            // Header (always visible)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    t212Expanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    InitialBadge(label: "T2", color: Color(hex: "#8fae6b"), size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Trading 212")
                            .font(.escudo(14, weight: .semibold))
                            .foregroundStyle(Color.escudoText)
                        Text("API · portfolio + dividends")
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoTextMuted)
                        Text(t212Connected
                            ? "LAST \(lastSyncString.uppercased()) · \(t212TxCount) TX"
                            : "NOT CONFIGURED")
                            .font(.escudo(10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(Color.escudoTextDim)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    chipLabel(
                        text: t212Connected ? "SYNCED" : "CONNECT",
                        color: t212Connected ? Color.escudoPos : Color.escudoAccent,
                        expanded: t212Expanded
                    )
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // Expanded content
            if t212Expanded {
                sourceDivider

                VStack(alignment: .leading, spacing: 14) {
                    // Environment picker
                    sectionLabel("ENVIRONMENT")
                    Picker("", selection: $t212Environment) {
                        ForEach(T212Environment.allCases, id: \.self) { env in
                            Text(env.displayName).tag(env)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: t212Environment) { env in
                        env.store()
                        BankSyncCoordinator.shared.buildServices()
                    }

                    // Credentials
                    sectionLabel("API CREDENTIALS")
                    if t212Editing || (t212ApiKey.isEmpty && t212AppKeyID.isEmpty) {
                        VStack(spacing: 8) {
                            TextField("App Key ID", text: $t212AppKeyID)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            SecureField("Secret Key", text: $t212ApiKey)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            saveButton(label: "Save Credentials", disabled: t212ApiKey.isEmpty) {
                                saveT212Key()
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("App Key ID: \(maskedID(t212AppKeyID))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.escudoTextMuted)
                                Text("Secret Key: ••••••••")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.escudoTextMuted)
                            }
                            Spacer()
                            editButton { t212Editing = true }
                        }
                    }

                    // Sync period
                    HStack {
                        Text("Sync period")
                            .font(.escudo(12))
                            .foregroundStyle(Color.escudoTextMuted)
                        Spacer()
                        Picker("", selection: $syncDaysBack) {
                            ForEach([7, 14, 30, 60, 90, 180, 365], id: \.self) { d in
                                Text(d == 365 ? "1 year" : "\(d) days").tag(d)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Sync + logs
                    HStack(spacing: 8) {
                        Button {
                            Task { await doSync() }
                        } label: {
                            HStack(spacing: 6) {
                                if syncCoordinator.isSyncing {
                                    ProgressView().scaleEffect(0.75)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(syncCoordinator.isSyncing ? "Syncing…" : "Sync All")
                                    .font(.escudo(12, weight: .semibold))
                            }
                            .foregroundStyle(Color.escudoText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.PrimaryBackground)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.escudoLine, lineWidth: 1))
                            .cornerRadius(8)
                        }
                        .disabled(syncCoordinator.isSyncing)

                        Button { showSyncLogs = true } label: {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(syncCoordinator.syncLogs.isEmpty ? Color.escudoTextDim : Color.escudoText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.PrimaryBackground)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.escudoLine, lineWidth: 1))
                                .cornerRadius(8)
                        }
                        .disabled(syncCoordinator.syncLogs.isEmpty)
                    }

                    if let err = syncCoordinator.lastError {
                        Text(err)
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoNeg)
                    }
                }
                .padding(16)
                .padding(.top, 4)
            }
        }
        .background(Color.escudoSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.escudoLine, lineWidth: 1))
        .cornerRadius(12)
    }

    // MARK: - Enable Banking credentials card

    private var ebCredentialsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    ebExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    InitialBadge(label: "EB", color: Color(hex: "#5b8fc9"), size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enable Banking")
                            .font(.escudo(14, weight: .semibold))
                            .foregroundStyle(Color.escudoText)
                        Text("Shared credentials · Revolut + Bankinter")
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoTextMuted)
                        Text(ebCredentialsSaved ? "CREDENTIALS SAVED" : "NOT CONFIGURED")
                            .font(.escudo(10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(Color.escudoTextDim)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    chipLabel(
                        text: ebCredentialsSaved ? "SAVED" : "SETUP",
                        color: ebCredentialsSaved ? Color.escudoPos : Color.escudoWarn,
                        expanded: ebExpanded
                    )
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if ebExpanded {
                sourceDivider

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("APP ID")
                    if ebCredentialsSaved && !ebExpanded {
                        // Won't show — ebExpanded is true here
                        EmptyView()
                    }
                    // Always show fields when expanded
                    TextField("App ID (UUID)", text: $ebAppID)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    sectionLabel("REDIRECT URL")
                    TextField("https://yoursite.github.io/escudo-auth/", text: $ebRedirectURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .onChange(of: ebRedirectURL) { url in
                            EnableBankingService.redirectURL = url
                        }

                    sectionLabel("PRIVATE KEY (PEM)")
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $ebPrivateKey)
                            .frame(height: 80)
                            .font(.system(.caption, design: .monospaced))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.escudoLine))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if ebPrivateKey.isEmpty {
                            Text("Paste RSA private key…")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.escudoTextDim)
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            showKeyFilePicker = true
                        } label: {
                            Label("Import Key File", systemImage: "doc.badge.plus")
                                .font(.escudo(11, weight: .semibold))
                                .foregroundStyle(Color.escudoAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.escudoAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .fileImporter(
                            isPresented: $showKeyFilePicker,
                            allowedContentTypes: [.text, .data],
                            allowsMultipleSelection: false
                        ) { result in
                            if case .success(let urls) = result,
                               let url = urls.first,
                               url.startAccessingSecurityScopedResource() {
                                defer { url.stopAccessingSecurityScopedResource() }
                                ebPrivateKey = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                            }
                        }

                        saveButton(
                            label: "Save",
                            disabled: ebAppID.isEmpty || ebPrivateKey.isEmpty
                        ) {
                            saveEnableBankingCredentials()
                        }
                    }
                }
                .padding(16)
                .padding(.top, 4)
            }
        }
        .background(Color.escudoSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.escudoLine, lineWidth: 1))
        .cornerRadius(12)
    }

    // MARK: - Revolut / Bankinter bank card

    @ViewBuilder
    private func bankCard(
        badge: String,
        badgeColor: Color,
        name: String,
        bank: EBBank,
        state: EBConnectionState,
        connecting: Bool,
        expanded: Binding<Bool>,
        aspspName: Binding<String>,
        aspspCountry: Binding<String>,
        onConnect: @escaping () -> Void
    ) -> some View {
        let connected = { if case .connected = state { return true }; return false }()
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    InitialBadge(label: badge, color: badgeColor, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.escudo(14, weight: .semibold))
                            .foregroundStyle(Color.escudoText)
                        Text("Enable Banking · auto-sync")
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoTextMuted)
                        Text(stateLabel(state))
                            .font(.escudo(10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(Color.escudoTextDim)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    chipLabel(
                        text: connected ? "LIVE" : "CONNECT",
                        color: connected ? Color.escudoPos : (ebCredentialsSaved ? Color.escudoAccent : Color.escudoTextDim),
                        expanded: expanded.wrappedValue
                    )
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                sourceDivider

                VStack(alignment: .leading, spacing: 14) {
                    if !ebCredentialsSaved {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.escudoWarn)
                            Text("Save Enable Banking credentials first")
                                .font(.escudo(12))
                                .foregroundStyle(Color.escudoTextMuted)
                        }
                    } else {
                        sectionLabel("ASPSP IDENTIFIER")
                        HStack(spacing: 8) {
                            TextField("Bank name", text: aspspName)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: aspspName.wrappedValue) {
                                    UserDefaults.standard.set($0, forKey: bank.aspspNameKey)
                                }
                            TextField("CC", text: aspspCountry)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 54)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .onChange(of: aspspCountry.wrappedValue) {
                                    UserDefaults.standard.set($0, forKey: bank.aspspCountryKey)
                                }
                        }

                        if connecting {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("Connecting…")
                                    .font(.escudo(12))
                                    .foregroundStyle(Color.escudoTextMuted)
                            }
                        } else {
                            Button(action: onConnect) {
                                Text(connected ? "Reconnect" : "Connect Bank")
                                    .font(.escudo(12, weight: .semibold))
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        connected ? Color.escudoPos.opacity(0.8) : Color.escudoAccent,
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                        }
                    }

                    if let err = syncError {
                        Text(err)
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoNeg)
                    }
                }
                .padding(16)
                .padding(.top, 4)
            }
        }
        .background(Color.escudoSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.escudoLine, lineWidth: 1))
        .cornerRadius(12)
    }

    // MARK: - SIBS card

    private var sibsCard: some View {
        let connected: Bool = {
            if case .connected = sibsState { return true }
            return false
        }()

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    sibsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    InitialBadge(label: "SB", color: Color(hex: "#1A73E8"), size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SIBS Open Banking")
                            .font(.escudo(14, weight: .semibold))
                            .foregroundStyle(Color.escudoText)
                        Text("PSD2 · bank + credit card accounts")
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoTextMuted)
                        Text(sibsStatLabel)
                            .font(.escudo(10, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(Color.escudoTextDim)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    chipLabel(
                        text: connected ? "LIVE" : (sibsCredentialsSaved ? "CONNECT" : "SETUP"),
                        color: connected ? Color.escudoPos : (sibsCredentialsSaved ? Color.escudoAccent : Color.escudoWarn),
                        expanded: sibsExpanded
                    )
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if sibsExpanded {
                sourceDivider

                VStack(alignment: .leading, spacing: 14) {
                    // Base URL (sandbox vs production)
                    sectionLabel("API BASE URL")
                    Picker("", selection: $sibsBaseURL) {
                        Text("Sandbox (site1)").tag("https://site1.sibsapimarket.com:8445/sibs/apimarket-sb")
                        Text("Sandbox (site2)").tag("https://site2.sibsapimarket.com:8445/sibs/apimarket-sb")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: sibsBaseURL) { url in SIBSService.baseURL = url }

                    // ASPSP code — identifies the bank
                    // API version picker
                    sectionLabel("API VERSION")
                    Picker("", selection: $sibsApiVersion) {
                        Text("v1-0-3 (Bankinter, most banks)").tag("v1-0-3")
                        Text("v1-0-4 (newer banks)").tag("v1-0-4")
                        Text("v1-0-2 (legacy)").tag("v1-0-2")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: sibsApiVersion) { v in SIBSService.apiVersion = v }

                    sectionLabel("ASPSP CODE (YOUR BANK)")
                    HStack(spacing: 6) {
                        TextField("e.g. BPIPPT", text: $sibsAspspCode)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .onChange(of: sibsAspspCode) { code in
                                SIBSService.aspspCode = code
                            }
                        Button {
                            if let url = URL(string: "https://developer.sibsapimarket.com") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(Color.escudoAccent)
                        }
                    }
                    Text("Find your bank code on developer.sibsapimarket.com → Sandbox → ASPSPs")
                        .font(.escudo(10))
                        .foregroundStyle(Color.escudoTextDim)

                    // Credentials
                    sectionLabel("OAUTH2 CREDENTIALS")
                    if !sibsCredentialsSaved {
                        VStack(spacing: 8) {
                            TextField("Client ID", text: $sibsClientID)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            SecureField("Client Secret", text: $sibsClientSecret)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            saveButton(
                                label: "Save Credentials",
                                disabled: sibsClientID.isEmpty || sibsClientSecret.isEmpty
                            ) {
                                saveSIBSCredentials()
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Client ID: \(maskedID(sibsClientID))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.escudoTextMuted)
                                Text("Client Secret: ••••••••")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color.escudoTextMuted)
                            }
                            Spacer()
                            editButton {
                                sibsCredentialsSaved = false
                            }
                        }

                        // Connect / disconnect
                        if connectingSIBS {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("Connecting — check Safari…")
                                    .font(.escudo(12))
                                    .foregroundStyle(Color.escudoTextMuted)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button {
                                    Task { await connectSIBS() }
                                } label: {
                                    Text(connected ? "Reconnect" : "Connect Bank")
                                        .font(.escudo(12, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            connected ? Color.escudoPos.opacity(0.8) : Color.escudoAccent,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                }

                                if connected {
                                    Button {
                                        SIBSService(clientID: sibsClientID, clientSecret: sibsClientSecret).disconnect()
                                        sibsState = .notConnected
                                    } label: {
                                        Text("Disconnect")
                                            .font(.escudo(12, weight: .semibold))
                                            .foregroundStyle(Color.escudoNeg)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.escudoNeg.opacity(0.5), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                    }

                    if let err = syncError {
                        Text(err)
                            .font(.escudo(11))
                            .foregroundStyle(Color.escudoNeg)
                    }
                }
                .padding(16)
                .padding(.top, 4)
            }
        }
        .background(Color.escudoSurface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.escudoLine, lineWidth: 1))
        .cornerRadius(12)
    }

    private var sibsStatLabel: String {
        switch sibsState {
        case .notConnected:          return sibsCredentialsSaved ? "NOT CONNECTED" : "NOT CONFIGURED"
        case .consentPending:        return "CONSENT PENDING"
        case .connected:             return "CONNECTED"
        }
    }

    // MARK: - Reusable sub-components

    private var sourceDivider: some View {
        Rectangle()
            .fill(Color.escudoLine)
            .frame(height: 1)
    }

    private func chipLabel(text: String, color: Color, expanded: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.escudo(9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(color)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.escudoTextMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.7), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.escudo(9, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Color.escudoTextMuted)
    }

    private func saveButton(label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.escudo(12, weight: .semibold))
                .foregroundStyle(disabled ? Color.escudoTextDim : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    disabled ? Color.escudoLine : Color.escudoAccent,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .disabled(disabled)
    }

    private func editButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Edit")
                .font(.escudo(11, weight: .semibold))
                .foregroundStyle(Color.escudoAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.escudoAccent.opacity(0.5), lineWidth: 1)
                )
        }
    }

    private func stateLabel(_ state: EBConnectionState) -> String {
        if case .connected = state { return "CONNECTED" }
        return "NOT CONNECTED"
    }

    private func maskedID(_ s: String) -> String {
        guard s.count > 6 else { return s.isEmpty ? "—" : "••••" }
        return "\(s.prefix(4))…\(s.suffix(2))"
    }

    // MARK: - Actions

    private func loadKeys() {
        t212ApiKey   = (try? KeychainHelper.load(key: KeychainKeys.trading212)) ?? ""
        t212AppKeyID = (try? KeychainHelper.load(key: KeychainKeys.trading212AppKeyID)) ?? ""
        ebAppID       = (try? KeychainHelper.load(key: KeychainKeys.ebAppID)) ?? ""
        ebPrivateKey  = (try? KeychainHelper.load(key: KeychainKeys.ebPrivateKey)) ?? ""
        ebRedirectURL = EnableBankingService.redirectURL
        ebCredentialsSaved = !ebAppID.isEmpty && !ebPrivateKey.isEmpty
        revolutASPSPName    = UserDefaults.standard.string(forKey: EBBank.revolut.aspspNameKey)    ?? EBBank.revolut.aspspName
        revolutASPSPCountry = UserDefaults.standard.string(forKey: EBBank.revolut.aspspCountryKey) ?? EBBank.revolut.aspspCountry
        bankinterASPSPName    = UserDefaults.standard.string(forKey: EBBank.bankinter.aspspNameKey)    ?? EBBank.bankinter.aspspName
        bankinterASPSPCountry = UserDefaults.standard.string(forKey: EBBank.bankinter.aspspCountryKey) ?? EBBank.bankinter.aspspCountry
        if ebCredentialsSaved {
            let svc = EnableBankingService(appID: ebAppID, privateKeyPEM: ebPrivateKey)
            revolutState   = svc.connectionState(for: .revolut)
            bankinterState = svc.connectionState(for: .bankinter)
        }

        // SIBS
        sibsClientID     = (try? KeychainHelper.load(key: KeychainKeys.sibsClientID))     ?? ""
        sibsClientSecret = (try? KeychainHelper.load(key: KeychainKeys.sibsClientSecret)) ?? ""
        sibsBaseURL      = SIBSService.baseURL
        sibsAspspCode    = SIBSService.aspspCode
        sibsApiVersion   = SIBSService.apiVersion
        sibsCredentialsSaved = !sibsClientID.isEmpty && !sibsClientSecret.isEmpty
        if sibsCredentialsSaved {
            let svc = SIBSService(clientID: sibsClientID, clientSecret: sibsClientSecret)
            sibsState = svc.connectionState
        }
    }

    private func saveT212Key() {
        let key = t212ApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let kid = t212AppKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        t212ApiKey = key; t212AppKeyID = kid
        try? KeychainHelper.save(key: KeychainKeys.trading212, value: key)
        if !kid.isEmpty {
            try? KeychainHelper.save(key: KeychainKeys.trading212AppKeyID, value: kid)
        }
        t212Editing = false
        BankSyncCoordinator.shared.buildServices()
    }

    private func saveEnableBankingCredentials() {
        let id  = ebAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ebPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !key.isEmpty else { return }
        ebAppID = id; ebPrivateKey = key
        try? KeychainHelper.save(key: KeychainKeys.ebAppID, value: id)
        try? KeychainHelper.save(key: KeychainKeys.ebPrivateKey, value: key)
        ebCredentialsSaved = true
        ebExpanded = false
        BankSyncCoordinator.shared.buildServices()
    }

    @MainActor
    private func doSync() async {
        await BankSyncCoordinator.shared.manualSync()
        UserDefaults.standard.set(Date.now, forKey: "lastT212Sync")
    }

    private func saveSIBSCredentials() {
        let id  = sibsClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sec = sibsClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !sec.isEmpty else { return }
        sibsClientID = id; sibsClientSecret = sec
        try? KeychainHelper.save(key: KeychainKeys.sibsClientID,     value: id)
        try? KeychainHelper.save(key: KeychainKeys.sibsClientSecret, value: sec)
        sibsCredentialsSaved = true
        BankSyncCoordinator.shared.buildServices()
    }

    @MainActor
    private func connectSIBS() async {
        connectingSIBS = true
        defer { connectingSIBS = false }
        syncError = nil
        let svc = SIBSService(clientID: sibsClientID, clientSecret: sibsClientSecret)
        do {
            try await svc.connect()
            sibsState = svc.connectionState
            BankSyncCoordinator.shared.buildServices()
            await BankSyncCoordinator.shared.manualSync()
        } catch {
            syncError = "SIBS: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func connectBank(_ bank: EBBank) async {
        let isRevolut = bank == .revolut
        if isRevolut { connectingRevolut = true } else { connectingBankinter = true }
        defer {
            if isRevolut { connectingRevolut = false } else { connectingBankinter = false }
        }
        syncError = nil
        let svc = EnableBankingService(appID: ebAppID, privateKeyPEM: ebPrivateKey)
        do {
            try await svc.connect(bank: bank)
            if isRevolut { revolutState = svc.connectionState(for: .revolut) }
            else         { bankinterState = svc.connectionState(for: .bankinter) }
            BankSyncCoordinator.shared.buildServices()
            await BankSyncCoordinator.shared.manualSync()
        } catch {
            syncError = "\(bank.displayName): \(error.localizedDescription)"
        }
    }
}
