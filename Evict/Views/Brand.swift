import SwiftUI

/// Evict's brand palette, taken from the app icon. Used for brand moments (the
/// mark, the memory bar); interactive controls keep the user's accent color.
enum Brand {
    static let indigo = Color(red: 0x4A / 255, green: 0x55 / 255, blue: 0xEA / 255)
    static let indigoLight = Color(red: 0x71 / 255, green: 0x80 / 255, blue: 0xFF / 255)
    static let indigoDeep = Color(red: 0x2D / 255, green: 0x35 / 255, blue: 0xA8 / 255)
    static let periwinkle = Color(red: 0x9A / 255, green: 0xA6 / 255, blue: 0xFF / 255)

    static let barGradient = LinearGradient(colors: [indigoLight, indigo], startPoint: .leading, endPoint: .trailing)
}

/// The "Free Slot" mark: three tiles, an empty slot, and the tile that left.
/// Drawn from the app icon's geometry (design/icon/generate.py), cropped to the art.
struct FreeSlotMark: View {
    var size: CGFloat = 24

    // Bounds of the art inside the 1024-pt icon canvas.
    nonisolated private static let origin = CGPoint(x: 262, y: 188)
    nonisolated private static let extent: CGFloat = 574

    var body: some View {
        Canvas { context, canvasSize in
            let k = canvasSize.width / Self.extent
            func rect(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> CGRect {
                CGRect(x: (x - Self.origin.x) * k, y: (y - Self.origin.y) * k, width: side * k, height: side * k)
            }
            func tile(_ r: CGRect, _ top: Color, _ bottom: Color) {
                context.fill(
                    Path(roundedRect: r, cornerRadius: 56 * k, style: .continuous),
                    with: .linearGradient(Gradient(colors: [top, bottom]),
                                          startPoint: CGPoint(x: r.midX, y: r.minY),
                                          endPoint: CGPoint(x: r.midX, y: r.maxY))
                )
            }

            tile(rect(262, 290, 216), Brand.indigoLight, Brand.indigo)
            tile(rect(262, 546, 216), Color(red: 0x4B / 255, green: 0x56 / 255, blue: 0xDC / 255), Brand.indigoDeep)
            tile(rect(518, 546, 216), Brand.periwinkle, Color(red: 0x6E / 255, green: 0x7A / 255, blue: 0xF5 / 255))

            context.stroke(
                Path(roundedRect: rect(526, 298, 200), cornerRadius: 50 * k, style: .continuous),
                with: .color(Color(red: 0x8E / 255, green: 0x97 / 255, blue: 0xC0 / 255)),
                style: StrokeStyle(lineWidth: max(12 * k, 0.75), lineCap: .round, dash: [34 * k, 24 * k])
            )

            var lifted = context
            lifted.translateBy(x: (708 - Self.origin.x) * k, y: (316 - Self.origin.y) * k)
            lifted.rotate(by: .degrees(12))
            lifted.addFilter(.shadow(color: Brand.indigoDeep.opacity(0.3), radius: 18 * k, x: -10 * k, y: 20 * k))
            let liftedTile = Path(roundedRect: CGRect(x: -108 * k, y: -108 * k, width: 216 * k, height: 216 * k),
                                  cornerRadius: 56 * k, style: .continuous)
            lifted.fill(liftedTile, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.93, green: 0.94, blue: 1)]),
                                                          startPoint: CGPoint(x: 0, y: -108 * k),
                                                          endPoint: CGPoint(x: 0, y: 108 * k)))
            lifted.stroke(liftedTile, with: .color(Color(red: 0.80, green: 0.83, blue: 0.95)), lineWidth: max(6 * k, 0.5))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
