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
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?

    func play(earpiece: Bool) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: earpiece ? .voiceChat : .default, options: earpiece ? [] : [.defaultToSpeaker])
        try? session.setActive(true)
        try? session.overrideOutputAudioPort(earpiece ? .none : .speaker)
        let sampleRate = 44100.0
        var theta = 0.0
        let step = 2.0 * Double.pi * 880.0 / sampleRate
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(theta) * 0.25)
                theta += step
                for buffer in buffers {
                    let pointer = buffer.mData?.assumingMemoryBound(to: Float.self)
                    pointer?[frame] = sample
                }
            }
            return noErr
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        node = source
        try? engine.start()
    }

    func stop() {
        engine.stop()
        if let node {
            engine.detach(node)
        }
        node = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

final class MicProbe {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var tapInstalled = false
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("refurbx-mic.caf")

    func record(seconds: TimeInterval, onLevel: @escaping (Int) -> Void, done: @escaping (Double, URL?) -> Void) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            done(0, nil)
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            done(0, nil)
            return
        }
        try? FileManager.default.removeItem(at: url)
        file = try? AVAudioFile(forWriting: url, settings: format.settings)
        var energy = 0.0
        var samples = 0
        tapInstalled = true
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
            let channel = buffer.floatChannelData?.pointee
            let count = Int(buffer.frameLength)
            var sum = 0.0
            if let channel {
                for index in 0..<count {
                    let value = Double(channel[index])
                    sum += value * value
                }
            }
            energy += sum
            samples += count
            let rms = sqrt(sum / Double(max(count, 1)))
            DispatchQueue.main.async { onLevel(Int(rms * 1000)) }
        }
        do {
            try engine.start()
        } catch {
            removeTap()
            done(0, nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.removeTap()
            if self.engine.isRunning { self.engine.stop() }
            let rms = sqrt(energy / Double(max(samples, 1)))
            done(rms, self.url)
        }
    }

    func stop() {
        removeTap()
        if engine.isRunning { engine.stop() }
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }
}

final class CameraSession: NSObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "refurbx.camera")
    private var device: AVCaptureDevice?
    private var focusObservation: NSKeyValueObservation?

    func start(front: Bool, onFocus: @escaping () -> Void, onError: @escaping (String) -> Void) {
        queue.async {
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
            self.device = camera
            self.session.addInput(input)
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                try? camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
                self.focusObservation = camera.observe(\.lensPosition, options: [.new]) { _, change in
                    if let value = change.newValue, value > 0.02 && value < 0.98 {
                        DispatchQueue.main.async(execute: onFocus)
                    }
                }
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.focusObservation = nil
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

    func torch(_ on: Bool) -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), camera.hasTorch else { return false }
        do {
            try camera.lockForConfiguration()
            camera.torchMode = on ? .on : .off
            camera.unlockForConfiguration()
            return true
        } catch {
            return false
        }
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
    private var onResult: ((Bool) -> Void)?

    func start(_ onResult: @escaping (Bool) -> Void) {
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            onResult(false)
            return
        }
        self.onResult = onResult
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        session.run(config)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finish(false)
        }
    }

    func stop() {
        session.pause()
        onResult = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if frame.sceneDepth?.depthMap != nil {
            finish(true)
        }
    }

    private func finish(_ ok: Bool) {
        guard !finished else { return }
        finished = true
        session.pause()
        DispatchQueue.main.async {
            self.onResult?(ok)
            self.onResult = nil
        }
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
                if abs(value - (first ?? 0)) > 0.8 { changed() }
            }
        } else {
            guard manager.isAccelerometerAvailable else { return false }
            manager.accelerometerUpdateInterval = 0.1
            var first: Double?
            manager.startAccelerometerUpdates(to: .main) { data, _ in
                guard let data else { return }
                let value = data.acceleration.x + data.acceleration.y + data.acceleration.z
                if first == nil { first = value; return }
                if abs(value - (first ?? 0)) > 0.25 { changed() }
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
        if mode == .fix { manager.requestLocation() }
        if mode == .heading { manager.startUpdatingHeading() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { onFix?(location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        _ = error
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
        onHeading?(newHeading)
    }
}

final class RadioProbe: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    var onReady: (() -> Void)?
    var onOff: (() -> Void)?
    var onDenied: (() -> Void)?

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
            central.scanForPeripherals(withServices: nil)
            onReady?()
        case .poweredOff:
            onOff?()
        case .unauthorized:
            onDenied?()
        default:
            break
        }
    }
}

enum NetworkProbe {
    static func isOnline() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var online = false
        monitor.pathUpdateHandler = { path in
            online = path.status == .satisfied
            semaphore.signal()
            monitor.cancel()
        }
        monitor.start(queue: DispatchQueue(label: "refurbx.net"))
        _ = semaphore.wait(timeout: .now() + 2)
        return online
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

enum FaceProbe {
    static func run(done: @escaping (String, String) -> Void) {
        let context = LAContext()
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
                    if code == LAError.userCancel.rawValue || code == LAError.appCancel.rawValue || code == LAError.systemCancel.rawValue {
                        done("skip", "Riconoscimento annullato")
                    } else {
                        done("fail", evalError?.localizedDescription ?? "Riconoscimento rifiutato")
                    }
                }
            }
        }
    }
}

func vibratePhone() {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
}
