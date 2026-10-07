import ARKit
import AudioToolbox
import AVFoundation
import CoreBluetooth
import CoreLocation
import CoreMotion
import CoreNFC
import LocalAuthentication
import Network
import SwiftUI
import UIKit

enum HardwareFit {
    static var pad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    static var systemName: String { pad ? "iPadOS" : "iOS" }

    static func supports(_ id: String) -> Bool {
        switch id {
        case "stylus":
            return acceptsPencil
        case "force":
            return UIScreen.main.traitCollection.forceTouchCapability == .available
        case "lidar":
            return ARWorldTrackingConfiguration.isSupported
                && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        case "truedepth":
            return CameraSession.hasTrueDepth()
        case "flash":
            return CameraSession.hasFlash()
        case "autofocus":
            return CameraSession.hasAutofocus()
        case "mute_switch":
            return hasSilentControl
        case "wireless":
            if pad { return false }
            guard let major = Machine.iphoneMajor else { return true }
            return major >= 10
        case "nfc":
            return NFCTagReaderSession.readingAvailable
        case "proximity", "earpiece", "call":
            return !pad
        default:
            return true
        }
    }

    static var acceptsPencil: Bool {
        guard pad else { return false }
        guard let major = Machine.ipadMajor else { return true }
        if let name = Machine.commercialName?.lowercased(), name.contains("pro") { return true }
        if major >= 7 { return true }
        if major == 6, let minor = Machine.ipadMinor, (3...8).contains(minor) { return true }
        return false
    }

    /// Every iPhone can silence the ringer. 15 Pro and later use the Action button.
    static var usesActionButton: Bool {
        guard let major = Machine.iphoneMajor else { return false }
        return major >= 16
    }

    static var hasSilentControl: Bool {
        if Machine.iphoneMajor != nil { return true }
        guard let major = Machine.ipadMajor else { return false }
        return major <= 7 || major == 11 || major == 12
    }

    static func rows(in group: String?) -> [Catalog.Row] {
        Catalog.rows.filter { (group == nil || $0.group == group) && supports($0.id) }
    }

    static var lockedRows: [Catalog.Row] {
        Catalog.rows.filter { !supports($0.id) }
    }
}

enum Machine {
    static var identifier: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static var iphoneMajor: Int? { applePart("iPhone", 0) }
    static var ipadMajor: Int? { applePart("iPad", 0) }
    static var ipadMinor: Int? { applePart("iPad", 1) }

    private static func applePart(_ prefix: String, _ index: Int) -> Int? {
        let id = identifier
        guard id.hasPrefix(prefix) else { return nil }
        let parts = id.dropFirst(prefix.count).split(separator: ",")
        guard parts.indices.contains(index) else { return nil }
        return Int(parts[index])
    }

    static var commercialName: String? {
        names[identifier]
    }

    static var modelName: String {
        commercialName ?? identifier
    }

    static var described: String {
        let code = identifier
        guard let name = commercialName else { return code }
        return "\(name) · \(code)"
    }

    private static let names: [String: String] = [
        "iPhone19,2": "iPhone 18 Pro",
        "iPhone19,3": "iPhone 18 Pro Max",
        "iPhone19,7": "iPhone 18 Pro Max",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone18,5": "iPhone 17e",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone14,6": "iPhone SE (2022)",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2020)",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone10,3": "iPhone X",
        "iPhone10,6": "iPhone X",
        "iPhone10,2": "iPhone 8 Plus",
        "iPhone10,5": "iPhone 8 Plus",
        "iPhone10,1": "iPhone 8",
        "iPhone10,4": "iPhone 8",
        "iPhone9,2": "iPhone 7 Plus",
        "iPhone9,4": "iPhone 7 Plus",
        "iPhone9,1": "iPhone 7",
        "iPhone9,3": "iPhone 7",
        "iPhone8,4": "iPhone SE (2016)",
        "iPhone8,1": "iPhone 6s",
        "iPhone8,2": "iPhone 6s Plus",
        "iPhone7,2": "iPhone 6",
        "iPhone7,1": "iPhone 6 Plus",
        "iPhone6,1": "iPhone 5s",
        "iPhone6,2": "iPhone 5s",
        "iPhone5,3": "iPhone 5c",
        "iPhone5,4": "iPhone 5c",
        "iPhone5,1": "iPhone 5",
        "iPhone5,2": "iPhone 5",
        "iPhone4,1": "iPhone 4s",
        "iPhone3,1": "iPhone 4",
        "iPhone3,2": "iPhone 4",
        "iPhone3,3": "iPhone 4",
        "iPhone2,1": "iPhone 3GS",
        "iPhone1,2": "iPhone 3G",
        "iPhone1,1": "iPhone",
        "iPad17,1": "iPad Pro 11\" (M5)",
        "iPad17,2": "iPad Pro 11\" (M5)",
        "iPad17,3": "iPad Pro 13\" (M5)",
        "iPad17,4": "iPad Pro 13\" (M5)",
        "iPad16,1": "iPad mini (A17 Pro)",
        "iPad16,2": "iPad mini (A17 Pro)",
        "iPad16,3": "iPad Pro 11\" (M4)",
        "iPad16,4": "iPad Pro 11\" (M4)",
        "iPad16,5": "iPad Pro 13\" (M4)",
        "iPad16,6": "iPad Pro 13\" (M4)",
        "iPad16,8": "iPad Air 11\" (M4)",
        "iPad16,9": "iPad Air 11\" (M4)",
        "iPad16,10": "iPad Air 13\" (M4)",
        "iPad16,11": "iPad Air 13\" (M4)",
        "iPad15,3": "iPad Air 11\" (M3)",
        "iPad15,4": "iPad Air 11\" (M3)",
        "iPad15,5": "iPad Air 13\" (M3)",
        "iPad15,6": "iPad Air 13\" (M3)",
        "iPad15,7": "iPad (A16)",
        "iPad15,8": "iPad (A16)",
        "iPad14,1": "iPad mini (6ª gen.)",
        "iPad14,2": "iPad mini (6ª gen.)",
        "iPad14,3": "iPad Pro 11\" (4ª gen.)",
        "iPad14,4": "iPad Pro 11\" (4ª gen.)",
        "iPad14,5": "iPad Pro 12,9\" (6ª gen.)",
        "iPad14,6": "iPad Pro 12,9\" (6ª gen.)",
        "iPad14,8": "iPad Air 11\" (M2)",
        "iPad14,9": "iPad Air 11\" (M2)",
        "iPad14,10": "iPad Air 13\" (M2)",
        "iPad14,11": "iPad Air 13\" (M2)",
        "iPad13,1": "iPad Air (4ª gen.)",
        "iPad13,2": "iPad Air (4ª gen.)",
        "iPad13,4": "iPad Pro 11\" (3ª gen.)",
        "iPad13,5": "iPad Pro 11\" (3ª gen.)",
        "iPad13,6": "iPad Pro 11\" (3ª gen.)",
        "iPad13,7": "iPad Pro 11\" (3ª gen.)",
        "iPad13,8": "iPad Pro 12,9\" (5ª gen.)",
        "iPad13,9": "iPad Pro 12,9\" (5ª gen.)",
        "iPad13,10": "iPad Pro 12,9\" (5ª gen.)",
        "iPad13,11": "iPad Pro 12,9\" (5ª gen.)",
        "iPad13,16": "iPad Air (5ª gen.)",
        "iPad13,17": "iPad Air (5ª gen.)",
        "iPad13,18": "iPad (10ª gen.)",
        "iPad13,19": "iPad (10ª gen.)",
        "iPad12,1": "iPad (9ª gen.)",
        "iPad12,2": "iPad (9ª gen.)",
        "iPad11,1": "iPad mini (5ª gen.)",
        "iPad11,2": "iPad mini (5ª gen.)",
        "iPad11,3": "iPad Air (3ª gen.)",
        "iPad11,4": "iPad Air (3ª gen.)",
        "iPad11,6": "iPad (8ª gen.)",
        "iPad11,7": "iPad (8ª gen.)",
        "iPad8,1": "iPad Pro 11\"",
        "iPad8,2": "iPad Pro 11\"",
        "iPad8,3": "iPad Pro 11\"",
        "iPad8,4": "iPad Pro 11\"",
        "iPad8,5": "iPad Pro 12,9\" (3ª gen.)",
        "iPad8,6": "iPad Pro 12,9\" (3ª gen.)",
        "iPad8,7": "iPad Pro 12,9\" (3ª gen.)",
        "iPad8,8": "iPad Pro 12,9\" (3ª gen.)",
        "iPad8,9": "iPad Pro 11\" (2ª gen.)",
        "iPad8,10": "iPad Pro 11\" (2ª gen.)",
        "iPad8,11": "iPad Pro 12,9\" (4ª gen.)",
        "iPad8,12": "iPad Pro 12,9\" (4ª gen.)",
        "iPad7,1": "iPad Pro 12,9\" (2ª gen.)",
        "iPad7,2": "iPad Pro 12,9\" (2ª gen.)",
        "iPad7,3": "iPad Pro 10,5\"",
        "iPad7,4": "iPad Pro 10,5\"",
        "iPad7,5": "iPad (6ª gen.)",
        "iPad7,6": "iPad (6ª gen.)",
        "iPad7,11": "iPad (7ª gen.)",
        "iPad7,12": "iPad (7ª gen.)",
        "iPad6,3": "iPad Pro 9,7\"",
        "iPad6,4": "iPad Pro 9,7\"",
        "iPad6,7": "iPad Pro 12,9\"",
        "iPad6,8": "iPad Pro 12,9\"",
        "iPad6,11": "iPad (5ª gen.)",
        "iPad6,12": "iPad (5ª gen.)",
        "iPad5,1": "iPad mini 4",
        "iPad5,2": "iPad mini 4",
        "iPad5,3": "iPad Air 2",
        "iPad5,4": "iPad Air 2",
        "iPad4,1": "iPad Air",
        "iPad4,2": "iPad Air",
        "iPad4,3": "iPad Air",
        "iPad4,4": "iPad mini 2",
        "iPad4,5": "iPad mini 2",
        "iPad4,6": "iPad mini 2",
        "iPad4,7": "iPad mini 3",
        "iPad4,8": "iPad mini 3",
        "iPad4,9": "iPad mini 3",
        "iPad3,1": "iPad (3ª gen.)",
        "iPad3,2": "iPad (3ª gen.)",
        "iPad3,3": "iPad (3ª gen.)",
        "iPad3,4": "iPad (4ª gen.)",
        "iPad3,5": "iPad (4ª gen.)",
        "iPad3,6": "iPad (4ª gen.)",
        "iPad2,1": "iPad 2",
        "iPad2,2": "iPad 2",
        "iPad2,3": "iPad 2",
        "iPad2,4": "iPad 2",
        "iPad2,5": "iPad mini",
        "iPad2,6": "iPad mini",
        "iPad2,7": "iPad mini",
        "iPad1,1": "iPad",
    ]
}

final class TonePlayer {
    private var player: AVAudioPlayer?
    private var toneURL: URL?
    private var earURL: URL?

    func play(earpiece: Bool, pan: Float = 0) {
        stop()
        if earpiece {
            AudioRoute.earpiece()
        } else {
            AudioRoute.speaker()
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
            samples.append(Int16(sin(phase) * (sweep ? 16000 : 22000)))
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

enum MicSeat {
    case bottom, front, back

    var title: String {
        switch self {
        case .bottom: return "Microfono in basso"
        case .front: return "Microfono frontale"
        case .back: return "Microfono posteriore"
        }
    }

    var spot: String {
        switch self {
        case .bottom: return "bottom"
        case .front: return "front"
        case .back: return "back"
        }
    }
}

enum AudioRoute {
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    static func builtInMic() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().availableInputs?.first { $0.portType == .builtInMic }
    }

    /// One real source per seat, in order basso, fronte, posteriore.
    /// A rear step exists only when a source is actually back/rear. Upper alone stays front.
    static func micSources() -> [AVAudioSessionDataSourceDescription] {
        let session = AVAudioSession.sharedInstance()
        deactivate()
        try? session.setCategory(.playAndRecord, mode: .videoRecording, options: [])
        try? session.setActive(true)
        guard let builtIn = builtInMic() else { return [] }
        try? session.setPreferredInput(builtIn)
        var byID: [NSNumber: AVAudioSessionDataSourceDescription] = [:]
        for source in builtIn.dataSources ?? [] {
            byID[source.dataSourceID] = source
        }
        for source in session.inputDataSources ?? [] where byID[source.dataSourceID] == nil {
            byID[source.dataSourceID] = source
        }
        var chosen: [MicSeat: AVAudioSessionDataSourceDescription] = [:]
        for source in byID.values {
            guard let seat = micSeat(for: source) else { continue }
            if let existing = chosen[seat] {
                if prefers(source, over: existing, for: seat) { chosen[seat] = source }
            } else {
                chosen[seat] = source
            }
        }
        return [MicSeat.bottom, .front, .back].compactMap { chosen[$0] }
    }

    static func micSeat(for source: AVAudioSessionDataSourceDescription) -> MicSeat? {
        let orientation = source.orientation?.rawValue.lowercased() ?? ""
        let location = source.location?.rawValue.lowercased() ?? ""
        let name = source.dataSourceName.lowercased()
        if orientation == "back" || orientation.contains("rear") { return .back }
        if orientation == "bottom" || orientation == "lower" { return .bottom }
        if orientation == "front" { return .front }
        if orientation == "top" { return .front }
        if isRearName(name) || isRearName(location) { return .back }
        if isFrontName(name) { return .front }
        if isBottomName(name) { return .bottom }
        if location == "lower" { return .bottom }
        if location == "upper" { return .front }
        return nil
    }

    private static func isRearName(_ value: String) -> Bool {
        value.contains("back") || value.contains("rear") || value.contains("posterior")
            || value.contains("posteriore") || value.contains("retro") || value.contains("dietro")
    }

    private static func isFrontName(_ value: String) -> Bool {
        value.contains("front") || value.contains("frontal") || value.contains("fronte") || value.contains("davanti")
    }

    private static func isBottomName(_ value: String) -> Bool {
        value.contains("bottom") || value.contains("lower") || value.contains("basso")
    }

    private static func prefers(_ candidate: AVAudioSessionDataSourceDescription, over current: AVAudioSessionDataSourceDescription, for seat: MicSeat) -> Bool {
        func score(_ source: AVAudioSessionDataSourceDescription) -> Int {
            let raw = source.orientation?.rawValue.lowercased() ?? ""
            switch seat {
            case .back: return raw == "back" || raw.contains("rear") ? 2 : 1
            case .front: return raw == "front" ? 2 : 1
            case .bottom: return raw == "bottom" ? 2 : 1
            }
        }
        return score(candidate) > score(current)
    }

    static func prepareMic(_ source: AVAudioSessionDataSourceDescription?) {
        let session = AVAudioSession.sharedInstance()
        deactivate()
        try? session.setCategory(.playAndRecord, mode: .videoRecording, options: [])
        if let builtIn = builtInMic() {
            if let source {
                try? builtIn.setPreferredDataSource(source)
                if let patterns = source.supportedPolarPatterns {
                    if patterns.contains(.omnidirectional) {
                        try? source.setPreferredPolarPattern(.omnidirectional)
                    } else if let pattern = patterns.first {
                        try? source.setPreferredPolarPattern(pattern)
                    }
                }
            }
            try? session.setPreferredInput(builtIn)
        }
        try? session.setActive(true)
    }

    static func speaker() {
        let session = AVAudioSession.sharedInstance()
        deactivate()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.overrideOutputAudioPort(.speaker)
        try? session.setActive(true)
    }

    static func earpiece() {
        let session = AVAudioSession.sharedInstance()
        deactivate()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [])
        try? session.overrideOutputAudioPort(AVAudioSession.PortOverride.none)
        if let builtIn = builtInMic() {
            try? session.setPreferredInput(builtIn)
        }
        try? session.setActive(true)
    }
}

final class MicProbe {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var peak = 0.0
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("refurbx-mic.m4a")

    func record(seconds: TimeInterval, source: AVAudioSessionDataSourceDescription? = nil, onLevel: @escaping (Int) -> Void, done: @escaping (Double, URL?) -> Void) {
        stop()
        do {
            AudioRoute.prepareMic(source)
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

final class CameraSession: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "refurbx.camera")
    private let meterQueue = DispatchQueue(label: "refurbx.light")
    private var focusObservation: NSKeyValueObservation?
    private var lastLens: Float?
    private var focusGeneration = 0
    private var onCodeHandler: ((String, CGRect) -> Void)?
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var retainedPreview: PreviewView?
    private var meterHandler: ((Double) -> Void)?
    private var meterClock = Date.distantPast
    private weak var meterDevice: AVCaptureDevice?

    func holdPreview(_ view: PreviewView) {
        previewLayer = view.previewLayer
        retainedPreview = view
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first(where: { $0.type == .qr }),
              let value = code.stringValue, !value.isEmpty else { return }
        guard let callback = onCodeHandler else { return }
        let deliver = {
            let box: CGRect
            if let layer = self.previewLayer, let seen = layer.transformedMetadataObject(for: code) {
                box = seen.bounds
            } else {
                box = code.bounds
            }
            self.onCodeHandler = nil
            callback(value, box)
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }

    static func backLenses() -> [AVCaptureDevice.DeviceType] {
        [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera].filter {
            AVCaptureDevice.default($0, for: .video, position: .back) != nil
        }
    }

    func start(front: Bool, lens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera, scanQR: Bool = false, onFocus: @escaping () -> Void, onCode: @escaping (String, CGRect) -> Void = { _, _ in }, onRunning: @escaping () -> Void, onError: @escaping (String) -> Void, onMeter: ((Double) -> Void)? = nil) {
        focusGeneration += 1
        let generation = focusGeneration
        onCodeHandler = nil
        queue.async {
            dispatchPrecondition(condition: .notOnQueue(.main))
            guard self.focusGeneration == generation else { return }
            self.focusObservation?.invalidate()
            self.focusObservation = nil
            self.tearDownSession()
            self.session.beginConfiguration()
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
            self.meterHandler = onMeter
            self.meterDevice = onMeter == nil ? nil : camera
            if onMeter != nil {
                let video = AVCaptureVideoDataOutput()
                video.alwaysDiscardsLateVideoFrames = true
                video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                video.setSampleBufferDelegate(self, queue: self.meterQueue)
                if self.session.canAddOutput(video) {
                    self.session.addOutput(video)
                }
            }
            var metadata: AVCaptureMetadataOutput?
            if scanQR {
                let output = AVCaptureMetadataOutput()
                if self.session.canAddOutput(output) {
                    self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    metadata = output
                    self.onCodeHandler = onCode
                }
            }
            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            }
            self.lockCamera(camera)
            self.session.commitConfiguration()
            if let metadata {
                self.session.beginConfiguration()
                self.armQR(metadata)
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
            if let metadata, !metadata.metadataObjectTypes.contains(.qr) {
                self.session.beginConfiguration()
                self.armQR(metadata)
                self.session.commitConfiguration()
            }
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
            DispatchQueue.main.async(execute: onRunning)
        }
    }

    private func armQR(_ output: AVCaptureMetadataOutput) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard output.availableMetadataObjectTypes.contains(.qr) else { return }
        if output.metadataObjectTypes.contains(.qr) { return }
        output.metadataObjectTypes = [.qr]
    }

    private func lockCamera(_ camera: AVCaptureDevice) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        } catch {}
    }

    private func tearDownSession() {
        dispatchPrecondition(condition: .notOnQueue(.main))
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(meterClock) >= 0.08 else { return }
        meterClock = now
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let luma = Self.meanLuma(pixel)
        var scene = luma
        if let camera = meterDevice {
            let iso = Double(camera.iso)
            let seconds = camera.exposureDuration.seconds
            if iso > 1, seconds > 0 {
                scene = 1.0 / (iso * seconds)
            }
        }
        let handler = meterHandler
        DispatchQueue.main.async { handler?(scene) }
    }

    private static func meanLuma(_ pixel: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixel) else { return 0 }
        guard CVPixelBufferGetPixelFormatType(pixel) == kCVPixelFormatType_32BGRA else { return 0 }
        let width = CVPixelBufferGetWidth(pixel)
        let height = CVPixelBufferGetHeight(pixel)
        let stride = CVPixelBufferGetBytesPerRow(pixel)
        let step = 28
        var sum = 0.0
        var count = 0
        var y = 0
        while y < height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            var x = 0
            while x < width {
                let index = x * 4
                if index + 2 >= stride { break }
                let blue = Double(row[index])
                let green = Double(row[index + 1])
                let red = Double(row[index + 2])
                sum += 0.0722 * blue + 0.7152 * green + 0.2126 * red
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else { return 0 }
        return sum / Double(count) / 255.0
    }

    func stop(done: (() -> Void)? = nil) {
        focusGeneration += 1
        let generation = focusGeneration
        onCodeHandler = nil
        meterHandler = nil
        meterDevice = nil
        let view = retainedPreview
        queue.async {
            dispatchPrecondition(condition: .notOnQueue(.main))
            guard self.focusGeneration == generation else {
                DispatchQueue.main.async { done?() }
                return
            }
            self.focusObservation?.invalidate()
            self.focusObservation = nil
            self.tearDownSession()
            DispatchQueue.main.async {
                guard self.focusGeneration == generation else {
                    done?()
                    return
                }
                view?.previewLayer.session = nil
                if self.retainedPreview === view {
                    self.retainedPreview = nil
                    self.previewLayer = nil
                }
                done?()
            }
        }
    }

    func setTorch(_ on: Bool, done: @escaping (Bool) -> Void) {
        queue.async {
            dispatchPrecondition(condition: .notOnQueue(.main))
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

    func ambientLevel() -> Double? {
        guard let camera = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return nil }
        let iso = Double(camera.iso)
        let seconds = camera.exposureDuration.seconds
        guard iso > 1, seconds > 0 else { return nil }
        return 1.0 / (iso * seconds)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var front = false
    private var runningObserver: NSObjectProtocol?
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var angleObservation: NSKeyValueObservation?
    private var rotationDeviceID = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        orient()
    }

    func attach(session: AVCaptureSession) {
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        if runningObserver == nil {
            runningObserver = NotificationCenter.default.addObserver(
                forName: .AVCaptureSessionDidStartRunning,
                object: session,
                queue: .main
            ) { [weak self] _ in
                self?.orient()
            }
        }
        orient()
    }

    func orient() {
        guard previewLayer.connection != nil else { return }
        let device = (previewLayer.session?.inputs.first as? AVCaptureDeviceInput)?.device
        if let device, rotationDeviceID != device.uniqueID {
            rotationDeviceID = device.uniqueID
            let next = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            coordinator = next
            angleObservation = next.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyAngle() }
            }
        }
        applyAngle()
    }

    private func applyAngle() {
        guard let connection = previewLayer.connection else { return }
        let device = (previewLayer.session?.inputs.first as? AVCaptureDeviceInput)?.device
        let mirror = front || device?.position == .front
        if connection.isVideoMirroringSupported {
            if mirror {
                connection.automaticallyAdjustsVideoMirroring = true
            } else {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        let fallback: CGFloat = mirror ? 0 : 90
        let angle = coordinator?.videoRotationAngleForHorizonLevelPreview ?? fallback
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    func releaseObservers() {
        if let runningObserver {
            NotificationCenter.default.removeObserver(runningObserver)
        }
        runningObserver = nil
        angleObservation?.invalidate()
        angleObservation = nil
        coordinator = nil
        rotationDeviceID = ""
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            releaseObservers()
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var front = false
    var onView: ((PreviewView) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.front = front
        view.previewLayer.videoGravity = .resizeAspectFill
        view.attach(session: session)
        onView?(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.front = front
        uiView.attach(session: session)
        onView?(uiView)
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.releaseObservers()
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

    func attitude(_ body: @escaping (_ roll: Double, _ pitch: Double, _ spin: Double, _ verticalRate: Double, _ time: TimeInterval) -> Void) -> Bool {
        guard manager.isDeviceMotionAvailable else { return false }
        manager.deviceMotionUpdateInterval = 0.05
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { motion, _ in
            guard let motion else { return }
            let wx = motion.rotationRate.x
            let wy = motion.rotationRate.y
            let wz = motion.rotationRate.z
            let spin = (wx * wx + wy * wy + wz * wz).squareRoot()
            let gx = motion.gravity.x
            let gy = motion.gravity.y
            let gz = motion.gravity.z
            let weight = max(0.2, (gx * gx + gy * gy + gz * gz).squareRoot())
            let verticalRate = (wx * gx + wy * gy + wz * gz) / weight
            body(motion.attitude.roll, motion.attitude.pitch, spin, verticalRate, motion.timestamp)
        }
        return true
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        manager.stopDeviceMotionUpdates()
    }
}

final class RingerWatch {
    private var token: Int32 = 0
    private var armed = false

    func start(_ body: @escaping (_ silent: Bool) -> Void) -> Bool {
        stop()
        var registered: Int32 = 0
        let ok = RingerNotify.watch(on: DispatchQueue.main, handler: body, token: &registered)
        guard ok else { return false }
        token = registered
        armed = true
        return true
    }

    func stop() {
        guard armed else { return }
        RingerNotify.cancel(token)
        armed = false
        token = 0
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
        let upright = UIImage(cgImage: cg, scale: 1, orientation: .right)
        return Frame(image: upright, live: live, near: live && close > 8)
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
    private let updates = DispatchQueue(label: "eu.refurbx.face", qos: .userInitiated)
    private let ciContext = CIContext()
    private var finished = false
    private var token = 0
    private var lastShot = 0.0
    private var onResult: ((Bool) -> Void)?
    var onPicture: ((_ points: [CGPoint], _ camera: UIImage?) -> Void)?

    func start(_ onResult: @escaping (Bool) -> Void) {
        token += 1
        finished = false
        lastShot = 0
        self.onResult = onResult
        guard ARFaceTrackingConfiguration.isSupported else {
            finish(false)
            return
        }
        session.delegateQueue = updates
        session.delegate = self
        session.run(ARFaceTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        token += 1
        session.pause()
        onResult = nil
        onPicture = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let shot = selfie(frame.capturedImage)
        var points: [CGPoint] = []
        if let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first {
            let vertices = face.geometry.vertices
            if vertices.count > 100 {
                let camera = frame.camera
                let viewport = CGSize(width: 900, height: 1600)
                points.reserveCapacity(vertices.count / 2)
                for index in stride(from: 0, to: vertices.count, by: 2) {
                    let vertex = vertices[index]
                    let world = face.transform * simd_float4(vertex.x, vertex.y, vertex.z, 1)
                    let projected = camera.projectPoint(simd_float3(world.x, world.y, world.z), orientation: .portrait, viewportSize: viewport)
                    let x = projected.x / viewport.width
                    let y = projected.y / viewport.height
                    if x < -0.15 || x > 1.15 || y < -0.15 || y > 1.15 { continue }
                    points.append(CGPoint(x: min(0.98, max(0.02, x)), y: min(0.98, max(0.02, y))))
                }
            }
        }
        let picture = points.count > 40 ? points : []
        DispatchQueue.main.async { [weak self] in
            self?.onPicture?(picture, shot)
        }
    }

    private func selfie(_ buffer: CVPixelBuffer) -> UIImage? {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastShot > 0.12 else { return nil }
        lastShot = now
        let source = CIImage(cvPixelBuffer: buffer)
        let oriented = source.oriented(CGImagePropertyOrientation.right)
        let longest = max(oriented.extent.width, oriented.extent.height)
        let scale = min(1, 420 / max(longest, 1))
        let fitted = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ciContext.createCGImage(fitted, from: fitted.extent) else { return nil }
        return UIImage(cgImage: cg)
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
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
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
        if mode == .fix && manager.accuracyAuthorization == .reducedAccuracy {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "DiagFix") { [weak self] _ in
                DispatchQueue.main.async { self?.beginUpdates() }
            }
            return
        }
        beginUpdates()
    }

    private func beginUpdates() {
        if mode == .fix { manager.startUpdatingLocation() }
        if mode == .heading { manager.startUpdatingHeading() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard mode == .fix, let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let fix = location
        DispatchQueue.main.async { [weak self] in self?.onFix?(fix) }
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
        let heading = newHeading
        DispatchQueue.main.async { [weak self] in self?.onHeading?(heading) }
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
    static func check(_ done: @escaping (String) -> Void) {
        let monitor = NWPathMonitor()
        let gate = Gate()
        monitor.pathUpdateHandler = { path in
            gate.run {
                let kind: String
                if path.status != .satisfied {
                    kind = "none"
                } else if path.usesInterfaceType(.wifi) {
                    kind = "wifi"
                } else if path.usesInterfaceType(.cellular) {
                    kind = "cellular"
                } else {
                    kind = "other"
                }
                monitor.cancel()
                DispatchQueue.main.async { done(kind) }
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
    struct Report {
        var total: Int64
        var free: Int64
        var used: Int64
        var note: String
    }

    static func read() -> Report? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let total = bytes(values.volumeTotalCapacity)
        guard total >= 16_000_000_000 else { return nil }
        let candidates: [Int64] = [
            bytes(values.volumeAvailableCapacityForImportantUsage),
            bytes(values.volumeAvailableCapacity),
            bytes(values.volumeAvailableCapacityForOpportunisticUsage),
        ]
        var free: Int64 = 0
        for candidate in candidates where candidate > 0 && candidate < total {
            free = candidate
            break
        }
        let used: Int64 = total > free ? total - free : 0
        let note = "Totale \(gb(total)) · Libero \(gb(free)) · Usato \(gb(used))"
        return Report(total: total, free: free, used: used, note: note)
    }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
    }

    private static func bytes(_ value: Any?) -> Int64 {
        var current: Any = value as Any
        for _ in 0..<4 {
            let mirror = Mirror(reflecting: current)
            guard mirror.displayStyle == .optional else { break }
            guard let child = mirror.children.first else { return 0 }
            current = child.value
        }
        if let number = current as? Int64 { return number }
        if let number = current as? Int { return Int64(number) }
        if let number = current as? UInt64 { return Int64(clamping: number) }
        if let number = current as? NSNumber { return number.int64Value }
        return 0
    }
}

enum SignedNfc {
    static func profile() -> (name: String, formats: [String]) {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else {
            return ("", [])
        }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let raw = xml.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any] else {
            return ("", [])
        }
        let name = plist["Name"] as? String ?? ""
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let value = entitlements["com.apple.developer.nfc.readersession.formats"]
        if let one = value as? String { return (name, [one]) }
        if let many = value as? [String] { return (name, many) }
        return (name, [])
    }
}

final class TagProbe: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var reported = false
    private var connecting = false
    private var generation = 0
    private let lock = NSLock()
    var onResult: ((String, String) -> Void)?
    var onActive: (() -> Void)?

    @objc func beginFromTap() {
        lock.lock()
        if session != nil {
            lock.unlock()
            return
        }
        generation += 1
        let token = generation
        reported = false
        connecting = false
        lock.unlock()
        guard NFCTagReaderSession.readingAvailable else {
            finish("absent", "Questo iPhone non legge i tag NFC", token: token)
            return
        }
        guard let opened = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil) else {
            finish("absent", "Lettura NFC non disponibile", token: token)
            return
        }
        lock.lock()
        if self.session != nil || token != generation {
            lock.unlock()
            return
        }
        self.session = opened
        lock.unlock()
        opened.begin()
    }

    func stop() {
        lock.lock()
        generation += 1
        connecting = false
        let current = session
        session = nil
        lock.unlock()
        onResult = nil
        onActive = nil
        current?.invalidate()
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        guard session === self.session else { return }
        session.alertMessage = "Tieni la scheda ferma sul retro, in alto."
        let callback = onActive
        DispatchQueue.main.async { callback?() }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard session === self.session, let tag = tags.first else { return }
        lock.lock()
        if connecting {
            lock.unlock()
            return
        }
        connecting = true
        lock.unlock()
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.lock.lock()
                self.connecting = false
                self.lock.unlock()
                guard session === self.session else { return }
                session.alertMessage = "Tieni la scheda ferma sul retro, in alto."
                session.restartPolling()
                return
            }
            guard session === self.session else { return }
            let kind = Self.kind(tag)
            session.alertMessage = "NFC ok"
            self.finish("pass", "Tag \(kind) letto")
            session.invalidate()
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        lock.lock()
        guard session === self.session else {
            lock.unlock()
            return
        }
        let token = generation
        self.session = nil
        connecting = false
        lock.unlock()
        let code = (error as? NFCReaderError)?.code
        if code == .readerSessionInvalidationErrorFirstNDEFTagRead {
            finish("pass", "Tag NFC letto", token: token)
            return
        }
        if code == .readerSessionInvalidationErrorUserCanceled {
            finish("cancel", "", token: token)
            return
        }
        if code == .readerSessionInvalidationErrorSessionTimeout {
            finish("closed", "Tempo scaduto. Premi Apri lettore tag e tieni la scheda ferma sul retro, in alto.", token: token)
            return
        }
        if code == .readerSessionInvalidationErrorSystemIsBusy {
            finish("closed", "NFC occupato. Chiudi le altre finestre e premi Apri lettore tag.", token: token)
            return
        }
        let nsError = error as NSError
        let raw = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let securityViolation = nsError.domain == NFCErrorDomain
            && nsError.code == NFCReaderError.Code.readerErrorSecurityViolation.rawValue
        let appleMissingEntitlement = raw.range(of: "Missing required entitlement", options: .caseInsensitive) != nil
        if securityViolation || appleMissingEntitlement {
            let signed = SignedNfc.profile()
            let note: String
            if signed.formats.contains("TAG") {
                note = "Il profilo \(signed.name) contiene TAG, ma iOS non lo vede nella firma DER."
            } else if signed.name.isEmpty {
                note = "Manca il permesso NFC TAG nella firma dell'app."
            } else {
                note = "Il profilo \(signed.name) non contiene TAG. Su Apple Developer eliminalo e rifallo con NFC Tag Reading."
            }
            finish("closed", note, token: token)
            return
        }
        finish("closed", raw.isEmpty ? "La finestra NFC si è chiusa. Premi Apri lettore tag." : raw, token: token)
    }

    private static func kind(_ tag: NFCTag) -> String {
        switch tag {
        case .miFare: return "MiFare"
        case .iso7816: return "ISO7816"
        case .iso15693: return "ISO15693"
        case .feliCa: return "FeliCa"
        @unknown default: return "NFC"
        }
    }

    private func finish(_ status: String, _ note: String, token: Int? = nil) {
        lock.lock()
        if let token, token != generation {
            lock.unlock()
            return
        }
        if reported {
            lock.unlock()
            return
        }
        reported = true
        let seen = generation
        lock.unlock()
        let callback = onResult
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.generation
            self.lock.unlock()
            if seen != current { return }
            callback?(status, note)
        }
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
