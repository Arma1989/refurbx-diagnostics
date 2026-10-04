import SwiftUI

private let navy = Color(red: 0.04, green: 0.06, blue: 0.16)
private let cyan = Color(red: 0.48, green: 0.84, blue: 1)
private let ink = Color.white.opacity(0.78)

struct GuideScreen: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: Double(model.index + 1), total: Double(max(Catalog.rows.count, 1)))
                .tint(cyan)
            Text("\(Catalog.group(model.currentId)) · \(model.index + 1) / \(Catalog.rows.count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(cyan)
            Text(Catalog.title(model.currentId))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(GuideCopy.line(model.currentId))
                .font(.body)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            DemoReel(testId: model.currentId)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button(action: { model.beginCurrent() }) {
                    Text("Inizia").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(cyan)
                .foregroundStyle(navy)
                Button("Salta", action: { model.skipCurrent() })
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(navy)
        }
    }
}

private enum GuideCopy {
    static func line(_ id: String) -> String {
        switch id {
        case "identity": return "Leggo modello, sistema e risoluzione. Non devi fare nulla."
        case "battery": return "Leggo la percentuale e se è in carica."
        case "memory": return "Mostro il totale, lo spazio libero e quello usato del telefono."
        case "network": return "Controllo che il Wi-Fi sia acceso. La password non viene letta."
        case "display": return "Lo schermo cambia colore. Tocca per andare avanti e cerca macchie o pixel spenti."
        case "touch": return "Trascina un dito su tutte le celle, anche sui bordi."
        case "multitouch": return "Appoggia due dita insieme, come nell'esempio."
        case "force": return "Questo schermo non misura la pressione. Il test resta non disponibile."
        case "stylus": return "L'iPhone non riceve la Apple Pencil. Il test resta non disponibile."
        case "speaker": return "Una nota sale dall'altoparlante in basso. Poi confermi a mano se è chiara."
        case "earpiece": return "Avvicina l'orecchio alla capsula in alto, segnata nell'esempio."
        case "microphone": return "Si provano i microfoni in basso, in alto e dietro. Poi confermi a mano."
        case "vibration": return "Il telefono vibra tre volte. Confermi solo se lo senti in mano."
        case "call": return "Tienilo come in chiamata. Il suono deve uscire solo dalla capsula in alto."
        case "headphones": return "Collega le cuffie se le hai. Se non le hai, salta."
        case "camera_back": return "Si apre la fotocamera dietro. Conferma solo se l'immagine è nitida."
        case "camera_front": return "Si apre la fotocamera davanti. Conferma solo se vedi il volto."
        case "autofocus": return "Avvicina un oggetto e poi allontanalo. Il fuoco deve muoversi."
        case "flash": return "Il flash si accende. Conferma solo se lo vedi acceso."
        case "truedepth": return "Guarda lo schermo. Il volto compare in punti bianchi su nero solo se viene seguito."
        case "lidar": return "La vista parte grigia. Avvicina la mano: solo il vicino diventa più scuro."
        case "proximity": return "Copri il sensore in alto, vicino alla capsula."
        case "light": return "iOS non consegna il sensore di luce. Il test resta non disponibile."
        case "accelerometer": return "Inclina il telefono verso i quattro bordi, come la pallina."
        case "gyroscope": return "Tienilo fermo, poi ruotalo di lato, avanti e intorno a te."
        case "compass": return "Tienilo in piano e giralo finché l'anello si riempie."
        case "gps": return "Cerco il satellite e mostro la precisione in metri. In negozio può non arrivare: in quel caso salta."
        case "bluetooth": return "Controllo che il Bluetooth si accenda. Se compare la richiesta, consenti."
        case "nfc": return "Si apre la lettura NFC. Avvicina un tag vero. Senza tag il test non risulta superato."
        case "volume_up": return "Premi il tasto volume più, sul fianco."
        case "volume_down": return "Premi il tasto volume meno, sul fianco."
        case "power_button": return "Premi il tasto di accensione, poi riapri lo schermo."
        case "mute_switch": return "Su questo iPhone il tasto Azione non dice all'app se l'hai premuto."
        case "charging": return "Collega il cavo. Il test passa quando il sistema vede la carica."
        case "wireless": return "Stacca il cavo e appoggia il telefono sul pad. Passa solo se, da staccato, torna in carica."
        case "biometrics": return "Usa il volto o l'impronta, se il telefono la chiede."
        default: return "Guarda l'esempio, poi inizia. Puoi sempre saltare."
        }
    }
}

private struct DemoReel: View {
    let testId: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let loop = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
            PhoneChrome {
                DemoScene(testId: testId, loop: loop)
            }
        }
    }
}

private struct PhoneChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.18))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .padding(8)
            content()
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 3)
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 54, height: 6)
                .offset(y: -132)
        }
        .frame(width: 168, height: 312)
        .shadow(color: cyan.opacity(0.18), radius: 24, y: 10)
    }
}

private struct DemoScene: View {
    let testId: String
    let loop: Double

    var body: some View {
        ZStack {
            switch testId {
            case "display":
                colorWash
            case "touch":
                touchGrid
            case "multitouch":
                twoFingers
            case "speaker", "vibration":
                bottomSound
            case "earpiece", "call", "proximity":
                topSensor
            case "microphone":
                micDots
            case "camera_back", "autofocus", "flash":
                rearCamera
            case "camera_front", "biometrics":
                frontFace
            case "truedepth":
                faceDots
            case "lidar":
                depthWash
            case "accelerometer", "gyroscope":
                tiltBall
            case "compass":
                compassDemo
            case "gps":
                pinPulse
            case "bluetooth", "nfc", "network":
                radioWaves
            case "volume_up", "volume_down", "power_button", "mute_switch":
                sideButton
            case "charging", "battery":
                cable
            case "wireless":
                wirelessPad
            case "headphones":
                earbuds
            case "memory", "identity":
                readout
            case "light", "force", "stylus":
                unavailable
            default:
                readout
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(8)
    }

    private var colorWash: some View {
        let colors: [Color] = [.white, .black, .red, .green, .blue, .yellow]
        let index = min(colors.count - 1, Int(loop * Double(colors.count)))
        return colors[index]
    }

    private var touchGrid: some View {
        let lit = Int(loop * 24)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(0..<24, id: \.self) { cell in
                RoundedRectangle(cornerRadius: 4)
                    .fill(cell <= lit ? Color(red: 0.12, green: 0.66, blue: 0.48) : Color.white.opacity(0.08))
            }
        }
        .padding(18)
    }

    private var twoFingers: some View {
        HStack(spacing: 18) {
            finger
            finger
        }
        .scaleEffect(0.86 + loop * 0.14)
    }

    private var finger: some View {
        Circle()
            .fill(cyan)
            .frame(width: 36, height: 36)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    private var bottomSound: some View {
        VStack {
            Spacer()
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Capsule()
                        .stroke(cyan.opacity(0.85 - Double(ring) * 0.22), lineWidth: 3)
                        .frame(width: 28 + CGFloat(loop) * 46 + CGFloat(ring) * 18, height: 12)
                }
            }
            .padding(.bottom, 28)
        }
    }

    private var topSensor: some View {
        VStack {
            ZStack {
                Capsule().fill(cyan).frame(width: 42, height: 8)
                if testId == "proximity" {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 54, height: 54)
                        .offset(y: 8 + CGFloat(loop) * 10)
                } else {
                    ForEach(0..<3, id: \.self) { ring in
                        Capsule()
                            .stroke(cyan.opacity(0.8 - Double(ring) * 0.2), lineWidth: 3)
                            .frame(width: 24 + CGFloat(loop) * 40 + CGFloat(ring) * 16, height: 10)
                    }
                }
            }
            .padding(.top, 22)
            Spacer()
        }
    }

    private var micDots: some View {
        let spot = Int(loop * 3) % 3
        return ZStack {
            Circle().fill(spot == 1 ? cyan : Color.white.opacity(0.25)).frame(width: 14, height: 14).offset(y: -108)
            Circle().fill(spot == 2 ? cyan : Color.white.opacity(0.25)).frame(width: 14, height: 14).offset(x: 48, y: -78)
            Capsule().fill(spot == 0 ? cyan : Color.white.opacity(0.25)).frame(width: 36, height: 8).offset(y: 118)
            Text(spot == 0 ? "Basso" : spot == 1 ? "Alto" : "Dietro")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private var rearCamera: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 74, height: 74)
                .offset(x: 28, y: -78)
            Circle()
                .fill(testId == "flash" && loop > 0.45 ? Color.white : cyan)
                .frame(width: 22, height: 22)
                .offset(x: 28, y: -92)
                .shadow(color: testId == "flash" && loop > 0.45 ? .white : cyan, radius: 12)
            if testId == "autofocus" {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 54 + CGFloat(loop) * 28, height: 54 + CGFloat(loop) * 28)
            }
        }
    }

    private var frontFace: some View {
        Circle()
            .stroke(cyan, lineWidth: 3)
            .frame(width: 72, height: 92)
            .offset(y: -10)
            .scaleEffect(0.92 + loop * 0.08)
    }

    private var faceDots: some View {
        ZStack {
            Color.black
            ForEach(0..<18, id: \.self) { index in
                let angle = Double(index) / 18 * .pi * 2
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
                    .offset(x: CGFloat(cos(angle) * (28 + loop * 6)), y: CGFloat(sin(angle) * (36 + loop * 4)) - 8)
            }
        }
    }

    private var depthWash: some View {
        ZStack {
            Color(white: 0.72)
            Circle()
                .fill(Color(white: 0.22))
                .frame(width: 40 + CGFloat((1 - loop) * 70), height: 40 + CGFloat((1 - loop) * 90))
                .blur(radius: 8)
        }
    }

    private var tiltBall: some View {
        let angle = loop * .pi * 2
        return Circle()
            .fill(cyan)
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .offset(x: CGFloat(cos(angle) * 42), y: CGFloat(sin(angle) * 70))
    }

    private var compassDemo: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { mark in
                Capsule()
                    .fill(Double(mark) / 8 < loop ? cyan : Color.white.opacity(0.2))
                    .frame(width: 6, height: 14)
                    .offset(y: -78)
                    .rotationEffect(.degrees(Double(mark) * 45))
            }
            Text("↑")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(loop * 360))
        }
    }

    private var pinPulse: some View {
        ZStack {
            Circle().stroke(cyan.opacity(1 - loop), lineWidth: 3).frame(width: 40 + CGFloat(loop) * 70, height: 40 + CGFloat(loop) * 70)
            Circle().fill(cyan).frame(width: 16, height: 16)
        }
    }

    private var radioWaves: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(cyan.opacity(0.75 - Double(ring) * 0.2), lineWidth: 3)
                    .frame(width: 36 + CGFloat(loop) * 30 + CGFloat(ring) * 28, height: 36 + CGFloat(loop) * 30 + CGFloat(ring) * 28)
            }
        }
    }

    private var sideButton: some View {
        let up = testId == "volume_up" || testId == "mute_switch"
        return HStack {
            Spacer()
            Capsule()
                .fill(cyan)
                .frame(width: 8, height: up ? 28 : 36)
                .offset(x: 6, y: up ? -40 : 20)
                .opacity(0.45 + loop * 0.55)
        }
    }

    private var cable: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(cyan)
                .frame(width: 22, height: 16 + CGFloat(loop) * 28)
        }
    }

    private var wirelessPad: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 10)
                .fill(cyan.opacity(0.25 + loop * 0.45))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(cyan, lineWidth: 3))
                .frame(width: 96, height: 16)
                .padding(.bottom, 16)
        }
    }

    private var earbuds: some View {
        HStack(spacing: 28) {
            Capsule().fill(cyan).frame(width: 22, height: 34)
            Capsule().fill(cyan).frame(width: 22, height: 34)
        }
        .offset(y: CGFloat((0.5 - loop) * 16))
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RefurbX")
                .font(.caption.weight(.semibold))
                .foregroundStyle(cyan)
            Text(testId == "memory" ? "256 GB" : "iPhone")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(testId == "memory" ? "libero \(Int(20 + loop * 8)) GB" : "in lettura")
                .font(.footnote)
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "minus.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.45))
            Text("Non disponibile")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ink)
        }
    }
}
