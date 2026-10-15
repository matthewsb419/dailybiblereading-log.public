import SwiftUI
import ReadingLogCore

/// The website's color variables for one theme, including the derived ones it computes in
/// applyTheme() (ghost, track, the pip tints…).
struct Palette: Equatable {
    let ink, raised, line, parchment, muted, brass, rust: Color
    let ghost, daynum, outnum, rustdeep, pipline, piptext, pipinvline, pipinvtext, track: Color
    let isLight: Bool

    init(_ t: Theme) {
        let H = Hex.self
        ink = H.color(t.ink); raised = H.color(t.raised); line = H.color(t.line); parchment = H.color(t.parchment)
        muted = H.color(t.muted); brass = H.color(t.brass); rust = H.color(t.rust)
        ghost = H.color(H.blend(t.muted, t.ink, 0.5)); daynum = ghost
        outnum = H.color(H.blend(t.muted, t.ink, 0.85)); rustdeep = H.color(H.blend(t.rust, t.ink, 0.32))
        pipline = H.color(t.parchment, 0.2); piptext = H.color(t.parchment, 0.3)
        pipinvline = H.color(t.ink, 0.35); pipinvtext = H.color(t.ink, 0.45)
        track = H.color(H.blend(t.muted, t.ink, 0.78))
        isLight = H.luminance(t.ink) > 0.5
    }

    static let themes = Content.shared.themes
    static func at(_ i: Int) -> Palette { Palette(themes.indices.contains(i) ? themes[i] : themes[0]) }
}

enum Hex {
    static func rgb(_ s: String) -> (Double, Double, Double) {
        let v = Int(s.dropFirst(), radix: 16) ?? 0
        return (Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
    }
    static func color(_ s: String, _ a: Double = 1) -> Color {
        let (r, g, b) = rgb(s)
        return Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
    static func blend(_ a: String, _ b: String, _ t: Double) -> String {
        let (r1, g1, b1) = rgb(a), (r2, g2, b2) = rgb(b)
        func m(_ x: Double, _ y: Double) -> Int { Int((x * (1 - t) + y * t).rounded()) }
        return String(format: "#%02x%02x%02x", m(r1, r2), m(g1, g2), m(b1, b2))
    }
    static func luminance(_ s: String) -> Double { let (r, g, b) = rgb(s); return (0.299 * r + 0.587 * g + 0.114 * b) / 255 }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.at(0) }
extension EnvironmentValues {
    var palette: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
}

extension Font {
    /// The website's serif stack: Iowan Old Style ships with iOS.
    static func serif(_ size: CGFloat) -> Font { .custom("Iowan Old Style", size: size) }
}
