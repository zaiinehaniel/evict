import SwiftUI

/// "Evict  412 of 994 GB free" with a thin bar for the used share, orange when space runs low.
struct DiskGauge: View {
    let volume: DiskVolume?

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLow: Bool { volume?.isLow ?? false }
    private var fraction: Double { volume?.usedFraction ?? 0 }

    private var barFill: AnyShapeStyle {
        switch (isLow, contrast == .increased) {
        case (true, _): AnyShapeStyle(.orange)
        case (false, true): AnyShapeStyle(Brand.indigo)
        case (false, false): AnyShapeStyle(Brand.barGradient)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                FreeSlotMark(size: 18)
                Text(verbatim: "Evict")
                    .font(.headline)
                Spacer()
                if let volume {
                    Text("\(Format.diskGigabytes(volume.available)) of \(Format.diskGigabytes(volume.total)) GB free")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
                    Capsule()
                        .fill(barFill)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Disk")
            .accessibilityValue(accessibilityValue)
        }
    }

    private var accessibilityValue: Text {
        guard let volume else { return Text(verbatim: "") }
        let available = Format.diskGigabytes(volume.available)
        let total = Format.diskGigabytes(volume.total)
        return isLow
            ? Text("\(available) of \(total) gigabytes free, low on space")
            : Text("\(available) of \(total) gigabytes free")
    }
}
