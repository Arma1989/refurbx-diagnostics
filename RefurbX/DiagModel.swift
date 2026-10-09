import Darwin
import ARKit
import AudioToolbox
import AVFoundation
import CoreLocation
import MediaPlayer
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
    @Published var qrCaught = false
    @Published var qrBox: CGRect = .zero
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
    @Published var gyroRollDeg: Double = 0
    @Published var gyroPitchDeg: Double = 0
    @Published var gyroYawDeg: Double = 0
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
    @Published var faceShot: UIImage?
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
    @Published var buttonBundle = false
    @Published var volumeUpMark = ""
    @Published var volumeDownMark = ""
    @Published var powerMark = ""
    @Published var muteMark = ""
    @Published var muteWord = ""
    @Published var qrText = ""
    @Published var lightLevel: Double = 0

    var planCount: Int { max(plan.count, 1) }
    var activeRows: [Catalog.Row] {
        let ids = plan.isEmpty ? Catalog.rows.map(\.id) : plan
        return ids.compactMap { id in Catalog.rows.first { $0.id == id } }
    }
    var showsLocked: Bool {
        let supported = Set(HardwareFit.rows(in: nil).map(\.id))
        return supported.isSubset(of: Set(plan))
    }
    var lockedRows: [Catalog.Row] { HardwareFit.lockedRows }

    let camera = CameraSession()

    private var cableWatch: Timer?

    init() {
        adoptCableLink()
        canResume = Self.loadRun() != nil
        startCableWatch()
    }

    private func startCableWatch() {
        cableWatch?.invalidate()
        cableWatch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.adoptCableLink()
                self?.flushOutbox()
            }
        }
    }

    private func adoptCableLink() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let file = docs.appendingPathComponent("bench.url")
        if let text = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let code = BenchLink.displayedCode(text), BenchLink.remember(text) {
            if benchLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                benchLink = code
                UserDefaults.standard.set(code, forKey: "refurbx.bench-link")
            }
            return
        }
        let fromArgs = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
        if let fromArgs, let code = BenchLink.displayedCode(fromArgs), BenchLink.remember(fromArgs), benchLink != code {
            benchLink = code
            UserDefaults.standard.set(code, forKey: "refurbx.bench-link")
        } else if let code = BenchLink.displayedCode(benchLink), benchLink != code, BenchLink.remember(benchLink) {
            benchLink = code
            UserDefaults.standard.set(code, forKey: "refurbx.bench-link")
        }
    }

    private func flushOutbox() {
        guard !outcomes.isEmpty else { return }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: benchPayload()) else { return }
        try? data.write(to: docs.appendingPathComponent("outbox.json"), options: .atomic)
    }
    private let tone = TonePlayer()
    private let mic = MicProbe()
    private let motion = MotionProbe()
    private let ringer = RingerWatch()
    private let place = PlaceProbe()
    private let radio = RadioProbe()
    private let depth = DepthProbe()
    private let faceTrack = FaceTrackProbe()
    private let face = FaceProbe()
    private let tags = TagProbe()
    var tagProbe: TagProbe { tags }
    private var bestGps: CLLocation?
    private var settled = false
    private var wave = 0
    private var volumePrevious: Float = -1
    private var volumeTimer: Timer?
    private var volumeObservation: NSKeyValueObservation?
    private var volumeHost: MPVolumeView?
    private weak var volumeCatcher: MPVolumeView?
    private var volumeArmed = false
    private var volumeWantsUp = false
    private var volumeDidSet = false
    private var volumeStable = 0
    private var volumeWait = 0
    private var volumeLast: Float = -1
    private var volumeToken = 0
    private var volumeTarget: Float = 0.5
    private var pendingCamera: (() -> Void)?
    private var muteToken = 0
    private var muteSawSound = false
    private var buttonFinishQueued = false
    private static let buttonIds: Set<String> = ["volume_up", "volume_down", "power_button", "mute_switch"]
    private var lightWarm = 0
    private var lightFloor = 0.0
    private var lightCeil = 0.0
    private var lightBase = 0.0
    private var lightPeak = 0.0
    private var lightFrames = 0
    private var lightUsesFrames = false
    private var playback: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private var proximityCovered = false
    private var proximityArmed = false
    private var micQueue: [AVAudioSessionDataSourceDescription] = []
    private var micCursor = 0
    private var micLines: [String] = []
    private var micBad = false
    private var micLabel = "Microfono"
    private var micToken = 0
    private var faceArmed = false
    private var qrOnce = false
    private var depthFrames = 0
    private var depthArmed = false
    private var depthLive = false
    private var sawUnplugged = false
    private var forceSoft = false
    private var forceHard = false
    private var openedLenses: [String] = []

    func begin(group: String?) {
        begin(ids: HardwareFit.rows(in: group).map(\.id))
    }

    func begin(ids: [String]) {
        let allowed = Set(ids)
        let chosen = Catalog.rows.filter { allowed.contains($0.id) && HardwareFit.supports($0.id) }
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
        case "replay-mute":
            break
        case "camera-pass":
            let note = currentId == "camera_front"
                ? "Immagine anteriore confermata"
                : "Immagine posteriore confermata · \(openedLenses.joined(separator: ", "))"
            settle(currentId, "pass", note)
        case "truedepth-retry":
            facePoints = []
            faceShot = nil
            faceArmed = false
            hint = "In alto a destra c'è la fotocamera a colori. Al centro i puntini TrueDepth. Gira la testa: devono girare con te."
            actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
            armFace()
        case "wifi-retry":
            readNetwork()
        case "bt-retry":
            startBluetooth()
        case "open-wifi":
            openRadio("WIFI")
        case "open-bluetooth":
            openRadio("Bluetooth")
        case "open-settings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case "nfc-retry":
            break
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
            if buttonBundle, act.status == "skip" {
                skipButtonBundle()
                return
            }
            settle(currentId, act.status, act.note)
        }
    }

    func onScenePhase(_ phase: ScenePhase) {
        guard phase == .active, !settled else { return }
        if currentId == "gps" {
            place.requestFix()
        }
        if keyOk { return }
        if currentId == "network" {
            readNetwork()
        } else if currentId == "bluetooth" {
            startBluetooth()
        }
    }

    private func openRadio(_ page: String) {
        openRadioCandidates(["App-Prefs:\(page)", "App-prefs:root=\(page)", "prefs:root=\(page)"], index: 0)
    }

    private func openRadioCandidates(_ raw: [String], index: Int) {
        if index >= raw.count {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        guard let url = URL(string: raw[index]) else {
            openRadioCandidates(raw, index: index + 1)
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.openRadioCandidates(raw, index: index + 1)
            }
        }
    }

    func skipCurrent() {
        if buttonBundle {
            skipButtonBundle()
            return
        }
        settle(currentId, "skip", "Non eseguito")
    }

    func failButton(_ id: String) {
        guard buttonBundle, !settled, !buttonFinishQueued else { return }
        switch id {
        case "volume_up":
            guard volumeUpMark.isEmpty else { return }
            volumeUpMark = "fail"
        case "volume_down":
            guard volumeDownMark.isEmpty else { return }
            volumeDownMark = "fail"
        case "power_button":
            guard powerMark.isEmpty else { return }
            powerMark = "fail"
        case "mute_switch":
            guard muteMark.isEmpty else { return }
            muteMark = "fail"
        default:
            return
        }
        finishButtonsIfReady()
    }

    func noteCameraPreview(_ view: PreviewView) {
        camera.holdPreview(view)
        let start = pendingCamera
        pendingCamera = nil
        start?()
    }

    func useLens(_ next: AVCaptureDevice.DeviceType) {
        lens = next
        lensName = Self.lensTitle(next)
        guard currentId == "camera_back" || currentId == "autofocus" else { return }
        if !openedLenses.contains(lensName) { openedLenses.append(lensName) }
        detail = openedLenses.joined(separator: " · ")
        pendingCamera = nil
        camera.start(front: false, lens: next, scanQR: currentId == "autofocus", onFocus: {}, onCode: { value, box in
            self.acceptQR(value, box)
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

    func notePencil() {
        guard still("stylus") else { return }
        settle("stylus", "pass", "Tratto della Apple Pencil ricevuto")
    }

    private func recordLocked() {
        guard showsLocked else { return }
        for row in lockedRows where !outcomes.contains(where: { $0.id == row.id }) {
            outcomes.append(Outcome(id: row.id, status: "absent", note: "Non su questo modello"))
        }
    }

    func settle(_ id: String, _ status: String, _ note: String) {
        guard !settled, currentId == id else { return }
        settled = true
        wave += 1
        outcomes.removeAll { $0.id == id }
        outcomes.append(Outcome(id: id, status: status, note: String(note.prefix(300))))
        actions = []
        cleanup(releaseCamera: true)
        goNext()
    }

    func shareText() -> String {
        let choice = Cosmetic.find(lookGrade)
        let model = Machine.described
        var lines = [
            "RefurbX Diagnostica",
            "\(model) · \(HardwareFit.systemName) \(UIDevice.current.systemVersion)",
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
        if showsLocked {
            for row in lockedRows {
                lines.append("\(row.title): \(statusIt("absent"))")
                lines.append("Non su questo modello")
            }
        }
        let text = lines.joined(separator: "\n")
        return text.count > 3500 ? String(text.prefix(3480)) + "…" : text
    }

    func prepareSheet() {
        guard phase == "report", let choice = Cosmetic.find(lookGrade), let when = testedAt else {
            sheetFile = nil
            return
        }
        var rows = activeRows.map { row in
            let item = outcomes.first { $0.id == row.id }
            return (group: row.group, title: row.title, status: item?.status ?? "skip", note: item?.note ?? "")
        }
        if showsLocked {
            rows += lockedRows.map { row in
                (group: "Non su questo modello", title: row.title, status: "absent", note: "Non su questo modello")
            }
        }
        sheetFile = SheetPDF.write(SheetFacts(
            grade: choice.id,
            title: choice.title,
            line: choice.line,
            when: when,
            device: "\(Machine.described) · \(HardwareFit.systemName) \(UIDevice.current.systemVersion)",
            cable: withCable,
            box: withBox,
            rows: rows
        ))
    }

    func sendToBench() {
        let raw = benchLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            benchState = "Scrivi il codice di sei lettere del banco."
            return
        }
        flushOutbox()
        benchSending = true
        benchState = "Cerco il banco…"
        Task {
            guard let target = await BenchLink.resolve(raw) else {
                self.benchSending = false
                self.benchState = "Non trovo il banco. Se compare il permesso Rete locale, accettalo e premi di nuovo Invia. Il telefono deve essere sulla stessa Wi-Fi del computer, oppure collegato col cavo."
                return
            }
            if let code = BenchLink.displayedCode(raw) {
                self.benchLink = code
                UserDefaults.standard.set(code, forKey: "refurbx.bench-link")
            }
            self.benchState = "Invio al banco…"
            let message = await BenchLink.deliver(target, payload: self.benchPayload())
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
                "os": "\(HardwareFit.systemName) \(UIDevice.current.systemVersion)",
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

    private func goNext() {
        guard index + 1 < plan.count else {
            recordLocked()
            if testedAt == nil { testedAt = Date() }
            phase = "report"
            currentId = "report"
            buttonBundle = false
            remember()
            prepareSheet()
            return
        }
        index += 1
        remember()
        enter()
    }

    private func enter() {
        let row = current
        if Self.buttonIds.contains(row.id), outcomes.contains(where: { $0.id == row.id }) {
            goNext()
            return
        }
        cleanup()
        currentId = row.id
        settled = false
        phase = "guide"
        hint = ""
        detail = ""
        actions = []
        showCamera = false
        qrCaught = false
        qrBox = .zero
        qrText = ""
        qrOnce = false
        fingers = 0
        proximityLit = false
        proximityCovered = false
        proximityArmed = false
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
        gyroRollDeg = 0
        gyroPitchDeg = 0
        gyroYawDeg = 0
        dotX = 0
        dotY = 0
        facePoints = []
        faceShot = nil
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
        volumeUpMark = ""
        volumeDownMark = ""
        powerMark = ""
        muteMark = ""
        muteWord = ""
        muteSawSound = false
        buttonFinishQueued = false
        buttonBundle = false
        lightLevel = 0
        lightWarm = 0
        lightFloor = 0
        lightCeil = 0
        lightBase = 0
        lightPeak = 0
        lightFrames = 0
        lightUsesFrames = false
        if row.id == "nfc" {
            armNfc()
        }
        buttonBundle = bundlesButtons(row.id)
        if Self.skipsGuide(row.id) {
            beginCurrent()
        }
        remember()
    }

    private func bundlesButtons(_ id: String) -> Bool {
        let present = plan.filter { Self.buttonIds.contains($0) }
        return present.count > 1 && present.contains(id)
    }

    private var bundledButtonIds: [String] {
        ["volume_up", "volume_down", "power_button", "mute_switch"].filter { plan.contains($0) }
    }

    private func buttonMark(_ id: String) -> String {
        switch id {
        case "volume_up": return volumeUpMark
        case "volume_down": return volumeDownMark
        case "power_button": return powerMark
        case "mute_switch": return muteMark
        default: return ""
        }
    }

    private func buttonsReady() -> Bool {
        let ids = bundledButtonIds
        guard ids.count > 1 else { return false }
        return ids.allSatisfy { id in
            let mark = buttonMark(id)
            return mark == "pass" || mark == "fail"
        }
    }

    private static let immediateIds: Set<String> = [
        "identity", "memory", "display", "network", "vibration",
        "flash", "bluetooth", "charging", "biometrics",
    ]

    private static func skipsGuide(_ id: String) -> Bool {
        guard id != "nfc" else { return false }
        return immediateIds.contains(id)
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
        case "display": hint = "Bianco, nero, rosso, verde, blu, giallo e grigio partono da soli. Poi conferma se lo schermo è uniforme."
        case "touch":
            hint = "Trascina il dito su tutte le celle, anche i bordi. Una cella spenta è una zona morta."
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
        case "volume_up":
            if buttonBundle { startButtonBundle() } else { watchVolume(up: true) }
        case "volume_down":
            if buttonBundle { startButtonBundle() } else { watchVolume(up: false) }
        case "power_button":
            if buttonBundle { startButtonBundle() } else { startPower() }
        case "mute_switch":
            if buttonBundle { startButtonBundle() } else { startMute() }
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
            startStylus()
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
        let os = "\(HardwareFit.systemName) \(UIDevice.current.systemVersion)"
        let note = "\(Machine.described) · \(os)"
        hint = os
        if Machine.isDuo {
            detail = "iPhone Duo\nCodice di fabbrica \(code)\nSchermo esterno e schermo interno"
        } else {
            detail = name == nil ? "Codice di fabbrica \(code)" : "\(name ?? "")\nCodice di fabbrica \(code)"
        }
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
                self.hint = "Il telefono è sul Wi-Fi. Conferma se è la rete."
                self.actions = [
                    Act(label: "Wi-Fi collegato", status: "pass", note: "Wi-Fi collegato"),
                    Act(label: "Non è collegato", status: "fail", note: "Wi-Fi non collegato"),
                    Act(label: "Salta", status: "skip", note: "Non eseguito"),
                ]
            } else {
                self.keyOk = false
                self.detail = "Wi-Fi non collegato"
                self.hint = "Apri il Wi-Fi, accendilo e torna qui: il controllo riparte da solo."
                self.actions = [
                    Act(label: "Apri Wi-Fi", status: "open-wifi", note: ""),
                    Act(label: "Riprova", status: "wifi-retry", note: ""),
                    Act(label: "Salta", status: "skip", note: "Non eseguito"),
                ]
            }
        }
    }

    private func startNfc() {
        hint = "Premi Apri lettore tag. Si apre la finestra di Apple dal basso. Tieni la scheda ferma sul retro, in alto."
        detail = "Lettore tag"
        actions = nfcActions()
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
            self.phase = "run"
            self.hint = status == "cancel"
                ? "Lettura chiusa. Premi Apri lettore tag e tieni la scheda ferma sul retro, in alto."
                : (note.isEmpty ? "La finestra NFC si è chiusa prima del tag. Premi Apri lettore tag." : note)
            self.detail = "Lettore chiuso"
            self.actions = self.nfcActions()
        }
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
            self.dotY = CGFloat(max(-1, min(1, -y)))
            if x < -0.55 { self.edgeLeft = true }
            if x > 0.55 { self.edgeRight = true }
            if y > 0.55 { self.edgeTop = true }
            if y < -0.55 { self.edgeBottom = true }
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
        hint = "Il cerchio segue il telefono. Tienilo fermo un secondo, inclinalo di lato e in avanti, poi giralo. Si accendono le quattro righe."
        actions = [
            Act(label: "Non ruota", status: "fail", note: "Il giroscopio non cambia"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        var originRoll = 0.0
        var originPitch = 0.0
        var haveOrigin = false
        var calmSince: TimeInterval?
        var turned = 0.0
        var lastTime: TimeInterval?
        let started = motion.attitude { [weak self] roll, pitch, spin, verticalRate, time in
            guard let self, self.still("gyroscope") else { return }
            if !haveOrigin {
                haveOrigin = true
                originRoll = roll
                originPitch = pitch
            }
            let rollShown = ((roll - originRoll) * 180 / .pi).rounded()
            let pitchShown = ((pitch - originPitch) * 180 / .pi).rounded()
            self.gyroRollDeg = rollShown
            self.gyroPitchDeg = pitchShown
            if let previous = lastTime {
                let dt = min(0.2, max(0, time - previous))
                turned += verticalRate * dt
            }
            lastTime = time
            let yawShown = (turned * 180 / .pi).rounded()
            self.gyroYawDeg = yawShown
            let stillLimit = calmSince == nil ? 0.42 : 0.65
            if spin < stillLimit {
                if calmSince == nil { calmSince = time }
                if let began = calmSince, time - began >= 1 {
                    self.gyroRest = true
                }
            } else {
                calmSince = nil
            }
            if abs(rollShown) >= 25 { self.gyroTilt = true }
            if abs(pitchShown) >= 25 { self.gyroPitch = true }
            if abs(yawShown) >= 35 { self.gyroYaw = true }
            let done = [self.gyroRest, self.gyroTilt, self.gyroPitch, self.gyroYaw].filter { $0 }.count
            self.detail = "\(done) di 4"
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
            Act(label: "Nessun fix", status: "skip", note: "Nessun fix"),
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
        volumeWantsUp = up
        keyOk = false
        hint = up
            ? "Premi volume su. Compare la spunta appena il tasto risponde."
            : "Premi volume giù. Compare la spunta appena il tasto risponde."
        detail = up ? "In attesa di volume +" : "In attesa di volume −"
        actions = [
            Act(label: "Non risponde", status: "fail", note: up ? "Volume su fermo" : "Volume giù fermo"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        armVolumeWatch(target: 0.5)
    }

    private func startButtonBundle() {
        volumeUpMark = ""
        volumeDownMark = ""
        powerMark = ""
        muteMark = ""
        muteWord = ""
        muteSawSound = false
        buttonFinishQueued = false
        keyOk = false
        let side = HardwareFit.pad ? "il tasto in alto" : "il tasto laterale"
        var parts: [String] = []
        if plan.contains("volume_up") || plan.contains("volume_down") {
            parts.append("Premi volume + e volume −.")
        }
        if plan.contains("power_button") {
            parts.append("Per l'accensione tieni premuti insieme \(side) e volume +. Lo schermo resta acceso e compare la V.")
        }
        if plan.contains("mute_switch") {
            let mute = HardwareFit.usesActionButton
                ? "Poi premi il tasto Azione fino a Silenzioso."
                : "Poi sposta l'interruttore fino a Silenzioso."
            parts.append(mute)
        }
        parts.append("Se uno non va, segna Non va solo su quella riga.")
        hint = parts.joined(separator: " ")
        detail = ""
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        if plan.contains("volume_up") || plan.contains("volume_down") {
            armVolumeWatch(target: 0.5)
        }
        if plan.contains("mute_switch") {
            armMuteWatch()
        }
        if plan.contains("power_button") {
            watch(UIApplication.userDidTakeScreenshotNotification) { [weak self] in
                guard let self, self.buttonBundle, self.powerMark.isEmpty, !self.buttonFinishQueued else { return }
                self.powerMark = "pass"
                self.finishButtonsIfReady()
            }
        }
    }

    private func armVolumeWatch(target: Float) {
        activateVolumeSession()
        volumeTimer?.invalidate()
        volumeTimer = nil
        volumeObservation?.invalidate()
        volumeObservation = nil
        volumeToken += 1
        let token = volumeToken
        volumeTarget = target
        volumeArmed = false
        volumeDidSet = false
        volumeStable = 0
        volumeWait = 0
        volumeLast = -1
        volumePrevious = -1
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.volumeToken == token else { return }
                self.noteVolume(AVAudioSession.sharedInstance().outputVolume)
            }
        }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.volumeToken == token else { return }
                self.pollVolume()
            }
        }
        volumeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        mountVolumeHost()
        later(0.05) {
            guard self.volumeToken == token else { return }
            self.pollVolume()
        }
    }

    func holdVolumeView(_ view: MPVolumeView?) {
        guard let view else { return }
        let watching = buttonBundle || currentId == "volume_up" || currentId == "volume_down"
        guard watching else { return }
        view.isHidden = false
        view.alpha = 0.02
        view.layoutIfNeeded()
        volumeCatcher = view
        guard !volumeArmed, !volumeDidSet, !volumeSliders().isEmpty else { return }
        if !buttonBundle, keyOk { return }
        pollVolume()
    }

    private func activateVolumeSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
    }

    private func mountVolumeHost() {
        volumeHost?.removeFromSuperview()
        volumeHost = nil
        let host = MPVolumeView(frame: CGRect(x: 16, y: 16, width: 200, height: 36))
        host.showsRouteButton = false
        host.isHidden = false
        host.alpha = 0.02
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = false
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow)
            ?? windows.first(where: { $0.windowScene?.activationState == .foregroundActive })
            ?? windows.first else { return }
        window.addSubview(host)
        host.layoutIfNeeded()
        volumeHost = host
    }

    private func volumeSliders() -> [UISlider] {
        var found: [UISlider] = []
        for host in [volumeCatcher, volumeHost].compactMap({ $0 }) {
            found.append(contentsOf: sliders(in: host))
        }
        return found
    }

    private func sliders(in host: MPVolumeView?) -> [UISlider] {
        guard let host else { return [] }
        var found: [UISlider] = []
        for view in host.subviews {
            if let slider = view as? UISlider {
                found.append(slider)
                continue
            }
            found.append(contentsOf: view.subviews.compactMap { $0 as? UISlider })
        }
        return found
    }

    private func applyVolume(_ target: Float) {
        volumeArmed = false
        let clamped = min(1, max(0, target))
        for slider in volumeSliders() {
            slider.setValue(clamped, animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }

    private func volumeSessionLive() -> Bool {
        if buttonBundle { return !settled }
        let id = volumeWantsUp ? "volume_up" : "volume_down"
        return still(id) && !keyOk
    }

    private func pollVolume() {
        guard volumeSessionLive() else { return }
        let now = AVAudioSession.sharedInstance().outputVolume
        if volumeArmed {
            noteVolume(now)
            return
        }
        let target = volumeTarget
        if !volumeDidSet {
            let sliders = volumeSliders()
            guard !sliders.isEmpty else {
                volumeWait += 1
                if volumeWait >= 16 {
                    armVolume(now)
                }
                return
            }
            applyVolume(target)
            volumeDidSet = true
            volumeWait = 0
            volumeStable = 0
            volumeLast = -1
            return
        }
        if volumeLast >= 0, abs(now - volumeLast) < 0.008 {
            volumeStable += 1
        } else {
            volumeStable = 0
        }
        volumeLast = now
        volumeWait += 1
        let close = abs(now - target) <= 0.06
        if close && volumeStable >= 2 {
            armVolume(now)
            return
        }
        if volumeSliders().isEmpty && volumeStable >= 2 {
            armVolume(now)
            return
        }
        if volumeWait >= 12 && volumeStable >= 2 {
            armVolume(now)
        }
    }

    private func armVolume(_ now: Float) {
        guard volumeSessionLive(), !volumeArmed else { return }
        volumePrevious = now
        volumeArmed = true
    }

    private func noteVolume(_ now: Float) {
        guard volumeArmed, volumePrevious >= 0, volumeSessionLive() else { return }
        let delta = now - volumePrevious
        if buttonBundle {
            guard abs(delta) >= 0.02, !buttonFinishQueued else { return }
            volumePrevious = now
            if delta >= 0.02, volumeUpMark.isEmpty { volumeUpMark = "pass" }
            if delta <= -0.02, volumeDownMark.isEmpty { volumeDownMark = "pass" }
            finishButtonsIfReady()
            return
        }
        let id = volumeWantsUp ? "volume_up" : "volume_down"
        let hit = volumeWantsUp ? delta >= 0.02 : delta <= -0.02
        guard hit else { return }
        markKey(id, note: volumeWantsUp ? "Volume su ricevuto" : "Volume giù ricevuto")
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
        keyOk = false
        let side = HardwareFit.pad ? "il tasto in alto" : "il tasto laterale"
        hint = "Tieni premuti insieme \(side) e volume +. Lo schermo resta acceso: appena compare lo screenshot, il test è ok."
        detail = "In attesa dello screenshot"
        watch(UIApplication.userDidTakeScreenshotNotification) { [weak self] in
            self?.markKey("power_button", note: "Screenshot con accensione e volume +")
        }
        actions = [
            Act(label: "Non risponde", status: "fail", note: "Il tasto laterale non fa lo screenshot"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
    }

    private func startMute() {
        guard HardwareFit.supports("mute_switch") else {
            settle("mute_switch", "absent", "Questo modello non ha il controllo del silenzioso")
            return
        }
        keyOk = false
        muteSawSound = false
        let action = HardwareFit.usesActionButton
        hint = action
            ? "Premi il tasto Azione finché in grande compare Silenzioso. L'app non emette suoni."
            : "Sposta l'interruttore finché in grande compare Silenzioso. L'app non emette suoni."
        detail = "In attesa"
        actions = [
            Act(label: "Non commuta", status: "fail", note: action ? "Il tasto Azione non mette in silenzioso" : "L'interruttore non mette in silenzioso"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        armMuteWatch()
    }

    private func armMuteWatch() {
        muteToken += 1
        let token = muteToken
        muteSawSound = false
        let ok = ringer.start { [weak self] silent in
            guard let self, self.muteToken == token, !self.settled else { return }
            let word = silent ? "Silenzioso" : "Suono"
            if self.buttonBundle {
                self.muteWord = word
                if !silent {
                    self.muteSawSound = true
                    return
                }
                guard self.muteSawSound, self.muteMark.isEmpty, !self.buttonFinishQueued else {
                    if !self.muteSawSound, self.muteMark.isEmpty, !self.buttonFinishQueued {
                        self.hint = "Ora è silenzioso. Passa a Suono e poi di nuovo a Silenzioso: compare la V."
                    }
                    return
                }
                self.muteMark = "pass"
                self.finishButtonsIfReady()
                return
            }
            guard self.still("mute_switch"), !self.keyOk else { return }
            self.detail = word
            if !silent {
                self.muteSawSound = true
                return
            }
            guard self.muteSawSound else { return }
            self.markKey("mute_switch", note: "Passato in silenzioso")
        }
        if !ok {
            hint = buttonBundle
                ? "Non riesco a leggere il silenzioso. Segna Non va su quella riga, oppure salta."
                : "Non riesco a leggere il silenzioso. Segna che non commuta, oppure salta."
        }
    }

    private func finishButtonsIfReady() {
        guard buttonBundle, !settled, !buttonFinishQueued, buttonsReady() else { return }
        buttonFinishQueued = true
        later(0.45) { self.commitButtonBundle() }
    }

    private func commitButtonBundle() {
        guard buttonBundle, !settled, buttonsReady() else { return }
        settled = true
        wave += 1
        if plan.contains("volume_up") {
            storeButton("volume_up", volumeUpMark, pass: "Volume su ricevuto", fail: "Volume su fermo")
        }
        if plan.contains("volume_down") {
            storeButton("volume_down", volumeDownMark, pass: "Volume giù ricevuto", fail: "Volume giù fermo")
        }
        if plan.contains("power_button") {
            storeButton("power_button", powerMark, pass: "Screenshot con accensione e volume +", fail: "Il tasto laterale non fa lo screenshot")
        }
        if plan.contains("mute_switch") {
            let muteFail = HardwareFit.usesActionButton
                ? "Il tasto Azione non mette in silenzioso"
                : "L'interruttore non mette in silenzioso"
            storeButton("mute_switch", muteMark, pass: "Passato in silenzioso", fail: muteFail)
        }
        actions = []
        cleanup()
        remember()
        DispatchQueue.main.async { self.goNext() }
    }

    private func skipButtonBundle() {
        guard buttonBundle, !settled else { return }
        settled = true
        wave += 1
        for id in bundledButtonIds {
            outcomes.removeAll { $0.id == id }
            outcomes.append(Outcome(id: id, status: "skip", note: "Non eseguito"))
        }
        actions = []
        cleanup()
        remember()
        DispatchQueue.main.async { self.goNext() }
    }

    private func storeButton(_ id: String, _ status: String, pass: String, fail: String) {
        let note = status == "pass" ? pass : fail
        outcomes.removeAll { $0.id == id }
        outcomes.append(Outcome(id: id, status: status, note: note))
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
            return
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
        hint = Machine.isDuo
            ? "Appoggia il dito sul tasto laterale. Il Duo legge l'impronta, non il volto."
            : "Usa il volto o l'impronta. Se la richiesta non compare, salta."
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        face.run { [weak self] status, note in
            self?.settle("biometrics", status, note)
            return
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
                : "Apri il Bluetooth, accendilo e torna qui: il controllo riparte da solo."
            self.actions = [
                Act(label: "Riprova", status: "bt-retry", note: ""),
                Act(label: denied ? "Apri Impostazioni" : "Apri Bluetooth", status: denied ? "open-settings" : "open-bluetooth", note: ""),
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
                self.pendingCamera = { [weak self] in
                    guard let self, self.still(id) else { return }
                    self.camera.start(front: front, lens: self.lens, onFocus: {}, onRunning: {
                        guard self.still(id) else { return }
                        self.hint = front
                            ? (Machine.isDuo
                                ? "Chiuso: camera esterna. Aperto: camera sotto il display interno. Conferma solo se entrambe sono pulite."
                                : "Il volto deve essere in verticale. Conferma solo se l'immagine è pulita e dritta.")
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
        qrOnce = false
        qrCaught = false
        qrBox = .zero
        qrText = ""
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.still("autofocus") else { return }
                guard granted else {
                    self.settle("autofocus", "skip", "Permesso fotocamera negato")
                    return
                }
                self.showCamera = true
                self.pendingCamera = { [weak self] in
                    guard let self, self.still("autofocus") else { return }
                    self.camera.start(front: false, scanQR: true, onFocus: {}, onCode: { value, box in
                        self.acceptQR(value, box)
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
    }

    private func acceptQR(_ value: String, _ box: CGRect) {
        guard still("autofocus"), !qrOnce else { return }
        qrOnce = true
        let short = value.count > 80 ? String(value.prefix(80)) + "…" : value
        qrBox = box.integral
        qrText = short
        qrCaught = true
        detail = short
        hint = "QR letto. Resta inquadrato un attimo."
        later(1.4) {
            guard self.still("autofocus") else { return }
            self.settle("autofocus", "pass", "QR letto: \(short)")
        }
    }

    private func startTrueDepth() {
        guard CameraSession.hasTrueDepth() else {
            settle("truedepth", "absent", "Niente fotocamera TrueDepth")
            return
        }
        hint = "In alto a destra c'è la fotocamera a colori, come in una videochiamata. Al centro i puntini bianchi sono il volto del sensore TrueDepth. Gira la testa: devono girare con te. L'infrarosso resta in iOS."
        actions = [
            Act(label: "I puntini girano", status: "pass", note: "TrueDepth ha seguito la testa. L'immagine a infrarossi resta nel sistema."),
            Act(label: "Non seguono la testa", status: "fail", note: "TrueDepth presente, la testa non è seguita"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        armFace()
    }

    private func armFace() {
        faceTrack.onPicture = { [weak self] points, shot in
            guard let self, self.still("truedepth") else { return }
            if let shot { self.faceShot = shot }
            guard points.count > 40 else { return }
            self.facePoints = points
            self.faceArmed = true
            self.detail = "Volto seguito. La finestra piccola è la fotocamera, i puntini sono il TrueDepth."
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
        lightBase = 0
        lightPeak = 0
        lightFrames = 0
        lightUsesFrames = false
        showCamera = false
        lightLevel = 0.25
        hint = Machine.isDuo
            ? "Il Duo ha quattro sensori di luce. Avvicina una luce finché la barra arriva al 100%."
            : "Metti una luce sul sensore davanti, in alto, finché la barra arriva al 100%. Non è la fotocamera dietro."
        detail = "Luce davanti"
        actions = [
            Act(label: "Non reagisce", status: "fail", note: "Il sensore davanti non reagisce"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        camera.start(front: true, onFocus: {}, onRunning: {}, onError: { [weak self] _ in
            self?.pollLight()
            return
        }, onMeter: { [weak self] raw in
            self?.lightUsesFrames = true
            self?.noteAmbient(raw)
            return
        })
        later(1.5) {
            guard self.still("light"), self.lightFrames == 0 else { return }
            self.pollLight()
        }
    }

    private func pollLight() {
        later(0.05) {
            guard self.still("light"), !self.lightUsesFrames else { return }
            if let raw = self.camera.ambientLevel() {
                self.noteAmbient(raw)
            }
            guard self.still("light"), !self.lightUsesFrames else { return }
            self.pollLight()
        }
    }

    private func noteAmbient(_ raw: Double) {
        guard raw.isFinite, raw > 0 else { return }
        lightFrames += 1
        if lightWarm < 6 {
            lightBase = lightWarm == 0 ? raw : (lightBase * 0.65 + raw * 0.35)
            lightWarm += 1
            lightLevel = 0.16
            detail = "Luce davanti 16%"
            return
        }
        let ratio = raw / max(lightBase, 0.000_1)
        let target = min(1, max(0, 0.16 + (ratio - 1) * 0.30))
        if target + 0.03 < lightLevel {
            lightLevel = target
        } else {
            lightLevel = lightLevel * 0.35 + target * 0.65
        }
        detail = "Luce davanti \(Int((lightLevel * 100).rounded()))%"
        if target >= 1 || lightLevel >= 0.995 {
            lightLevel = 1
            detail = "Luce davanti 100%"
            settle("light", "pass", "La luce davanti è arrivata al 100%")
        }
    }

    private func watchProximity() {
        proximityLit = false
        proximityCovered = false
        proximityArmed = false
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        try? session.setActive(true)
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        guard device.isProximityMonitoringEnabled else {
            releaseProximity()
            settle("proximity", "absent", "Niente sensore di prossimità")
            return
        }
        hint = "Copri il sensore in alto, vicino alla capsula, poi allontana la mano. Lo schermo può spegnersi solo mentre è coperto."
        detail = "Avvicina la mano"
        actions = [
            Act(label: "Non reagisce", status: "fail", note: "Il sensore di prossimità non reagisce"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
        watch(UIDevice.proximityStateDidChangeNotification) { [weak self] in
            guard let self, self.proximityArmed else { return }
            self.noteProximity(UIDevice.current.proximityState)
        }
        later(0.45) {
            guard self.still("proximity") else { return }
            self.proximityArmed = true
            if UIDevice.current.proximityState {
                self.proximityLit = true
                self.proximityCovered = true
                self.detail = "Coperto. Allontana la mano."
            } else {
                self.detail = "Avvicina la mano al sensore"
            }
        }
    }

    private func noteProximity(_ near: Bool) {
        guard still("proximity"), proximityArmed else { return }
        if near {
            proximityLit = true
            proximityCovered = true
            detail = "Coperto. Allontana la mano."
            return
        }
        guard proximityCovered else {
            proximityLit = false
            detail = "Avvicina la mano al sensore"
            return
        }
        proximityArmed = false
        releaseProximity()
        later(0.35) {
            guard self.still("proximity") else { return }
            self.settle("proximity", "pass", "Sensore coperto e poi libero")
        }
    }

    private func releaseProximity() {
        UIDevice.current.isProximityMonitoringEnabled = false
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    private func startCompass() {
        hint = "Tienilo in piano. Gira piano finché si accendono tutti gli 8 punti. Il test resta qui finché il giro non è completo."
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
            let degrees = Int(heading.magneticHeading.rounded()) % 360
            self.detail = String(format: "%03d° · %@ · %d di 8", degrees, Self.cardinal(heading.magneticHeading), self.compassMarks.count)
            if self.compassMarks.count >= 8 {
                self.settle("compass", "pass", "Giro completo, 8 direzioni")
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
        hint = HardwareFit.pad
            ? "Collega le cuffie se le hai. Se non le hai, salta."
            : "Collega cuffie Bluetooth o un adattatore. L'iPhone non ha il jack. Se non ne hai, salta."
        watch(AVAudioSession.routeChangeNotification) { [weak self] in
            if self?.headphonesNow() == true { self?.settle("headphones", "pass", "Cuffia collegata") }
        }
    }

    private func headphonesNow() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { port in
            port.portType == .headphones || port.portType == .bluetoothA2DP || port.portType == .bluetoothHFP || port.portType == .bluetoothLE || port.portType == .usbAudio
        }
    }

    private func startStylus() {
        guard HardwareFit.acceptsPencil else {
            settle("stylus", "absent", "Questo modello non riceve la penna")
            return
        }
        hint = "Scrivi con la Apple Pencil. Il dito non conta."
        actions = [
            Act(label: "Non ho la penna", status: "skip", note: "Penna non provata"),
            Act(label: "Salta", status: "skip", note: "Non eseguito"),
        ]
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
        showCamera = false
        face.cancel()
        faceTrack.stop()
        tone.stop()
        mic.stop()
        motion.stop()
        ringer.stop()
        place.stop()
        radio.stop()
        depth.stop()
        tags.stop()
        playback?.stop()
        playback = nil
        pendingCamera = nil
        if releaseCamera {
            camera.setTorch(false) { _ in }
            camera.stop()
        }
        volumeTimer?.invalidate()
        volumeTimer = nil
        volumeObservation?.invalidate()
        volumeObservation = nil
        volumeHost?.removeFromSuperview()
        volumeHost = nil
        volumeCatcher = nil
        volumeArmed = false
        volumePrevious = -1
        volumeDidSet = false
        volumeToken += 1
        muteToken += 1
        releaseProximity()
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
    }

    private static func cardinal(_ heading: Double) -> String {
        let names = ["Nord", "Nord-est", "Est", "Sud-est", "Sud", "Sud-ovest", "Ovest", "Nord-ovest"]
        let turn = heading.truncatingRemainder(dividingBy: 360)
        let positive = turn < 0 ? turn + 360 : turn
        let index = Int((positive + 22.5) / 45) % 8
        return names[index]
    }

    private static func micPlace(_ source: AVAudioSessionDataSourceDescription) -> (title: String, spot: String) {
        guard let seat = AudioRoute.micSeat(for: source) else {
            return (source.dataSourceName, "")
        }
        return (seat.title, seat.spot)
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
    private static let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    private static let hostKey = "refurbx.bench-host"

    static func displayedCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.host != nil, let last = url.path.split(separator: "/").last {
            let code = String(last).uppercased()
            if isCode(code) { return code }
        }
        let compact = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        return isCode(compact) ? compact : nil
    }

    @discardableResult
    static func remember(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, let scheme = url.scheme, scheme == "http" || scheme == "https" else { return false }
        guard displayedCode(trimmed) != nil else { return false }
        var base = "\(scheme)://\(host)"
        if let port = url.port { base += ":\(port)" }
        UserDefaults.standard.set(base, forKey: hostKey)
        return true
    }

    static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, let scheme = url.scheme, scheme == "http" || scheme == "https" else { return nil }
        guard let code = displayedCode(trimmed) else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.port = url.port
        parts.path = "/api/intake/\(code)"
        return parts.url
    }

    static func resolve(_ raw: String) async -> URL? {
        if let direct = parse(raw) {
            remember(raw)
            return direct
        }
        guard let code = displayedCode(raw) else { return nil }
        if let saved = UserDefaults.standard.string(forKey: hostKey), let intake = intakeURL(saved, code), await reachable(intake) {
            return intake
        }
        return await hearBench(code)
    }

    private static func isCode(_ value: String) -> Bool {
        value.count == 6 && value.allSatisfy { alphabet.contains($0) }
    }

    private static func intakeURL(_ base: String, _ code: String) -> URL? {
        guard var parts = URLComponents(string: base) else { return nil }
        parts.path = "/api/intake/\(code)"
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    private static func reachable(_ intake: URL, timeout: TimeInterval = 4) async -> Bool {
        guard var parts = URLComponents(url: intake, resolvingAgainstBaseURL: false) else { return false }
        let code = parts.path.split(separator: "/").last.map(String.init) ?? ""
        parts.path = "/api/join/\(code)"
        guard let url = parts.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    private struct Heard {
        var publicBase: String?
        var lanBase: String?
    }

    private static func hearBench(_ code: String) async -> URL? {
        let packets = await listenBeacons(seconds: 4)
        for packet in packets {
            if let base = packet.publicBase, let intake = intakeURL(base, code), await reachable(intake) {
                UserDefaults.standard.set(base, forKey: hostKey)
                return intake
            }
            if let base = packet.lanBase, let intake = intakeURL(base, code), await reachable(intake, timeout: 1.2) {
                UserDefaults.standard.set(base, forKey: hostKey)
                return intake
            }
        }
        return nil
    }

    private static func listenBeacons(seconds: TimeInterval) async -> [Heard] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: collectBeacons(seconds: seconds))
            }
        }
    }

    private static func collectBeacons(seconds: TimeInterval) -> [Heard] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if fd < 0 { return [] }
        defer { close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(43721).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 { return [] }
        var wait = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        let deadline = Date().addingTimeInterval(seconds)
        var heard: [Heard] = []
        var seen = Set<String>()
        while Date() < deadline {
            var buf = [UInt8](repeating: 0, count: 512)
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buf.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, raw.baseAddress, raw.count, 0, $0, &fromLen)
                    }
                }
            }
            if count <= 0 { continue }
            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let named = withUnsafePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, fromLen, &hostBuf, socklen_t(hostBuf.count), nil, 0, NI_NUMERICHOST)
                }
            }
            let source = named == 0 ? String(cString: hostBuf) : ""
            let text = String(bytes: buf.prefix(Int(count)), encoding: .utf8) ?? ""
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3, parts[0] == "REFURBX" else { continue }
                let key = source + "|" + parts[1] + "|" + parts[2]
                if seen.contains(key) { continue }
                seen.insert(key)
                heard.append(Heard(publicBase: cleanPublic(parts[1]), lanBase: cleanLan(parts[2], source: source)))
            }
        }
        return heard
    }

    private static func cleanPublic(_ raw: String) -> String? {
        guard let url = URL(string: raw), url.scheme == "https", let host = url.host else { return nil }
        let known = host == "refurbx.eu" || host.hasSuffix(".refurbx.eu") || host.hasSuffix(".trycloudflare.com")
        guard known else { return nil }
        return "https://\(host)"
    }

    private static func cleanLan(_ raw: String, source: String) -> String? {
        guard let url = URL(string: raw), url.scheme == "http", let host = url.host, host == source, privateHost(host) else { return nil }
        let port = url.port ?? 43123
        guard port == 43123 else { return nil }
        return "http://\(host):\(port)"
    }

    private static func privateHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        return parts[0] == 172 && (16...31).contains(parts[1])
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

