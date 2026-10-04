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
    @Published var pressure = "Premi lo schermo"

    let camera = CameraSession()
    private let tone = TonePlayer()
    private let mic = MicProbe()
    private let motion = MotionProbe()
    private let place = PlaceProbe()
    private let radio = RadioProbe()
    private let depth = DepthProbe()
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

    func settle(_ id: String, _ status: String, _ note: String) {
        guard !settled, currentId == id else { return }
        settled = true
        wave += 1
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
        for item in outcomes {
            lines.append("\(Catalog.title(item.id)): \(statusIt(item.status))")
            if !item.note.isEmpty { lines.append(item.note) }
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
            hint = "Tocca ogni cella. Una zona che resta scura è morta."
            actions = [Act(label: "Zona morta", status: "fail", note: "Area del touch non risponde"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        case "multitouch":
            hint = "Appoggia almeno due dita insieme."
            actions = [Act(label: "Non legge due dita", status: "fail", note: "Multi-touch assente"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        case "speaker":
            tone.play(earpiece: false)
            hint = "Ascolta la nota dall'altoparlante. Non la segno io."
            actions = confirm("Si sente chiara", "Altoparlante confermato", "Distorta o muta", "Altoparlante non accettato", replay: "replay-speaker")
        case "microphone": recordMic()
        case "vibration":
            vibratePhone()
            hint = "Deve vibrare adesso."
            actions = confirm("L'ho sentita", "Vibrazione sentita", "Non vibra", "Nessuna vibrazione", replay: nil)
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
                settle("mute_switch", "absent", "Questo iPhone ha il tasto Azione, non l'interruttore del silenzioso")
            } else {
                settle("mute_switch", "absent", "iOS non consegna lo stato dell'interruttore silenzioso alle app")
            }
        case "charging": watchCharge()
        case "biometrics":
            hint = "Usa il volto o l'impronta."
            FaceProbe.run { [weak self] status, note in self?.settle("biometrics", status, note) }
        case "bluetooth": startBluetooth()
        case "nfc":
            settle("nfc", "skip", "La lettura NFC si attiva dal portale Apple. Senza quel permesso la salto.")
        case "flash": startFlash()
        case "autofocus": startAutofocus()
        case "truedepth":
            if CameraSession.hasTrueDepth() {
                settle("truedepth", "pass", "Camera TrueDepth presente. L'immagine a infrarossi resta nel sistema.")
            } else {
                settle("truedepth", "absent", "Niente camera TrueDepth")
            }
        case "lidar": startDepth()
        case "memory": settleSoon("memory", "pass", DiskProbe.note())
        case "proximity": watchProximity()
        case "light": settle("light", "absent", "iOS non consegna il sensore di luce alle app")
        case "compass": startCompass()
        case "headphones": watchHeadphones()
        case "call":
            tone.play(earpiece: true)
            hint = "Tieni il telefono come in chiamata. La nota deve uscire dalla capsula."
            actions = confirm("Si sente in capsula", "Capsula di chiamata confermata", "Non si sente", "Chiamata non udibile", replay: "replay-ear")
        case "force":
            hint = "Premi piano e poi forte. Se la pressione non cambia, questo schermo non la misura."
            actions = [Act(label: "La pressione non varia", status: "absent", note: "Lo schermo non riporta la pressione"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        case "stylus":
            hint = "L'iPhone non usa la penna. Se arriva un tratto di Apple Pencil, lo segno."
            actions = [Act(label: "Non ha la penna", status: "absent", note: "Nessun tratto di penna"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        default:
            settle(row.id, "skip", "Test non eseguito")
        }
    }

    private func confirm(_ pass: String, _ passNote: String, _ fail: String, _ failNote: String, replay: String?) -> [Act] {
        var items = [Act(label: pass, status: "pass", note: passNote), Act(label: fail, status: "fail", note: failNote)]
        if let replay { items.append(Act(label: "Risenti", status: replay, note: "")) }
        items.append(Act(label: "Salta", status: "skip", note: "Non eseguito"))
        return items
    }

    private func settleSoon(_ id: String, _ status: String, _ note: String) {
        detail = note
        hint = "Lettura dal telefono"
        later(0.45) { self.settle(id, status, note) }
    }

    private func later(_ seconds: Double, _ block: @escaping () -> Void) {
        let seen = wave
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if seen == self.wave { block() }
        }
    }

    private func readIdentity() {
        let model = Machine.identifier
        let os = "iOS \(UIDevice.current.systemVersion)"
        let screen = "\(Int(UIScreen.main.bounds.width))×\(Int(UIScreen.main.bounds.height))"
        settleSoon("identity", "pass", "\(model) · \(os) · \(screen)")
    }

    private func readBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let note = batteryNote() {
            settleSoon("battery", "pass", note)
            return
        }
        later(1.2) {
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
        return "\(percent)%. Cicli e salute celle non escono da un'app di terzi."
    }

    private func readNetwork() {
        if NetworkProbe.isOnline() {
            settleSoon("network", "pass", "Rete attiva")
        } else {
            settle("network", "fail", "Nessuna rete internet")
        }
    }

    private func watchMotion(gyro: Bool, id: String, absent: String, prompt: String) {
        hint = prompt
        actions = [Act(label: "Non risponde", status: "fail", note: "Nessun cambiamento"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        let started = motion.watch(gyro: gyro) { [weak self] in
            self?.settle(id, "pass", "Valore cambiato")
        }
        if !started { settle(id, "absent", absent) }
    }

    private func startGps() {
        hint = "Cerco il fix. In negozio può non arrivare: in quel caso si salta."
        actions = [Act(label: "Salta", status: "skip", note: "Nessun fix GPS")]
        place.onFix = { [weak self] location in
            let meters = max(0, Int(location.horizontalAccuracy.rounded()))
            self?.settle("gps", "pass", "Fix ±\(meters) m")
        }
        place.onDenied = { [weak self] in
            self?.settle("gps", "skip", "Permesso posizione negato")
        }
        place.requestFix()
        later(20) { if self.currentId == "gps" && !self.settled { self.settle("gps", "skip", "Nessun fix in tempo") } }
    }

    private func watchVolume(up: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        volumeStart = session.outputVolume
        hint = up ? "Premi il tasto volume su." : "Premi il tasto volume giù."
        let id = up ? "volume_up" : "volume_down"
        actions = [Act(label: "Non risponde", status: "fail", note: up ? "Volume su fermo" : "Volume giù fermo"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = session.outputVolume
                if self.volumeStart >= 0 && abs(now - self.volumeStart) > 0.01 {
                    self.settle(id, "pass", up ? "Volume su ricevuto" : "Volume giù ricevuto")
                }
            }
        }
    }

    private func watchCharge() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if chargingNow() {
            settle("charging", "pass", "Il sistema vede la carica")
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
        hint = "Avvio la ricerca Bluetooth."
        radio.onReady = { [weak self] in self?.settle("bluetooth", "pass", "Scansione Bluetooth avviata") }
        radio.onOff = { [weak self] in self?.settle("bluetooth", "skip", "Bluetooth spento") }
        radio.onDenied = { [weak self] in self?.settle("bluetooth", "skip", "Permesso Bluetooth negato") }
        radio.start()
    }

    private func openCamera(front: Bool) {
        let id = front ? "camera_front" : "camera_back"
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.currentId == id else { return }
                guard granted else {
                    self.settle(id, "skip", "Permesso fotocamera negato")
                    return
                }
                self.showCamera = true
                self.hint = "Guarda l'immagine. Non segno io se è nitida."
                self.actions = [
                    Act(label: "Immagine ok", status: "pass", note: "Immagine confermata"),
                    Act(label: "Immagine difettosa", status: "fail", note: "Immagine non accettata"),
                    Act(label: "Salta", status: "skip", note: "Non eseguito"),
                ]
                self.camera.start(front: front, onFocus: {}, onError: { message in
                    DispatchQueue.main.async { self.settle(id, "fail", message) }
                })
            }
        }
    }

    private func startFlash() {
        guard CameraSession.hasFlash() else {
            settle("flash", "absent", "Niente flash")
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.currentId == "flash" else { return }
                guard granted else {
                    self.settle("flash", "skip", "Permesso fotocamera negato")
                    return
                }
                guard self.camera.torch(true) else {
                    self.settle("flash", "fail", "Il flash non si accende")
                    return
                }
                self.hint = "Il flash è acceso. Conferma solo se lo vedi."
                self.actions = [Act(label: "Si vede", status: "pass", note: "Flash acceso"), Act(label: "Non si accende", status: "fail", note: "Flash comandato ma non visibile")]
            }
        }
    }

    private func startAutofocus() {
        guard CameraSession.hasAutofocus() else {
            settle("autofocus", "absent", "Obiettivo a fuoco fisso")
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.currentId == "autofocus", granted else {
                    if self.currentId == "autofocus" { self.settle("autofocus", "skip", "Permesso fotocamera negato") }
                    return
                }
                self.showCamera = true
                self.hint = "Inquadra un oggetto. Segno il test solo se la messa a fuoco si muove."
                self.actions = [Act(label: "Non mette a fuoco", status: "fail", note: "Nessuna messa a fuoco"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
                self.camera.start(front: false, onFocus: {
                    self.settle("autofocus", "pass", "Messa a fuoco rilevata")
                }, onError: { message in
                    DispatchQueue.main.async { self.settle("autofocus", "fail", message) }
                })
            }
        }
    }

    private func startDepth() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard self.currentId == "lidar" else { return }
                guard granted else {
                    self.settle("lidar", "skip", "Permesso fotocamera negato")
                    return
                }
                self.hint = "Cerco una mappa di profondità vera."
                self.depth.start { ok in
                    if ok {
                        self.settle("lidar", "pass", "Mappa di profondità ricevuta")
                    } else {
                        self.settle("lidar", "absent", "Questo iPhone non consegna la profondità LiDAR")
                    }
                }
            }
        }
    }

    private func watchProximity() {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        guard device.isProximityMonitoringEnabled else {
            settle("proximity", "absent", "Niente sensore di prossimità")
            return
        }
        hint = "Avvicina il telefono all'orecchio."
        actions = [Act(label: "Non risponde", status: "fail", note: "Il sensore non cambia"), Act(label: "Salta", status: "skip", note: "Non eseguito")]
        watch(UIDevice.proximityStateDidChangeNotification) { [weak self] in
            if UIDevice.current.proximityState { self?.settle("proximity", "pass", "Sensore di prossimità attivato") }
        }
    }

    private func startCompass() {
        hint = "Ruota il telefono in piano."
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
    }

    private func watchHeadphones() {
        if headphonesNow() {
            settle("headphones", "pass", "Cuffia già collegata")
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
            port.portType == .headphones || port.portType == .bluetoothA2DP || port.portType == .bluetoothHFP || port.portType == .usbAudio
        }
    }

    private func recordMic() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard self.currentId == "microphone" else { return }
                guard granted else {
                    self.settle("microphone", "skip", "Permesso microfono negato")
                    return
                }
                self.hint = "Parla per due secondi. Poi riascolti la voce."
                self.mic.record(seconds: 2, onLevel: { level in
                    self.detail = "Livello \(level)"
                }, done: { rms, url in
                    guard self.currentId == "microphone", !self.settled else { return }
                    if let url {
                        self.playback = try? AVAudioPlayer(contentsOf: url)
                        self.playback?.play()
                    }
                    self.detail = "Livello \(Int(rms * 1000))"
                    self.hint = rms < 0.02 ? "Segnale molto basso. Se non ti senti, segna non conforme." : "Riascolta. Segna solo se riconosci la voce."
                    self.actions = self.confirm("Mi sento", "Voce registrata e riascoltata", "Non si sente", "Microfono senza voce utile", replay: nil)
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
        tone.stop()
        mic.stop()
        motion.stop()
        place.stop()
        radio.stop()
        depth.stop()
        camera.stop()
        camera.torch(false)
        volumeTimer?.invalidate()
        volumeTimer = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
    }
}
