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
        let title: String
        let weight: Int
        let critical: Bool
    }

    static let rows: [Row] = [
        Row(id: "identity", title: "Identità", weight: 1, critical: false),
        Row(id: "battery", title: "Batteria", weight: 2, critical: false),
        Row(id: "network", title: "Rete", weight: 1, critical: false),
        Row(id: "display", title: "Display", weight: 3, critical: true),
        Row(id: "touch", title: "Touchscreen", weight: 3, critical: true),
        Row(id: "multitouch", title: "Multi-touch", weight: 2, critical: false),
        Row(id: "speaker", title: "Altoparlante", weight: 3, critical: true),
        Row(id: "microphone", title: "Microfono", weight: 3, critical: true),
        Row(id: "vibration", title: "Vibrazione", weight: 2, critical: false),
        Row(id: "earpiece", title: "Capsula auricolare", weight: 2, critical: false),
        Row(id: "camera_back", title: "Camera posteriore", weight: 3, critical: true),
        Row(id: "camera_front", title: "Camera anteriore", weight: 2, critical: false),
        Row(id: "accelerometer", title: "Accelerometro", weight: 2, critical: false),
        Row(id: "gyroscope", title: "Giroscopio", weight: 1, critical: false),
        Row(id: "gps", title: "GPS", weight: 1, critical: false),
        Row(id: "volume_up", title: "Volume +", weight: 2, critical: false),
        Row(id: "volume_down", title: "Volume −", weight: 2, critical: false),
        Row(id: "power_button", title: "Accensione", weight: 2, critical: false),
        Row(id: "mute_switch", title: "Silenzioso", weight: 1, critical: false),
        Row(id: "charging", title: "Ricarica cavo", weight: 3, critical: true),
        Row(id: "biometrics", title: "Biometria", weight: 1, critical: false),
        Row(id: "bluetooth", title: "Bluetooth", weight: 1, critical: false),
        Row(id: "nfc", title: "NFC", weight: 1, critical: false),
        Row(id: "flash", title: "Flash", weight: 1, critical: false),
        Row(id: "autofocus", title: "Autofocus", weight: 1, critical: false),
        Row(id: "truedepth", title: "TrueDepth", weight: 1, critical: false),
        Row(id: "lidar", title: "Scanner LiDAR", weight: 1, critical: false),
        Row(id: "memory", title: "Memoria", weight: 1, critical: false),
        Row(id: "proximity", title: "Prossimità", weight: 1, critical: false),
        Row(id: "light", title: "Sensore di luce", weight: 1, critical: false),
        Row(id: "compass", title: "Bussola", weight: 1, critical: false),
        Row(id: "headphones", title: "Cuffie", weight: 1, critical: false),
        Row(id: "call", title: "Chiamata", weight: 1, critical: false),
        Row(id: "force", title: "3D Touch", weight: 1, critical: false),
        Row(id: "stylus", title: "Penna", weight: 1, critical: false),
    ]

    static func title(_ id: String) -> String {
        rows.first { $0.id == id }?.title ?? id
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
