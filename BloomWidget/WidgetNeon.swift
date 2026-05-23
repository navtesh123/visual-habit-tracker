// PRD §7.3 — widget-side mirror of the Neon Playroom palette so the
// extension renders in brand colors without compiling the full
// DesignSystem folder. The colorset names are identical to the main app
// because the widget reuses the same Assets.xcassets.

import SwiftUI

enum WidgetNeon {
    static let midnightAbyss = Color("MidnightAbyss")
    static let ghostWhite    = Color("GhostWhite")
    static let limeSqueeze   = Color("LimeSqueeze")
    static let amethystGlow  = Color("AmethystGlow")
    static let sunsetOrange  = Color("SunsetOrange")
    static let emeraldSprint = Color("EmeraldSprint")
    static let skyboundBlue  = Color("SkyboundBlue")
    static let goldenRod     = Color("GoldenRod")
    static let lavenderMist  = Color("LavenderMist")

    /// Resolve an accent color from the raw `AccentToken.rawValue` written
    /// by the main app into the widget snapshot.
    static func accent(forTokenRaw raw: String) -> Color {
        switch raw {
        case "amethystGlow":  return amethystGlow
        case "sunsetOrange":  return sunsetOrange
        case "emeraldSprint": return emeraldSprint
        case "skyboundBlue":  return skyboundBlue
        case "goldenRod":     return goldenRod
        case "limeSqueeze":   return limeSqueeze
        default:              return amethystGlow
        }
    }
}
