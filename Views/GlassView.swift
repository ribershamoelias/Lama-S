import SwiftUI
import AppKit

/// Wraps NSVisualEffectView to provide a native macOS frosted-glass background.
struct GlassView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Convenience modifier — apply glass background with rounded corners.
extension View {
    func glassBackground(
        material: NSVisualEffectView.Material = .hudWindow,
        cornerRadius: CGFloat = 12
    ) -> some View {
        self.background(
            GlassView(material: material)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        )
    }
}
