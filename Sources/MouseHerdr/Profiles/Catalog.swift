import SwiftUI

/// The mice MouseHerdr recognises besides the MX Master 4.
///
/// Each one is a line: how to spot it, which shared body it is drawn from, and which of the usual
/// buttons it has. Product ids come from published tables (the Linux kernel's HID drivers, Solaar,
/// libratbag, OpenRazer, rivalcfg, ckb-next and the USB ID list); names are what the mouse reports.
/// None of these has been checked on the device itself: they use only the buttons macOS reports
/// for any mouse, or, on Logitech's Bluetooth mice, controls the mouse lists itself over HID++.
/// A mouse that needs its own shape or controls gets a file of its own, like MXMaster4.swift.
enum MouseCatalog {
    private struct Brand {
        let name: String
        /// Every vendor id its mice report, over USB and over Bluetooth.
        let vendors: Set<Int>
    }

    private static let apple = Brand(name: "Apple", vendors: [0x05AC, 0x004C])
    private static let logitech = Brand(name: "Logitech", vendors: [MouseProfile.logitech])
    private static let microsoft = Brand(name: "Microsoft", vendors: [0x045E])
    private static let razer = Brand(name: "Razer", vendors: [0x1532])
    private static let steelSeries = Brand(name: "SteelSeries", vendors: [0x1038])
    private static let corsair = Brand(name: "Corsair", vendors: [0x1B1C])
    private static let glorious = Brand(name: "Glorious", vendors: [0x258A, 0x22D4, 0x3794])
    private static let kensington = Brand(name: "Kensington", vendors: [0x047D])
    private static let elecom = Brand(name: "Elecom", vendors: [0x056E])
    private static let evoluent = Brand(name: "Evoluent", vendors: [0x1A7C])
    private static let keychron = Brand(name: "Keychron", vendors: [0x3434])
    private static let satechi = Brand(name: "Satechi", vendors: [])
    private static let zowie = Brand(name: "Zowie", vendors: [0x1AF3])
    private static let dell = Brand(name: "Dell", vendors: [0x413C])
    private static let hp = Brand(name: "HP", vendors: [0x03F0])
    private static let lenovo = Brand(name: "Lenovo", vendors: [0x17EF])

    private static func mouse(_ id: String, _ brand: Brand, _ name: String, ids: Set<Int> = [], names: [String],
                              _ body: MouseBody, _ buttons: MouseProfile.Buttons,
                              kind: MouseProfile.Kind = .mouse, note: String? = nil) -> MouseProfile {
        .make(id, brand: brand.name, name: name, vendors: brand.vendors, ids: ids, names: names,
              body: body, buttons: buttons, kind: kind, note: note)
    }

    // MARK: Bodies in the colours these mice come in

    private static let silverPlain = MouseBody.plain.finished(.silver)
    private static let blackPlain = MouseBody.plain.finished(.black)
    private static let silverCompact = MouseBody.compact.finished(.silver)
    private static let silverSculpted = MouseBody.sculpted.finished(.silver)
    private static let blackVertical = MouseBody.vertical.finished(.black)
    private static let greyGaming = MouseBody.gaming.finished(.graphite)

    private static let noSpareButton = "Open the agent wheel from the MouseHerdr menu bar icon instead."
    private static let behindReceiver = "A USB receiver doesn't say which mouse is behind it, so this is a plain layout. Pick your model under “All mice” for its picture and buttons."

    // MARK: The list

    static let mice: [MouseProfile] = [
        // Apple
        mouse("magicMouse", apple, "Magic Mouse", ids: [0x030D, 0x0269, 0x0323], names: ["Magic Mouse"],
              .magic, .none,
              note: "The Magic Mouse has no wheel to press and no spare button, so nothing on it can open the agent wheel. \(noSpareButton)"),
        mouse("appleMouse", apple, "Apple Mouse", ids: [0x0304], names: ["Mighty Mouse", "Apple Optical USB Mouse", "Apple Mouse"],
              MouseBody.plain.finished(.white), .wheel),

        // Logitech: the MX line over Bluetooth, where the direct link can reach the extra buttons
        mouse("mxMaster3S", logitech, "MX Master 3S", ids: [0xB034, 0xB035], names: ["MX Master 3S"], .sculpted, .mxMaster),
        mouse("mxMaster3", logitech, "MX Master 3", ids: [0xB023], names: ["MX Master 3"], .sculpted, .mxMaster),
        mouse("mxMaster2S", logitech, "MX Master 2S", ids: [0xB019], names: ["MX Master 2S"], .sculpted, .mxMaster),
        mouse("mxMaster", logitech, "MX Master", ids: [0xB012, 0xB017, 0xB01E], names: ["MX Master"], .sculpted, .mxMaster),
        mouse("mxAnywhere3", logitech, "MX Anywhere 3 / 3S", ids: [0xB025, 0xB02D, 0xB037, 0xB038], names: ["MX Anywhere 3"],
              .compact, .sidesAndTop(cid: 0x00C4, title: "Top button",
                                     blurb: "The small button behind the scroll wheel. Out of the box it switches the wheel between ratchet and free-spin.")),
        mouse("mxAnywhere2", logitech, "MX Anywhere 2 / 2S", ids: [0xB013, 0xB018, 0xB01F, 0xB01A], names: ["MX Anywhere 2"],
              .compact, .middleAndSides),
        mouse("mxVertical", logitech, "MX Vertical", ids: [0xB020, 0xC08A], names: ["MX Vertical"],
              .vertical, .sidesAndTop(cid: 0x00FD, title: "Top button",
                                      blurb: "The button on top of the mouse. Out of the box it changes the pointer speed.")),
        mouse("lift", logitech, "Lift", names: ["LIFT"],
              .vertical, .sidesAndTop(cid: 0x00FD, title: "Middle button",
                                      blurb: "The button below the scroll wheel. Out of the box it changes the pointer speed.")),
        mouse("mxErgo", logitech, "MX Ergo", ids: [0xB01D], names: ["MX Ergo"],
              .thumbBall, .sidesAndTop(cid: 0x00ED, title: "Precision button",
                                       blurb: "The button beside the ball. Out of the box it slows the pointer for fine work.")),
        mouse("ergoM575", logitech, "Ergo M575", names: ["M575"], .thumbBall, .wheelAndSides),
        mouse("m570", logitech, "M570 trackball", names: ["M570"], .thumbBall, .wheelAndSides),
        mouse("m720", logitech, "M720 Triathlon", ids: [0xB015], names: ["M720"], .sculpted, .sidesAndThumb(cid: 0x00D0)),
        mouse("signatureM650", logitech, "Signature M650", ids: [0xB02A], names: ["M650"], .plain, .wheelAndSides),
        mouse("m590", logitech, "M585 / M590", ids: [0xB01B], names: ["M585", "M590"], .plain, .wheelAndSides),
        mouse("m705", logitech, "M705 Marathon", names: ["M705"], .plain, .wheelAndSides),
        mouse("m510", logitech, "M510", names: ["M510"], .plain, .wheelAndSides),
        mouse("pebble", logitech, "Pebble", names: ["Pebble", "M350"], silverCompact, .wheel),
        mouse("popMouse", logitech, "POP Mouse", names: ["POP Mouse"], silverCompact, .wheel),
        mouse("m185", logitech, "M185 / M235 / M325", names: ["M185", "M235", "M325"], .compact, .wheel),
        // Logitech G
        mouse("g502", logitech, "G502", ids: [0xC07D, 0xC332, 0xC08B, 0xC08D, 0xC099, 0xC095, 0xC098], names: ["G502"],
              .gaming, .wheelAndSides),
        mouse("gPro", logitech, "G Pro / Pro X Superlight", ids: [0xC088, 0xC094, 0xC09B, 0xC09A, 0xC085, 0xC08C],
              names: ["PRO X", "G Pro"], .ambi, .wheelAndSides),
        mouse("g203", logitech, "G203 / G102", ids: [0xC084, 0xC092, 0xC09D], names: ["G203", "G102"], .ambi, .wheelAndSides),
        mouse("g305", logitech, "G305 / G304", names: ["G305", "G304"], .ambi, .wheelAndSides),
        mouse("g403", logitech, "G403 / G703", ids: [0xC083, 0xC08F, 0xC082, 0xC087, 0xC090], names: ["G403", "G703"],
              .gaming, .wheelAndSides),
        mouse("g903", logitech, "G903 / G900", ids: [0xC086, 0xC091, 0xC081], names: ["G903", "G900"], .ambi, .wheelAndSides),
        mouse("logitechReceiver", logitech, "Mouse on a Logitech receiver",
              ids: [0xC52B, 0xC532,                                      // Unifying
                    0xC52F, 0xC534, 0xC526,                              // Nano
                    0xC539, 0xC53F, 0xC543, 0xC547, 0xC54D, 0xC545,      // Lightspeed
                    0xC53A, 0xC531,                                      // PowerPlay, G700
                    0xC548],                                             // Bolt
              names: ["USB Receiver"], .plain, .wheelAndSides, kind: .receiver, note: behindReceiver),

        // Microsoft
        mouse("msBasicOptical", microsoft, "Basic Optical Mouse", ids: [0x00CB, 0x0083, 0x0084, 0x0040, 0x0797, 0x0737, 0x00A4],
              names: ["Microsoft USB Optical Mouse", "Basic Optical Mouse", "Wheel Mouse Optical", "Compact Optical Mouse", "Optical Mouse 200"],
              blackPlain, .wheel),
        mouse("msBluetoothMouse", microsoft, "Bluetooth Mouse / Modern Mobile Mouse",
              names: ["Microsoft Bluetooth Mouse", "Modern Mobile Mouse", "Surface Mobile Mouse", "Designer Mouse",
                      "BluetoothMouse3600", "Mobile Mouse 3600", "Wireless Mobile Mouse"],
              silverCompact, .wheel),
        mouse("msArc", microsoft, "Arc Mouse", names: ["Arc Mouse", "Arc Touch"], .arc, .none,
              note: "Arc mice send a Mac only left and right clicks; their middle click needs Microsoft's software for Windows. \(noSpareButton)"),
        mouse("msErgonomic", microsoft, "Bluetooth Ergonomic Mouse", names: ["Ergonomic Mouse"], silverSculpted, .wheelAndSides),
        mouse("surfacePrecision", microsoft, "Surface Precision Mouse", names: ["Precision Mouse"], silverSculpted, .wheelAndSides),
        mouse("msSculptErgonomic", microsoft, "Sculpt Ergonomic Mouse", names: ["Sculpt Ergonomic"], blackPlain, .wheelAndBack),
        mouse("msSculptComfort", microsoft, "Sculpt Comfort Mouse", names: ["Sculpt Comfort"], blackPlain, .wheel),
        mouse("msIntelliMouse", microsoft, "Classic / Pro IntelliMouse", ids: [0x0823, 0x082A], names: ["IntelliMouse"],
              greyGaming, .wheelAndSides),
        mouse("msComfort4500", microsoft, "Comfort Mouse 4500", ids: [0x076C], names: ["Comfort Mouse"], blackPlain, .wheelAndSides),
        mouse("microsoftReceiver", microsoft, "Mouse on a Microsoft receiver", ids: [0x07A5, 0x07B2, 0x07FD, 0x0745, 0x071F],
              names: ["Transceiver"], .plain, .wheelAndSides, kind: .receiver, note: behindReceiver),

        // Razer
        mouse("razerDeathAdder", razer, "DeathAdder",
              ids: [0x0016, 0x0029, 0x0037, 0x0038, 0x0043, 0x004F, 0x0054, 0x005C, 0x006E, 0x0071, 0x0098, 0x0084, 0x008C,
                    0x007C, 0x007D, 0x009C, 0x00A1, 0x00B2, 0x00B6, 0x00B7, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00BE, 0x00BF],
              names: ["DeathAdder"], .gaming, .wheelAndSides),
        mouse("razerViper", razer, "Viper",
              ids: [0x0078, 0x007A, 0x007B, 0x008A, 0x0091, 0x009E, 0x009F, 0x00A5, 0x00A6, 0x00B8, 0x00C0, 0x00C1,
                    0x00DE, 0x00DF, 0x00E5, 0x00E6],
              names: ["Razer Viper"], .ambi, .wheelAndSides),
        mouse("razerBasilisk", razer, "Basilisk",
              ids: [0x0064, 0x0065, 0x0083, 0x0085, 0x0086, 0x0088, 0x0099, 0x00AA, 0x00AB, 0x00B9, 0x00CB, 0x00CC, 0x00CD,
                    0x00D6, 0x00D7, 0x00D3, 0x00D4],
              names: ["Basilisk"], .gaming, .wheelAndSides),
        mouse("razerNaga", razer, "Naga",
              ids: [0x0015, 0x001F, 0x002E, 0x0036, 0x003E, 0x003F, 0x0040, 0x0041, 0x0050, 0x0053, 0x0067, 0x008D, 0x008F,
                    0x0090, 0x0096, 0x00A7, 0x00A8, 0x00B4],
              names: ["Razer Naga"], .gaming, .wheel,
              note: "The thumb keys type numbers instead of pressing mouse buttons, so only the wheel click can be given an action."),
        mouse("razerProClick", razer, "Pro Click", ids: [0x0077, 0x0080, 0x009A, 0x00D0, 0x00D1], names: ["Pro Click"],
              MouseBody.sculpted.finished(.white), .wheelAndSides),
        mouse("razerProClickVertical", razer, "Pro Click V2 Vertical", ids: [0x00C7, 0x00C8], names: ["Pro Click V2 Vertical"],
              blackVertical, .wheelAndSides),
        mouse("razerOrochi", razer, "Orochi", ids: [0x0013, 0x0039, 0x0048, 0x0094, 0x0095, 0x00E0], names: ["Orochi"],
              .ambi, .wheelAndSides),
        mouse("razerCobra", razer, "Cobra", ids: [0x00A3, 0x00AF, 0x00B0, 0x00DA, 0x00DB], names: ["Razer Cobra"], .ambi, .wheelAndSides),

        // SteelSeries
        mouse("steelSeriesRival", steelSeries, "Rival",
              ids: [0x1824, 0x184C, 0x1870, 0x1830, 0x1872, 0x183C, 0x183E, 0x1724, 0x172E, 0x172B, 0x1726, 0x1720, 0x171E, 0x1736],
              names: ["SteelSeries Rival"], .gaming, .wheelAndSides),
        mouse("steelSeriesAerox", steelSeries, "Aerox",
              ids: [0x1836, 0x183A, 0x187A, 0x1838, 0x1878, 0x1850, 0x1854, 0x185E, 0x1862, 0x1852, 0x185A, 0x1876, 0x1858, 0x1874],
              names: ["Aerox"], .ambi, .wheelAndSides),
        mouse("steelSeriesPrime", steelSeries, "Prime",
              ids: [0x182E, 0x182A, 0x1856, 0x182C, 0x1842, 0x184A, 0x1840, 0x1848, 0x184D],
              names: ["SteelSeries Prime"], .gaming, .wheelAndSides),
        mouse("steelSeriesSensei", steelSeries, "Sensei", ids: [0x1832, 0x1834, 0x1722], names: ["Sensei"], .ambi, .wheelAndSides),

        // Corsair
        mouse("corsairM65", corsair, "M65", ids: [0x1B12, 0x1B2E, 0x1B5A], names: ["M65"], .gaming, .wheelAndSides),
        mouse("corsairHarpoon", corsair, "Harpoon", ids: [0x1B3C, 0x1B75, 0x1B5E, 0x1B65], names: ["Harpoon"], .gaming, .wheelAndSides),
        mouse("corsairKatar", corsair, "Katar", ids: [0x1B22, 0x1B93, 0x1BAC], names: ["Katar"], .ambi, .wheelAndSides),
        mouse("corsairDarkCore", corsair, "Dark Core / Ironclaw",
              ids: [0x1B35, 0x1B64, 0x1B4B, 0x1B51, 0x1B80, 0x1B81, 0x1B7E, 0x1B7F, 0x1B5D, 0x1B4C, 0x1B66, 0x1B5C],
              names: ["Dark Core", "Ironclaw", "Nightsword"], .gaming, .wheelAndSides),

        // Other gaming mice
        mouse("gloriousModelO", glorious, "Model O / Model D", ids: [0x0033, 0x0036, 0x1503, 0xA000],
              names: ["Glorious Model", "Model O", "Model D"], .ambi, .wheelAndSides),
        mouse("zowie", zowie, "Zowie gaming mouse", ids: [0x0001], names: ["ZOWIE"], .ambi, .wheelAndSides),
        mouse("keychronM", keychron, "M series", names: ["Keychron M"], .ambi, .wheelAndSides),

        // Trackballs and vertical mice
        mouse("kensingtonExpert", kensington, "Expert Mouse", ids: [0x1020, 0x1021, 0x8018], names: ["Expert Mouse", "Expert Wireless"],
              .fingerBall, .upperPair),
        mouse("kensingtonSlimBlade", kensington, "SlimBlade", ids: [0x2041], names: ["SlimBlade"],
              MouseBody.fingerBall.finished(.graphite), .upperPair),
        mouse("elecomEXG", elecom, "EX-G trackball", ids: [0x00FB, 0x018F, 0x00FC, 0x018C, 0x00FD, 0x018E], names: ["EX-G"],
              MouseBody.thumbBall.finished(.black, ball: Color(red: 0.78, green: 0.16, blue: 0.18)), .wheelAndSides),
        mouse("evoluentVertical", evoluent, "VerticalMouse", ids: [0x0068, 0x0168, 0x0191, 0x0195], names: ["VerticalMouse", "Evoluent"],
              blackVertical, .wheelAndSides),

        // Plain office mice
        mouse("satechiM1", satechi, "M1", names: ["Satechi"], silverCompact, .wheel),
        mouse("dellOptical", dell, "MS116 optical mouse", ids: [0x301A, 0x3012, 0x3010], names: ["MS116", "Dell USB Optical Mouse"],
              blackPlain, .wheel),
        mouse("hpOptical", hp, "USB optical mouse", ids: [0x134A, 0x094A, 0x0941, 0x0641, 0x1F4A], names: ["HP USB Optical Mouse"],
              blackPlain, .wheel),
        mouse("lenovoOptical", lenovo, "USB optical mouse", ids: [0x600E, 0x608D, 0x6019, 0x602E, 0x6093],
              names: ["Lenovo USB Optical Mouse", "Lenovo Optical Mouse"], blackPlain, .wheel),
    ]

    /// The brands in the order the window lists them.
    static let brands = ["Apple", "Logitech", "Microsoft", "Razer", "SteelSeries", "Corsair", "Glorious", "Zowie", "Keychron",
                         "Kensington", "Elecom", "Evoluent", "Satechi", "Dell", "HP", "Lenovo", "Other"]
}
