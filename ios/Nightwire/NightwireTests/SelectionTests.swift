import XCTest
@testable import Nightwire

final class SelectionTests: XCTestCase {
    func testAutomaticSelectionPrefersPluggedInUSBEthernet() {
        let chosen = InterfaceChooser.resolve(
            candidates: [
                candidate("en0", .wifi, pluggedIn: true, addressed: true, defaultPath: true),
                candidate("pdp_ip0", .cellular, pluggedIn: true, addressed: true, defaultPath: false),
                candidate("en2", .usbEthernet, pluggedIn: true, addressed: false, defaultPath: false)
            ],
            pinnedName: nil
        )
        XCTAssertEqual(chosen, "en2")
    }

    func testPinnedInterfaceWinsOverTheDongle() {
        let chosen = InterfaceChooser.resolve(
            candidates: [
                candidate("en2", .usbEthernet, pluggedIn: true, addressed: true, defaultPath: true),
                candidate("en0", .wifi, pluggedIn: true, addressed: true, defaultPath: false)
            ],
            pinnedName: "en0"
        )
        XCTAssertEqual(chosen, "en0")
    }

    func testMissingPinFallsBackToTheDongle() {
        let chosen = InterfaceChooser.resolve(
            candidates: [
                candidate("en0", .wifi, pluggedIn: true, addressed: true, defaultPath: true)
            ],
            pinnedName: "en2"
        )
        XCTAssertEqual(chosen, "en0")
    }

    func testAddressedDongleBeatsAnUnaddressedOne() {
        let chosen = InterfaceChooser.resolve(
            candidates: [
                candidate("en3", .usbEthernet, pluggedIn: true, addressed: false, defaultPath: true),
                candidate("en2", .usbEthernet, pluggedIn: true, addressed: true, defaultPath: false)
            ],
            pinnedName: nil
        )
        XCTAssertEqual(chosen, "en2")
    }

    func testWithoutADongleTheDefaultPathWins() {
        let chosen = InterfaceChooser.resolve(
            candidates: [
                candidate("pdp_ip0", .cellular, pluggedIn: true, addressed: true, defaultPath: false),
                candidate("en0", .wifi, pluggedIn: true, addressed: true, defaultPath: true)
            ],
            pinnedName: nil
        )
        XCTAssertEqual(chosen, "en0")
    }

    func testEmptyCandidateList() {
        XCTAssertNil(InterfaceChooser.resolve(candidates: [], pinnedName: nil))
    }

    func testKindResolverTrustsThePathOverMedia() {
        XCTAssertEqual(
            InterfaceKindResolver.resolve(pathKind: .wifi, catalogKind: nil, mediaKind: .usbEthernet, bsdName: "en0"),
            .wifi
        )
    }

    func testKindResolverDoesNotGuessEthernetFromTheBSDName() {
        XCTAssertEqual(
            InterfaceKindResolver.resolve(pathKind: nil, catalogKind: nil, mediaKind: nil, bsdName: "en2"),
            .other
        )
        XCTAssertEqual(
            InterfaceKindResolver.resolve(pathKind: nil, catalogKind: .usbEthernet, mediaKind: nil, bsdName: "en5"),
            .usbEthernet
        )
        XCTAssertEqual(
            InterfaceKindResolver.resolve(pathKind: nil, catalogKind: nil, mediaKind: nil, bsdName: "pdp_ip0"),
            .cellular
        )
        XCTAssertEqual(
            InterfaceKindResolver.resolve(pathKind: nil, catalogKind: nil, mediaKind: nil, bsdName: "en0"),
            .wifi
        )
    }

    func testNaming() {
        XCTAssertEqual(InterfaceNaming.displayName(kind: .usbEthernet, localized: "Ethernet", bsdName: "en2"), "USB Ethernet")
        XCTAssertEqual(InterfaceNaming.displayName(kind: .usbEthernet, localized: "AX88179A", bsdName: "en2"), "AX88179A")
        XCTAssertEqual(InterfaceNaming.displayName(kind: .wifi, localized: nil, bsdName: "en0"), "Wi-Fi")
        XCTAssertEqual(InterfaceNaming.displayName(kind: .cellular, localized: "", bsdName: "pdp_ip0"), "Cellular")
    }

    func testPlugState() {
        XCTAssertTrue(PlugState.isPluggedIn(kind: .usbEthernet, isUp: false, inPath: false, hasAddress: false, mediaValid: true))
        XCTAssertFalse(PlugState.isPluggedIn(kind: .usbEthernet, isUp: false, inPath: false, hasAddress: false, mediaValid: false))
        XCTAssertTrue(PlugState.isPluggedIn(kind: .wifi, isUp: false, inPath: true, hasAddress: false, mediaValid: false))
        XCTAssertFalse(PlugState.isPluggedIn(kind: .wifi, isUp: false, inPath: false, hasAddress: false, mediaValid: true))
    }

    func testLinkState() {
        XCTAssertTrue(LinkState.hasLink(hasGlobalIPv4: true, isRunning: false, mediaValid: true, mediaStatus: 0))
        XCTAssertTrue(LinkState.hasLink(hasGlobalIPv4: false, isRunning: false, mediaValid: true, mediaStatus: 0x3))
        XCTAssertFalse(LinkState.hasLink(hasGlobalIPv4: false, isRunning: true, mediaValid: true, mediaStatus: 0x1))
        XCTAssertTrue(LinkState.hasLink(hasGlobalIPv4: false, isRunning: true, mediaValid: false, mediaStatus: 0))
    }

    func testCaption() {
        XCTAssertEqual(
            SelectionCaption.text(pinnedName: nil, interfaceNames: ["en2"], selectedKind: .usbEthernet),
            "Automatic · USB Ethernet is connected"
        )
        XCTAssertEqual(
            SelectionCaption.text(pinnedName: "en0", interfaceNames: ["en0"], selectedKind: .wifi),
            "Pinned"
        )
        XCTAssertEqual(
            SelectionCaption.text(pinnedName: "en2", interfaceNames: ["en0"], selectedKind: .wifi),
            "Waiting for en2. Showing another interface until it returns."
        )
    }

    private func candidate(
        _ name: String,
        _ kind: InterfaceKind,
        pluggedIn: Bool,
        addressed: Bool,
        defaultPath: Bool
    ) -> InterfaceCandidate {
        InterfaceCandidate(
            name: name,
            kind: kind,
            isPluggedIn: pluggedIn,
            hasGlobalIPv4: addressed,
            isDefaultPath: defaultPath
        )
    }
}
