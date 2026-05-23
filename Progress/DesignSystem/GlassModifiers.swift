import SwiftUI

// MARK: - Reduce Transparency / Motion environment
//
// PRD §7.4: respect Reduce Transparency and Reduce Motion. When enabled,
// glass effects must degrade to a solid material and morph/timelapse motion
// must be disabled. These helpers expose the system flags via environment.

private struct ReduceTransparencyKey: EnvironmentKey {
    static let defaultValue: Bool = UIAccessibility.isReduceTransparencyEnabled
}

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = UIAccessibility.isReduceMotionEnabled
}

extension EnvironmentValues {
    var reduceTransparencyEnabled: Bool {
        get { self[ReduceTransparencyKey.self] }
        set { self[ReduceTransparencyKey.self] = newValue }
    }
    var reduceMotionEnabled: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}

// MARK: - Glass modifiers
//
// Thin wrappers around iOS 26 Liquid Glass APIs (PRD §7.2). Only the
// navigation/control layer should use these — never the content layer.

extension View {
    /// Standard glass treatment for floating controls (default Capsule shape).
    ///
    /// Falls back to a solid material when Reduce Transparency is on (PRD §7.4).
    @ViewBuilder
    func glassControl() -> some View {
        modifier(GlassControlModifier(shape: .capsule))
    }

    /// Glass treatment shaped to a custom rounded rect. Prefer `.buttonStyle(.glass)`
    /// for buttons — `.glassEffect` with `RoundedRectangle` can snap to Capsule
    /// (PRD §7.2 known pitfall).
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = AppShape.tileRadius) -> some View {
        modifier(GlassControlModifier(shape: .roundedRect(cornerRadius)))
    }
}

private struct GlassControlModifier: ViewModifier {
    enum Shape {
        case capsule
        case roundedRect(CGFloat)
    }

    let shape: Shape
    @Environment(\.reduceTransparencyEnabled) private var reduceTransparency

    func body(content: Content) -> some View {
        switch shape {
        case .capsule:
            if reduceTransparency {
                content
                    .background(.thickMaterial, in: AppShape.pill)
                    .clipShape(AppShape.pill)
            } else {
                content
                    .glassEffect(.regular, in: AppShape.pill)
            }
        case .roundedRect(let r):
            let s = RoundedRectangle(cornerRadius: r, style: .continuous)
            if reduceTransparency {
                content
                    .background(.thickMaterial, in: s)
                    .clipShape(s)
            } else {
                content
                    .glassEffect(.regular, in: s)
            }
        }
    }
}

/// Wrap a group of glass controls so they morph and blend together
/// (PRD §7.2 — `GlassEffectContainer`).
struct GlassGroup<Content: View>: View {
    @Environment(\.reduceTransparencyEnabled) private var reduceTransparency
    @ViewBuilder var content: () -> Content

    var body: some View {
        if reduceTransparency {
            content()
        } else {
            GlassEffectContainer {
                content()
            }
        }
    }
}
