import ARKit
import AudioToolbox
import AVFoundation
import CoreBluetooth
import CoreLocation
import CoreMotion
import Darwin
import LocalAuthentication
import Network
import SwiftUI
import UIKit

enum Machine {
    static var identifier: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static var iphoneMajor: Int? {
        let id = identifier
        guard id.hasPrefix("iPhone") else { return nil }
        let rest = id.dropFirst("iPhone".count)
        let major = rest.split(separator: ",").first ?? ""
        return Int(major)
    }
}

final class TonePlayer {
    private var player: AVAudioPlayer?
    private var toneURL: URL?

    func play(earpiece: Bool) {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: earpiece ? .voiceChat : .default, options: earpiece ? [] : [.defaultToSpeaker])
            try session.setActive(true)
            if !earpiece {
                try session.overrideOutputAudioPort(.speaker)
            }
        } catch {
            return
        }
        guard let url = prepareTone() else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 1
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func prepareTone() -> URL? {
        if let toneURL { return toneURL }
        let rate = 44100
        let count = rate
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for index in 0..<count {
            let value = sin(2 * Double.pi * 880 * Double(index) / Double(rate))
            samples.append(Int16(value * 16000))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("refurbx-tone.wav")
        do {
            try wav(samples: samples, rate: rate).write(to: url)
            toneURL = url
            return url
        } catch {
            return nil
        }
    }

    private func wav(samples: [Int16], rate: Int) -> Data {
        let dataSize = samples.count * 2
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: string.utf8) }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append("RIFF")
        append32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(rate))
        append32(UInt32(rate * 2))
        append16(2)
        append16(16)
        append("data")
        append32(UInt32(dataSize))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

final class MicProbe {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var peak = 0.0
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("refurbx-mic.m4a")

    func record(seconds: TimeInterval, onLevel: @escaping (Int) -> Void, done: @escaping (Double, URL?) -> Void) {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            try? FileManager.default.removeItem(at: url)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                DispatchQueue.main.async { done(0, nil) }
                return
            }
            self.recorder = recorder
        } catch {
            DispatchQueue.main.async { done(0, nil) }
            return
        }
        let started = Date()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self, let recorder = self.recorder else {
                timer.invalidate()
                return
            }
            recorder.updateMeters()
            let linear = pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)
            self.peak = max(self.peak, linear)
            onLevel(Int(linear * 1000))
            if Date().timeIntervalSince(started) >= seconds {
                timer.invalidate()
                self.timer = nil
                recorder.stop()
                done(self.peak, self.url)
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        peak = 0
    }
}

final class CameraSession: NSObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "refurbx.camera")
    private var focusObservation: NSKeyValueObservation?
    private var lastLens: Float?
    private var focusGeneration = 0

    func start(front: Bool, onFocus: @escaping () -> Void, onRunning: @escaping () -> Void, onError: @escaping (String) -> Void) {
        focusGeneration += 1
        let generation = focusGeneration
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            let position: AVCaptureDevice.Position = front ? .front : .back
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { onError(front ? "Niente camera anteriore" : "Niente camera posteriore") }
                return
            }
            self.session.addInput(input)
            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                try? camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async(execute: onRunning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.focusGeneration == generation else { return }
                self.lastLens = nil
                self.focusObservation = camera.observe(\.lensPosition, options: [.new]) { [weak self] _, change in
                    guard let value = change.newValue else { return }
                    DispatchQueue.main.async {
                        guard let self, self.focusGeneration == generation else { return }
                        if let previous = self.lastLens, abs(value - previous) > 0.04 {
                            onFocus()
                        }
                        self.lastLens = value
                    }
                }
            }
        }
    }

    func stop(done: (() -> Void)? = nil) {
        focusGeneration += 1
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.focusObservation?.invalidate()
                self.focusObservation = nil
                done?()
            }
        }
    }

    func setTorch(_ on: Bool, done: @escaping (Bool) -> Void) {
        queue.async {
            let ok = self.applyTorch(on)
            DispatchQueue.main.async { done(ok) }
        }
    }

    private func applyTorch(_ on: Bool) -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), camera.hasTorch else { return false }
        do {
            try camera.lockForConfiguration()
            if on {
                try camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                camera.torchMode = .off
            }
            camera.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    static func hasFlash() -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.hasTorch == true
    }

    static func hasAutofocus() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return false }
        return camera.isFocusModeSupported(.autoFocus) || camera.isFocusModeSupported(.continuousAutoFocus)
    }

    static func hasTrueDepth() -> Bool {
        AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class DepthProbe: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private var finished = false
    private var token = 0
    private var onResult: ((Bool) -> Void)?

    func start(_ onResult: @escaping (Bool) -> Void) {
        token += 1
        let current = token
        finished = false
        self.onResult = onResult
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            finish(false)
            return
        }
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.token == current else { return }
            self.finish(false)
        }
    }

    func stop() {
        token += 1
        session.pause()
        onResult = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if frame.sceneDepth?.depthMap != nil {
            finish(true)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        finish(false)
    }

    private func finish(_ ok: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.finish(ok) }
            return
        }
        guard !finished else { return }
        finished = true
        session.pause()
        let callback = onResult
        onResult = nil
        callback?(ok)
    }
}

final class MotionProbe {
    private let manager = CMMotionManager()

    func watch(gyro: Bool, changed: @escaping () -> Void) -> Bool {
        if gyro {
            guard manager.isGyroAvailable else { return false }
            manager.gyroUpdateInterval = 0.1
            var first: Double?
            manager.startGyroUpdates(to: .main) { data, _ in
                guard let data else { return }
                let value = abs(data.rotationRate.x) + abs(data.rotationRate.y) + abs(data.rotationRate.z)
                if first == nil { first = value; return }
                if abs(value - (first ?? 0)) > 0.45 { changed() }
            }
        } else {
            guard manager.isAccelerometerAvailable else { return false }
            manager.accelerometerUpdateInterval = 0.1
            var first: Double?
            manager.startAccelerometerUpdates(to: .main) { data, _ in
                guard let data else { return }
                let value = data.acceleration.x + data.acceleration.y + data.acceleration.z
                if first == nil { first = value; return }
                if abs(value - (first ?? 0)) > 0.2 { changed() }
            }
        }
        return true
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
    }
}

final class PlaceProbe: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private enum Mode { case idle, fix, heading }
    private var mode: Mode = .idle
    var onFix: ((CLLocation) -> Void)?
    var onHeading: ((CLHeading) -> Void)?
    var onDenied: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.headingFilter = 5
    }

    func requestFix() {
        mode = .fix
        begin()
    }

    func startHeading() {
        mode = .heading
        begin()
    }

    func stop() {
        mode = .idle
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func begin() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorized()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            onDenied?()
        }
    }

    private func startAuthorized() {
        if mode == .fix { manager.startUpdatingLocation() }
        if mode == .heading { manager.startUpdatingHeading() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        onFix?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as NSError).code
        if code == CLError.denied.rawValue { onDenied?() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorized()
        case .denied, .restricted:
            if mode != .idle { onDenied?() }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        onHeading?(newHeading)
    }
}

final class RadioProbe: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    var onResult: ((String, String) -> Void)?

    func start() {
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        manager?.stopScan()
        manager = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            onResult?("pass", "Bluetooth acceso")
        case .poweredOff:
            onResult?("skip", "Bluetooth spento")
        case .unauthorized:
            onResult?("skip", "Permesso Bluetooth negato")
        case .unsupported:
            onResult?("absent", "Niente Bluetooth")
        default:
            break
        }
    }
}

enum NetworkProbe {
    static func check(_ done: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor()
        let gate = Gate()
        monitor.pathUpdateHandler = { path in
            gate.run {
                let online = path.status == .satisfied
                monitor.cancel()
                DispatchQueue.main.async { done(online) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "refurbx.net"))
    }
}

final class Gate {
    private var used = false
    func run(_ block: () -> Void) {
        if used { return }
        used = true
        block()
    }
}

enum DiskProbe {
    static func note() -> String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else {
            return "Capacità non letta"
        }
        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        let used = Int64(total) - free
        return "Disco \(format(used)) usati su \(format(Int64(total)))"
    }

    private static func format(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000.0)
    }
}

final class FaceProbe {
    private var context: LAContext?

    func run(done: @escaping (String, String) -> Void) {
        let context = LAContext()
        self.context = context
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            let code = error.flatMap { LAError.Code(rawValue: $0.code) }
            if code == .biometryNotAvailable {
                done("absent", "Nessun Face ID o Touch ID")
            } else if code == .biometryNotEnrolled {
                done("skip", "Nessun volto o impronta registrata")
            } else {
                done("skip", error?.localizedDescription ?? "Biometria non disponibile")
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Prova il riconoscimento per la diagnosi") { ok, evalError in
            DispatchQueue.main.async {
                if ok {
                    done("pass", "Riconoscimento accettato. L'immagine a infrarossi resta nel sistema.")
                } else {
                    let code = (evalError as NSError?)?.code
                    if code == LAError.userCancel.rawValue || code == LAError.appCancel.rawValue || code == LAError.systemCancel.rawValue || code == LAError.biometryLockout.rawValue {
                        done("skip", "Riconoscimento annullato")
                    } else {
                        done("fail", evalError?.localizedDescription ?? "Riconoscimento rifiutato")
                    }
                }
            }
        }
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }
}

func vibratePhone() {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
}
