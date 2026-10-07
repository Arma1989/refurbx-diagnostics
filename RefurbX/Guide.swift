import SwiftUI

private let cyan = Look.cyan
private let ink = Look.ink

struct GuideScreen: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(
                index: model.index,
                total: model.planCount,
                group: Catalog.group(model.currentId),
                title: Catalog.title(model.currentId),
                message: GuideCopy.line(model.currentId)
            )
            Spacer(minLength: 8)
            DemoReel(testId: model.currentId)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar {
                if model.currentId == "nfc" {
                    NfcTap(title: "Apri lettore tag", probe: model.tagProbe)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    BenchButton(title: "Inizia") { model.beginCurrent() }
                }
                BenchButton(title: "Salta", kind: .secondary) { model.skipCurrent() }
            }
        }
    }
}

private enum GuideCopy {
    static func line(_ id: String) -> String {
        switch id {
        case "identity": return "Mostro il nome commerciale e il codice di fabbrica, per esempio iPhone 17 Pro Max e iPhone18,2."
        case "memory": return "Mostro il totale, lo spazio libero e quello usato del telefono."
        case "network": return "Controllo se il Wi-Fi è collegato. Se non lo è, collega il Wi-Fi e riprova."
        case "display": return "Lo schermo cambia colore. Tocca per andare avanti e cerca macchie o pixel spenti."
        case "touch": return "Trascina un dito su tutte le celle, anche sui bordi."
        case "multitouch": return "Appoggia due dita insieme, come nell'esempio."
        case "force": return "Premi piano e poi forte nel riquadro. Questo schermo misura la pressione."
        case "stylus": return "Scrivi con la Apple Pencil. Il dito non fa passare il test."
        case "speaker": return "Una nota sale dall'altoparlante in basso. Poi confermi a mano se è chiara."
        case "earpiece": return "Avvicina l'orecchio alla capsula in alto, segnata nell'esempio."
        case "microphone": return "Basso, fronte e posteriore: ognuno registra due secondi e mezzo. Poi riascolti e confermi a mano."
        case "vibration": return "Il telefono vibra tre volte. Confermi solo se lo senti in mano."
        case "call": return "Tienilo come in chiamata. Il suono deve uscire solo dalla capsula in alto."
        case "headphones": return "Collega le cuffie se le hai. Se non le hai, salta."
        case "camera_back": return "Si apre la fotocamera dietro. Conferma solo se l'immagine è nitida."
        case "camera_front": return "Si apre la fotocamera davanti. Il volto deve essere dritto, in verticale."
        case "autofocus": return "Inquadra un codice QR con la camera dietro. Appena lo vede, compare il riquadro e si passa avanti."
        case "flash": return "Il flash si accende. Conferma solo se lo vedi acceso."
        case "truedepth": return "In alto a destra vedi la fotocamera, come in una videochiamata. Al centro i puntini bianchi sono il volto TrueDepth: girano con la testa."
        case "lidar": return "La vista a infrarossi resta aperta. Avvicina la mano: solo il vicino diventa più scuro."
        case "proximity": return "Copri il sensore in alto, vicino alla capsula."
        case "light": return "Metti una luce sul sensore davanti, in alto. La barra sale. Toglila e scende subito."
        case "accelerometer": return "Inclina il telefono verso i quattro bordi, come la pallina."
        case "gyroscope": return "Tienilo fermo, poi inclinalo di lato, avanti e giralo. I tre assi devono muoversi."
        case "compass": return "Tienilo in piano e fai un giro completo. Si accendono 8 punti. Finché manca un punto, il test non va avanti."
        case "gps": return "Consente la posizione precisa. Si apre una mappa con il punto reale: confermi tu quando è quello giusto."
        case "bluetooth": return "Resta sulla schermata. Si vede se il Bluetooth è acceso. Se è spento, accendilo e riprova."
        case "nfc": return "Premi Apri lettore tag. Si apre la finestra di Apple: tieni la scheda ferma sul retro, in alto."
        case "volume_up": return "Premi volume più. Compare una spunta appena il tasto risponde."
        case "volume_down": return "Premi volume meno. Compare una spunta appena il tasto risponde."
        case "power_button": return "Premi il tasto di accensione, poi riapri lo schermo."
        case "mute_switch":
            if HardwareFit.usesActionButton {
                return "Premi il tasto Azione. In grande compare Suono o Silenzioso. L'app non emette suoni. La spunta arriva solo quando diventa silenzioso."
            }
            return "Sposta l'interruttore. In grande compare Suono o Silenzioso. L'app non emette suoni. La spunta arriva solo quando diventa silenzioso."
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
            PhoneChrome(testId: testId, loop: loop) {
                DemoScene(testId: testId, loop: loop)
            }
        }
    }
}

private struct PhoneChrome<Content: View>: View {
    var testId: String = ""
    var loop: Double = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.20, blue: 0.30), Color(red: 0.05, green: 0.07, blue: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .padding(8)
            content()
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.7), cyan.opacity(0.35), Color.white.opacity(0.18)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 2
                )
        }
        .aspectRatio(188.0 / 360.0, contentMode: .fit)
        .frame(maxWidth: 200, maxHeight: 360)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.black.opacity(0.92))
                .frame(width: 78, height: 24)
                .overlay(Circle().fill(Color.white.opacity(0.18)).frame(width: 8, height: 8).offset(x: 22))
                .padding(.top, 16)
        }
        .overlay {
            if testId == "mute_switch" {
                MuteSide(loop: loop)
            }
        }
        .shadow(color: cyan.opacity(0.28), radius: 32, y: 16)
    }
}

private struct MuteSide: View {
    let loop: Double

    var body: some View {
        Group {
            if HardwareFit.usesActionButton {
                actionColumn
            } else {
                ringerColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: -6, y: 62)
        .allowsHitTesting(false)
    }

    private var actionColumn: some View {
        let hot = loop > 0.08 && loop < 0.34
        return VStack(spacing: 16) {
            Capsule()
                .fill(hot ? cyan : Color(white: 0.94))
                .frame(width: hot ? 18 : 14, height: 44)
                .shadow(color: cyan.opacity(hot ? 1 : 0.35), radius: hot ? 14 : 3)
                .overlay(Capsule().stroke(Color.white.opacity(hot ? 1 : 0.55), lineWidth: 1.5))
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 8, height: 28)
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 8, height: 28)
        }
    }

    private var ringerColumn: some View {
        let down = loop > 0.42
        return ZStack {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 14, height: 48)
            Capsule()
                .fill(down ? cyan : Color.white.opacity(0.95))
                .frame(width: 18, height: 22)
                .shadow(color: cyan.opacity(down ? 0.9 : 0), radius: 8)
                .offset(y: down ? 11 : -11)
        }
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
            case "camera_back", "flash":
                rearCamera
            case "autofocus":
                qrTarget
            case "camera_front", "biometrics":
                frontFace
            case "light":
                lightMeter
            case "truedepth":
                faceDots
            case "lidar":
                depthWash
            case "accelerometer":
                tiltBall
            case "gyroscope":
                gyroDemo
            case "compass":
                compassDemo
            case "gps":
                pinPulse
            case "bluetooth", "nfc", "network":
                radioWaves
            case "volume_up", "volume_down", "power_button":
                sideButton
            case "mute_switch":
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            case "charging":
                cable
            case "wireless":
                wirelessPad
            case "headphones":
                earbuds
            case "memory", "identity":
                readout
            case "force":
                forceDemo
            case "stylus":
                pencilDemo
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
            Text(spot == 0 ? "Basso" : spot == 1 ? "Fronte" : "Retro")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private var qrTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(cyan, lineWidth: 3)
                .frame(width: 78, height: 78)
                .scaleEffect(0.92 + loop * 0.08)
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    qrCell
                    qrCell
                    qrCell
                }
                HStack(spacing: 4) {
                    qrCell
                    Color.clear.frame(width: 10, height: 10)
                    qrCell
                }
                HStack(spacing: 4) {
                    qrCell
                    qrCell
                    qrCell
                }
            }
        }
    }

    private var qrCell: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.white)
            .frame(width: 10, height: 10)
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
        ZStack(alignment: .topTrailing) {
            Color.black
            ForEach(0..<18, id: \.self) { index in
                let angle = Double(index) / 18 * .pi * 2
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
                    .offset(x: CGFloat(cos(angle) * (28 + loop * 6)), y: CGFloat(sin(angle) * (36 + loop * 4)) - 8)
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.22))
                .frame(width: 46, height: 62)
                .overlay(Circle().fill(cyan.opacity(0.8)).frame(width: 16, height: 16))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 1.5))
                .padding(8)
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
        let phase = loop * 4
        let step = Int(phase) % 4
        let along = phase - Double(Int(phase))
        let eased = along * along * (3 - 2 * along)
        let spots: [(CGFloat, CGFloat)] = [(62, 0), (0, 118), (-62, 0), (0, -118)]
        let here = spots[step]
        let next = spots[(step + 1) % 4]
        let x = here.0 + (next.0 - here.0) * eased
        let y = here.1 + (next.1 - here.1) * eased
        let reached = along > 0.62
        return ZStack {
            Capsule()
                .fill(step == 3 && reached ? Look.pass : Color.white.opacity(0.2))
                .frame(width: 86, height: 8)
                .offset(y: -132)
            Capsule()
                .fill(step == 1 && reached ? Look.pass : Color.white.opacity(0.2))
                .frame(width: 86, height: 8)
                .offset(y: 132)
            Capsule()
                .fill(step == 2 && reached ? Look.pass : Color.white.opacity(0.2))
                .frame(width: 8, height: 150)
                .offset(x: -72)
            Capsule()
                .fill(step == 0 && reached ? Look.pass : Color.white.opacity(0.2))
                .frame(width: 8, height: 150)
                .offset(x: 72)
            Circle()
                .fill(cyan)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .offset(x: x, y: y)
        }
        .frame(width: 168, height: 300)
    }

    private var gyroDemo: some View {
        let roll = sin(loop * .pi * 2) * 20
        let pitch = cos(loop * .pi * 2) * 14
        let side: CGFloat = 150
        let shift = CGFloat(pitch / 35) * side * 0.28
        return ZStack {
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 2).frame(width: side, height: side)
            ZStack {
                VStack(spacing: 0) {
                    Color(red: 0.16, green: 0.40, blue: 0.72)
                    Color(red: 0.34, green: 0.24, blue: 0.14)
                }
                .frame(width: side * 1.7, height: side * 1.7)
                .offset(y: shift)
                Capsule().fill(Color.white.opacity(0.9)).frame(width: side * 0.46, height: 2)
                Capsule().fill(Color.white.opacity(0.45)).frame(width: side * 0.22, height: 2).offset(y: -side * 0.12)
                Capsule().fill(Color.white.opacity(0.45)).frame(width: side * 0.22, height: 2).offset(y: side * 0.12)
            }
            .rotationEffect(.degrees(-roll))
            .frame(width: side, height: side)
            .clipShape(Circle())
            HStack(spacing: side * 0.07) {
                Capsule().fill(cyan).frame(width: side * 0.2, height: 3)
                Circle().stroke(cyan, lineWidth: 2).frame(width: 10, height: 10)
                Capsule().fill(cyan).frame(width: side * 0.2, height: 3)
            }
        }
        .frame(width: side, height: side)
    }

    private var compassDemo: some View {
        let turn = -loop * 360
        return ZStack {
            Circle().stroke(Color.white.opacity(0.28), lineWidth: 2).frame(width: 150, height: 150)
            ZStack {
                ForEach(0..<12, id: \.self) { tick in
                    let major = tick % 3 == 0
                    Capsule()
                        .fill(Color.white.opacity(major ? 0.9 : 0.35))
                        .frame(width: major ? 2 : 1, height: major ? 12 : 7)
                        .offset(y: -68)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                Text("N")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.86, green: 0.28, blue: 0.30))
                    .offset(y: -52)
            }
            .rotationEffect(.degrees(turn))
            Capsule().fill(cyan).frame(width: 4, height: 12).offset(y: -78)
            Text(String(format: "%03.0f°", loop * 359))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
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
        let up = testId == "volume_up"
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

    private var lightMeter: some View {
        let level = lightDrop(loop)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 32, height: 6)
                Capsule()
                    .fill(cyan)
                    .frame(width: 14 + CGFloat(level) * 92, height: 12)
                    .shadow(color: cyan.opacity(0.55), radius: 6)
            }
            .padding(.top, 36)
            Text("\(Int((level * 100).rounded()))%")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(cyan)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func lightDrop(_ loop: Double) -> Double {
        if loop < 0.34 { return 0.12 + (loop / 0.34) * 0.84 }
        if loop < 0.5 { return 0.96 }
        return max(0.08, 0.96 - (loop - 0.5) / 0.4 * 0.88)
    }

    private var forceDemo: some View {
        Circle()
            .stroke(cyan, lineWidth: 3)
            .frame(width: 70 + CGFloat(loop) * 46, height: 70 + CGFloat(loop) * 46)
    }

    private var pencilDemo: some View {
        Path { path in
            path.move(to: CGPoint(x: 36, y: 118))
            path.addLine(to: CGPoint(x: 36 + 130 * loop, y: 118 - 74 * loop))
        }
        .stroke(cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .frame(width: 180, height: 160)
    }
}
