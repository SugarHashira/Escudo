import Combine
import CoreData
import Foundation
import StoreKit
import SwiftUI
import UserNotifications
import WidgetKit

struct SettingsView: View {
  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  @AppStorage("colourScheme", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var colourScheme: Int = 0
  var colourSchemeString: String {
    if colourScheme == 1 {
      return String(localized: "Light")
    } else if colourScheme == 2 {
      return String(localized: "Dark")
    } else {
      return String(localized: "System")
    }
  }



  @AppStorage("firstWeekday", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var firstWeekday: Int = 1
  var firstWeekdayString: String {
    if firstWeekday == 1 {
      return String(localized: "Sunday")
    } else {
      return String(localized: "Monday")
    }
  }

  @AppStorage("showNotifications", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var showNotifications: Bool = false
  @AppStorage("notificationOption", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var option: Int = 1
  var notificationString: String {
    if showNotifications {
      if option == 1 {
        return String(localized: "Mornings")
      } else if option == 2 {
        return String(localized: "Evenings")
      } else {
        return String(localized: "Custom")
      }
    } else {
      return String(localized: "Off")
    }
  }

  @EnvironmentObject var appLockVM: AppLockViewModel
  @Namespace var animation

  var iCloudString: String {
    if NSUbiquitousKeyValueStore.default.bool(forKey: "icloud_sync") {
      return String(localized: "On")
    } else {
      return String(localized: "Off")
    }
  }

  @Environment(\.openURL) var openURL
  let supportEmail = SupportEmail(toAddress: "sugarhashira@users.noreply.github.com", subject: "Escudo Support")
  let featureRequestEmail = SupportEmail(
    toAddress: "sugarhashira@users.noreply.github.com", subject: "Escudo Feature Request")

  @AppStorage("numberEntryType", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var numberEntryType: Int = 2

  var numberEntryString: String {
    if numberEntryType == 1 {
      return String(localized: "Type 1")
    } else {
      return String(localized: "Type 2")
    }
  }

  @AppStorage("showCents", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var showCents: Bool = true

  @AppStorage("animated", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var animated:
    Bool = true

  @AppStorage("currency", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var currency:
    String = Locale.current.currencyCode ?? "EUR"

  @AppStorage("incomeTracking", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var incomeTracking: Bool = true

  @AppStorage("autoCategorizerEnabled")
  var autoCategorizerEnabled: Bool = true
    
  @AppStorage("showExpenseOrIncomeSign", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var showExpenseOrIncomeSign: Bool = true

  @AppStorage(
    "showUpcomingTransactions", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
  var showUpcoming: Bool = true

  var upcomingString: String {
    if showUpcoming {
      return String(localized: "Shown")
    } else {
      return String(localized: "Hidden")
    }
  }

    @AppStorage("haptics", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo"))
    var hapticType: Int = 1

    var hapticString: String {
      if hapticType == 0 {
        return String(localized: "None")
      } else if hapticType == 1 {
        return String(localized: "Subtle")
      } else {
        return String(localized: "Excessive")
      }
    }

  // popups

  @State var showImportGuide = false
  @State var showUpdate: Bool = false
  @State private var showRestorePicker = false
  @State private var restoreError: String? = nil
  @State private var restoreSuccess = false

  @EnvironmentObject var tabBarManager: TabBarManager

  @EnvironmentObject var dataController: DataController

  var body: some View {
    NavigationView {
      VStack {
        HStack {
          Text("SETTINGS")
            .font(.escudo(10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Color.escudoTextMuted)
            .accessibility(addTraits: .isHeader)
          Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 10)

        ScrollView(showsIndicators: false) {
          EscudoNetWorthTile()
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

          VStack(spacing: 5) {
            Text("GENERAL")
              .font(.escudo(9, weight: .semibold))
              .tracking(1.6)
              .foregroundStyle(Color.escudoTextMuted)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 13) {

              NavigationLink(destination: AccountsView()) {
                SettingsRowView(
                  systemImage: "creditcard.fill", title: "Accounts", colour: 104,
                  optionalText: nil)
              }

              NavigationLink(destination: SettingsNotificationsView()) {
                SettingsRowView(
                  systemImage: "bell.fill", title: "Notifications", colour: 102,
                  optionalText: notificationString)
              }

              NavigationLink(destination: SettingsCurrencyView()) {
                SettingsRowView(
                  systemImage: "coloncurrencysign.square.fill", title: "Currency", colour: 103,
                  optionalText: currency)
              }

              NavigationLink(
                destination: SettingsNumberEntryView()
                  .onAppear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationHideTab()
                    }
                  }
                  .onDisappear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationShowTab()
                    }
                  }
              ) {
                SettingsRowView(
                  systemImage: "keyboard.fill", title: "Number Entry", colour: 104,
                  optionalText: numberEntryString)
              }

              ToggleRow(
                icon: "faceid", color: "105", text: "Authentication",
                bool: appLockVM.isAppLockEnabled,
                onTap: {
                  appLockVM.appLockStateChange(appLockState: !appLockVM.isAppLockEnabled)
                })

              ToggleRow(
                icon: "banknote.fill", color: "106", text: "Income Tracking", bool: incomeTracking,
                onTap: {
                  incomeTracking.toggle()

                  if !incomeTracking {
                    UserDefaults(suiteName: "group.com.sugarhashira.Escudo")!.set(
                      false, forKey: "insightsViewIncomeFiltering")
                    UserDefaults(suiteName: "group.com.sugarhashira.Escudo")!.set(
                      3, forKey: "logInsightsType")
                  }
                })

              NavigationLink(destination: SettingsWeekStartView()) {
                SettingsRowView(systemImage: "calendar", title: "Time Frames", colour: 109)
              }

              NavigationLink(destination: SettingsHapticsView()) {
                SettingsRowView(
                  systemImage: "hand.tap.fill", title: "Haptics", colour: 100,
                  optionalText: hapticString)
              }

              NavigationLink(destination: SettingsGoofyView()) {
                SettingsRowView(systemImage: "flame.fill", title: "Feature Lab", colour: 122)
              }

            }
            .padding(10)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 25)
          .onChange(of: currency) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: firstWeekday) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: showCents) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }

          VStack(spacing: 5) {
            Text("APPEARANCE")
              .font(.escudo(9, weight: .semibold))
              .tracking(1.6)
              .foregroundStyle(Color.escudoTextMuted)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 13) {
              NavigationLink(destination: SettingsAppearanceView()) {
                SettingsRowView(
                  systemImage: "circle.righthalf.filled", title: "Theme", colour: 100,
                  optionalText: colourSchemeString)
              }

ToggleRow(
                icon: "centsign.circle.fill", color: "107", text: "Display Cents", bool: showCents,
                onTap: {
                  showCents.toggle()
                })

              NavigationLink(destination: SettingsUpcomingView()) {
                SettingsRowView(
                  systemImage: "sun.min.fill", title: "Upcoming Logs", colour: 108,
                  optionalText: upcomingString)
              }
                
              ToggleRow(
                icon: "plusminus", color: "123", text: "Display +/- Symbol", bool: showExpenseOrIncomeSign,
                onTap: {
                    showExpenseOrIncomeSign.toggle()
                })

              ToggleRow(
                icon: "hare.fill", color: "121", text: "Animated Charts", bool: animated, smaller: true,
                onTap: {
                  animated.toggle()
                })

            }
            .padding(10)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 25)
          .onChange(of: currency) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: firstWeekday) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }
          .onChange(of: showCents) { _ in
            WidgetCenter.shared.reloadAllTimelines()
          }

          VStack(spacing: 5) {
            Text("DATA")
              .font(.escudo(9, weight: .semibold))
              .tracking(1.6)
              .foregroundStyle(Color.escudoTextMuted)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 13) {
              NavigationLink(
                destination: SettingsCategoryView()
                  .onAppear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationHideTab()
                    }
                  }
                  .onDisappear {
                    withAnimation(.easeOut.speed(1.5)) {
                      tabBarManager.navigationShowTab()
                    }
                  }

              ) {
                SettingsRowView(
                  systemImage: "rectangle.grid.2x2.fill", title: "Categories", colour: 110)
              }

              Button {
                backupDatabase()
              } label: {
                SettingsRowView(
                  systemImage: "externaldrive.fill", title: "Backup Database", colour: 111)
              }

              Button {
                showRestorePicker = true
              } label: {
                SettingsRowView(
                  systemImage: "externaldrive.badge.plus", title: "Restore from Backup", colour: 111)
              }
              .fileImporter(
                isPresented: $showRestorePicker,
                allowedContentTypes: [.init(filenameExtension: "sqlite")!, .item],
                allowsMultipleSelection: false
              ) { result in
                if let url = try? result.get().first {
                  restoreDatabase(from: url)
                }
              }
              .alert("Restore Complete", isPresented: $restoreSuccess) {
                Button("OK", role: .cancel) {}
              } message: {
                Text("All your data has been restored successfully.")
              }
              .alert("Restore Failed", isPresented: Binding(
                get: { restoreError != nil },
                set: { if !$0 { restoreError = nil } }
              )) {
                Button("OK", role: .cancel) {}
              } message: {
                Text(restoreError ?? "")
              }

              //
              //                            NavigationLink(destination: SettingsQuickAddWidgetView()) {
              //                                SettingsRowView(systemImage: "bolt.square.fill", title: "Quick-Add Widget", colour: 115)
              //                            }

              NavigationLink(destination: SettingsSyncView()
                .onAppear { withAnimation(.easeOut.speed(1.5)) { tabBarManager.navigationHideTab() } }
                .onDisappear { withAnimation(.easeOut.speed(1.5)) { tabBarManager.navigationShowTab() } }
              ) {
                SettingsRowView(
                  systemImage: "arrow.clockwise.circle.fill", title: "Auto Sync", colour: 112)
              }

              NavigationLink(destination: EscudoImportSourcesView()
                .onAppear { withAnimation(.easeOut.speed(1.5)) { tabBarManager.navigationHideTab() } }
                .onDisappear { withAnimation(.easeOut.speed(1.5)) { tabBarManager.navigationShowTab() } }
              ) {
                SettingsRowView(
                  systemImage: "square.and.arrow.down.fill", title: "Import Sources", colour: 112)
              }

              NavigationLink(destination: CategorizationQueueView()
                .onAppear { withAnimation(.easeOut.speed(1.5)) { tabBarManager.navigationHideTab() } }
                .onDisappear { withAnimation(.easeOut.speed(1.5)) { tabBarManager.navigationShowTab() } }
              ) {
                SettingsRowView(
                  systemImage: "tag.fill", title: "Review Uncategorized", colour: 111)
              }

              ToggleRow(
                icon: "wand.and.stars", color: "111", text: "Auto-categorize",
                bool: autoCategorizerEnabled,
                onTap: {
                  autoCategorizerEnabled.toggle()
                })

              Button {
                showImportGuide = true
              } label: {
                SettingsRowView(
                  systemImage: "doc.text.fill", title: "Import CSV / PDF", colour: 112)
              }

              Button {
                exportData()
              } label: {
                SettingsRowView(
                  systemImage: "square.and.arrow.up.fill", title: "Export Data", colour: 113)
              }

              NavigationLink(destination: SettingsEraseView()) {
                SettingsRowView(systemImage: "xmark.bin.fill", title: "Erase Data", colour: 114)
              }
            }
            .padding(10)
            .background(Color.SettingsBackground, in: RoundedRectangle(cornerRadius: 9))
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 25)

          Spacer()
            .frame(height: 95)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      }
      .navigationBarTitle("")
      .navigationBarHidden(true)
      .background(Color.PrimaryBackground)
      .fullScreenCover(isPresented: $showUpdate) {
        UpdateAlert()
      }
      .fullScreenCover(isPresented: $showImportGuide) {
        ImportDataView()
      }
    }
  }

  @ViewBuilder
    func ToggleRow(icon: String, color: String, text: String, bool: Bool, smaller: Bool = false, onTap: @escaping () -> Void)
    -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
            .font(.system(smaller ? .subheadline : .body, design: .rounded))
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color(color), in: RoundedRectangle(cornerRadius: 6))

      Text(text)
        .font(.system(.body, design: .rounded).weight(.medium))
        .lineLimit(1)
        .foregroundColor(Color.PrimaryText)

      Spacer()

      ZStack(alignment: bool ? .trailing : .leading) {
        Capsule()
          .frame(width: 42, height: 28)
          .foregroundColor(bool ? Color.escudoAccent : .gray.opacity(0.8))

        Circle()
          .foregroundColor(Color.white)
          .padding(2)
          .frame(width: 28, height: 28)
          .matchedGeometryEffect(id: "toggle\(color)", in: animation)
      }
      .onTapGesture {
        withAnimation {
          onTap()
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  func makeAttributedString() -> AttributedString {
    var string = AttributedString("SugarHashira")
    string.foregroundColor = Color.PrimaryText
    string.link = URL(string: "https://www.github.com/SugarHashira")

    return string
  }

  func shareSheet(url: String) {
    let url = URL(string: url)
    let activityView = UIActivityViewController(activityItems: [url!], applicationActivities: nil)

    let allScenes = UIApplication.shared.connectedScenes
    let scene = allScenes.first { $0.activationState == .foregroundActive }

    if let windowScene = scene as? UIWindowScene {
      windowScene.keyWindow?.rootViewController?.present(
        activityView, animated: true, completion: nil)
    }
  }

  // MARK: - Database backup / restore

  func backupDatabase() {
    dataController.save()
    guard let storeURL = dataController.container.persistentStoreDescriptions.first?.url else { return }

    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("Escudo_backup.sqlite")
    try? FileManager.default.removeItem(at: tmp)

    // Open source in a fresh read-only coordinator so the active store's locks don't interfere,
    // then migrate to tmp — this forces a full WAL checkpoint into a clean single-file backup.
    let backupCoordinator = NSPersistentStoreCoordinator(
      managedObjectModel: dataController.container.managedObjectModel)
    do {
      let sourceStore = try backupCoordinator.addPersistentStore(
        ofType: NSSQLiteStoreType,
        configurationName: nil,
        at: storeURL,
        options: [
          NSReadOnlyPersistentStoreOption: true,
          NSMigratePersistentStoresAutomaticallyOption: true,
          NSInferMappingModelAutomaticallyOption: true,
        ]
      )
      try backupCoordinator.migratePersistentStore(
        sourceStore,
        to: tmp,
        options: [NSSQLitePragmasOption: ["journal_mode": "DELETE"]],
        withType: NSSQLiteStoreType
      )
    } catch {
      print("Backup failed: \(error)")
      return
    }

    let av = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
    let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
    (scene as? UIWindowScene)?.keyWindow?.rootViewController?.present(av, animated: true)
  }

  func restoreDatabase(from url: URL) {
    guard url.startAccessingSecurityScopedResource() else {
      restoreError = "Could not access the selected file."
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }

    guard let storeURL = dataController.container.persistentStoreDescriptions.first?.url else { return }
    let fm = FileManager.default

    let coordinator = dataController.container.persistentStoreCoordinator
    do {
      for store in coordinator.persistentStores {
        try coordinator.remove(store)
      }
    } catch {
      restoreError = "Could not close the current database."
      return
    }

    let walURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
    let shmURL = storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
    let srcWal = url.deletingPathExtension().appendingPathExtension("sqlite-wal")
    let srcShm = url.deletingPathExtension().appendingPathExtension("sqlite-shm")

    do {
      try fm.replaceItem(at: storeURL, withItemAt: url, backupItemName: nil, options: [], resultingItemURL: nil)
      if fm.fileExists(atPath: srcWal.path) { try? fm.replaceItem(at: walURL, withItemAt: srcWal, backupItemName: nil, options: [], resultingItemURL: nil) } else { try? fm.removeItem(at: walURL) }
      if fm.fileExists(atPath: srcShm.path) { try? fm.replaceItem(at: shmURL, withItemAt: srcShm, backupItemName: nil, options: [], resultingItemURL: nil) } else { try? fm.removeItem(at: shmURL) }
    } catch {
      restoreError = "Could not replace the database file."
      return
    }

    do {
      try coordinator.addPersistentStore(
        ofType: NSSQLiteStoreType,
        configurationName: nil,
        at: storeURL,
        options: [
          NSMigratePersistentStoresAutomaticallyOption: true,
          NSInferMappingModelAutomaticallyOption: true
        ]
      )
      dataController.container.viewContext.reset()
      restoreSuccess = true
    } catch {
      restoreError = "Database restored but failed to reload — please restart the app."
    }
  }

  func exportData() {
    let fetchRequest = dataController.fetchRequestForExport()
    let transactions = dataController.results(for: fetchRequest)

    let fileName = "export.csv"
    let path = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    var csvText = "Date,Note,Amount,Category,Type\n"

    for transaction in transactions {
      var string = transaction.wrappedNote
      let type: String

      if transaction.income {
        type = "Income"
      } else {
        type = "Expense"
      }

      string.removeAll(where: { $0 == "," })

      csvText +=
        "\(transaction.wrappedDate),\(string),\(String(format: "%.2f", transaction.wrappedAmount)),\(transaction.category?.wrappedName ?? ""),\(type)\n"
    }

    do {
      try csvText.write(to: path!, atomically: true, encoding: String.Encoding.utf8)
    } catch {
      print("\(error)")
    }

    var filesToShare = [Any]()
    filesToShare.append(path!)

    let av = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)

    let allScenes = UIApplication.shared.connectedScenes
    let scene = allScenes.first { $0.activationState == .foregroundActive }

    if let windowScene = scene as? UIWindowScene {
      windowScene.keyWindow?.rootViewController?.present(av, animated: true, completion: nil)
    }
  }
}


struct SettingsRowView: View {
  var systemImage: String
  var title: String
  var colour: Int
  var optionalText: String?

  @Environment(\.dynamicTypeSize) var dynamicTypeSize

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(.body, design: .rounded))

        //                .font(.system(size: 17))
        //                .padding(5)
        .foregroundColor(.white)
        .frame(
          width: dynamicTypeSize > .xLarge ? 40 : 30, height: dynamicTypeSize > .xLarge ? 40 : 30,
          alignment: .center
        )
        .background(Color("\(colour)"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

      Text(LocalizedStringKey(title))
        .font(.system(.body, design: .rounded).weight(.medium))

        //                .font(.system(size: 17, weight: .medium, design: .rounded))
        .lineLimit(1)
        .foregroundColor(Color.PrimaryText)

      Spacer()

      if optionalText != nil {
        Text(optionalText!)
          .font(.system(.body, design: .rounded))

          //                    .font(.system(size: 17, weight: .regular, design: .rounded))
          .foregroundColor(.DarkIcon.opacity(0.6))
          .layoutPriority(1)
          .padding(.trailing, -8)
      }

      Image(systemName: "chevron.forward")
        .font(.system(.subheadline, design: .rounded))
        //                .font(.system(size: 15))
        .foregroundColor(.DarkIcon.opacity(0.6))
    }
    .frame(maxWidth: .infinity)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }
}

struct SettingsCategoryView: View {
  @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

  var body: some View {
    CategoryView(mode: .settings)
      .navigationBarBackButtonHidden(true)
      .navigationBarTitle("")
      .navigationBarHidden(true)
      .background(Color.PrimaryBackground)
  }
}

// MARK: - Net Worth Tile (design spec screen 13)

struct EscudoNetWorthTile: View {
    @EnvironmentObject var dataController: DataController
    @AppStorage("currency", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var currency: String = Locale.current.currencyCode ?? "EUR"
    var sym: String { Locale.current.localizedCurrencySymbol(forCurrencyCode: currency) ?? currency }

    private var currentNet: Double {
        let exp = dataController.getCalendarMonthSpent(offset: 0)
        let inc = dataController.getCalendarMonthIncome(offset: 0)
        return inc - exp
    }

    private var prevNet: Double {
        let exp = dataController.getCalendarMonthSpent(offset: -1)
        let inc = dataController.getCalendarMonthIncome(offset: -1)
        return inc - exp
    }

    private var delta: Double { currentNet - prevNet }

    private var prevMonthShort: String {
        let cal = Calendar(identifier: .gregorian)
        let prev = cal.date(byAdding: .month, value: -1, to: Date.now) ?? Date.now
        let fmt = DateFormatter(); fmt.dateFormat = "MMM"
        return fmt.string(from: prev).lowercased()
    }

    private func amtStr(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: abs(v))) ?? String(Int(abs(v)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THIS MONTH")
                .font(.escudo(9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.escudoAccent.opacity(0.7))

            HStack(alignment: .lastTextBaseline) {
                Text(currentNet >= 0 ? "+" : "−")
                    .font(.escudo(22, weight: .semibold))
                    .foregroundStyle(currentNet >= 0 ? Color.escudoPos : Color.escudoNeg)
                Text("\(sym)\(amtStr(currentNet))")
                    .font(.escudo(36, weight: .semibold))
                    .tracking(-1.0)
                    .foregroundStyle(Color.escudoText)
                    .monospacedDigit()

                Spacer()

                if abs(prevNet) > 0.01 {
                    let arrow  = delta >= 0 ? "↗" : "↘"
                    let colour = delta >= 0 ? Color.escudoPos : Color.escudoNeg
                    Text("\(arrow) \(sym)\(amtStr(abs(delta))) vs \(prevMonthShort)")
                        .font(.escudo(11, weight: .semibold))
                        .foregroundStyle(colour)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Color.escudoAccent.opacity(0.1)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.escudoAccent.opacity(0.35), lineWidth: 1))
        )
        .cornerRadius(10)
    }
}
