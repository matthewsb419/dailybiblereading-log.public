#if DEBUG
import SwiftUI
import ReadingLogCore

/// Debug builds only: `-snapshot` renders every page top to bottom into the app's Documents
/// folder, so a whole page can be checked without scrolling the simulator.
@MainActor
enum Snapshot {
    static func renderAll(store: Store, palette: Palette) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for page in Page.allCases {
            let view = PageBody(page: page)
                .environment(store).environment(KegRunner()).environment(\.palette, palette)
                .frame(width: 402)
                .background(palette.ink)
            let r = ImageRenderer(content: view)
            r.scale = 1
            r.proposedSize = ProposedViewSize(width: 402, height: nil)
            guard let cg = r.cgImage else { print("snapshot: \(page) did not render"); continue }
            // slices short enough to read
            var y = 0, n = 0
            while y < cg.height {
                let h = min(1300, cg.height - y)
                if let part = cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: h)),
                   let png = UIImage(cgImage: part).pngData() {
                    try? png.write(to: dir.appendingPathComponent("snap-\(page.rawValue)-\(n).png"))
                }
                y += h; n += 1
            }
        }
    }

    struct PageBody: View {
        let page: Page
        @State var day = 0
        @Environment(Store.self) var store
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch page {
                case .today: TodayView(viewDay: .constant(store.log.currentDay))
                case .record: RecordView(page: .constant(.record))
                case .plan: PlanView(page: .constant(.plan))
                case .goals: GoalsView()
                case .quotes: QuotesView()
                case .next: NextView()
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 22)
        }
    }
}
#endif
