import Foundation

struct Outcome: Identifiable {
    let id: String
    var status: String
    var note: String
}

struct Mark {
    var letter: String
    var label: String
    var score: Int
}

enum Catalog {
    struct Row {
        let id: String
        let group: String
        let title: String
        let weight: Int
        let critical: Bool
    }

    static let rows: [Row] = [
        Row(id: "identity", group: "Sistema", title: "Identità", weight: 1, critical: false),
        Row(id: "memory", group: "Sistema", title: "Memoria", weight: 1, critical: false),
        Row(id: "network", group: "Sistema", title: "Wi-Fi", weight: 1, critical: false),
        Row(id: "display", group: "Schermo", title: "Display", weight: 3, critical: true),
        Row(id: "touch", group: "Schermo", title: "Touchscreen", weight: 3, critical: true),
        Row(id: "multitouch", group: "Schermo", title: "Multi-touch", weight: 2, critical: false),
        Row(id: "force", group: "Schermo", title: "3D Touch", weight: 1, critical: false),
        Row(id: "stylus", group: "Schermo", title: "Penna", weight: 1, critical: false),
        Row(id: "speaker", group: "Audio", title: "Altoparlante", weight: 3, critical: true),
        Row(id: "earpiece", group: "Audio", title: "Capsula auricolare", weight: 2, critical: false),
        Row(id: "microphone", group: "Audio", title: "Microfono", weight: 3, critical: true),
        Row(id: "vibration", group: "Audio", title: "Vibrazione", weight: 2, critical: false),
        Row(id: "call", group: "Audio", title: "Chiamata", weight: 1, critical: false),
        Row(id: "headphones", group: "Audio", title: "Cuffie", weight: 1, critical: false),
        Row(id: "camera_back", group: "Foto", title: "Camera posteriore", weight: 3, critical: true),
        Row(id: "camera_front", group: "Foto", title: "Camera anteriore", weight: 2, critical: false),
        Row(id: "autofocus", group: "Foto", title: "Autofocus", weight: 1, critical: false),
        Row(id: "flash", group: "Foto", title: "Flash", weight: 1, critical: false),
        Row(id: "truedepth", group: "Foto", title: "TrueDepth", weight: 1, critical: false),
        Row(id: "lidar", group: "Sensori", title: "Scanner LiDAR", weight: 1, critical: false),
        Row(id: "proximity", group: "Sensori", title: "Prossimità", weight: 1, critical: false),
        Row(id: "light", group: "Sensori", title: "Sensore di luce", weight: 1, critical: false),
        Row(id: "accelerometer", group: "Sensori", title: "Accelerometro", weight: 2, critical: false),
        Row(id: "gyroscope", group: "Sensori", title: "Giroscopio", weight: 1, critical: false),
        Row(id: "compass", group: "Sensori", title: "Bussola", weight: 1, critical: false),
        Row(id: "gps", group: "Sensori", title: "GPS", weight: 1, critical: false),
        Row(id: "bluetooth", group: "Connettività", title: "Bluetooth", weight: 1, critical: false),
        Row(id: "nfc", group: "Connettività", title: "NFC", weight: 1, critical: false),
        Row(id: "cellular", group: "Connettività", title: "Rete", weight: 1, critical: false),
        Row(id: "volume_up", group: "Tasti", title: "Volume +", weight: 2, critical: false),
        Row(id: "volume_down", group: "Tasti", title: "Volume −", weight: 2, critical: false),
        Row(id: "power_button", group: "Tasti", title: "Accensione", weight: 2, critical: false),
        Row(id: "mute_switch", group: "Tasti", title: "Silenzioso", weight: 1, critical: false),
        Row(id: "charging", group: "Energia", title: "Ricarica cavo", weight: 3, critical: true),
        Row(id: "wireless", group: "Energia", title: "Ricarica wireless", weight: 2, critical: false),
        Row(id: "biometrics", group: "Sicurezza", title: "Biometria", weight: 1, critical: false),
    ]

    static var groups: [String] {
        var names: [String] = []
        for row in rows where !names.contains(row.group) {
            names.append(row.group)
        }
        return names
    }

    static func count(_ group: String) -> Int {
        rows.filter { $0.group == group }.count
    }

    static func homeTitle(_ group: String) -> String {
        group == "Foto" ? "Fotocamere" : group
    }

    static func homeLine(_ group: String) -> String {
        switch group {
        case "Sistema": return "Modello, memoria e Wi-Fi"
        case "Schermo": return "Colori e touch"
        case "Audio": return "Speaker, microfoni, vibrazione"
        case "Foto": return "Obiettivi e profondità"
        case "Sensori": return "Movimento, bussola, GPS"
        case "Connettività": return "Bluetooth, NFC e rete"
        case "Tasti": return "Volume, accensione, silenzioso"
        case "Energia": return "Cavo e wireless"
        case "Sicurezza": return "Face ID o Touch ID"
        default: return "\(count(group)) prove"
        }
    }

    static func testSymbol(_ id: String) -> String {
        switch id {
        case "identity": return HardwareFit.pad ? "ipad" : "iphone"
        case "memory": return "memorychip"
        case "network": return "wifi"
        case "display": return "rectangle.inset.filled"
        case "touch": return "hand.tap.fill"
        case "multitouch": return "hand.raised.fingers.spread.fill"
        case "force": return "hand.point.up.left.fill"
        case "stylus": return "pencil.tip"
        case "speaker": return "speaker.wave.2.fill"
        case "earpiece": return "ear"
        case "microphone": return "mic.fill"
        case "vibration": return "iphone.radiowaves.left.and.right"
        case "call": return "phone.fill"
        case "headphones": return "headphones"
        case "camera_back": return "camera.fill"
        case "camera_front": return "person.crop.rectangle.fill"
        case "autofocus": return "viewfinder"
        case "flash": return "bolt.fill"
        case "truedepth": return "faceid"
        case "lidar": return "cube.transparent"
        case "proximity": return "dot.radiowaves.up.forward"
        case "light": return "sun.max.fill"
        case "accelerometer": return "move.3d"
        case "gyroscope": return "gyroscope"
        case "compass": return "location.north.line"
        case "gps": return "location.fill"
        case "bluetooth": return "antenna.radiowaves.left.and.right"
        case "nfc": return "wave.3.right"
        case "cellular": return "cellularbars"
        case "volume_up": return "speaker.plus.fill"
        case "volume_down": return "speaker.minus.fill"
        case "power_button": return "power"
        case "mute_switch": return "bell.slash.fill"
        case "charging": return "cable.connector"
        case "wireless": return "battery.100.bolt"
        case "biometrics": return "lock.fill"
        default: return "circle"
        }
    }

    static func symbol(_ group: String) -> String {
        switch group {
        case "Sistema": return "cpu"
        case "Schermo": return "rectangle.inset.filled"
        case "Audio": return "speaker.wave.2.fill"
        case "Foto": return "camera.fill"
        case "Sensori": return "gyroscope"
        case "Connettività": return "antenna.radiowaves.left.and.right"
        case "Tasti": return "button.horizontal.top.press.fill"
        case "Energia": return "bolt.fill"
        case "Sicurezza": return "faceid"
        default: return "circle"
        }
    }

    static func title(_ id: String) -> String {
        rows.first { $0.id == id }?.title ?? id
    }

    static func group(_ id: String) -> String {
        rows.first { $0.id == id }?.group ?? ""
    }
}

enum Cosmetic {
    struct Choice {
        let id: String
        let title: String
        let line: String
    }

    static let choices: [Choice] = [
        Choice(id: "A+", title: "Come nuovo", line: "Segni assenti. Sembra appena uscito dalla scatola."),
        Choice(id: "A", title: "Eccellente", line: "Micro-segni, visibili solo da molto vicino."),
        Choice(id: "B", title: "Buono", line: "Segni di uso visibili su scocca o vetro."),
        Choice(id: "C", title: "Segnato", line: "Tanti segni su vetro e scocca. Il vetro è intero: il telefono non è rotto."),
    ]

    static func find(_ id: String) -> Choice? {
        choices.first { $0.id == id }
    }
}

func gradeOf(_ items: [Outcome]) -> Mark {
    var earned = 0
    var total = 0
    var criticalFails = 0
    var criticalSkips = 0
    for row in Catalog.rows {
        guard let item = items.first(where: { $0.id == row.id }) else { continue }
        if item.status == "skip" && row.critical { criticalSkips += 1 }
        if item.status == "pending" || item.status == "skip" || item.status == "absent" { continue }
        total += row.weight
        if item.status == "pass" { earned += row.weight }
        if item.status == "fail" && row.critical { criticalFails += 1 }
    }
    let score = total == 0 ? 0 : Int((Double(earned) * 100.0 / Double(total)).rounded())
    let order = ["A", "B", "C", "D"]
    func cap(_ letter: String, _ limit: String) -> String {
        let left = order.firstIndex(of: letter) ?? 0
        let right = order.firstIndex(of: limit) ?? 0
        return order[max(left, right)]
    }
    var letter = score >= 90 ? "A" : score >= 75 ? "B" : score >= 50 ? "C" : "D"
    if criticalFails >= 2 { letter = "D" }
    else if criticalFails == 1 { letter = cap(letter, "C") }
    else if criticalSkips >= 2 { letter = cap(letter, "C") }
    else if criticalSkips == 1 { letter = cap(letter, "B") }
    let label = letter == "A" ? "Eccellente" : letter == "B" ? "Buono" : letter == "C" ? "Da sistemare" : "Non conforme"
    return Mark(letter: letter, label: label, score: score)
}

func statusIt(_ status: String) -> String {
    switch status {
    case "pass": return "Conforme"
    case "fail": return "Non conforme"
    case "skip": return "Non eseguito"
    case "absent": return "Non disponibile"
    default: return status
    }
}
