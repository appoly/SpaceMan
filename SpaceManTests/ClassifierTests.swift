import Testing
@testable import SpaceMan

struct ClassifierTests {
    private let context = NamingContext(
        home: "/Users/test", osBuild: "26A1", simulatorRuntimes: nil, unavailableSimulatorUDIDs: []
    )

    private func folder(_ name: String, _ size: Int64 = 0, _ children: [FSNode] = []) -> FSNode {
        FSNode(name: name, isDirectory: true, size: size + children.reduce(0) { $0 + $1.size }, children: children)
    }

    private func folder(_ name: String, _ children: [FSNode]) -> FSNode {
        folder(name, 0, children)
    }

    private var tree: FSNode {
        folder("/", [
            folder("Users", [
                folder("test", [
                    folder("Library", [
                        folder("Developer", 5, [
                            folder("Xcode", [
                                folder("DerivedData", [folder("App-abcdefghijklmnopqrstuvwxyzab", 40)]),
                                folder("Other", 10)
                            ])
                        ])
                    ]),
                    folder("Stuff", 30)
                ])
            ])
        ])
    }

    private func classify(_ rules: [Rule]) -> [StorageItem] {
        Classifier(root: tree, rules: rules, context: context, minimumSize: 1).classify()
    }

    @Test func deeperRulesClaimSpaceFromShallowerOnes() throws {
        let categories = classify([
            Rule(.appleDevelopment, nil, "~/Library/Developer", "Developer"),
            Rule(
                .appleDevelopment, nil, "~/Library/Developer/Xcode/DerivedData", "DerivedData",
                children: .named(.derivedData)
            )
        ])

        let development = try #require(categories.item(withID: "category:appleDevelopment"))
        #expect(development.children?.map(\.title) == ["DerivedData", "Developer"])
        #expect(development.children?.map(\.size) == [40, 15])
        let appItemID = "/Users/test/Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab"
        #expect(categories.item(withID: appItemID)?.title == "App")
    }

    @Test func unclaimedSpaceLandsInOtherWithCollapsedChains() throws {
        let categories = classify([Rule(.appleDevelopment, nil, "~/Library/Developer", "Developer")])

        let other = try #require(categories.item(withID: "category:other"))
        #expect(other.size == 30)
        #expect(other.children?.map(\.title) == ["Users/test/Stuff"])
    }

    @Test func totalsAddUpToScannedSize() {
        let categories = classify(Catalogue.rules)
        #expect(categories.reduce(0) { $0 + $1.size } == tree.size)
    }

    @Test func wildcardsMatchPathComponents() throws {
        let categories = classify([Rule(.caches, "Group", "~/Library/Developer/*", .folderName)])
        let group = try #require(categories.item(withID: "group:caches:Group"))
        #expect(group.children?.map(\.title) == ["Xcode"])
    }
}

struct NamerTests {
    private let context = NamingContext(
        home: "/Users/test", osBuild: "26A1", simulatorRuntimes: nil, unavailableSimulatorUDIDs: []
    )

    private func name(_ namer: Namer, _ path: String) -> ItemName {
        namer.name(for: path, context: context)
    }

    @Test func swiftPMArtifactsDecodeNameAndVersion() {
        let googleAdsPath = "/x/https___dl_google_com_firebase_ios_appads_2_3_0_GoogleAdsOnDeviceConversion_zip"
        #expect(name(.swiftPMArtifact, googleAdsPath).title == "GoogleAdsOnDeviceConversion 2.3.0")
        let capturePath = "/x/https___b_stripecdn_com_content_CaptureCore_xcframework_zip"
        #expect(name(.swiftPMArtifact, capturePath).title == "CaptureCore")
    }

    @Test func hashSuffixesAreStripped() {
        #expect(name(.hashSuffixed, "/x/Alamofire-63cd6d99").title == "Alamofire")
        #expect(name(.hashSuffixed, "/x/abseil-cpp-SwiftPM-05c6c0b2").title == "abseil-cpp-SwiftPM")
    }

    @Test func deviceSupportSplitsModelFromVersion() {
        let expected = ItemName(title: "27.0 (24A437)", subtitle: "iPhone18,1")
        #expect(name(.deviceSupportVersion, "/x/iPhone18,1 27.0 (24A437)") == expected)
        #expect(name(.deviceSupportVersion, "/x/17.5 (21F79)").title == "17.5 (21F79)")
    }

    @Test func huggingFaceReposBecomeOwnerSlashName() {
        let expected = ItemName(title: "mistralai/Mistral-7B-v0.1", subtitle: "model")
        #expect(name(.huggingFaceRepo, "/x/models--mistralai--Mistral-7B-v0.1") == expected)
    }

    @Test func mobileAssetsUseKnownNamesThenHumanise() {
        let siriPath = "/x/com_apple_MobileAsset_UAF_Siri_Understanding"
        #expect(name(.mobileAsset, siriPath).title == "Siri language understanding")
        let fmPath = "/x/com_apple_MobileAsset_UAF_FM_GenerativeModels"
        #expect(name(.mobileAsset, fmPath).title == "FM Generative Models")
    }

    @Test func staleDyldCachesAreFlagged() {
        #expect(name(.dyldCache, "/x/26A1").flags.isEmpty)
        #expect(!name(.dyldCache, "/x/25A2").flags.isEmpty)
    }
}

struct LocationTreeTests {
    @Test func foldersKeepRawNamesAndCarryWhatTheyWereIdentifiedAs() throws {
        let derivedData = FSNode(name: "DerivedData", isDirectory: true, size: 50, children: [])
        let root = FSNode(name: "/", isDirectory: true, size: 60, children: [
            FSNode(name: "Users", isDirectory: true, size: 60, children: [derivedData])
        ])
        let identified = StorageItem(
            id: "/Users/DerivedData", title: "Xcode build products", path: "/Users/DerivedData", size: 50,
            category: .appleDevelopment
        )
        let category = StorageItem(
            id: "category:appleDevelopment", kind: .category, title: "Dev", size: 50, category: .appleDevelopment,
            children: [identified]
        )

        let locations = LocationTree.items(root: root, categories: [category], minimumSize: 5)

        let users = try #require(locations.first)
        #expect(users.title == "Users")
        #expect(users.identifiedAs == nil)
        #expect(users.children?.map(\.title) == ["DerivedData", "Smaller items"])
        let folder = try #require(users.children?.first)
        #expect(folder.identifiedAs == "Xcode build products")
        #expect(folder.category == .appleDevelopment)
    }
}

struct TreeUpdateTests {
    private func folder(_ name: String, _ size: Int64, _ children: [FSNode] = []) -> FSNode {
        FSNode(name: name, isDirectory: true, size: size + children.reduce(0) { $0 + $1.size }, children: children)
    }

    @Test func removingANodeShrinksEveryAncestor() throws {
        let derivedData = folder("DerivedData", 3, [folder("App", 40)])
        let tree = folder("/", 1, [folder("Users", 2, [derivedData, folder("Keep", 9)])])

        let updated = tree.replacing(at: "/Users/DerivedData/App", with: nil, retainThreshold: 1)

        #expect(updated.size == tree.size - 40)
        #expect(updated.node(at: "/Users")?.size == 14)
        #expect(updated.node(at: "/Users/DerivedData")?.size == 3)
        #expect(updated.node(at: "/Users/DerivedData/App") == nil)
        #expect(updated.node(at: "/Users/Keep")?.size == 9)
    }

    @Test func replacingANodeAppliesTheDifferenceAndDropsItBelowTheThreshold() {
        let tree = folder("/", 0, [folder("Trash", 10)])

        let grown = tree.replacing(at: "/Trash", with: folder("Trash", 50), retainThreshold: 5)
        #expect(grown.size == 50)
        #expect(grown.node(at: "/Trash")?.size == 50)

        let emptied = tree.replacing(at: "/Trash", with: folder("Trash", 1), retainThreshold: 5)
        #expect(emptied.size == 1)
        #expect(emptied.node(at: "/Trash") == nil)
    }
}
