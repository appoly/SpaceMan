import Testing
@testable import SpaceMan

struct ClassifierTests {
    private let context = NamingContext(home: "/Users/test", osBuild: "26A1", simulatorRuntimes: nil, unavailableSimulatorUDIDs: [])

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
                                folder("Other", 10),
                            ]),
                        ]),
                    ]),
                    folder("Stuff", 30),
                ]),
            ]),
        ])
    }

    private func classify(_ rules: [Rule]) -> [StorageItem] {
        Classifier(root: tree, rules: rules, context: context, minimumSize: 1).classify()
    }

    @Test func deeperRulesClaimSpaceFromShallowerOnes() throws {
        let categories = classify([
            Rule(.appleDevelopment, nil, "~/Library/Developer", "Developer"),
            Rule(.appleDevelopment, nil, "~/Library/Developer/Xcode/DerivedData", "DerivedData", children: .named(.derivedData)),
        ])

        let development = try #require(categories.item(withID: "category:appleDevelopment"))
        #expect(development.children?.map(\.title) == ["DerivedData", "Developer"])
        #expect(development.children?.map(\.size) == [40, 15])
        #expect(categories.item(withID: "/Users/test/Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab")?.title == "App")
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
    private let context = NamingContext(home: "/Users/test", osBuild: "26A1", simulatorRuntimes: nil, unavailableSimulatorUDIDs: [])

    private func name(_ namer: Namer, _ path: String) -> ItemName {
        namer.name(for: path, context: context)
    }

    @Test func swiftPMArtifactsDecodeNameAndVersion() {
        #expect(name(.swiftPMArtifact, "/x/https___dl_google_com_firebase_ios_appads_2_3_0_GoogleAdsOnDeviceConversion_zip").title
            == "GoogleAdsOnDeviceConversion 2.3.0")
        #expect(name(.swiftPMArtifact, "/x/https___b_stripecdn_com_content_CaptureCore_xcframework_zip").title == "CaptureCore")
    }

    @Test func hashSuffixesAreStripped() {
        #expect(name(.hashSuffixed, "/x/Alamofire-63cd6d99").title == "Alamofire")
        #expect(name(.hashSuffixed, "/x/abseil-cpp-SwiftPM-05c6c0b2").title == "abseil-cpp-SwiftPM")
    }

    @Test func deviceSupportSplitsModelFromVersion() {
        #expect(name(.deviceSupportVersion, "/x/iPhone18,1 27.0 (24A437)") == ItemName(title: "27.0 (24A437)", subtitle: "iPhone18,1"))
        #expect(name(.deviceSupportVersion, "/x/17.5 (21F79)").title == "17.5 (21F79)")
    }

    @Test func huggingFaceReposBecomeOwnerSlashName() {
        #expect(name(.huggingFaceRepo, "/x/models--mistralai--Mistral-7B-v0.1") == ItemName(title: "mistralai/Mistral-7B-v0.1", subtitle: "model"))
    }

    @Test func mobileAssetsUseKnownNamesThenHumanise() {
        #expect(name(.mobileAsset, "/x/com_apple_MobileAsset_UAF_Siri_Understanding").title == "Siri language understanding")
        #expect(name(.mobileAsset, "/x/com_apple_MobileAsset_UAF_FM_GenerativeModels").title == "FM Generative Models")
    }

    @Test func staleDyldCachesAreFlagged() {
        #expect(name(.dyldCache, "/x/26A1").flags.isEmpty)
        #expect(!name(.dyldCache, "/x/25A2").flags.isEmpty)
    }
}
