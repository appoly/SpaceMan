import AppKit
import SwiftUI

/// Shown instead of scanning when Full Disk Access is missing, as the scan would otherwise miss data.
struct FullDiskAccessSetupView: View {
    let scanWithoutAccess: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 8) {
                Text("SpaceMan needs Full Disk Access").font(.title2.bold())
                Text("To measure everything on your Mac, including other apps' data, Mail and Messages, SpaceMan " +
                     "needs to read every folder. It only reads sizes and never changes anything without asking.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 460)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Click **Open Settings**.", systemImage: "1.circle")
                Label("Turn on **SpaceMan**, or add it with **+** if it isn't listed.", systemImage: "2.circle")
                Label("Choose **Quit & Reopen** when asked. The scan starts straight away.", systemImage: "3.circle")
            }

            VStack(spacing: 10) {
                HStack {
                    Button("Scan Without Permissions", action: scanWithoutAccess)
                    Button("Open Settings") { openURL(PrivacySettings.fullDiskAccess.url) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                Text("Scanning without permissions skips folders macOS would ask about, such as Documents, " +
                     "Desktop and other apps' data, and lists them as unreadable.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 460)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
