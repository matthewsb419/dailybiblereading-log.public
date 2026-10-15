import SwiftUI
import ReadingLogCore

// Small building blocks that mirror the website's CSS classes.

struct Card<Content: View>: View {
    @Environment(\.palette) var c
    var top: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.line))
            .padding(.top, top)
            .padding(.bottom, 12)
    }
}

/// Small caps label, as `.eyebrow` / `.sechead`.
struct Eyebrow: View {
    @Environment(\.palette) var c
    let text: String
    var color: Color? = nil
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11)).tracking(1.5).foregroundStyle(color ?? c.muted)
    }
}

struct SectionHead: View {
    let left: String
    var right: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Eyebrow(text: left); Spacer(); Eyebrow(text: right) }.padding(.bottom, 10)
    }
}

struct Note: View {
    @Environment(\.palette) var c
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(c.muted).lineSpacing(2)
            .padding(.leading, 9)
            .overlay(alignment: .leading) { Rectangle().fill(c.line).frame(width: 2) }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A progress bar with the 80% target tick, as `.bar` with `<i>` and `<u>`.
struct Meter: View {
    @Environment(\.palette) var c
    let pct: Double
    var marker: Double? = Program.monthTarget
    var alt = false
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(c.track)
                Capsule().fill(alt ? c.parchment : c.brass).frame(width: g.size.width * min(1, max(0, pct / 100)))
                if let m = marker {
                    Rectangle().fill(c.parchment).frame(width: 2, height: height + 6).offset(x: g.size.width * m / 100 - 1)
                }
            }
        }
        .frame(height: height)
    }
}

/// One labelled bar: label · bar · percent · grade.
struct BarRow: View {
    @Environment(\.palette) var c
    let label: String
    let pct: Double?
    var grade: String? = nil
    var alt = false
    var digits = 1
    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased()).font(.system(size: 11)).tracking(1.1).foregroundStyle(c.muted)
                .lineLimit(1).fixedSize().frame(width: 64, alignment: .leading)
            if let p = pct { Meter(pct: p, alt: alt) } else { Capsule().fill(c.track).frame(height: 5) }
            Text(pct.map { Fmt.fixed($0, digits) + "%" } ?? "—").font(.system(size: 12).monospacedDigit()).foregroundStyle(c.parchment)
                .frame(width: 50, alignment: .trailing)
            Text(grade ?? "—").font(.serif(15)).foregroundStyle(c.brass).frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

/// Label · detail · percent with grade, as `.arow`.
struct ARow: View {
    @Environment(\.palette) var c
    let label: String
    let detail: String
    let pct: String
    var on = false
    var grade: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased()).font(.system(size: 11)).tracking(1.1).foregroundStyle(c.muted).frame(width: 58, alignment: .leading)
            Text(detail).font(.system(size: 12)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(pct).font(.serif(18)).foregroundStyle(on ? c.brass : c.parchment)
                if let g = grade { Text(g).font(.serif(15)).foregroundStyle(c.brass) }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) }
    }
}

struct StatTile: View {
    @Environment(\.palette) var c
    let label: String, value: String
    var sub: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(c.muted)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(c.parchment).lineLimit(1).minimumScaleFactor(0.7)
            if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(c.muted).lineLimit(2) }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.line))
    }
}

/// Seven little squares for the last week, as `.dots`.
struct Dots: View {
    @Environment(\.palette) var c
    let states: [Log.DayState]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                RoundedRectangle(cornerRadius: 5)
                    .fill(s == .complete ? c.brass : (s == .fail ? c.rust : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(s == .missed ? c.line : (s == .fail ? c.rust : c.brass)))
                    .frame(width: 22, height: 22)
            }
        }
    }
}

struct WeekRow: View {
    @Environment(\.palette) var c
    let label: String
    let states: [Log.DayState]
    let n: Int, of: Int
    var pct: Double? = nil
    var body: some View {
        HStack(spacing: 12) {
            Text(label.uppercased()).font(.system(size: 11)).tracking(1.1).foregroundStyle(c.muted).frame(width: 58, alignment: .leading)
            Dots(states: states)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n)/\(of)").fixedSize().font(.serif(17).monospacedDigit()).foregroundStyle(c.parchment)
                if let pct = pct {
                    Text(Fmt.fixed(pct, 0) + "%").font(.system(size: 13)).foregroundStyle(pct >= Program.weekTarget ? c.brass : c.muted).fixedSize()
                }
            }
            .frame(minWidth: 66, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}

/// The No / Yes (/ Didn't meet) toggle for a tracker; tapping the selected one clears it.
struct TrackerToggle: View {
    @Environment(\.palette) var c
    let tracker: Tracker
    let value: String?
    let pick: (String?) -> Void
    var body: some View {
        HStack(spacing: 7) {
            Text(tracker.label).font(.system(size: 12)).foregroundStyle(c.muted)
            HStack(spacing: 0) {
                seg("no", "No")
                Rectangle().fill(c.line).frame(width: 1)
                seg("yes", "Yes")
                if let off = tracker.off { Rectangle().fill(c.line).frame(width: 1); seg("off", off) }
            }
            .fixedSize()
            .clipShape(Capsule())
            .overlay(Capsule().stroke(c.line))
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(tracker.hint ?? "")
    }
    func seg(_ v: String, _ text: String) -> some View {
        let sel = value == v
        let bg: Color = !sel ? .clear : (v == "off" ? c.line : (v == tracker.good ? c.brass : c.rust))
        let fg: Color = !sel ? c.ghost : (v == tracker.good && v != "off" ? c.ink : c.parchment)
        return Button { pick(sel ? nil : v) } label: {
            Text(text).font(.system(size: 12, weight: sel ? .semibold : .regular)).foregroundStyle(fg)
                .padding(.horizontal, 13).padding(.vertical, 5).background(bg)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tracker-\(tracker.id)-\(v)")
        .accessibilityAddTraits(sel ? .isSelected : [])
    }
}

struct OutlineButton: View {
    @Environment(\.palette) var c
    let title: String
    var quiet = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13)).foregroundStyle(quiet ? c.muted : c.brass)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(quiet ? c.line : c.brass))
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    @Environment(\.palette) var c
    let title: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(c.ink)
                .padding(.horizontal, 16).padding(.vertical, 7).background(c.brass, in: Capsule())
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }
}

struct LinkButton: View {
    @Environment(\.palette) var c
    let title: String
    var danger = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: danger ? .semibold : .regular)).foregroundStyle(danger ? c.rust : c.brass)
        }
        .buttonStyle(.plain)
    }
}

/// A multi-line box in the website's serif style.
struct WriteBox: View {
    @Environment(\.palette) var c
    @Binding var text: String
    var minHeight: CGFloat = 76
    var size: CGFloat = 16
    var body: some View {
        TextField("—", text: $text, axis: .vertical)
            .font(.serif(size)).foregroundStyle(c.parchment).lineSpacing(3)
            .lineLimit(3...)
            .padding(.horizontal, 11).padding(.vertical, 10)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(c.ink, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(c.line))
    }
}

extension View {
    func hairline(_ c: Palette) -> some View { overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 1) } }
}
