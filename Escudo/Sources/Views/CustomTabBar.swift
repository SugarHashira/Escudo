//
//  CustomTabBar.swift
//  Escudo — redesigned tab bar matching the Escudo design handoff.
//  Pill container · LOG · STATS · [+] · BUDGET · SET
//

import Foundation
import SwiftUI

// MARK: - Main CustomTabBar

struct CustomTabBar: View {
    @EnvironmentObject var appLockVM: AppLockViewModel
    @Binding var currentTab: String
    var topEdge:    CGFloat
    var bottomEdge: CGFloat

    @State private var addTransaction = false
    @State private var checkingFace   = false

    @FetchRequest(sortDescriptors: [SortDescriptor(\.date, order: .reverse)]) private var transactions: FetchedResults<Transaction>

    @State var count = 0
    @Binding var counter: Int
    var launchAdd: Bool

    @AppStorage("confetti",              store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var confetti:     Bool = false
    @AppStorage("firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.sugarhashira.Escudo")) var firstLaunch: Bool = true

    // Map external tab names → new label strings
    private func label(for tab: String) -> String {
        switch tab {
        case "Log":      return "LOG"
        case "Insights": return "STATS"
        case "Budget":   return "BUDGET"
        case "Settings": return "SET"
        default:         return tab.uppercased()
        }
    }

    private let tabs: [String] = ["Log", "Insights", "Budget", "Settings"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // Gradient fade behind bar
            LinearGradient(
                colors: [Color.PrimaryBackground.opacity(0), Color.PrimaryBackground],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            // Tab bar — surface bg + 1px top border (spec)
            HStack(spacing: 0) {
                // LOG
                tabItem("Log")

                // STATS
                tabItem("Insights")

                // Centre + olive raised pill (56×40, spec)
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    addTransaction = true
                } label: {
                    Text("+")
                        .font(.escudo(20, weight: .semibold))
                        .foregroundStyle(Color.escudoBg)
                        .frame(width: 56, height: 40)
                        .background(Color.escudoAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Add New Transaction")
                .padding(.horizontal, 8)

                // BUDGET
                tabItem("Budget")

                // SETTINGS
                tabItem("Settings")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, max(bottomEdge, 8))
            .background(
                Color.escudoSurface
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.escudoLine)
                            .frame(height: 1)
                    }
            )
        }
        .frame(maxWidth: .infinity)
        // Full-screen add transaction
        .fullScreenCover(isPresented: $addTransaction, onDismiss: {
            if confetti, count != transactions.count { counter += 1 }
            if firstLaunch { firstLaunch = false }
        }) {
            TransactionView(toEdit: nil)
        }
        .onChange(of: launchAdd)          { _ in addTransaction = true }
        .onChange(of: addTransaction)     { _ in if addTransaction { count = transactions.count } }
        .onOpenURL { url in
            guard url.host == "newExpense" else { return }
            addTransaction = true
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: String) -> some View {
        let active = currentTab == tab
        Button {
            DispatchQueue.main.async { currentTab = tab }
        } label: {
            VStack(spacing: 0) {
                // 2px accent underline above label (spec)
                Rectangle()
                    .fill(active ? Color.escudoAccent : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)

                Spacer()

                Group {
                    if tab == "Settings" {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: active ? .semibold : .regular))
                    } else {
                        Text(label(for: tab))
                            .font(.escudo(10, weight: .semibold))
                            .tracking(1.4)
                    }
                }
                .foregroundStyle(active ? Color.escudoAccent : Color.escudoTextMuted)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab) tab")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Supporting button styles (kept for other views that import them)

struct BouncyButton: ButtonStyle {
    var duration: Double
    var scale: Double

    public func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}

struct MyButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.LightIcon)
            .frame(width: 65, height: 38)
            .background(
                configuration.isPressed ? Color.SubtitleText : Color.DarkBackground,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
    }
}
