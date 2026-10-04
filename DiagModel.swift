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

    let camera = CameraSession()
    private let tone = TonePlayer()
    private let mic = MicProbe()
    private let motion = MotionProbe()
    private let place = PlaceProbe()
    private let radio = RadioProbe()
    private let depth = DepthProbe()
    private let face = FaceProbe()
    private var settled = false
    private var wave = 0
    private var sawBackground = false
    private var armPower = false
    private var volumeStart: Float = -1
    private var volumeTimer: Timer?
    private var playback: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []

    func begin() {
        index = 0
        enter()
    }

    func onAction(_ act: Act) {
        switch act.status {
        case "replay-speaker":
            tone.play(earpiece: false)
        case "replay-ear":
            tone.play(earpiece: true)
        case "replay-vibration":
            vibratePhone()
        case "replay-mic":
            playback?.currentTime = 0
            playback?.play()
        default:
            settle(currentId, act.status, act.note)
        }
    }

    func onScenePhase(_ phase: ScenePhase) {
        guard armPower, currentId == "power_button" else { return }
        if phase == .background || phase == .inactive { sawBackground = true }
        if phase == .active && sawBackground {
            armPower = false
            settle("power_button", "pass", "Schermo spento e riacceso")
        }
    }

    func touchProgress(_ done: Int, _ total: Int) {
        detail = "\(done) di \(total)"
    }

    func settle(_ id: String, _ status: String, _ note: String) {
        guard !settled, currentId == id else { return }
        settled = true
        wave += 1
        outcomes.removeAll { $0.id == id }
        outcomes.append(Outcome(id: id, status: status, note: String(note.prefix(300))))
        cleanup()
        guard index + 1 < Catalog.rows.count else {
            phase = "report"
            currentId = "report"
            return
        }
        index += 1
        DispatchQueue.main.async { self.enter() }
    }

    func shareText() -> String {
        let mark = gradeOf(outcomes)
        var lines = [
            "RefurbX Diagnostics",
            "\(UIDevice.current.model) \(UIDevice.current.systemVersion)",
            "Grado \(mark.letter) · \(mark.label) · \(mark.score)/100",
            "",
        ]
        for row in Catalog.rows {
            let item = outcomes.first { $0.id == row.id }
            let status = item?.status ?? "skip"
            lines.append("\(row.title): \(statusIt(status))")
            if let note = item?.note, !note.isEmpty { lines.append(note) }
        }
        let text = lines.joined(separator: "\n")
        return text.count > 3500 ? String(text.prefix(3480)) + "…" : text
    }

    private func enter() {
        cleanup()
        let row = Catalog.rows[index]
        currentId = row.id
        settled = false
        phase = "run"
        hint = ""
        detail = ""
        actions = []
        showCamera = false
        fingers = 0
        switch row.id {
        case "identity": readIdentity()
        case "battery": readBattery()
        case "network": readNetwork()
        case "display": hint = "Tocca lo schermo per passare di colore."
        case "touch":
            hint = "Trascina il dito su tutte le celle. Una zona che resta scura è morta."
            actions = [Act(label: "Zona morta", status: "fail", note: "Area del touch non risponde"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        case "multitouch":
            hint = "Appoggia almeno due dita insieme."
            actions = [Act(label: "Non legge due dita", status: "fail", note: "Multi-touch assente"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        case "speaker":
            tone.play(earpiece: false)
            hint = "Ascolta la nota dall'altoparlante in basso."
            actions = confirm("Si sente chiara", "Altoparlante confermato", "Distorta o muta", "Altoparlante non accettato", replay: "replay-speaker")
        case "microphone": afterCamera { self.recordMic() }
        case "vibration":
            vibratePhone()
            hint = "Deve vibrare adesso."
            actions = confirm("L'ho sentita", "Vibrazione sentita", "Non vibra", "Nessuna vibrazione", replay: "replay-vibration")
        case "earpiece":
            tone.play(earpiece: true)
            hint = "Avvicina l'orecchio alla capsula in alto."
            actions = confirm("Si sente in capsula", "Capsula confermata", "Non si sente", "Capsula muta", replay: "replay-ear")
        case "camera_back": openCamera(front: false)
        case "camera_front": openCamera(front: true)
        case "accelerometer": watchMotion(gyro: false, id: "accelerometer", absent: "Niente accelerometro", prompt: "Inclina il telefono.")
        case "gyroscope": watchMotion(gyro: true, id: "gyroscope", absent: "Niente giroscopio", prompt: "Ruota il telefono di scatto.")
        case "gps": startGps()
        case "volume_up", "volume_down": watchVolume(up: row.id == "volume_up")
        case "power_button":
            armPower = true
            sawBackground = false
            hint = "Premi il tasto di accensione. Lo schermo si spegne: riaccendilo."
            actions = [Act(label: "Non risponde", status: "fail", note: "Tasto di accensione fermo"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        case "mute_switch":
            if let major = Machine.iphoneMajor, major >= 16 {
                show("Questo iPhone ha il tasto Azione, non l'interruttore del silenzioso")
                settleSoon("mute_switch", "absent", "Questo iPhone ha il tasto Azione, non l'interruttore del silenzioso")
            } else {
                show("iOS non consegna lo stato dell'interruttore silenzioso alle app")
                settleSoon("mute_switch", "absent", "iOS non consegna lo stato dell'interruttore silenzioso alle app")
            }
        case "charging": watchCharge()
        case "biometrics":
            hint = "Usa il volto o l'impronta. Se non compare nulla, salta."
            actions = [Act(label: "Salta", status: "skip", note: "Riconoscimento non eseguito")]
            face.run { [weak self] status, note in self?.settle("biometrics", status, note) }
        case "bluetooth": startBluetooth()
        case "nfc":
            show("La lettura NFC non è in questa versione.")
            settleSoon("nfc", "skip", "La lettura NFC si attiva dal portale Apple. Senza quel permesso la salto.")
        case "flash": startFlash()
        case "autofocus": startAutofocus()
        case "truedepth":
            if CameraSession.hasTrueDepth() {
                show("Camera TrueDepth presente")
                settleSoon("truedepth", "pass", "Camera TrueDepth presente. L'immagine a infrarossi resta nel sistema.")
            } else {
                show("Niente camera TrueDepth")
                settleSoon("truedepth", "absent", "Niente camera TrueDepth")
            }
        case "lidar": startDepth()
        case "memory":
            let note = DiskProbe.note()
            show(note)
            settleSoon("memory", "pass", note)
        case "proximity": watchProximity()
        case "light":
            show("iOS non consegna il sensore di luce alle app")
            settleSoon("light", "absent", "iOS non consegna il sensore di luce alle app")
        case "compass": startCompass()
        case "headphones": watchHeadphones()
        case "call":
            tone.play(earpiece: true)
            hint = "Tieni il telefono come in chiamata. La nota deve uscire dalla capsula."
            actions = confirm("Si sente in capsula", "Capsula di chiamata confermata", "Non si sente", "Chiamata non udibile", replay: "replay-ear")
        case "force":
            show("Questo schermo non misura la pressione")
            settleSoon("force", "absent", "Questo schermo non misura la pressione")
        case "stylus":
            show("L'iPhone non ha la penna")
            settleSoon("stylus", "absent", "Nessun tratto di penna")
        default:
            settle(row.id, "skip", "Test non eseguito")
        }
    }

    private func show(_ note: String) {
        detail = note
        hint = "Lettura dal telefono"
    }

    private func confirm(_ pass: String, _ passNote: String, _ fail: String, _ failNote: String, replay: String?) -> [Act] {
        var items = [Act(label: pass, status: "pass", note: passNote), Act(label: fail, status: "fail", note: failNote)]
        if let replay {
            let label = replay == "replay-vibration" ? "Ripeti" : "Risenti"
            items.append(Act(label: label, status: replay, note: ""))
        }
        items.append(Act(label: "Salta", status: "skip", note: "Non eseguito"))
        return items
    }

    private func settleSoon(_ id: String, _ status: String, _ note: String) {
        later(0.8) { self.settle(id, status, note) }
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
        let model = Machine.identifier
        let os = "iOS \(UIDevice.current.systemVersion)"
        let screen = "\(Int(UIScreen.main.bounds.width))×\(Int(UIScreen.main.bounds.height))"
        let note = "\(model) · \(os) · \(screen)"
        show(note)
        settleSoon("identity", "pass", note)
    }

    private func readBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        hint = "Leggo la percentuale."
        if let note = batteryNote() {
            show(note)
            settleSoon("battery", "pass", note)
            return
        }
        later(1.2) {
            guard self.still("battery") else { return }
            if let note = self.batteryNote() {
                self.settle("battery", "pass", note)
            } else {
                self.settle("battery", "fail", "Percentuale non disponibile")
            }
        }
    }

    private func batteryNote() -> String? {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return nil }
        let percent = Int((level * 100).rounded())
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "in carica"
        case .full: state = "carica"
        case .unplugged: state = "non in carica"
        default: state = "stato sconosciuto"
        }
        return "\(percent)%, \(state). Cicli e salute celle non escono da un'app di terzi."
    }

    private func readNetwork() {
        hint = "Controllo la rete."
        NetworkProbe.check { [weak self] online in
            guard let self, self.still("network") else { return }
            if online {
                self.settle("network", "pass", "Rete attiva")
            } else {
                self.settle("network", "fail", "Nessuna rete internet")
            }
        }
        later(4) {
            if self.still("network") { self.settle("network", "fail", "Nessuna rete internet") }
        }
    }

    private func watchMotion(gyro: Bool, id: String, absent: String, prompt: String) {
        hint = prompt
        actions = [Act(label: "Non risponde", status: "fail", note: "Nessun cambiamento"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        let started = motion.watch(gyro: gyro) { [weak self] in
            self?.settle(id, "pass", "Valore cambiato")
        }
        if !started {
            actions = []
            show(absent)
            settleSoon(id, "absent", absent)
        }
    }

    private func startGps() {
        hint = "Cerco il fix. In negozio può non arrivare: in quel caso salta."
        actions = [Act(label: "Salta", status: "skip", note: "Nessun fix GPS")]
        place.onFix = { [weak self] location in
            let meters = max(0, Int(location.horizontalAccuracy.rounded()))
            self?.settle("gps", "pass", "Fix ±\(meters) m")
        }
        place.onDenied = { [weak self] in
            self?.settle("gps", "skip", "Permesso posizione negato")
        }
        place.requestFix()
        later(25) { if self.still("gps") { self.settle("gps", "skip", "Nessun fix in tempo") } }
    }

    private func watchVolume(up: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        volumeStart = session.outputVolume
        let id = up ? "volume_up" : "volume_down"
        if up && volumeStart > 0.95 {
            hint = "Il volume è già al massimo. Premi volume giù e poi volume su."
        } else if !up && volumeStart < 0.05 {
            hint = "Il volume è già al minimo. Premi volume su e poi volume giù."
        } else {
            hint = up ? "Premi il tasto volume su." : "Premi il tasto volume giù."
        }
        actions = [Act(label: "Non risponde", status: "fail", note: up ? "Volume su fermo" : "Volume giù fermo"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = session.outputVolume
                if self.volumeStart >= 0 && abs(now - self.volumeStart) > 0.01 {
                    self.settle(id, "pass", up ? "Volume su ricevuto" : "Volume giù ricevuto")
                }
            }
        }
        volumeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func watchCharge() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if chargingNow() {
            show("Il sistema vede la carica")
            settleSoon("charging", "pass", "Il sistema vede la carica")
            return
        }
        hint = "Collega il cavo di ricarica."
        actions = [Act(label: "Non carica", status: "fail", note: "Non entra in carica"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        watch(UIDevice.batteryStateDidChangeNotification) { [weak self] in
            if self?.chargingNow() == true { self?.settle("charging", "pass", "Il sistema vede la carica") }
        }
    }

    private func chargingNow() -> Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    private func startBluetooth() {
        hint = "Controllo che il Bluetooth si accenda. Se compare la richiesta, consenti."
        actions = [Act(label: "Salta", status: "skip", note: "Bluetooth non verificato")]
        radio.onResult = { [weak self] status, note in
            self?.settle("bluetooth", status, note)
        }
        radio.start()
        later(20) {
            if self.still("bluetooth") { self.settle("bluetooth", "skip", "Bluetooth non ha risposto") }
        }
    }

    private func openCamera(front: Bool) {
        let id = front ? "camera_front" : "camera_back"
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
                self.camera.start(front: front, onFocus: {}, onRunning: {
                    guard self.still(id) else { return }
                    self.hint = "Guarda l'immagine. Non segno io se è nitida."
                    self.actions = [
                        Act(label: "Immagine ok", status: "pass", note: "Immagine confermata"),
                        Act(label: "Immagine difettosa", status: "fail", note: "Immagine non accettata"),
                        Act(label: "Salta", status: "skip", note: "Non eseguito"),
                    ]
                }, onError: { message in
                    self.settle(id, "fail", message)
                })
            }
        }
    }

    private func startFlash() {
        guard CameraSession.hasFlash() else {
            show("Niente flash")
            settleSoon("flash", "absent", "Niente flash")
            return
        }
        hint = "Accendo il flash. Se compare la richiesta, consenti."
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
                        self.actions = self.confirm("Si vede", "Flash acceso", "Non si accende", "Flash comandato ma non visibile", replay: nil)
                    }
                }
            }
        }
    }

    private func startAutofocus() {
        guard CameraSession.hasAutofocus() else {
            show("Obiettivo a fuoco fisso")
            settleSoon("autofocus", "absent", "Obiettivo a fuoco fisso")
            return
        }
        hint = "Apro la fotocamera per la messa a fuoco."
        actions = [Act(label: "Non mette a fuoco", status: "fail", note: "Nessuna messa a fuoco"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.still("autofocus") else { return }
                guard granted else {
                    self.settle("autofocus", "skip", "Permesso fotocamera negato")
                    return
                }
                self.showCamera = true
                self.hint = "Inquadra un oggetto vicino e poi uno lontano."
                self.camera.start(front: false, onFocus: {
                    self.settle("autofocus", "pass", "Messa a fuoco rilevata")
                }, onRunning: {}, onError: { message in
                    self.settle("autofocus", "fail", message)
                })
            }
        }
    }

    private func startDepth() {
        hint = "Cerco una mappa di profondità vera."
        actions = [Act(label: "Salta", status: "skip", note: "Profondità non verificata")]
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
                        if ok {
                            self.settle("lidar", "pass", "Mappa di profondità ricevuta")
                        } else {
                            self.settle("lidar", "absent", "Questo iPhone non consegna la profondità LiDAR")
                        }
                    }
                }
            }
        }
    }

    private func watchProximity() {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        guard device.isProximityMonitoringEnabled else {
            show("Niente sensore di prossimità")
            settleSoon("proximity", "absent", "Niente sensore di prossimità")
            return
        }
        hint = "Copri il sensore in alto, vicino alla capsula. Lo schermo si spegne apposta: allontanalo."
        actions = [Act(label: "Non risponde", status: "fail", note: "Il sensore non cambia"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        watch(UIDevice.proximityStateDidChangeNotification) { [weak self] in
            if UIDevice.current.proximityState { self?.settle("proximity", "pass", "Sensore di prossimità attivato") }
        }
        later(0.6) {
            if self.still("proximity") && UIDevice.current.proximityState {
                self.settle("proximity", "pass", "Sensore di prossimità attivato")
            }
        }
    }

    private func startCompass() {
        hint = "Ruota il telefono in piano, come una bussola."
        actions = [Act(label: "Non risponde", status: "fail", note: "La bussola non gira"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        var first: CLHeading?
        place.onHeading = { [weak self] heading in
            if first == nil { first = heading; return }
            if abs(heading.magneticHeading - (first?.magneticHeading ?? 0)) > 8 {
                self?.settle("compass", "pass", "La bussola segue la rotazione")
            }
        }
        place.onDenied = { [weak self] in self?.settle("compass", "skip", "Permesso posizione negato") }
        place.startHeading()
        later(20) {
            if self.still("compass") { self.settle("compass", "skip", "La bussola non ha girato") }
        }
    }

    private func watchHeadphones() {
        if headphonesNow() {
            show("Cuffia già collegata")
            settleSoon("headphones", "pass", "Cuffia già collegata")
            return
        }
        hint = "Collega le cuffie. Se non ne hai, salta."
        actions = [Act(label: "Nessuna cuffia", status: "skip", note: "Nessuna cuffia collegata")]
        watch(AVAudioSession.routeChangeNotification) { [weak self] in
            if self?.headphonesNow() == true { self?.settle("headphones", "pass", "Cuffia collegata") }
        }
    }

    private func headphonesNow() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { port in
            port.portType == .headphones || port.portType == .bluetoothA2DP || port.portType == .bluetoothHFP || port.portType == .bluetoothLE || port.portType == .usbAudio
        }
    }

    private func recordMic() {
        guard still("microphone") else { return }
        hint = "Parla per tre secondi. Poi riascolti la voce."
        actions = [Act(label: "Salta", status: "skip", note: "Non eseguito")]
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard self.still("microphone") else { return }
                guard granted else {
                    self.settle("microphone", "skip", "Permesso microfono negato")
                    return
                }
                self.mic.record(seconds: 3, onLevel: { level in
                    Task { @MainActor in
                        guard self.still("microphone") else { return }
                        self.detail = "Livello \(level)"
                    }
                }, done: { rms, url in
                    Task { @MainActor in
                        guard self.still("microphone") else { return }
                        if let url {
                            self.playback = try? AVAudioPlayer(contentsOf: url)
                            self.playback?.play()
                        }
                        self.detail = "Livello \(Int(rms * 1000))"
                        self.hint = rms < 0.02 ? "Segnale molto basso. Se non ti senti, segna non conforme." : "Riascolta. Segna solo se riconosci la voce."
                        var items = self.confirm("Mi sento", "Voce registrata e riascoltata", "Non si sente", "Microfono senza voce utile", replay: nil)
                        if self.playback != nil {
                            items.insert(Act(label: "Riascolta", status: "replay-mic", note: ""), at: 2)
                        }
                        self.actions = items
                    }
                })
            }
        }
    }

    private func watch(_ name: Notification.Name, _ block: @escaping () -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            block()
        }
        observers.append(token)
    }

    private func cleanup() {
        armPower = false
        showCamera = false
        face.cancel()
        tone.stop()
        mic.stop()
        motion.stop()
        place.stop()
        radio.stop()
        depth.stop()
        playback?.stop()
        playback = nil
        camera.setTorch(false) { _ in }
        camera.stop()
        volumeTimer?.invalidate()
        volumeTimer = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
    }
}
