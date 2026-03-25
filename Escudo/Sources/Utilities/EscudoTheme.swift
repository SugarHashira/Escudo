// EscudoTheme.swift
// Design tokens from the Escudo redesign handoff.
// All semantic names map to existing asset-catalog Colors;
// these aliases let new code use design-spec names directly.

import SwiftUI

// MARK: - Semantic token aliases (new code uses these)

extension Color {
    // Backgrounds
    static var escudoBg:      Color { .PrimaryBackground   }   // #12100e / #f3efe6
    static var escudoSurface: Color { .SecondaryBackground }   // #1a1714 / #ebe6da
    static var escudoSurface2:Color { .TertiaryBackground  }   // #221e19 / #e0dace

    // Borders
    static var escudoLine:    Color { .Outline              }   // #2b2520 / #d4cdbe
    static var escudoLineStrong: Color { Color(hex: "3a322b") } // dark only; swap in light if needed

    // Text
    static var escudoText:    Color { .PrimaryText          }   // #ece5d8 / #1e1b17
    static var escudoTextDim: Color { .SubtitleText         }   // #a69c8b / #5a5347
    static var escudoTextMuted: Color { .EvenLighterText    }   // #6b6355 / #8a8273

    // Accent — olive
    static var escudoAccent:    Color { .DarkBackground     }   // #b4b85a / #6c7028
    static var escudoAccentDim: Color {
        Color(hex: "7a7c3c") // dark; light: #9da044 — add asset if needed
    }

    // Semantic status
    static var escudoPos:  Color { .IncomeGreen  }              // #8fae6b / #52703a
    static var escudoNeg:  Color { .AlertRed     }              // #c46a4a / #a84a2a
    static var escudoWarn: Color { .Alert        }              // #d9a441 / #a7791f
}

// MARK: - Category palette (for merchant badges, bar fills, sparklines)

enum EscudoCategoryColor {
    static let terracotta = Color(hex: "c46a4a")  // Groceries, Netflix
    static let olive      = Color(hex: "b4b85a")  // Subscriptions, Continente
    static let green      = Color(hex: "8fae6b")  // Transport, Uber, T212
    static let amber      = Color(hex: "d9a441")  // Eating out, Fuel
    static let tan        = Color(hex: "9a7a52")  // Fuel secondary
    static let slate      = Color(hex: "7a8a9a")  // Home
    static let mauve      = Color(hex: "a87a9a")  // Health
    static let grey       = Color(hex: "7f7f7a")  // Misc
}

// MARK: - Typography helpers

extension Font {
    /// JetBrains Mono with graceful monospace fallback.
    /// To enable JetBrains Mono: add the .ttf files to the project
    /// and register them in Info.plist under "Fonts provided by application".
    static func escudo(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if UIFont(name: fontName(for: weight), size: size) != nil {
            return Font.custom(fontName(for: weight), size: size)
        }
        return Font.system(size: size, weight: weight, design: .monospaced)
    }

    private static func fontName(for weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold, .heavy, .black: return "JetBrainsMono-Bold"
        case .medium:                          return "JetBrainsMono-Medium"
        default:                               return "JetBrainsMono-Regular"
        }
    }

    // Predefined scale from the spec
    static var escudoHero:     Font { escudo(40, weight: .semibold) }
    static var escudoHeadline: Font { escudo(22, weight: .semibold) }
    static var escudoAmount:   Font { escudo(15, weight: .semibold) }
    static var escudoBody:     Font { escudo(13, weight: .medium)   }
    static var escudoMeta:     Font { escudo(11)                    }
    static var escudoLabel:    Font { escudo(10, weight: .semibold) }
    static var escudoSmallCap: Font { escudo(9,  weight: .semibold) }
}

// MARK: - InitialBadge component

/// Two-letter square badge — the Escudo identity mark for merchants & categories.
struct InitialBadge: View {
    let label:  String
    let color:  Color
    var size:   CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.escudoLine, lineWidth: 1)
                )
            Text(label)
                .font(.escudo(size * 0.38, weight: .semibold))
                .foregroundStyle(Color.escudoBg)
                .tracking(-0.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - SectionHead component

/// Small-caps label with full-width hairline rule — Bloomberg terminal look.
struct EscudoSectionHead: View {
    let label:  String
    var right:  String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.escudoSmallCap)
                .foregroundStyle(Color.escudoTextMuted)
                .tracking(1.6)
            Rectangle()
                .fill(Color.escudoLine)
                .frame(height: 1)
            if let right {
                Text(right)
                    .font(.escudoMeta)
                    .foregroundStyle(Color.escudoTextDim)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - Chip component

struct EscudoChip: View {
    let title:  String
    var active: Bool = false

    var body: some View {
        Text(title)
            .font(.escudo(11, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(active ? Color.escudoBg : Color.escudoTextDim)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.escudoAccent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(active ? Color.clear : Color.escudoLine, lineWidth: 1)
                    )
            )
    }
}
