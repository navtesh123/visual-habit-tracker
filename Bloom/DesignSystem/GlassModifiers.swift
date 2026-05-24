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
// SDK-compatible wrappers for the navigation/control layer. On SDKs without
// iOS 26 Liquid Glass symbols, these preserve the same surface hierarchy using
// SwiftUI materials.

extension View {
    /// Standard glass treatment for floating controls (default Capsule shape).
    ///
    /// Falls back to a solid material when Reduce Transparency is on (PRD §7.4).
    @ViewBuilder
    func glassControl() -> some View {
        modifier(GlassControlModifier(shape: .capsule))
    }

    /// Glass treatment shaped to a custom rounded rect.
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
            content
                .background(material, in: AppShape.pill)
                .clipShape(AppShape.pill)
        case .roundedRect(let r):
            let s = RoundedRectangle(cornerRadius: r, style: .continuous)
            content
                .background(material, in: s)
                .clipShape(s)
        }
    }

    private var material: Material {
        reduceTransparency ? .thickMaterial : .ultraThinMaterial
    }
}

/// Wrap a group of glass controls so they morph and blend together
/// where supported. On this SDK it simply preserves grouping semantics.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.reduceTransparencyEnabled) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(material, in: AppShape.pill)
            .clipShape(AppShape.pill)
            .overlay(
                AppShape.pill
                    .strokeBorder(NeonPlayroom.ghostWhite.opacity(0.16), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var material: Material {
        reduceTransparency ? .thickMaterial : .ultraThinMaterial
    }
}
