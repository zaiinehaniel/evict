import SwiftUI

struct AboutView: View {
    /// Where the source lives. Update if the repository moves.
    static let repositoryURL = URL(string: "https://github.com/zaiinehaniel/evict")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(verbatim: "Evict")
                .font(.title.weight(.semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Evict the apps that overstayed.")
                .padding(.top, 6)

            Link("View on GitHub", destination: Self.repositoryURL)
                .padding(.top, 10)

            VStack(spacing: 2) {
                Text("Free and open source under the MIT License.")
                Text("Evict never connects to the internet and collects no data.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(width: 480)
    }
}
