import SwiftUI

/// "Evict  11.2 of 16 GB" with a thin bar that turns warm under memory pressure.
struct MemoryGauge: View {
    let system: SystemMemory
    /// On battery with stricter idle times: shows a small battery glyph.
    var isSavingEnergy = false

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usedText: String { Format.gigabytes(system.used) }
    private var totalText: String { Format.gigabytes(system.total, fractionDigits: 0) }
    private var isTight: Bool { system.pressure != .normal }

    private var barFill: AnyShapeStyle {
        switch (isTight, contrast == .increased) {
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
                if isSavingEnergy {
                    Image(systemName: "battery.50percent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("On battery: apps count as idle after half the usual time")
                        .accessibilityLabel("On battery: apps count as idle after half the usual time")
                }
                if isTight {
                    Text("Under pressure")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("\(usedText) of \(totalText) GB")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
                    Capsule()
                        .fill(barFill)
                        .frame(width: geometry.size.width * system.fraction)
                }
            }
            .frame(height: 6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: system.fraction)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Memory")
            .accessibilityValue(isTight
                ? Text("\(usedText) of \(totalText) gigabytes used, under pressure")
                : Text("\(usedText) of \(totalText) gigabytes used"))
        }
    }
}
