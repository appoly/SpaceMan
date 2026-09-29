import AppKit
import SwiftUI

/// Shown instead of scanning when Full Disk Access is missing: without it the scan would trigger a prompt for each
/// protected folder and still miss data.
struct FullDiskAccessSetupView: View {
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

            Button("Open Settings") { openURL(PrivacySettings.fullDiskAccess.url) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
