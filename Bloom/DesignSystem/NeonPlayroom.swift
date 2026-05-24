import SwiftUI

/// Neon Playroom palette — the content/brand layer (PRD §7.1, §7.3).
///
/// Use these as solid fills on cards, accent borders, CTAs, empty states, and the
/// timelapse end-card. Never apply Liquid Glass on top of these tokens —
/// glass belongs to the navigation/control layer only.
enum NeonPlayroom {
    /// Primary dark background and primary text on light surfaces. `#141414`.
    static let midnightAbyss = Color("MidnightAbyss")
    /// Light surfaces and text on dark backgrounds. `#FDF9F0`.
    static let ghostWhite = Color("GhostWhite")
    /// Primary capture CTA and active state. `#FFB81A`.
    static let limeSqueeze = Color("LimeSqueeze")
    /// Project accent / decorative. `#7A78FF`.
    static let amethystGlow = Color("AmethystGlow")
    /// Project accent / decorative. `#FF6D38`.
    static let sunsetOrange = Color("SunsetOrange")
    /// Project accent / decorative. `#00A652`.
    static let emeraldSprint = Color("EmeraldSprint")
    /// Project accent / decorative. `#478BFF`.
    static let skyboundBlue = Color("SkyboundBlue")
    /// Project accent / decorative. `#FFC412`.
    static let goldenRod = Color("GoldenRod")
    /// Muted card background. `#CCCCFF`.
    static let lavenderMist = Color("LavenderMist")
}
