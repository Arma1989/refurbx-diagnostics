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
    private var earURL: URL?

    func play(earpiece: Bool, pan: Float = 0) {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            if earpiece {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
            } else {
                try session.setCategory(.playback, mode: .default, options: [])
            }
            try session.setActive(true)
        } catch {
            return
        }
        guard let url = prepareTone(sweep: !earpiece) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 1
        player?.pan = max(-1, min(1, pan))
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func prepareTone(sweep: Bool) -> URL? {
        if sweep, let toneURL { return toneURL }
        if !sweep, let earURL { return earURL }
        let rate = 44100
        let count = rate * (sweep ? 2 : 1)
        var samples = [Int16]()
        samples.reserveCapacity(count)
        var phase = 0.0
        for index in 0..<count {
            let freq: Double
            if sweep {
                let unit = Double(index) / Double(count)
                freq = 180 + unit * 3200
            } else {
                freq = 520
            }
            phase += 2 * Double.pi * freq / Double(rate)
            samples.append(Int16(sin(phase) * (sweep ? 14000 : 12000)))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(sweep ? "refurbx-sweep.wav" : "refurbx-ear.wav")
        do {
            try wav(samples: samples, rate: rate).write(to: url)
            if sweep { toneURL = url } else { earURL = url }
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

    func record(seconds: TimeInterval, source: AVAudioSessionDataSourceDescription? = nil, onLevel: @escaping (Int) -> Void, done: @escaping (Double, URL?) -> Void) {
        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            if let source, let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try builtIn.setPreferredDataSource(source)
                try session.setPreferredInput(builtIn)
            }
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

    static func backLenses() -> [AVCaptureDevice.DeviceType] {
        [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera].filter {
            AVCaptureDevice.default($0, for: .video, position: .back) != nil
        }
    }

    func start(front: Bool, lens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera, onFocus: @escaping () -> Void, onRunning: @escaping () -> Void, onError: @escaping (String) -> Void) {
        focusGeneration += 1
        let generation = focusGeneration
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            let position: AVCaptureDevice.Position = front ? .front : .back
            let wanted: AVCaptureDevice.DeviceType = front ? .builtInWideAngleCamera : lens
            guard let camera = AVCaptureDevice.default(wanted, for: .video, position: position)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
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

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            previewLayer.session = nil
        }
    }
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
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.previewLayer.session = nil
    }
}

final class DepthProbe: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private var finished = false
    private var token = 0
    private var onResult: ((Bool) -> Void)?
    var onPicture: ((UIImage, Bool, Bool) -> Void)?

    func start(_ onResult: @escaping (Bool) -> Void) {
        token += 1
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
    }

    func stop() {
        token += 1
        session.pause()
        onResult = nil
        onPicture = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !finished, let map = frame.sceneDepth?.depthMap else { return }
        guard let made = DepthImage.make(from: map) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            self.onPicture?(made.image, made.live, made.near)
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

    func follow(_ body: @escaping (CMDeviceMotion) -> Void) -> Bool {
        guard manager.isDeviceMotionAvailable else { return false }
        manager.deviceMotionUpdateInterval = 0.05
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            if let motion { body(motion) }
        }
        return true
    }

    func gravity(_ body: @escaping (_ x: Double, _ y: Double) -> Void) -> Bool {
        guard manager.isDeviceMotionAvailable else { return false }
        manager.deviceMotionUpdateInterval = 0.05
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { motion, _ in
            guard let motion else { return }
            body(motion.gravity.x, motion.gravity.y)
        }
        return true
    }

    func attitude(_ body: @escaping (_ roll: Double, _ pitch: Double, _ yaw: Double, _ rate: Double) -> Void) -> Bool {
        guard manager.isDeviceMotionAvailable else { return false }
        manager.deviceMotionUpdateInterval = 0.05
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { motion, _ in
            guard let motion else { return }
            let rate = abs(motion.rotationRate.x) + abs(motion.rotationRate.y) + abs(motion.rotationRate.z)
            body(motion.attitude.roll, motion.attitude.pitch, motion.attitude.yaw, rate)
        }
        return true
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        manager.stopDeviceMotionUpdates()
    }
}

enum DepthImage {
    struct Frame {
        let image: UIImage
        let live: Bool
        let near: Bool
    }

    static func make(from buffer: CVPixelBuffer) -> Frame? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 1, height > 1, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let disparity = format == kCVPixelFormatType_DisparityFloat32 || format == kCVPixelFormatType_DisparityFloat16
        let stepX = max(1, width / 96)
        let stepY = max(1, height / 128)
        let outW = max(1, width / stepX)
        let outH = max(1, height / stepY)
        var pixels = [UInt8](repeating: 198, count: outW * outH)
        var valid = 0
        var close = 0
        var index = 0
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let value = read(base, format: format, x: x, y: y, buffer: buffer)
                let gray = shade(value, disparity: disparity)
                if index < pixels.count { pixels[index] = gray }
                if let meters = metres(value, disparity: disparity) {
                    valid += 1
                    if meters < 0.55 { close += 1 }
                }
                index += 1
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(
                width: outW,
                height: outH,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: outW,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }
        let live = valid > 20
        return Frame(image: UIImage(cgImage: cg), live: live, near: live && close > 8)
    }

    private static func shade(_ value: Float, disparity: Bool) -> UInt8 {
        guard let meters = metres(value, disparity: disparity) else { return 198 }
        let unit = min(1, max(0, (meters - 0.15) / (2.0 - 0.15)))
        return UInt8(36 + unit * 188)
    }

    private static func metres(_ value: Float, disparity: Bool) -> Float? {
        guard value.isFinite, value > 0 else { return nil }
        let meters = disparity ? 1 / value : value
        guard meters.isFinite, meters > 0.05, meters < 8 else { return nil }
        return meters
    }

    private static func read(_ base: UnsafeMutableRawPointer, format: OSType, x: Int, y: Int, buffer: CVPixelBuffer) -> Float {
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        if format == kCVPixelFormatType_DepthFloat32 || format == kCVPixelFormatType_DisparityFloat32 {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            return row[x]
        }
        if format == kCVPixelFormatType_DepthFloat16 || format == kCVPixelFormatType_DisparityFloat16 {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt16.self)
            return float16to32(row[x])
        }
        return 0
    }

    private static func float16to32(_ bits: UInt16) -> Float {
        let sign = (bits & 0x8000) >> 15
        let exponent = (bits & 0x7C00) >> 10
        let fraction = bits & 0x03FF
        if exponent == 0 { return 0 }
        if exponent == 31 { return sign == 1 ? -Float.infinity : Float.infinity }
        let value = Float(fraction) / 1024 + 1
        let scaled = ldexpf(value, Int32(exponent) - 15)
        return sign == 1 ? -scaled : scaled
    }
}

final class FaceTrackProbe: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private var finished = false
    private var token = 0
    private var onResult: ((Bool) -> Void)?
    var onPicture: (([CGPoint]) -> Void)?

    func start(_ onResult: @escaping (Bool) -> Void) {
        token += 1
        let current = token
        finished = false
        self.onResult = onResult
        guard ARFaceTrackingConfiguration.isSupported else {
            finish(false)
            return
        }
        session.delegate = self
        session.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.token == current else { return }
            self.finish(false)
        }
    }

    func stop() {
        token += 1
        session.pause()
        onResult = nil
        onPicture = nil
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        publish(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        publish(anchors)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        finish(false)
    }

    private func publish(_ anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let vertices = face.geometry.vertices
        guard vertices.count > 100 else { return }
        var points: [CGPoint] = []
        points.reserveCapacity(vertices.count)
        for vertex in vertices {
            let x = 0.5 + CGFloat(vertex.x) / 0.20
            let y = 0.58 - CGFloat(vertex.y) / 0.26
            points.append(CGPoint(x: min(0.98, max(0.02, x)), y: min(0.98, max(0.02, y))))
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPicture?(points)
        }
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
        onFix = nil
        onHeading = nil
        onDenied = nil
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
        guard mode == .fix, let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        onFix?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard mode != .idle else { return }
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
        guard mode == .heading, newHeading.headingAccuracy >= 0 else { return }
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
    static func check(_ done: @escaping (Bool, String) -> Void) {
        let monitor = NWPathMonitor()
        let gate = Gate()
        monitor.pathUpdateHandler = { path in
            gate.run {
                let online = path.status == .satisfied
                let note: String
                if !online {
                    note = "Nessuna rete internet"
                } else if path.usesInterfaceType(.wifi) {
                    note = "Wi-Fi attivo"
                } else if path.usesInterfaceType(.cellular) {
                    note = "Rete cellulare attiva"
                } else {
                    note = "Rete attiva"
                }
                monitor.cancel()
                DispatchQueue.main.async { done(online, note) }
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
