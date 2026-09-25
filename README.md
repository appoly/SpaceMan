# SpaceMan

A macOS app that shows where your disk space went, grouped by what it *is* ("iOS & Apple development",
"AI models & tools", "Applications"…) rather than where it lives, with friendly names read from on-disk metadata
(simulator device names, DerivedData project names, runtime versions, app names from bundle IDs).

A **Folders** view (toolbar switch) shows the same scan by location instead, with raw folder names and what the
catalogue identified each one as.

Tick items (or use the context menu) to add them to the **Clean Up** list in the inspector, which totals their
on-disk size; **Clean Up…** then moves them to the Trash (via Finder, so it can remove other apps and ask for a
password) or deletes them immediately, and rescans. Only whole, concrete folders you can delete are selectable:
categories, groups and catch-alls whose folder also holds separately listed items aren't, and neither are your
home folder, its top-level folders, `~/Library/*` or top-level system folders.

## How it works

1. **Scan** – `FileSystemScanner` walks the data volume (`/System/Volumes/Data`) with `getattrlistbulk`, counting
   allocated bytes (so sparse VM images report real usage) and hard links once. Only entries ≥ 20 MB are kept in
   memory; everything smaller is folded into its parent.
2. **Classify** – `Catalogue` is a list of `Rule`s mapping path patterns to a category, group, `Namer` and short
   description. The deepest matching rule wins, so `~/Library/Developer` never hides DerivedData or simulators
   inside it. Space no rule claims appears under **Other** as a folder hierarchy.
3. **Account for the rest** – other APFS volumes (system, Preboot, swap) come from `ATTR_VOL_SPACEUSED`, simulator
   runtimes in root-only folders from `xcrun simctl runtime list`, and whatever's left of the data volume's usage is
   shown as **Hidden from scan** (snapshots, purgeable data, protected folders).

To teach it about a new space hog, add a `Rule` to `Catalogue.swift` (and a `Namer` case if the folder name needs
decoding).

## Building

Open `SpaceMan.xcodeproj` and run. The app is unsandboxed so it can read arbitrary paths.

To distribute, archive and use Organizer › Distribute App › Direct Distribution, which signs with the team's
Developer ID Application certificate and notarises the app (Hardened Runtime is already on).

Build with an Xcode whose SDK matches the running macOS: a macOS 27.1 beta SDK build crashes in SwiftUI's state
initialisation on macOS 27.0.

## Full Disk Access

Without it, ~900 folders (Mail, Messages, Safari, other apps' containers…) can't be read and land in
"Hidden from scan", and macOS prompts for Desktop/Documents/Downloads access. Grant it in System Settings ›
Privacy & Security › Full Disk Access, then rescan. The grant is tied to the code signature, which is why the
project signs with a development team: an ad-hoc-signed build would lose the grant on every rebuild.
