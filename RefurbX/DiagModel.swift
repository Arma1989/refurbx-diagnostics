import ARKit
import AudioToolbox
import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

struct Act: Identifiable {
    var id: String { label }
    let label: String
    let status: String
    let note: String
}

@MainActor
final class DiagModel: ObservableObject {
    @Published var phase = "intro"
    @Published var currentId = ""
    @Published var hint = ""
    @Published var detail = ""
    @Published var index = -1
    @Published var showCamera = false
    @Published var actions: [Act] = []
    @Published var outcomes: [Outcome] = []
    @Published var fingers = 0
    @Published var dotX: CGFloat = 0
    @Published var dotY: CGFloat = 0
    @Published var edgeLeft = false
    @Published var edgeRight = false
    @Published var edgeTop = false
    @Published var edgeBottom = false
    @Published var gyroRest = false
    @Published var gyroTilt = false
    @Published var gyroPitch = false
    @Published var gyroYaw = false
    @Published var compassMarks: Set<Int> = []
    @Published var heading: Double = 0
    @Published var proximityLit = false
    @Published var depthShot: UIImage?
    @Published var lenses: [AVCaptureDevice.DeviceType] = []
    @Published var lens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    @Published var lensName = ""
    @Published var lookGrade = ""
    @Published var testedAt: Date?
    @Published var sheetFile: URL?
    @Published var withCable = false
    @Published var withBox = false
    @Published var forceUnit: CGFloat = 0
    @Published var canResume = false
    @Published var facePoints: [CGPoint] = []
    @Published var micSpot = ""
    @Published var micLevel = 0
    @Published var audioSpot = ""
    @Published var memoryTotal = ""
    @Published var memoryFree = ""
    @Published var memoryUsed = ""
    @Published var gpsAccuracy = ""
    @Published var gpsLatitude: Double?
    @Published var gpsLongitude: Double?
    @Published var plan: [String] = []
    @Published var benchLink = UserDefaults.standard.string(forKey: "refurbx.bench-link") ?? ""
    @Published var benchState = ""
    @Published var benchSending = false
    @Published var keyOk = false
    @Published var lightLevel: Double = 0

    var planCount: Int { max(plan.count, 1) }
    var activeRows: [Catalog.Row] {
        let ids = plan.isEmpty ? Catalog.rows.map(\.id) : plan
        return ids.compactMap { id in Catalog.rows.first { $0.id == id } }
    }

    let camera = CameraSession()

    init() {
        canResume = Self.loadRun() != nil
    }
    private let tone = TonePlayer()
    private let mic = MicProbe()
    private let motion = MotionProbe()
    private let place = PlaceProbe()
    private let radio = RadioProbe()
    private let depth = DepthProbe()
    private let faceTrack = FaceTrackProbe()
    private let face = FaceProbe()
    private let tags = TagProbe()
    private var bestGps: CLLocation?
    private var settled = false
    private var wave = 0
    private var sawLock = false
    private var sawBackground = false
    private var armPower = false
    private var volumePrevious: Float = -1
    private var volumeTimer: Timer?
    private var volumeObservation: NSKeyValueObservation?
    private var lightWarm = 0
    private var lightFloor = 0.0
    private var lightCeil = 0.0
    private var playback: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private var micQueue: [AVAudioSessionDataSourceDescription] = []
    private var micCursor = 0
    private var micLines: [String] = []
    private var micBad = false
    private var micLabel = "Microfono"
    private var micToken = 0
    private var faceArmed = false
    private var depthFrames = 0
    private var depthArmed = false
    private var depthLive = false
    private var sawUnplugged = false
    private var forceSoft = false
    private var forceHard = false
    private var openedLenses: [String] = []
    private var nfcAttempt = 0

    func begin(group: String?) {
        let chosen = HardwareFit.rows(in: group)
        guard !chosen.isEmpty else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        plan = chosen.map(\.id)
        outcomes = []
        lookGrade = ""
        testedAt = nil
        sheetFile = nil
        withCable = false
        withBox = false
        index = 0
        Self.clearRun()
        canResume = false
        enter()
    }

    func resume() {
        guard let saved = Self.loadRun() else {
            begin(group: nil)
            return
        }
        let raw = saved.plan.isEmpty ? Catalog.rows.map(\.id) : saved.plan
        plan = raw.filter { id in
            HardwareFit.supports(id) && Catalog.rows.contains { row in row.id == id }
        }
        guard !plan.isEmpty else {
            begin(group: nil)
            return
        }
        outcomes = saved.items.map { Outcome(id: $0.id, status: $0.status, note: $0.note) }
        lookGrade = saved.look
        testedAt = saved.tested
        withCable = saved.cable
        withBox = saved.box
        index = min(max(0, saved.index), max(0, plan.count - 1))
        if saved.phase == "report" {
            cleanup()
            phase = "report"
            currentId = "report"
            prepareSheet()
            return
        }
        enter()
    }

    func restart() {
        cleanup()
        Self.clearRun()
        canResume = false
        phase = "intro"
        currentId = ""
        index = -1
        plan = []
        outcomes = []
        lookGrade = ""
        testedAt = nil
        sheetFile = nil
        actions = []
        hint = ""
        detail = ""
    }

    func chooseLook(_ id: String) {
        guard Cosmetic.find(id) != nil else { return }
        lookGrade = id
        remember()
        prepareSheet()
    }

    func setCable(_ on: Bool) { withCable = on; remember(); prepareSheet() }
    func setBox(_ on: Bool) { withBox = on; remember(); prepareSheet() }

    func onAction(_ act: Act) {
        switch act.status {
        case "replay-speaker":
            tone.play(earpiece: false, pan: 0)
        case "replay-ear":
            tone.play(earpiece: true)
        case "replay-vibration":
            pulseVibration()
        case "replay-mic":
            AudioRoute.speaker()
            playback?.currentTime = 0
            playback?.play()
        case "replay-flash":
            camera.setTorch(false) { _ in
                self.camera.setTorch(true) { _ in }
            }
        case "replay-mute":
            AudioServicesPlaySystemSound(1104)
        case "camera-pass":
            let note = currentId == "camera_front"
                ? "Immagine anteriore confermata"
                : "Immagine posteriore confermata · \(openedLenses.joined(separator: ", "))"
            settle(currentId, "pass", note)
        case "truedepth-retry":
            facePoints = []
            faceArmed = false
            hint = "I puntini bianchi sono il volto visto dal sensore TrueDepth, non dalla fotocamera. Gira la testa: devono girare con te."
            actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
            armFace()
        case "wifi-retry":
            readNetwork()
        case "bt-retry":
            startBluetooth()
        case "open-settings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case "nfc-retry":
            openNfcSheet()
        case "lidar-ok":
            guard depthLive else {
                hint = "La mappa non è ancora arrivata. Avvicina un oggetto: deve scurirsi."
                return
            }
            settle("lidar", "pass", "LiDAR: il vicino è più scuro del fondo")
        case "mic-ok", "mic-bad":
            if act.status == "mic-bad" { micBad = true }
            micLines.append("\(micLabel) \(act.status == "mic-bad" ? "non si sente" : "si sente")")
            advanceMic()
        default:
            settle(currentId, act.status, act.note)
        }
    }

    func onScenePhase(_ phase: ScenePhase) {
        if phase == .active, currentId == "gps", !settled {
            place.requestFix()
        }
        guard armPower, currentId == "power_button", !settled else { return }
        if phase == .background { sawBackground = true }
        if phase == .active && (sawLock || sawBackground) {
            armPower = false
            keyOk = true
            detail = "Accensione ricevuta"
            hint = "Tasto ok."
            later(0.8) {
                guard self.still("power_button") else { return }
                self.settle("power_button", "pass", "Schermo spento e riacceso")
            }
        }
    }

    func skipCurrent() {
        settle(currentId, "skip", "Non eseguito")
    }

    func useLens(_ next: AVCaptureDevice.DeviceType) {
        lens = next
        lensName = Self.lensTitle(next)
        guard currentId == "camera_back" || currentId == "autofocus" else { return }
        if !openedLenses.contains(lensName) { openedLenses.append(lensName) }
        detail = openedLenses.joined(separator: " · ")
        camera.start(front: false, lens: next, scanQR: currentId == "autofocus", onFocus: {}, onCode: { value in
            self.acceptQR(value)
        }, onRunning: {}, onError: { message in
            self.detail = message
        })
    }

    func touchProgress(_ done: Int, _ total: Int) {
        detail = "\(done) di \(total)"
    }

    func noteForce(_ force: CGFloat, max possible: CGFloat) {
        guard still("force"), possible > 1 else { return }
        let unit = min(1, max(0, force / possible))
        forceUnit = unit
        detail = "Pressione \(Int((unit * 100).rounded()))"
        if unit > 0.08 && unit < 0.45 { forceSoft = true }
        if unit >= 0.75 { forceHard = true }
        if forceSoft && forceHard {
            settle("force", "pass", "Pressione leggera e forte rilevate")
        }
    }

    func settle(_ id: String, _ status: String, _ note: String) {
        guard !settled, currentId == id else { return }
        settled = true
        wave += 1
        outcomes.removeAll { $0.id == id }
        outcomes.append(Outcome(id: id, status: status, note: String(note.prefix(300))))
        let cameraWasOpen = showCamera
        actions = []
        cleanup(releaseCamera: !cameraWasOpen)
        let proceed = { [weak self] in
            guard let self else { return }
            guard self.index + 1 < self.plan.count else {
                if self.testedAt == nil { self.testedAt = Date() }
                self.phase = "report"
                self.currentId = "report"
                self.remember()
                self.prepareSheet()
                return
            }
            self.index += 1
            self.remember()
            self.enter()
        }
        guard cameraWasOpen else {
            DispatchQueue.main.async { proceed() }
            return
        }
        let gate = Once()
        let go = { gate.run(proceed) }
        DispatchQueue.main.async {
            self.camera.setTorch(false) { _ in }
            self.camera.stop(done: go)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { go() }
    }

    func shareText() -> String {
        let choice = Cosmetic.find(lookGrade)
        let model = Machine.described
        var lines = [
            "RefurbX Diagnostica",
            "\(model) · iOS \(UIDevice.current.systemVersion)",
            "Grado estetico \(choice?.id ?? "—") · \(choice?.title ?? "da scegliere")",
            "Cavo \(withCable ? "sì" : "no") · Scatola \(withBox ? "sì" : "no")",
            "",
        ]
        for row in activeRows {
            let item = outcomes.first { $0.id == row.id }
            let status = item?.status ?? "skip"
            lines.append("\(row.title): \(statusIt(status))")
            if let note = item?.note, !note.isEmpty { lines.append(note) }
        }
        let text = lines.joined(separator: "\n")
        return text.count > 3500 ? String(text.prefix(3480)) + "…" : text
    }

    func prepareSheet() {
        guard phase == "report", let choice = Cosmetic.find(lookGrade), let when = testedAt else {
            sheetFile = nil
            return
        }
        let rows = activeRows.map { row in
            let item = outcomes.first { $0.id == row.id }
            return (group: row.group, title: row.title, status: item?.status ?? "skip", note: item?.note ?? "")
        }
        sheetFile = SheetPDF.write(SheetFacts(
            grade: choice.id,
            title: choice.title,
            line: choice.line,
            when: when,
            device: "\(Machine.described) · iOS \(UIDevice.current.systemVersion)",
            cable: withCable,
            box: withBox,
            rows: rows
        ))
    }

    func sendToBench() {
        let raw = benchLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = BenchLink.parse(raw) else {
            benchState = "Incolla il link intero del banco, quello sotto il codice."
            return
        }
        UserDefaults.standard.set(raw, forKey: "refurbx.bench-link")
        benchSending = true
        benchState = "Invio al banco…"
        let payload = benchPayload()
        Task {
            let message = await BenchLink.deliver(target, payload: payload)
            self.benchSending = false
            self.benchState = message
        }
    }

    private func benchPayload() -> [String: Any] {
        let scale = UIScreen.main.scale
        let screen = "\(Int(UIScreen.main.bounds.width * scale))×\(Int(UIScreen.main.bounds.height * scale))"
        let choice = Cosmetic.find(lookGrade)
        let appearance = "Grado estetico \(choice?.id ?? "—") \(choice?.title ?? "") · Cavo \(withCable ? "sì" : "no") · Scatola \(withBox ? "sì" : "no")"
        return [
            "device": [
                "userAgent": "RefurbX Diagnostica",
                "platform": "ios",
                "model": Machine.described,
                "os": "iOS \(UIDevice.current.systemVersion)",
                "screen": screen,
                "dpr": scale,
                "cores": ProcessInfo.processInfo.processorCount,
                "touchPoints": 5,
                "language": "it",
                "secureContext": benchLink.lowercased().hasPrefix("https"),
            ],
            "tests": outcomes.map { ["id": $0.id, "status": $0.status, "note": $0.note] },
            "note": appearance,
        ]
    }

    private func enter() {
        cleanup()
        let row = current
        currentId = row.id
        settled = false
        phase = "guide"
        remember()
        hint = ""
        detail = ""
        actions = []
        showCamera = false
        fingers = 0
        proximityLit = false
        depthShot = nil
        lensName = ""
        openedLenses = []
        forceUnit = 0
        forceSoft = false
        forceHard = false
        edgeLeft = false
        edgeRight = false
        edgeTop = false
        edgeBottom = false
        gyroRest = false
        gyroTilt = false
        gyroPitch = false
        gyroYaw = false
        dotX = 0
        dotY = 0
        facePoints = []
        faceArmed = false
        depthFrames = 0
        depthArmed = false
        depthLive = false
        micSpot = ""
        micLevel = 0
        audioSpot = ""
        memoryTotal = ""
        memoryFree = ""
        memoryUsed = ""
        gpsAccuracy = ""
        gpsLatitude = nil
        gpsLongitude = nil
        bestGps = nil
        sawUnplugged = false
        keyOk = false
        lightLevel = 0
        lightWarm = 0
        lightFloor = 0
        lightCeil = 0
    }

    func beginCurrent() {
        guard phase == "guide", !settled else { return }
        phase = "run"
        launch()
    }

    private var current: Catalog.Row {
        let id = plan.indices.contains(index) ? plan[index] : ""
        return Catalog.rows.first { $0.id == id } ?? Catalog.rows[0]
    }

    private func launch() {
        let row = current
        switch row.id {
        case "identity": readIdentity()
        case "network": readNetwork()
        case "display": hint = "Tocca lo schermo per passare di colore. Poi conferma se è uniforme."
        case "touch":
            hint = "Le celle sono piccole. Trascina il dito su tutte, anche i bordi. Una cella spenta è una zona morta."
            actions = [
                Act(label: "Zona morta", status: "fail", note: "Una zona del touch non risponde"),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        case "multitouch":
            hint = "Appoggia due dita insieme. Il numero deve arrivare almeno a 2."
            actions = [
                Act(label: "Non legge più dita", status: "fail", note: "Multi-touch incompleto"),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        case "speaker": startSpeaker()
        case "microphone": afterCamera { self.recordMic() }
        case "vibration":
            pulseVibration()
            hint = "Il telefono deve vibrare tre volte. Conferma solo se lo senti in mano."
            actions = [
                Act(label: "L'ho sentita", status: "pass", note: "Vibrazione sentita"),
                Act(label: "Non vibra", status: "fail", note: "Motore di vibrazione fermo"),
                Act(label: "Ripeti", status: "replay-vibration", note: ""),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        case "earpiece":
            audioSpot = "ear"
            tone.play(earpiece: true)
            hint = "Conferma a mano. Avvicina l'orecchio alla capsula in alto, segnata sul disegno. Il suono non deve uscire dal basso."
            actions = [
                Act(label: "Passa", status: "pass", note: "Capsula in alto confermata a mano"),
                Act(label: "Fallito", status: "fail", note: "Capsula muta o audio dal basso"),
                Act(label: "Risenti", status: "replay-ear", note: ""),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        case "camera_back": openCamera(front: false)
        case "camera_front": openCamera(front: true)
        case "accelerometer": startAccel()
        case "gyroscope": startGyro()
        case "gps": startGps()
        case "volume_up": watchVolume(up: true)
        case "volume_down": watchVolume(up: false)
        case "power_button": startPower()
        case "mute_switch": startMute()
        case "charging": watchCharge()
        case "wireless": watchWireless()
        case "biometrics": startBiometrics()
        case "bluetooth": startBluetooth()
        case "nfc": startNfc()
        case "flash": startFlash()
        case "autofocus": startAutofocus()
        case "truedepth": startTrueDepth()
        case "lidar": startDepth()
        case "memory": readMemory()
        case "proximity": watchProximity()
        case "light": startLight()
        case "compass": startCompass()
        case "headphones": watchHeadphones()
        case "call":
            audioSpot = "ear"
            tone.play(earpiece: true)
            hint = "Conferma a mano. Tienilo come in chiamata: la nota deve uscire solo dalla capsula in alto, non dal vivavoce in basso."
            actions = [
                Act(label: "Passa", status: "pass", note: "Capsula di chiamata confermata a mano"),
                Act(label: "Fallito", status: "fail", note: "In chiamata l'audio non resta in capsula"),
                Act(label: "Risenti", status: "replay-ear", note: ""),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        case "force": startForce()
        case "stylus":
            settle("stylus", "absent", "L'iPhone non riceve la Apple Pencil")
        default:
            settle(row.id, "skip", "Test non eseguito")
        }
    }

    private func show(_ note: String) {
        detail = note
        hint = "Lettura dal telefono"
    }

    private func settleSoon(_ id: String, _ status: String, _ note: String) {
        show(note)
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        later(0.6) { self.settle(id, status, note) }
    }

    private func later(_ seconds: Double, _ block: @escaping () -> Void) {
        let seen = wave
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if seen == self.wave { block() }
        }
    }

    private func still(_ id: String) -> Bool {
        currentId == id && !settled
    }

    private func afterCamera(_ block: @escaping () -> Void) {
        camera.stop(done: block)
    }

    private func readIdentity() {
        let code = Machine.identifier
        let name = Machine.commercialName
        let os = "iOS \(UIDevice.current.systemVersion)"
        let scale = UIScreen.main.scale
        let points = "\(Int(UIScreen.main.bounds.width))×\(Int(UIScreen.main.bounds.height))"
        let pixels = "\(Int(UIScreen.main.bounds.width * scale))×\(Int(UIScreen.main.bounds.height * scale))"
        let note = "\(Machine.described) · \(os) · \(points) pt · \(pixels) px"
        hint = "\(os) · \(points) pt · \(pixels) px"
        detail = name == nil ? "Codice di fabbrica \(code)" : "\(name ?? "")\nCodice di fabbrica \(code)"
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        later(3) { self.settle("identity", "pass", note) }
    }

    private func readMemory() {
        guard let report = DiskProbe.read() else {
            memoryTotal = ""
            memoryFree = ""
            memoryUsed = ""
            settle("memory", "fail", "Capacità del telefono non letta")
            return
        }
        memoryTotal = DiskProbe.gb(report.total)
        memoryFree = DiskProbe.gb(report.free)
        memoryUsed = DiskProbe.gb(report.used)
        hint = "Totale, libero e usato sono quelli del telefono."
        detail = report.note
        actions = [
            Act(label: "Numeri giusti", status: "pass", note: report.note),
            Act(label: "Numeri sbagliati", status: "fail", note: "La memoria letta non torna"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
    }

    private func readNetwork() {
        keyOk = false
        hint = "Controllo se il Wi-Fi è collegato."
        detail = "In controllo"
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        NetworkProbe.check { [weak self] kind in
            guard let self, self.still("network") else { return }
            if kind == "wifi" {
                self.keyOk = true
                self.detail = "Wi-Fi collegato"
                self.hint = "Il telefono è sul Wi-Fi. Conferma se è la rete del negozio."
                self.actions = [
                    Act(label: "Wi-Fi collegato", status: "pass", note: "Wi-Fi collegato"),
                    Act(label: "Non è collegato", status: "fail", note: "Wi-Fi non collegato"),
                    Act(label: "Salta", status: "skip", note: "Non eseguito"),
                ]
            } else {
                self.keyOk = false
                self.detail = "Wi-Fi non collegato"
                self.hint = "Collega il Wi-Fi e riprova."
                self.actions = [
                    Act(label: "Riprova", status: "wifi-retry", note: ""),
                    Act(label: "Salta", status: "skip", note: "Non eseguito"),
                ]
            }
        }
    }

    private func startNfc() {
        hint = "Si apre il lettore tag di Apple. Tieni la scheda ferma sul retro, in alto."
        detail = "Apro il lettore"
        actions = nfcActions()
        armNfc()
        openNfcSheet()
    }

    private func nfcActions() -> [Act] {
        [
            Act(label: "Apri lettore tag", status: "nfc-retry", note: ""),
            Act(label: "Non legge", status: "fail", note: "NFC non ha letto un tag"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
    }

    private func armNfc() {
        tags.onActive = { [weak self] in
            guard let self, self.still("nfc") else { return }
            self.detail = "Lettore tag aperto"
            self.hint = "Finestra di Apple aperta. Tieni la scheda ferma sul retro, in alto, finché non compare NFC ok."
        }
        tags.onResult = { [weak self] status, note in
            guard let self, self.still("nfc") else { return }
            if status == "pass" {
                self.settle("nfc", "pass", note)
                return
            }
            if status == "absent" {
                self.settle("nfc", "absent", note)
                return
            }
            self.hint = status == "cancel"
                ? "Lettura chiusa. Premi Apri lettore tag e tieni la scheda ferma sul retro, in alto."
                : (note.isEmpty ? "La finestra NFC si è chiusa prima del tag. Premi Apri lettore tag." : note)
            self.detail = "Lettore chiuso"
            self.actions = self.nfcActions()
        }
    }

    private func openNfcSheet() {
        guard still("nfc") else { return }
        nfcAttempt += 1
        let opened = tags.beginNow()
        if opened {
            hint = "Si apre il lettore tag di Apple. Tieni la scheda ferma sul retro, in alto."
            detail = "Lettore tag in apertura"
        }
        actions = nfcActions()
    }

    private func startSpeaker() {
        audioSpot = "speaker"
        tone.play(earpiece: false, pan: 0)
        hint = "Conferma a mano. Stacca le cuffie: la nota sale dall'altoparlante in basso, segnato sul disegno. Deve essere chiara, senza crepitii."
        actions = [
            Act(label: "Passa", status: "pass", note: "Altoparlante in basso confermato a mano"),
            Act(label: "Fallito", status: "fail", note: "Altoparlante assente o distorto"),
            Act(label: "Risenti", status: "replay-speaker", note: ""),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
    }

    private func startAccel() {
        hint = "Inclina il telefono finché i quattro bordi diventano verdi."
        actions = [
            Act(label: "Non si muove", status: "fail", note: "L'accelerometro non cambia"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        let started = motion.gravity { [weak self] x, y in
            guard let self, self.still("accelerometer") else { return }
            self.dotX = CGFloat(max(-1, min(1, x)))
            self.dotY = CGFloat(max(-1, min(1, y)))
            if x < -0.55 { self.edgeLeft = true }
            if x > 0.55 { self.edgeRight = true }
            if y < -0.55 { self.edgeTop = true }
            if y > 0.55 { self.edgeBottom = true }
            let done = [self.edgeLeft, self.edgeRight, self.edgeTop, self.edgeBottom].filter { $0 }.count
            self.detail = "\(done) di 4 lati"
            if done == 4 {
                self.settle("accelerometer", "pass", "Quattro inclinazioni rilevate")
            }
        }
        if !started {
            settle("accelerometer", "absent", "Niente accelerometro")
        }
    }

    private func startGyro() {
        hint = "Tienilo fermo un attimo, poi ruotalo di lato, avanti e intorno a te."
        actions = [
            Act(label: "Non ruota", status: "fail", note: "Il giroscopio non cambia"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        var origin: (Double, Double, Double)?
        var stillSamples = 0
        let started = motion.attitude { [weak self] roll, pitch, yaw, rate in
            guard let self, self.still("gyroscope") else { return }
            if origin == nil {
                origin = (roll, pitch, yaw)
                return
            }
            if rate < 0.25 {
                stillSamples += 1
                if stillSamples > 8 { self.gyroRest = true }
            } else {
                stillSamples = 0
            }
            let base = origin ?? (0, 0, 0)
            if abs(roll - base.0) > 0.45 { self.gyroTilt = true }
            if abs(pitch - base.1) > 0.45 { self.gyroPitch = true }
            if Self.angleGap(yaw, base.2) > 0.6 { self.gyroYaw = true }
            if self.gyroRest && self.gyroTilt && self.gyroPitch && self.gyroYaw {
                self.settle("gyroscope", "pass", "Fermo, rollio, beccheggio e imbardata rilevati")
            }
        }
        if !started {
            settle("gyroscope", "absent", "Niente giroscopio")
        }
    }

    private func startGps() {
        hint = "Cerco il satellite. Se iOS chiede la posizione, consenti e scegli Precisa. La mappa resta aperta finché non confermi."
        detail = "In cerca"
        gpsAccuracy = "In cerca"
        gpsLatitude = nil
        gpsLongitude = nil
        bestGps = nil
        actions = [
            Act(label: "Apri Impostazioni", status: "open-settings", note: ""),
            Act(label: "Nessun fix", status: "skip", note: "Nessun fix in negozio"),
        ]
        place.onFix = { [weak self] location in
            guard let self, self.still("gps"), location.horizontalAccuracy >= 0 else { return }
            if let best = self.bestGps, location.horizontalAccuracy >= best.horizontalAccuracy { return }
            self.bestGps = location
            let meters = max(0, Int(location.horizontalAccuracy.rounded()))
            let lat = String(format: "%.5f", location.coordinate.latitude)
            let lon = String(format: "%.5f", location.coordinate.longitude)
            self.gpsLatitude = location.coordinate.latitude
            self.gpsLongitude = location.coordinate.longitude
            self.gpsAccuracy = "±\(meters) m"
            self.detail = "±\(meters) m · \(lat), \(lon)"
            if location.horizontalAccuracy <= 100 {
                self.hint = "Posizione corretta. Conferma se il punto sulla mappa è quello giusto."
            } else {
                self.hint = "Fix largo. La mappa resta aperta: avvicinati a una finestra oppure accetta questo punto."
            }
            self.actions = [
                Act(label: "Posizione corretta", status: "pass", note: "Fix ±\(meters) m"),
                Act(label: "Apri Impostazioni", status: "open-settings", note: ""),
                Act(label: "Nessun fix", status: "skip", note: "Nessun fix utile"),
            ]
        }
        place.onDenied = { [weak self] in
            guard let self, self.still("gps") else { return }
            self.hint = "Posizione negata. In Impostazioni consenti Posizione e Precisa, poi torna nell'app."
            self.detail = "Permesso assente"
            self.gpsAccuracy = "Negato"
            self.actions = [
                Act(label: "Apri Impostazioni", status: "open-settings", note: ""),
                Act(label: "Salta", status: "skip", note: "Permesso posizione negato"),
            ]
        }
        place.requestFix()
        later(20) {
            guard self.still("gps"), self.bestGps == nil else { return }
            self.hint = "Ancora nessun satellite. Una finestra aiuta. Il test resta qui finché non arriva un fix o salti."
        }
    }

    private func watchVolume(up: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        keyOk = false
        volumePrevious = session.outputVolume
        let id = up ? "volume_up" : "volume_down"
        if up && volumePrevious > 0.95 {
            hint = "Il volume è già al massimo. Premi volume giù una volta, poi di nuovo volume su. Compare la spunta appena il tasto risponde."
        } else if !up && volumePrevious < 0.05 {
            hint = "Il volume è già al minimo. Premi volume su una volta, poi di nuovo volume giù. Compare la spunta appena il tasto risponde."
        } else {
            hint = up
                ? "Premi volume su. Compare la spunta appena il tasto risponde."
                : "Premi volume giù. Compare la spunta appena il tasto risponde."
        }
        detail = up ? "In attesa di volume +" : "In attesa di volume −"
        actions = [
            Act(label: "Non risponde", status: "fail", note: up ? "Volume su fermo" : "Volume giù fermo"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        volumeObservation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            let now = change.newValue ?? session.outputVolume
            let previous = change.oldValue ?? -1
            Task { @MainActor in
                self?.noteVolume(up: up, previous: previous, now: now)
            }
        }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = session.outputVolume
                self.noteVolume(up: up, previous: self.volumePrevious, now: now)
                self.volumePrevious = now
            }
        }
        volumeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func noteVolume(up: Bool, previous: Float, now: Float) {
        let id = up ? "volume_up" : "volume_down"
        guard still(id), !keyOk, previous >= 0 else { return }
        let hit = up ? now > previous + 0.008 : now < previous - 0.008
        guard hit else { return }
        markKey(id, note: up ? "Volume su ricevuto" : "Volume giù ricevuto")
    }

    private func markKey(_ id: String, note: String) {
        guard still(id), !keyOk else { return }
        keyOk = true
        detail = note
        hint = "Tasto ok."
        later(0.8) {
            guard self.still(id) else { return }
            self.settle(id, "pass", note)
        }
    }

    private func startPower() {
        armPower = true
        sawLock = false
        sawBackground = false
        hint = "Premi il tasto laterale finché lo schermo si spegne, poi riaccendilo e torna nell'app."
        watch(UIApplication.protectedDataWillBecomeUnavailableNotification) { [weak self] in
            self?.sawLock = true
        }
        actions = [
            Act(label: "Non spegne", status: "fail", note: "Il tasto laterale non spegne lo schermo"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
    }

    private func startMute() {
        guard Self.hasRingSwitch() else {
            settle("mute_switch", "absent", "Questo modello ha il tasto Azione, non l'interruttore silenzioso")
            return
        }
        hint = "Porta l'interruttore su Suoneria e ascolta il clic. Poi su Silenzioso: il clic di sistema non deve sentirsi. La nota musicale, se parte, non segue quell'interruttore."
        actions = [
            Act(label: "Suoneria e silenzioso ok", status: "pass", note: "Suoneria e silenzioso confermati dall'operatore"),
            Act(label: "Non commuta", status: "fail", note: "L'interruttore non cambia il clic di sistema"),
            Act(label: "Ascolta il clic", status: "replay-mute", note: ""),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        AudioServicesPlaySystemSound(1104)
    }

    private func watchCharge() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        actions = [
            Act(label: "Non entra in carica", status: "fail", note: "Il cavo non fa entrare in carica"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        if chargingNow() {
            settleSoon("charging", "pass", "Il sistema vede la carica")
            return
        }
        hint = "Collega il cavo. Se il sistema vede la carica, il test prosegue da solo."
        watch(UIDevice.batteryStateDidChangeNotification) { [weak self] in
            if self?.chargingNow() == true { self?.settle("charging", "pass", "Il sistema vede la carica") }
        }
    }

    private func chargingNow() -> Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    private func watchWireless() {
        guard Self.hasWirelessCharge() else {
            settle("wireless", "absent", "Questo iPhone non ha la ricarica wireless")
            return
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        sawUnplugged = false
        actions = [
            Act(label: "Non carica", status: "fail", note: "Sul pad non entra in carica"),
            Act(label: "Salta", status: "skip", note: "Nessun pad da provare"),
        ]
        watch(UIDevice.batteryStateDidChangeNotification) { [weak self] in
            self?.noteWireless()
        }
        noteWireless()
        armWirelessPoll()
    }

    private func noteWireless() {
        guard still("wireless") else { return }
        switch UIDevice.current.batteryState {
        case .unplugged:
            sawUnplugged = true
            hint = "Cavo staccato. Appoggia il telefono sul pad, senza ricollegare il cavo."
            detail = "In attesa del pad"
        case .charging, .full:
            if sawUnplugged {
                settle("wireless", "pass", "In carica sul pad, a cavo staccato")
            } else {
                hint = "Stacca il cavo. Il pad si prova solo quando il telefono non è già in carica."
                detail = "Stacca il cavo"
            }
        default:
            hint = "Appoggia il telefono sul pad wireless."
            detail = "In attesa"
        }
    }

    private func armWirelessPoll() {
        later(0.4) {
            guard self.still("wireless") else { return }
            self.noteWireless()
            self.armWirelessPoll()
        }
    }

    private static func hasWirelessCharge() -> Bool {
        guard let major = Machine.iphoneMajor else { return true }
        return major >= 10
    }

    private func startBiometrics() {
        hint = "Usa il volto o l'impronta. Se la richiesta non compare, salta."
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        face.run { [weak self] status, note in
            self?.settle("biometrics", status, note)
        }
        later(25) {
            guard self.still("biometrics") else { return }
            self.hint = "Il riconoscimento non ha risposto. Salta e vai avanti."
        }
    }

    private func startBluetooth() {
        keyOk = false
        hint = "Controllo il Bluetooth. Resta su questa schermata: si vede se è acceso."
        detail = "In controllo"
        actions = [
            Act(label: "Salta", status: "skip", note: "Bluetooth non verificato"),
        ]
        radio.onResult = { [weak self] status, note in
            guard let self, self.still("bluetooth") else { return }
            if status == "pass" {
                self.keyOk = true
                self.detail = "Bluetooth acceso"
                self.hint = "Il Bluetooth risponde. Conferma se funziona."
                self.actions = [
                    Act(label: "Funziona", status: "pass", note: "Bluetooth acceso"),
                    Act(label: "Non funziona", status: "fail", note: "Bluetooth acceso ma non utilizzabile"),
                    Act(label: "Salta", status: "skip", note: "Non eseguito"),
                ]
                return
            }
            if status == "absent" {
                self.settle("bluetooth", "absent", note)
                return
            }
            self.keyOk = false
            let denied = note.localizedCaseInsensitiveContains("permesso") || note.localizedCaseInsensitiveContains("negato")
            self.detail = denied ? "Permesso negato" : "Bluetooth spento"
            self.hint = denied
                ? "In Impostazioni consenti il Bluetooth a RefurbX, poi riprova."
                : "Accendi il Bluetooth e riprova."
            self.actions = [
                Act(label: "Riprova", status: "bt-retry", note: ""),
                Act(label: denied ? "Apri Impostazioni" : "Non funziona", status: denied ? "open-settings" : "fail", note: denied ? "" : "Bluetooth spento"),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        }
        radio.stop()
        radio.start()
    }

    private func openCamera(front: Bool) {
        let id = front ? "camera_front" : "camera_back"
        if !front {
            lenses = CameraSession.backLenses()
            lens = lenses.contains(.builtInWideAngleCamera) ? .builtInWideAngleCamera : (lenses.first ?? .builtInWideAngleCamera)
            lensName = Self.lensTitle(lens)
            openedLenses = [lensName]
        }
        hint = "Apro la fotocamera. Se compare la richiesta, consenti."
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.still(id) else { return }
                guard granted else {
                    self.settle(id, "skip", "Permesso fotocamera negato")
                    return
                }
                self.showCamera = true
                self.camera.start(front: front, lens: self.lens, onFocus: {}, onRunning: {
                    guard self.still(id) else { return }
                    self.hint = front
                        ? "Il volto deve essere in verticale. Conferma solo se l'immagine è pulita e dritta."
                        : "Cambia obiettivo se ce n'è più di uno. Conferma solo se l'immagine è nitida."
                    self.detail = front ? "" : self.openedLenses.joined(separator: " · ")
                    self.actions = [
                        Act(label: "Immagine ok", status: "camera-pass", note: ""),
                        Act(label: "Immagine sporca o nera", status: "fail", note: front ? "Camera anteriore non utilizzabile" : "Camera posteriore non utilizzabile"),
                        Act(label: "Salta", status: "skip", note: "Non eseguito"),
                    ]
                }, onError: { message in
                    self.settle(id, "fail", message)
                })
            }
        }
        later(12) {
            guard self.still(id), self.actions.count < 2 else { return }
            self.hint = "La fotocamera non si è aperta."
            self.actions = [
                Act(label: "Non si apre", status: "fail", note: "La fotocamera non si è aperta"),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        }
    }

    private func startFlash() {
        guard CameraSession.hasFlash() else {
            settle("flash", "absent", "Niente flash")
            return
        }
        hint = "Accendo il flash. Se compare la richiesta, consenti. Conferma solo se lo vedi acceso."
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.still("flash") else { return }
                guard granted else {
                    self.settle("flash", "skip", "Permesso fotocamera negato")
                    return
                }
                self.camera.stop {
                    guard self.still("flash") else { return }
                    self.camera.setTorch(true) { ok in
                        guard self.still("flash") else { return }
                        guard ok else {
                            self.settle("flash", "fail", "Il flash non si accende")
                            return
                        }
                        self.hint = "Il flash è acceso. Conferma solo se lo vedi."
                        self.actions = [
                            Act(label: "Si vede", status: "pass", note: "Flash acceso"),
                            Act(label: "Non si accende", status: "fail", note: "Flash spento o debole"),
                            Act(label: "Spegni e riaccendi", status: "replay-flash", note: ""),
                            Act(label: "Salta", status: "skip", note: "Non eseguito"),
                        ]
                    }
                }
            }
        }
        later(12) {
            guard self.still("flash"), self.actions.count < 2 else { return }
            self.hint = "Il flash non ha risposto."
            self.actions = [
                Act(label: "Non si accende", status: "fail", note: "Il flash non si accende"),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        }
    }

    private func startAutofocus() {
        guard CameraSession.hasAutofocus() else {
            settle("autofocus", "absent", "Obiettivo a fuoco fisso")
            return
        }
        hint = "Apro la fotocamera dietro. Inquadra un codice QR."
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.still("autofocus") else { return }
                guard granted else {
                    self.settle("autofocus", "skip", "Permesso fotocamera negato")
                    return
                }
                self.showCamera = true
                self.camera.start(front: false, scanQR: true, onFocus: {}, onCode: { value in
                    self.acceptQR(value)
                }, onRunning: {
                    guard self.still("autofocus") else { return }
                    self.hint = "Inquadra un codice QR. Se lo legge, il test è ok."
                    self.detail = "In attesa del QR"
                    self.actions = [
                        Act(label: "Non legge il QR", status: "fail", note: "Il QR non viene letto"),
                        Act(label: "Salta", status: "skip", note: "Non eseguito"),
                    ]
                }, onError: { message in
                    self.settle("autofocus", "fail", message)
                })
            }
        }
    }

    private func acceptQR(_ value: String) {
        guard still("autofocus") else { return }
        let short = value.count > 80 ? String(value.prefix(80)) + "…" : value
        detail = short
        settle("autofocus", "pass", "QR letto: \(short)")
    }

    private func startTrueDepth() {
        guard CameraSession.hasTrueDepth() else {
            settle("truedepth", "absent", "Niente fotocamera TrueDepth")
            return
        }
        hint = "I puntini bianchi sono il volto visto dal sensore TrueDepth, non dalla fotocamera a colori. Gira la testa: i puntini devono girare con te. La foto a infrarossi non si vede, resta in iOS."
        actions = [
            Act(label: "I puntini girano", status: "pass", note: "TrueDepth ha seguito la testa. L'immagine a infrarossi resta nel sistema."),
            Act(label: "Non seguono la testa", status: "fail", note: "TrueDepth presente, la testa non è seguita"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        armFace()
    }

    private func armFace() {
        faceTrack.onPicture = { [weak self] points in
            guard let self, self.still("truedepth"), points.count > 40 else { return }
            self.facePoints = points
            self.faceArmed = true
            self.detail = "Volto seguito. Gira la testa: i puntini devono girare con te."
        }
        faceTrack.start { _ in }
    }

    private func startDepth() {
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            settle("lidar", "absent", "Questo iPhone non consegna la profondità LiDAR")
            return
        }
        hint = "Parte grigia e resta aperta. Avvicina la mano: solo le zone vicine diventano più scure. Conferma quando hai visto abbastanza."
        actions = [
            Act(label: "Si scurisce", status: "lidar-ok", note: ""),
            Act(label: "Resta chiara", status: "fail", note: "La profondità non si scurisce"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        depth.onPicture = { [weak self] image, live, near in
            guard let self, self.still("lidar") else { return }
            self.depthShot = image
            guard live else { return }
            self.depthLive = true
            self.detail = near ? "Vicino più scuro" : "Inquadra qualcosa di vicino"
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.still("lidar") else { return }
                guard granted else {
                    self.settle("lidar", "skip", "Permesso fotocamera negato")
                    return
                }
                self.camera.stop {
                    guard self.still("lidar") else { return }
                    self.depth.start { ok in
                        guard self.still("lidar") else { return }
                        if !ok {
                            self.settle("lidar", "skip", "Nessuna mappa di profondità")
                        }
                    }
                }
            }
        }
    }

    private func startLight() {
        lightWarm = 0
        lightFloor = 0
        lightCeil = 0
        lightLevel = 0
        hint = "Apro la fotocamera dietro. Poi copri l'obiettivo con la mano e scoprilo: la barra deve muoversi."
        detail = "In avvio"
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.still("light") else { return }
                guard granted else {
                    self.settle("light", "skip", "Permesso fotocamera negato")
                    return
                }
                self.showCamera = true
                self.camera.start(front: false, onFocus: {}, onRunning: {
                    guard self.still("light") else { return }
                    self.hint = "Copri e scopri l'obiettivo posteriore. iOS non dà i lux: la barra segue la luce vista dalla fotocamera."
                    self.detail = "Copri e scopri l'obiettivo"
                    self.actions = [
                        Act(label: "Non reagisce", status: "fail", note: "La fotocamera non ha reagito alla luce"),
                        Act(label: "Salta", status: "skip", note: "Non eseguito"),
                    ]
                    self.pollLight()
                }, onError: { message in
                    self.settle("light", "fail", message)
                })
            }
        }
    }

    private func pollLight() {
        later(0.25) {
            guard self.still("light") else { return }
            if let value = self.camera.ambientLevel() {
                self.noteLight(value)
            }
            guard self.still("light") else { return }
            self.pollLight()
        }
    }

    private func noteLight(_ value: Double) {
        lightWarm += 1
        if lightWarm <= 4 {
            lightLevel = 0.45
            return
        }
        if lightWarm == 5 {
            lightFloor = value
            lightCeil = value
        }
        lightFloor = min(lightFloor, value)
        lightCeil = max(lightCeil, value)
        let span = lightCeil - lightFloor
        lightLevel = span < 0.0000001 ? 0.5 : min(1, max(0, (value - lightFloor) / span))
        let ratio = lightCeil / max(lightFloor, 1e-9)
        if ratio > 1.15 {
            detail = "La luce sta cambiando"
        }
        if lightWarm >= 10 && ratio >= 3 {
            settle("light", "pass", "La fotocamera ha reagito coprendo e scoprendo l'obiettivo")
        }
    }

    private func watchProximity() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        try? session.setActive(true)
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        guard device.isProximityMonitoringEnabled else {
            settle("proximity", "absent", "Niente sensore di prossimità")
            return
        }
        hint = "Copri il sensore in alto, vicino alla capsula. Lo schermo può spegnersi un attimo."
        actions = [
            Act(label: "Non reagisce", status: "fail", note: "Il sensore di prossimità non reagisce"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        watch(UIDevice.proximityStateDidChangeNotification) { [weak self] in
            if UIDevice.current.proximityState {
                self?.proximityLit = true
                self?.settle("proximity", "pass", "Sensore di prossimità attivato")
            }
        }
        later(0.6) {
            if self.still("proximity") && UIDevice.current.proximityState {
                self.proximityLit = true
                self.settle("proximity", "pass", "Sensore di prossimità attivato")
            }
        }
    }

    private func startCompass() {
        hint = "Tieni il telefono in piano e ruotalo finché l'anello si riempie."
        actions = [
            Act(label: "Non gira", status: "fail", note: "La bussola non segue la rotazione"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        compassMarks = []
        heading = 0
        place.onHeading = { [weak self] heading in
            guard let self, self.still("compass") else { return }
            self.heading = heading.magneticHeading
            let bucket = Int(heading.magneticHeading / 45) % 8
            self.compassMarks.insert(bucket)
            self.detail = "\(self.compassMarks.count) di 8 direzioni"
            if self.compassMarks.count >= 6 {
                self.settle("compass", "pass", "Anello seguito per \(self.compassMarks.count) direzioni")
            }
        }
        place.onDenied = { [weak self] in
            guard let self, self.still("compass") else { return }
            self.hint = "La bussola chiede la posizione. Consenti Posizione, poi torna nell'app e ruota il telefono."
            self.actions = [
                Act(label: "Apri Impostazioni", status: "open-settings", note: ""),
                Act(label: "Salta", status: "skip", note: "Permesso posizione negato"),
            ]
        }
        place.startHeading()
    }

    private func watchHeadphones() {
        actions = [
            Act(label: "Non ho le cuffie", status: "skip", note: "Nessuna cuffia da provare"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        if headphonesNow() {
            settleSoon("headphones", "pass", "Cuffia già collegata")
            return
        }
        hint = "Collega cuffie Bluetooth o un adattatore. L'iPhone non ha il jack. Se non ne hai, salta."
        watch(AVAudioSession.routeChangeNotification) { [weak self] in
            if self?.headphonesNow() == true { self?.settle("headphones", "pass", "Cuffia collegata") }
        }
    }

    private func headphonesNow() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { port in
            port.portType == .headphones || port.portType == .bluetoothA2DP || port.portType == .bluetoothHFP || port.portType == .bluetoothLE || port.portType == .usbAudio
        }
    }

    private func startForce() {
        guard UIScreen.main.traitCollection.forceTouchCapability == .available else {
            settle("force", "absent", "Questo schermo non misura la pressione")
            return
        }
        hint = "Premi piano e poi forte nel riquadro."
        actions = [
            Act(label: "Non misura la pressione", status: "absent", note: "Questo schermo non misura la pressione"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
    }

    private func recordMic() {
        guard still("microphone") else { return }
        hint = "Parla per due secondi e mezzo. Poi riascolti la voce."
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard self.still("microphone") else { return }
                guard granted else {
                    self.settle("microphone", "skip", "Permesso microfono negato")
                    return
                }
                self.micQueue = AudioRoute.micSources()
                self.micCursor = 0
                self.micLines = []
                self.micBad = false
                self.captureMic()
            }
        }
    }

    private func captureMic() {
        guard still("microphone") else { return }
        let source: AVAudioSessionDataSourceDescription? = micQueue.indices.contains(micCursor) ? micQueue[micCursor] : nil
        let place = source.map(Self.micPlace) ?? (title: "Microfono", spot: "")
        micLabel = place.title
        micSpot = place.spot
        micLevel = 0
        micToken += 1
        let token = micToken
        hint = "Parla verso \(micLabel.lowercased()), segnato sul disegno, per due secondi e mezzo. Poi confermi a mano: il livello da solo non basta."
        detail = micQueue.count > 1 ? "\(micCursor + 1) di \(micQueue.count)" : micLabel
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        mic.record(seconds: 2.5, source: source, onLevel: { level in
            Task { @MainActor in
                guard self.micToken == token, self.still("microphone") else { return }
                self.micLevel = min(100, level / 4)
                self.detail = "\(self.micLabel) · livello \(self.micLevel)"
            }
        }, done: { rms, url in
            Task { @MainActor in
                guard self.micToken == token, self.still("microphone") else { return }
                if let url {
                    AudioRoute.speaker()
                    self.playback = try? AVAudioPlayer(contentsOf: url)
                    self.playback?.prepareToPlay()
                    self.playback?.play()
                }
                let loud = min(100, Int(rms * 250))
                self.micLevel = max(self.micLevel, loud)
                self.detail = "\(self.micLabel) · livello \(self.micLevel)"
                self.hint = "Conferma a mano \(self.micLabel.lowercased()). Riascolta e segna solo se riconosci la voce. Il livello non chiude il test."
                var items = [
                    Act(label: "Passa", status: "mic-ok", note: ""),
                    Act(label: "Fallito", status: "mic-bad", note: ""),
                ]
                if self.playback != nil {
                    items.append(Act(label: "Riascolta", status: "replay-mic", note: ""))
                }
                items.append(Act(label: "Salta", status: "skip", note: "Non eseguito"))
                self.actions = items
            }
        })
        later(7) {
            guard self.micToken == token, self.still("microphone"), self.actions.count < 2 else { return }
            self.hint = "La registrazione non è arrivata."
            self.actions = [
                Act(label: "Non si sente", status: "fail", note: "Registrazione assente"),
                Act(label: "Salta", status: "skip", note: "Non eseguito"),
            ]
        }
    }

    private func advanceMic() {
        let next = micCursor + 1
        if micQueue.isEmpty || next >= micQueue.count {
            let note = micLines.joined(separator: " · ")
            settle("microphone", micBad ? "fail" : "pass", note.isEmpty ? "Microfono verificato" : note)
            return
        }
        micCursor = next
        playback?.stop()
        captureMic()
    }

    private func pulseVibration() {
        let seen = wave
        for step in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.45) {
                guard seen == self.wave, self.currentId == "vibration" else { return }
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }

    private func watch(_ name: Notification.Name, _ block: @escaping () -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            block()
        }
        observers.append(token)
    }

    private func cleanup(releaseCamera: Bool = true) {
        armPower = false
        showCamera = false
        face.cancel()
        faceTrack.stop()
        tone.stop()
        mic.stop()
        motion.stop()
        place.stop()
        radio.stop()
        depth.stop()
        tags.stop()
        playback?.stop()
        playback = nil
        if releaseCamera {
            camera.setTorch(false) { _ in }
            camera.stop()
        }
        volumeTimer?.invalidate()
        volumeTimer = nil
        volumeObservation?.invalidate()
        volumeObservation = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
    }

    private static func hasRingSwitch() -> Bool {
        guard let major = Machine.iphoneMajor else { return false }
        return major <= 15
    }

    private static func angleGap(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: .pi * 2)
        return min(raw, .pi * 2 - raw)
    }

    private static func micPlace(_ source: AVAudioSessionDataSourceDescription) -> (title: String, spot: String) {
        if let orientation = source.orientation {
            switch orientation {
            case .back:
                return ("Microfono posteriore", "back")
            case .front, .top:
                return ("Microfono frontale", "front")
            case .bottom:
                return ("Microfono in basso", "bottom")
            default:
                break
            }
        }
        if let location = source.location {
            switch location {
            case .lower:
                return ("Microfono in basso", "bottom")
            case .upper:
                return ("Microfono frontale", "front")
            default:
                break
            }
        }
        let name = source.dataSourceName.lowercased()
        if name.contains("back") || name.contains("rear") || name.contains("posterior") || name.contains("dietro") {
            return ("Microfono posteriore", "back")
        }
        if name.contains("front") || name.contains("top") || name.contains("upper") || name.contains("frontal") || name.contains("davanti") || name.contains("alto") {
            return ("Microfono frontale", "front")
        }
        if name.contains("bottom") || name.contains("lower") || name.contains("basso") {
            return ("Microfono in basso", "bottom")
        }
        return (source.dataSourceName, "")
    }

    private func remember() {
        let saved = SavedRun(
            phase: phase,
            index: index,
            plan: plan,
            items: outcomes.map { SavedItem(id: $0.id, status: $0.status, note: $0.note) },
            look: lookGrade,
            tested: testedAt,
            cable: withCable,
            box: withBox
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        let url = Self.runURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        canResume = true
    }

    private static func loadRun() -> SavedRun? {
        guard let data = try? Data(contentsOf: runURL()) else { return nil }
        return try? JSONDecoder().decode(SavedRun.self, from: data)
    }

    private static func clearRun() {
        try? FileManager.default.removeItem(at: runURL())
    }

    private static func runURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RefurbX/run.json")
    }

    static func lensTitle(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInUltraWideCamera: return "Ultra-grandangolo"
        case .builtInTelephotoCamera: return "Teleobiettivo"
        case .builtInWideAngleCamera: return "Grandangolo"
        default: return "Obiettivo"
        }
    }
}

private struct SavedItem: Codable {
    var id: String
    var status: String
    var note: String
}

private struct SavedRun: Codable {
    var phase: String
    var index: Int
    var plan: [String]
    var items: [SavedItem]
    var look: String
    var tested: Date?
    var cable: Bool
    var box: Bool

    init(phase: String, index: Int, plan: [String], items: [SavedItem], look: String, tested: Date?, cable: Bool, box: Bool) {
        self.phase = phase
        self.index = index
        self.plan = plan
        self.items = items
        self.look = look
        self.tested = tested
        self.cable = cable
        self.box = box
    }

    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: CodingKeys.self)
        phase = try keys.decode(String.self, forKey: .phase)
        index = try keys.decode(Int.self, forKey: .index)
        plan = try keys.decodeIfPresent([String].self, forKey: .plan) ?? []
        items = try keys.decode([SavedItem].self, forKey: .items)
        look = try keys.decodeIfPresent(String.self, forKey: .look) ?? ""
        tested = try keys.decodeIfPresent(Date.self, forKey: .tested)
        cable = try keys.decode(Bool.self, forKey: .cable)
        box = try keys.decode(Bool.self, forKey: .box)
    }

    func encode(to encoder: Encoder) throws {
        var keys = encoder.container(keyedBy: CodingKeys.self)
        try keys.encode(phase, forKey: .phase)
        try keys.encode(index, forKey: .index)
        try keys.encode(plan, forKey: .plan)
        try keys.encode(items, forKey: .items)
        try keys.encode(look, forKey: .look)
        try keys.encodeIfPresent(tested, forKey: .tested)
        try keys.encode(cable, forKey: .cable)
        try keys.encode(box, forKey: .box)
    }

    private enum CodingKeys: String, CodingKey {
        case phase, index, plan, items, look, tested, cable, box
    }
}

enum BenchLink {
    static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, let scheme = url.scheme, scheme == "http" || scheme == "https" else { return nil }
        let code = (url.path.split(separator: "/").last.map(String.init) ?? "").uppercased()
        guard code.count == 6, code.allSatisfy({ "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }) else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.port = url.port
        parts.path = "/api/intake/\(code)"
        return parts.url
    }

    static func deliver(_ url: URL, payload: [String: Any]) async -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return "Non riesco a preparare la scheda."
        }
        request.httpBody = body
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let message = json?["message"] as? String, status < 400 { return message }
            if let error = json?["error"] as? String, !error.isEmpty { return error }
            if status == 0 { return "Il banco non ha risposto." }
            return "Il banco ha risposto \(status)."
        } catch {
            return "Non raggiungo il banco. Controlla che il telefono e il computer siano raggiungibili."
        }
    }
}

private final class Once {
    private var done = false

    func run(_ body: () -> Void) {
        if done { return }
        done = true
        body()
    }
}
