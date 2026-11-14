import SwiftUI
import XCTest
@testable import MouseHerdr

final class MouseCatalogTests: XCTestCase {
    private let everything = MouseProfile.all + MouseProfile.fallbacks

    // MARK: Recognising mice

    /// What real mice report (vendor id, product id, name) and the profile each should get.
    private let sightings: [(vendor: Int, product: Int, name: String, profile: String)] = [
        // The three devices on the Mac this was developed on.
        (0x046D, 0xB042, "MX Master 4", "mxMaster4"),
        (0x045E, 0x00CB, "Microsoft USB Optical Mouse", "msBasicOptical"),
        (0x046D, 0xC52B, "USB Receiver", "logitechReceiver"),
        // Logitech over Bluetooth, by product id.
        (0x046D, 0xB034, "MX Master 3S", "mxMaster3S"),
        (0x046D, 0xB023, "MX Master 3", "mxMaster3"),
        (0x046D, 0xB019, "MX Master 2S", "mxMaster2S"),
        (0x046D, 0xB012, "MX Master", "mxMaster"),
        (0x046D, 0xB025, "MX Anywhere 3", "mxAnywhere3"),
        (0x046D, 0xB037, "MX Anywhere 3S", "mxAnywhere3"),
        (0x046D, 0xB01A, "MX Anywhere 2S", "mxAnywhere2"),
        (0x046D, 0xB020, "MX Vertical", "mxVertical"),
        (0x046D, 0xB01D, "MX Ergo", "mxErgo"),
        (0x046D, 0xB015, "M720 Triathlon", "m720"),
        (0x046D, 0xB02A, "Signature M650", "signatureM650"),
        // Logitech by name alone, for models whose product ids are not published.
        (0x046D, 0xBFFF, "LIFT", "lift"),
        (0x046D, 0xBFFF, "ERGO M575", "ergoM575"),
        (0x046D, 0xBFFF, "Logi POP Mouse", "popMouse"),
        (0x046D, 0xBFFF, "Logitech Pebble", "pebble"),
        // Logitech over USB.
        (0x046D, 0xC08B, "G502 HERO Gaming Mouse", "g502"),
        (0x046D, 0xC094, "PRO X Wireless", "gPro"),
        (0x046D, 0xC092, "G203 LIGHTSYNC Gaming Mouse", "g203"),
        (0x046D, 0xC548, "USB Receiver", "logitechReceiver"),
        // Apple: the same mouse has one vendor id over Bluetooth and another over USB, and carries its owner's name.
        (0x004C, 0x0269, "Roy’s Magic Mouse", "magicMouse"),
        (0x05AC, 0x0269, "Magic Mouse", "magicMouse"),
        (0x05AC, 0x030D, "Magic Mouse", "magicMouse"),
        (0x004C, 0x0323, "Magic Mouse", "magicMouse"),
        (0x05AC, 0x0304, "Apple Optical USB Mouse", "appleMouse"),
        // Microsoft.
        (0x045E, 0x0823, "Microsoft Classic IntelliMouse", "msIntelliMouse"),
        (0x045E, 0x082A, "Microsoft Pro IntelliMouse", "msIntelliMouse"),
        (0x045E, 0x0FFF, "Microsoft Modern Mobile Mouse", "msBluetoothMouse"),
        (0x045E, 0x0FFF, "Microsoft Bluetooth Mouse", "msBluetoothMouse"),
        (0x045E, 0x0FFF, "Surface Arc Mouse", "msArc"),
        (0x045E, 0x0FFF, "Microsoft Arc Mouse", "msArc"),
        (0x045E, 0x0FFF, "Microsoft Bluetooth Ergonomic Mouse", "msErgonomic"),
        (0x045E, 0x0FFF, "Microsoft Sculpt Ergonomic Mouse", "msSculptErgonomic"),
        (0x045E, 0x0FFF, "Surface Precision Mouse", "surfacePrecision"),
        (0x045E, 0x076C, "Comfort Mouse 4500", "msComfort4500"),
        (0x045E, 0x07A5, "Microsoft® 2.4GHz Transceiver v9.0", "microsoftReceiver"),
        // Razer.
        (0x1532, 0x0084, "Razer DeathAdder V2", "razerDeathAdder"),
        (0x1532, 0x007A, "Razer Viper Ultimate (Wired)", "razerViper"),
        (0x1532, 0x0099, "Razer Basilisk V3", "razerBasilisk"),
        (0x1532, 0x0080, "Razer Pro Click", "razerProClick"),
        (0x1532, 0x00C7, "Razer Pro Click V2 Vertical Edition", "razerProClickVertical"),
        (0x1532, 0x0095, "Razer Orochi V2", "razerOrochi"),
        // Other makers.
        (0x1038, 0x1824, "SteelSeries Rival 3", "steelSeriesRival"),
        (0x1038, 0x183A, "SteelSeries Aerox 3 Wireless", "steelSeriesAerox"),
        (0x1B1C, 0x1B5A, "CORSAIR M65 RGB ELITE Gaming Mouse", "corsairM65"),
        (0x1B1C, 0x1B75, "Corsair HARPOON RGB PRO Gaming Mouse", "corsairHarpoon"),
        (0x258A, 0x0036, "Glorious Model O", "gloriousModelO"),
        (0x047D, 0x1020, "Kensington Expert Mouse", "kensingtonExpert"),
        (0x047D, 0x2041, "Kensington Slimblade Trackball", "kensingtonSlimBlade"),
        (0x056E, 0x00FB, "ELECOM TrackBall Mouse", "elecomEXG"),
        (0x1A7C, 0x0191, "Evoluent VerticalMouse 4", "evoluentVertical"),
        (0x413C, 0x301A, "Dell MS116 USB Optical Mouse", "dellOptical"),
        (0x03F0, 0x134A, "HP USB Optical Mouse", "hpOptical"),
        (0x17EF, 0x608D, "Lenovo USB Optical Mouse", "lenovoOptical"),
        // A maker whose vendor id is not known is recognised by name, whatever id it reports.
        (0x1234, 0x5678, "Satechi M1 Mouse", "satechiM1"),
    ]

    func testMiceOfEveryBrandAreRecognisedFromWhatTheyReport() {
        for seen in sightings {
            let found = MouseProfile.matching(vendor: seen.vendor, product: seen.product, name: seen.name)
            XCTAssertEqual(found?.id, seen.profile, "\(String(format: "%04x:%04x", seen.vendor, seen.product)) \(seen.name)")
        }
    }

    func testTheLongestNameWinsSoSimilarModelsAreToldApart() {
        func named(_ name: String) -> String? { MouseProfile.matching(vendor: 0x046D, product: 0xBFFF, name: name)?.id }
        XCTAssertEqual(named("MX Master 4"), "mxMaster4")
        XCTAssertEqual(named("MX Master 3S"), "mxMaster3S")
        XCTAssertEqual(named("MX Master 3 Mac"), "mxMaster3")
        XCTAssertEqual(named("MX Master 2S"), "mxMaster2S")
        XCTAssertEqual(named("Wireless Mouse MX Master"), "mxMaster")
        XCTAssertEqual(named("mx master 3s"), "mxMaster3S", "names are matched whatever their case")
        // Whatever order the list is in: "Ergonomic Mouse" comes first there, yet the longer name wins.
        XCTAssertEqual(MouseProfile.matching(vendor: 0x045E, product: 0x0FFF, name: "Microsoft Sculpt Ergonomic Mouse")?.id, "msSculptErgonomic")
        XCTAssertEqual(MouseProfile.matching(vendor: 0x045E, product: 0x0FFF, name: "Microsoft Bluetooth Ergonomic Mouse")?.id, "msErgonomic")
        XCTAssertEqual(MouseProfile.matching(vendor: 0x1532, product: 0x0FFF, name: "Razer Pro Click V2 Vertical Edition")?.id, "razerProClickVertical")
    }

    func testAMouseWithNoVendorIdIsRecognisedByNameAlone() {
        XCTAssertEqual(MouseProfile.matching(vendor: 0, product: 0, name: "Someone’s Magic Mouse")?.id, "magicMouse")
        XCTAssertEqual(MouseProfile.matching(vendor: 0, product: 0, name: "MX Anywhere 3S")?.id, "mxAnywhere3")
    }

    func testAnotherMakersIdOrNameIsNotMistakenForAKnownMouse() {
        // Logitech's product id under Microsoft's vendor id is not an MX Master 3S.
        XCTAssertNil(MouseProfile.matching(vendor: 0x045E, product: 0xB034, name: "Wireless Mouse"))
        // Nor is a Razer device that happens to carry a Logitech name.
        XCTAssertNil(MouseProfile.matching(vendor: 0x1532, product: 0x0001, name: "MX Master 3S"))
        XCTAssertNil(MouseProfile.matching(vendor: 0x1234, product: 0x5678, name: "Unrecognized mouse"))
        XCTAssertNil(MouseProfile.matching(vendor: 0, product: 0, name: ""))
    }

    func testAnUnknownMouseGetsALayoutThatFitsItsButtons() {
        XCTAssertEqual(MouseProfile.fallback(buttons: 0).id, "generic", "a mouse that doesn't say is assumed to have side buttons")
        XCTAssertEqual(MouseProfile.fallback(buttons: 2).id, "generic2")
        XCTAssertEqual(MouseProfile.fallback(buttons: 3).id, "generic3")
        XCTAssertEqual(MouseProfile.fallback(buttons: 5).id, "generic")
        XCTAssertEqual(MouseProfile.fallback(buttons: 16).id, "generic")
        XCTAssertEqual(MouseProfile.generic3.controls.map(\.slot), [.middle])
        XCTAssertEqual(Set(MouseProfile.generic.controls.map(\.slot)), [.middle, .back, .forward])
        XCTAssertTrue(MouseProfile.generic2.controls.allSatisfy(\.virtual))
    }

    // MARK: The list itself

    func testTheListIsBigEnoughAndCoversTheWellKnownMakers() {
        let mice = MouseProfile.all.filter { $0.kind == .mouse }
        XCTAssertGreaterThanOrEqual(mice.count, 50)
        let brands = Set(mice.map(\.brand))
        for brand in ["Apple", "Logitech", "Microsoft", "Razer", "SteelSeries", "Corsair", "Kensington"] {
            XCTAssertTrue(brands.contains(brand), brand)
        }
        XCTAssertGreaterThanOrEqual(brands.count, 12)
    }

    func testEveryProfileCanBeToldFromEveryOther() {
        XCTAssertEqual(Set(everything.map(\.id)).count, everything.count, "profile ids are unique")
        var claimed: [String: String] = [:]
        for p in MouseProfile.all {
            XCTAssertFalse(p.productIDs.isEmpty && p.nameContains.isEmpty, "\(p.id) has no way to be recognised")
            for vendor in p.vendorIDs {
                for product in p.productIDs {
                    let key = String(format: "%04x:%04x", vendor, product)
                    XCTAssertNil(claimed[key], "\(key) is claimed by \(claimed[key] ?? "") and \(p.id)")
                    claimed[key] = p.id
                }
            }
        }
        // Two profiles that could both be asked about a device must not share a name to look for.
        for (i, a) in MouseProfile.all.enumerated() {
            for b in MouseProfile.all.dropFirst(i + 1) where a.vendorIDs.isEmpty || b.vendorIDs.isEmpty || !a.vendorIDs.isDisjoint(with: b.vendorIDs) {
                let shared = Set(a.nameContains.map { $0.lowercased() }).intersection(b.nameContains.map { $0.lowercased() })
                XCTAssertTrue(shared.isEmpty, "\(a.id) and \(b.id) both look for \(shared)")
            }
        }
        for p in MouseProfile.fallbacks {
            XCTAssertTrue(p.productIDs.isEmpty && p.nameContains.isEmpty, "\(p.id) must match nothing")
            XCTAssertEqual(p.kind, .fallback)
        }
    }

    func testOnlyTheMXMaster4IsSaidToBeTested() {
        XCTAssertEqual(everything.filter(\.tested).map(\.id), ["mxMaster4"])
    }

    func testEveryProfileIsListedUnderItsBrandInTheWindow() {
        for p in everything {
            XCTAssertTrue(MouseCatalog.brands.contains(p.brand), "\(p.id): \(p.brand)")
        }
        let listed = MousePickerPanel.models(matching: "").flatMap(\.models)
        XCTAssertEqual(Set(listed.map(\.id)), Set(everything.filter { $0.kind != .receiver }.map(\.id)))
        XCTAssertEqual(MousePickerPanel.models(matching: "razer viper").flatMap(\.models).map(\.id), ["razerViper"])
        XCTAssertEqual(MousePickerPanel.models(matching: "MASTER 3s").flatMap(\.models).map(\.id), ["mxMaster3S"])
        XCTAssertTrue(MousePickerPanel.models(matching: "no such mouse anywhere").isEmpty)
    }

    // MARK: What the buttons do out of the box

    func testTheWheelClickOpensTheAgentWheelOnEveryOtherMouseThatHasOne() {
        for p in everything where p.id != "mxMaster4" {
            let middle = p.control(.middle)
            XCTAssertNotNil(middle, "\(p.id) has no middle click to offer")
            if p.controls.allSatisfy(\.virtual) {
                // Nothing on the mouse can open the wheel, and the window says so.
                XCTAssertNil(p.wheelControl, p.id)
                XCTAssertEqual(p.defaults[.middle], .standard, p.id)
                XCTAssertNotNil(p.note, "\(p.id) should explain that it has no spare button")
            } else {
                XCTAssertEqual(p.defaults[.middle]?.kind, "agentWheel", p.id)
                XCTAssertEqual(p.wheelControl?.slot, .middle, p.id)
            }
            XCTAssertFalse(p.hasHaptics, p.id)
        }
    }

    func testTheMXMaster4KeepsTheDefaultsItHad() {
        let p = MouseProfile.mxMaster4
        XCTAssertEqual(p.defaults[.middle], .standard)
        XCTAssertEqual(p.defaults[.thumbPanel], Action(kind: "dragWindow"))
        XCTAssertNil(p.wheelControl, "its wheel opens with a tap on the pad, not with a button of its own")
        XCTAssertTrue(p.hasHaptics)
        XCTAssertTrue(p.usesDirectLink)
        XCTAssertEqual(p.fullName, "Logitech MX Master 4")
    }

    func testControlsThatNeedTheDirectLinkAreOnlyOnLogitechMice() {
        for p in everything where p.usesDirectLink {
            XCTAssertEqual(p.vendorIDs, [MouseProfile.logitech], p.id)
        }
        XCTAssertTrue(MouseProfile.named("mxMaster3S")?.usesDirectLink ?? false)
        XCTAssertEqual(MouseProfile.named("mxMaster3S")?.control(.gesture)?.cid, 0x00C3)
        XCTAssertFalse(MouseProfile.named("msBasicOptical")?.usesDirectLink ?? true)
    }

    // MARK: The drawings

    func testEveryDrawingFitsItsCanvasAndItsLabelsDoNotCollide() {
        let chip = MouseArt.chipSize
        for p in everything {
            let size = p.art.size
            XCTAssertEqual(size, MouseBody.canvas, "\(p.id): every mouse is drawn on the same canvas")
            let canvas = CGRect(origin: .zero, size: size)
            let body = p.art.bounds
            XCTAssertTrue(canvas.contains(body), "\(p.id): the body \(body) leaves the canvas")
            XCTAssertGreaterThan(body.width, 100, p.id)
            XCTAssertGreaterThan(body.height, 250, p.id)
            for c in p.controls {
                XCTAssertTrue(c.rect.width > 4 && c.rect.height > 4, "\(p.id) \(c.slot): no place on the drawing")
                XCTAssertTrue(body.insetBy(dx: -12, dy: -12).contains(c.rect), "\(p.id) \(c.slot): \(c.rect) is off the mouse")
                let label = CGRect(x: c.chip.x - chip.width / 2, y: c.chip.y - chip.height / 2, width: chip.width, height: chip.height)
                XCTAssertTrue(canvas.contains(label), "\(p.id) \(c.slot): its label \(label) leaves the canvas")
                XCTAssertEqual(c.chipOnLeft, c.chip.x < size.width / 2, "\(p.id) \(c.slot)")
                // A label sits beside the mouse, not on it.
                XCTAssertFalse(label.intersects(p.art.body.boundingRect), "\(p.id) \(c.slot): its label covers the mouse")
            }
            for side in [true, false] {
                let heights = p.controls.filter { $0.chipOnLeft == side }.map(\.chip.y).sorted()
                for (above, below) in zip(heights, heights.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(below - above, chip.height + 4, "\(p.id): labels overlap at \(above) and \(below)")
                }
            }
            // The corner under the right-hand labels belongs to the "Your mouse" plate.
            for c in p.controls where !c.chipOnLeft {
                XCTAssertLessThan(c.chip.y + chip.height / 2, 410, "\(p.id) \(c.slot): its label runs into the mouse's name plate")
            }
        }
    }

    func testLabelsAreSpreadApartAndKeptOnTheCanvas() {
        XCTAssertEqual(MouseProfile.spread([]), [])
        XCTAssertEqual(MouseProfile.spread([150]), [150])
        XCTAssertEqual(MouseProfile.spread([100, 300]), [100, 300], "labels with room stay beside their controls")
        XCTAssertEqual(MouseProfile.spread([238, 276]), [224, 290], "two close ones move apart around their middle")
        let crowded = MouseProfile.spread([460, 470, 478])
        XCTAssertEqual(crowded.count, 3)
        XCTAssertLessThanOrEqual(crowded.last ?? 0, 480)
        for (a, b) in zip(crowded, crowded.dropFirst()) { XCTAssertEqual(b - a, 66, accuracy: 0.001) }
        let top = MouseProfile.spread([10, 20])
        XCTAssertGreaterThanOrEqual(top.first ?? 0, 40)
    }
}
