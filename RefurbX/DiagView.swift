import AVKit
import MapKit
import MediaPlayer
import SwiftUI

private let navy = Look.navy
private let cyan = Look.cyan

struct DiagView: View {
    @StateObject private var model = DiagModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Look.wash()
            switch model.phase {
            case "report":
                ReportScreen(model: model)
            case "guide":
                GuideScreen(model: model)
            case "run":
                if model.currentId == "display" {
                    DisplayPane(
                        onPass: { model.settle("display", "pass", "Schermo confermato") },
                        onFail: { model.settle("display", "fail", "Difetti visibili") },
                        onSkip: { model.settle("display", "skip", "Non eseguito") }
                    )
                } else if model.currentId == "touch" {
                    TouchFull(model: model)
                } else {
                    RunScreen(model: model)
                }
            default:
                IntroScreen(
                    canResume: model.canResume,
                    startAll: { model.begin(group: nil) },
                    startGroup: { model.begin(group: $0) },
                    resume: { model.resume() }
                )
            }
        }
        .onChange(of: scenePhase) { _, phase in
            model.onScenePhase(phase)
        }
        .preferredColorScheme(.dark)
    }
}

private struct IntroScreen: View {
    let canResume: Bool
    let startAll: () -> Void
    let startGroup: (String) -> Void
    let resume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(cyan.opacity(0.16))
                        .frame(width: 52, height: 52)
                    Circle()
                        .stroke(cyan.opacity(0.55), lineWidth: 1)
                        .frame(width: 52, height: 52)
                    Image(systemName: "iphone")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(cyan)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("REFURBX")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(cyan)
                    Text("Diagnostica")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            Text("Scegli tutte le prove, oppure un solo banco: audio, fotocamere, sensori.")
                .font(.system(size: 17))
                .foregroundStyle(Look.ink)
            if canResume {
                BenchButton(title: "Riprendi la scheda", kind: .secondary, action: resume)
            }
            BenchButton(title: "Tutti i test · \(HardwareFit.rows(in: nil).count)", action: startAll)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Catalog.groups.filter { !HardwareFit.rows(in: $0).isEmpty }, id: \.self) { group in
                        Button(action: { startGroup(group) }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(cyan.opacity(0.14))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: Catalog.symbol(group))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(cyan)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Catalog.homeTitle(group))
                                        .font(.system(size: 17, weight: .semibold))
                                    Text(Catalog.homeLine(group))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Look.mute)
                                }
                                Spacer()
                                Text("\(HardwareFit.rows(in: group).count)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Look.mute)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Look.mute)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cyan)
                                    .frame(width: 3)
                                    .padding(.vertical, 14)
                                    .padding(.leading, 0)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Look.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
    }
}

private struct RunScreen: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(
                index: model.index,
                total: model.planCount,
                group: Catalog.group(model.currentId),
                title: Catalog.title(model.currentId),
                message: model.hint
            )
            if !model.detail.isEmpty {
                Text(model.detail)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(cyan)
            }
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.actions.isEmpty {
                ActionBar {
                    ForEach(model.actions) { act in
                        BenchButton(title: act.label, kind: buttonKind(act)) { model.onAction(act) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var stage: some View {
        if model.currentId == "memory" {
            MemoryBoard(total: model.memoryTotal, free: model.memoryFree, used: model.memoryUsed)
        } else if model.currentId == "identity" {
            Text(model.detail.isEmpty ? "Lettura del modello" : model.detail)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if model.currentId == "network" || model.currentId == "bluetooth" {
            KeyMark(on: model.keyOk, waiting: model.detail.isEmpty ? "Controllo" : model.detail)
        } else if model.currentId == "volume_up" || model.currentId == "volume_down" || model.currentId == "power_button" {
            ZStack {
                if model.currentId != "power_button" {
                    VolumeCatcher()
                        .frame(width: 200, height: 36)
                }
                KeyMark(
                    on: model.keyOk,
                    waiting: model.keyOk
                        ? "Tasto ok"
                        : (model.currentId == "volume_down" ? "Premi volume −" : model.currentId == "volume_up" ? "Premi volume +" : "Premi accensione")
                )
            }
        } else if model.currentId == "light" {
            VStack(spacing: 12) {
                LightBar(level: model.lightLevel)
                if model.showCamera {
                    CameraPreview(session: model.camera.session, front: false)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        } else if model.currentId == "gps" {
            GpsBoard(accuracy: model.gpsAccuracy, latitude: model.gpsLatitude, longitude: model.gpsLongitude)
        } else if model.currentId == "multitouch" {
            MultiPane(count: model.fingers, onCount: { model.fingers = $0 }, onPass: { model.settle("multitouch", "pass", "\($0) dita") })
        } else if model.currentId == "accelerometer" {
            AccelPad(model: model)
        } else if model.currentId == "gyroscope" {
            GyroList(model: model)
        } else if model.currentId == "compass" {
            CompassRing(marks: model.compassMarks, heading: model.heading)
        } else if model.currentId == "truedepth" {
            FacePlate(points: model.facePoints)
        } else if model.currentId == "lidar" {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.72))
                if let image = model.depthShot {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(8)
                } else {
                    Text("Grigia finché non inquadri qualcosa di vicino")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(white: 0.28))
                        .padding(24)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if model.currentId == "microphone" || model.audioSpot == "speaker" || model.audioSpot == "ear" {
            PhoneMap(spot: model.currentId == "microphone" ? model.micSpot : model.audioSpot, level: model.currentId == "microphone" ? model.micLevel : 0)
        } else if model.currentId == "force" {
            ForcePad { model.noteForce($0, max: $1) }
                .overlay {
                    Text("\(Int((model.forceUnit * 100).rounded()))")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)
                        .allowsHitTesting(false)
                }
        } else if model.showCamera {
            VStack(spacing: 8) {
                CameraPreview(session: model.camera.session, front: model.currentId == "camera_front")
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if model.currentId == "autofocus" {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(cyan, lineWidth: 3)
                                .frame(width: 160, height: 160)
                                .allowsHitTesting(false)
                        }
                    }
                if model.currentId == "camera_back", model.lenses.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(model.lenses, id: \.rawValue) { type in
                            let title = DiagModel.lensTitle(type)
                            Button(title) { model.useLens(type) }
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(model.lens == type ? cyan : Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(model.lens == type ? navy : .white)
                        }
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    private func buttonKind(_ act: Act) -> BenchButton.Kind {
        switch act.status {
        case "pass", "mic-ok", "camera-pass", "truedepth-retry": return .primary
        case "fail", "mic-bad": return .danger
        default: return .secondary
        }
    }
}

private struct GradeFilm: View {
    let name: String
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(360.0 / 640.0, contentMode: .fit)
            .frame(maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Look.line, lineWidth: 1))
            .onAppear { start() }
            .onChange(of: name) { _, _ in start() }
            .onDisappear {
                player?.pause()
                looper = nil
                player = nil
            }
    }

    private func start() {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return }
        let queue = AVQueuePlayer()
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        queue.isMuted = true
        queue.play()
    }
}

private struct ReportSection: Identifiable {
    let title: String
    let rows: [Catalog.Row]
    var id: String { title }
}

private struct ReportScreen: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        let choice = Cosmetic.find(model.lookGrade)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SCHEDA")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(cyan)
                if let when = model.testedAt {
                    Text(Self.stamp.string(from: when))
                        .font(.system(size: 15))
                        .foregroundStyle(Look.mute)
                }
                BenchCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GRADO ESTETICO")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(cyan)
                        Text(choice?.id ?? "—")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(choice?.title ?? "Scegli l'aspetto del dispositivo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(choice?.line ?? "Il grado della scheda è quello estetico di RefurbX: A+, A, B o C. I test funzionali restano elencati sotto.")
                            .font(.system(size: 16))
                            .foregroundStyle(Look.ink)
                        Text(functionLine)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Look.mute)
                    }
                }
                Text("Guarda l'esempio e scegli il grado che somiglia di più al telefono.")
                    .font(.system(size: 16))
                    .foregroundStyle(Look.ink)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Cosmetic.choices, id: \.id) { item in
                        Button(action: { model.chooseLook(item.id) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.id)
                                    .font(.system(size: 28, weight: .semibold))
                                Text(item.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(item.line)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Look.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .foregroundStyle(.white)
                            .background(model.lookGrade == item.id ? cyan.opacity(0.16) : Look.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(model.lookGrade == item.id ? cyan : Look.line, lineWidth: model.lookGrade == item.id ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let choice {
                    GradeFilm(name: choice.film)
                    Text("Esempio \(choice.id) · \(choice.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Look.mute)
                }
                BenchCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("IN DOTAZIONE")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(cyan)
                        Toggle("Cavo", isOn: Binding(get: { model.withCable }, set: { model.setCable($0) }))
                            .tint(cyan)
                            .foregroundStyle(.white)
                        Toggle("Scatola", isOn: Binding(get: { model.withBox }, set: { model.setBox($0) }))
                            .tint(cyan)
                            .foregroundStyle(.white)
                    }
                }
                ForEach(grouped) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(cyan)
                            .padding(.top, 6)
                        BenchCard {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(section.rows.enumerated()), id: \.element.id) { offset, row in
                                    let item = model.outcomes.first { $0.id == row.id }
                                    resultRow(row, item: item)
                                    if offset < section.rows.count - 1 {
                                        Rectangle().fill(Look.line).frame(height: 1)
                                    }
                                }
                            }
                        }
                    }
                }
                BenchCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BANCO")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(cyan)
                        Text("Incolla il link che vedi sul computer, sotto il codice.")
                            .font(.system(size: 15))
                            .foregroundStyle(Look.ink)
                        TextField("https://…/t/CODICE", text: $model.benchLink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(12)
                            .foregroundStyle(.white)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button(action: { model.sendToBench() }) {
                            Text(model.benchSending ? "Invio…" : "Invia al banco")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(navy)
                                .background(cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.benchSending || model.benchLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !model.benchState.isEmpty {
                            Text(model.benchState)
                                .font(.system(size: 15))
                                .foregroundStyle(Look.ink)
                        }
                    }
                }
                Text(SheetPDF.disclaimer)
                    .font(.system(size: 13))
                    .foregroundStyle(Look.mute)
                if let file = model.sheetFile {
                    ShareLink(item: file) {
                        Text("Invia scheda PDF")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(navy)
                            .background(cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Scegli il grado estetico per creare il PDF.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Look.ink)
                }
                BenchButton(title: "Nuova diagnosi", kind: .secondary) { model.restart() }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }

    private var functionLine: String {
        let rows = model.activeRows
        let pass = rows.filter { row in model.outcomes.first { $0.id == row.id }?.status == "pass" }.count
        let fail = rows.filter { row in model.outcomes.first { $0.id == row.id }?.status == "fail" }.count
        let skipped = rows.count - pass - fail
        return "Funzioni: \(pass) conformi · \(fail) da rivedere · \(skipped) saltate o assenti"
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    private var grouped: [ReportSection] {
        var order: [String] = []
        var buckets: [String: [Catalog.Row]] = [:]
        for row in model.activeRows {
            if buckets[row.group] == nil { order.append(row.group) }
            buckets[row.group, default: []].append(row)
        }
        return order.map { ReportSection(title: $0, rows: buckets[$0] ?? []) }
    }

    private func resultRow(_ row: Catalog.Row, item: Outcome?) -> some View {
        let status = item?.status ?? "skip"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).foregroundStyle(.white)
                Spacer(minLength: 12)
                Text(statusIt(status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color(status))
            }
            if let note = item?.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Look.mute)
            }
        }
        .padding(.vertical, 10)
    }

    private func color(_ status: String) -> Color {
        switch status {
        case "pass": return Look.pass
        case "fail": return Look.fail
        default: return .white.opacity(0.55)
        }
    }
}

private struct DisplayPane: View {
    let onPass: () -> Void
    let onFail: () -> Void
    let onSkip: () -> Void
    @State private var cursor = 0
    private let colors: [Color] = [.white, .black, .red, .green, .blue, .yellow, Color(white: 0.5)]

    var body: some View {
        if cursor < colors.count {
            ZStack {
                colors[cursor].ignoresSafeArea()
                TapCatcher { cursor += 1 }.ignoresSafeArea()
                Text(cursor == 0 ? "Tocca per il colore successivo" : "\(cursor + 1) / \(colors.count)")
                    .foregroundStyle(cursor == 0 || cursor == 5 || cursor == 6 ? .black : .white)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Button("Salta", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .padding(.trailing, 16)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("DISPLAY")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(cyan)
                Text("Lo schermo è uniforme, senza pixel spenti, macchie o linee?")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                BenchButton(title: "Schermo ok", action: onPass)
                BenchButton(title: "Vedo difetti", kind: .danger, action: onFail)
                BenchButton(title: "Salta", kind: .secondary, action: onSkip)
            }
            .padding(22)
        }
    }
}

private struct TapCatcher: UIViewRepresentable {
    let onTap: () -> Void

    func makeUIView(context: Context) -> TapView {
        let view = TapView()
        view.onTap = onTap
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TapView, context: Context) {
        uiView.onTap = onTap
    }
}

final class TapView: UIView {
    var onTap: (() -> Void)?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTap?()
    }
}

private struct TouchFull: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        ZStack {
            TouchGrid(
                onProgress: { model.touchProgress($0, $1) },
                onPass: { model.settle("touch", "pass", "Tutte le celle rispondono") }
            )
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            Text(model.detail.isEmpty ? "Tutto lo schermo" : model.detail)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            Button("Salta") { model.settle("touch", "skip", "Non eseguito") }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        .overlay(alignment: .bottom) {
            Button("Zona morta") { model.settle("touch", "fail", "Una zona del touch non risponde") }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 12)
        }
    }
}

private struct MemoryBoard: View {
    let total: String
    let free: String
    let used: String

    var body: some View {
        VStack(spacing: 12) {
            line("Totale", total)
            line("Libero", free)
            line("Usato", used)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Look.line, lineWidth: 1))
    }
}

private struct GpsBoard: View {
    let accuracy: String
    let latitude: Double?
    let longitude: Double?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 12) {
            map
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Look.line, lineWidth: 1)
                )
            Text(accuracy.isEmpty ? "In attesa" : accuracy)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var map: some View {
        if let latitude, let longitude {
            Map(position: $position) {
                Marker("Fix", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            .mapStyle(.standard)
            .onAppear { recenter(latitude, longitude) }
            .onChange(of: latitude) { _, value in recenter(value, longitude) }
            .onChange(of: longitude) { _, value in recenter(latitude, value) }
        } else {
            ZStack {
                Look.card
                VStack(spacing: 8) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(cyan)
                    Text("In cerca del punto")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func recenter(_ latitude: Double, _ longitude: Double) {
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        ))
    }
}

private struct TouchGrid: UIViewRepresentable {
    let onProgress: (Int, Int) -> Void
    let onPass: () -> Void

    func makeUIView(context: Context) -> TouchGridView {
        let view = TouchGridView()
        view.onProgress = onProgress
        view.onPass = onPass
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: TouchGridView, context: Context) {
        uiView.onProgress = onProgress
        uiView.onPass = onPass
    }
}

final class TouchGridView: UIView {
    var onProgress: ((Int, Int) -> Void)?
    var onPass: (() -> Void)?
    private let cell: CGFloat = 28
    private var columns = 8
    private var rows = 12
    private var hit: [Bool] = []
    private var sent = false

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildIfNeeded()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { paint(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { paint(touches) }

    private func rebuildIfNeeded() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let nextColumns = max(8, Int(bounds.width / cell))
        let nextRows = max(12, Int(bounds.height / cell))
        if nextColumns == columns, nextRows == rows, hit.count == nextColumns * nextRows { return }
        columns = nextColumns
        rows = nextRows
        hit = Array(repeating: false, count: columns * rows)
        sent = false
    }

    private func paint(_ touches: Set<UITouch>) {
        guard bounds.width > 1, bounds.height > 1, !hit.isEmpty else { return }
        let width = bounds.width / CGFloat(columns)
        let height = bounds.height / CGFloat(rows)
        for touch in touches {
            let point = touch.location(in: self)
            let column = min(columns - 1, max(0, Int(point.x / width)))
            let row = min(rows - 1, max(0, Int(point.y / height)))
            hit[row * columns + column] = true
        }
        setNeedsDisplay()
        let done = hit.filter { $0 }.count
        onProgress?(done, hit.count)
        if !sent && hit.allSatisfy({ $0 }) {
            sent = true
            onPass?()
        }
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 1, bounds.height > 1, !hit.isEmpty else { return }
        let width = bounds.width / CGFloat(columns)
        let height = bounds.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let filled = hit[row * columns + column]
                let color = filled
                    ? UIColor(red: 0.12, green: 0.66, blue: 0.48, alpha: 1)
                    : UIColor(red: 0.14, green: 0.19, blue: 0.34, alpha: 1)
                color.setFill()
                let box = CGRect(
                    x: CGFloat(column) * width + 1,
                    y: CGFloat(row) * height + 1,
                    width: max(1, width - 2),
                    height: max(1, height - 2)
                )
                UIBezierPath(roundedRect: box, cornerRadius: 3).fill()
            }
        }
    }
}

private struct MultiPane: View {
    let count: Int
    let onCount: (Int) -> Void
    let onPass: (Int) -> Void

    var body: some View {
        MultitouchReader(onCount: onCount, onPass: onPass)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Text(count >= 2 ? "\(count)" : "\(count) / 2")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
    }
}

private struct MultitouchReader: UIViewRepresentable {
    let onCount: (Int) -> Void
    let onPass: (Int) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.onCount = onCount
        view.onPass = onPass
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onCount = onCount
        uiView.onPass = onPass
    }
}

final class TouchView: UIView {
    var onCount: ((Int) -> Void)?
    var onPass: ((Int) -> Void)?
    private var sent = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }

    private func report(_ event: UIEvent?) {
        let count = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        onCount?(count)
        if !sent && count >= 2 {
            sent = true
            onPass?(count)
        }
    }
}

private struct PhoneMap: View {
    let spot: String
    let level: Int

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 3)
                    .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white.opacity(0.04)))
                    .frame(width: 168, height: 300)
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 62, height: 18)
                    .offset(y: -118)
                Capsule()
                    .fill(spot == "ear" || spot == "front" ? cyan : Color.white.opacity(0.28))
                    .frame(width: 48, height: 8)
                    .offset(y: -92)
                Circle()
                    .fill(spot == "back" ? cyan : Color.white.opacity(0.28))
                    .frame(width: 16, height: 16)
                    .offset(x: 46, y: -86)
                Capsule()
                    .fill(spot == "speaker" || spot == "bottom" ? cyan : Color.white.opacity(0.28))
                    .frame(width: 56, height: 8)
                    .offset(y: 128)
                Text(caption)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(width: 110)
            }
            .frame(width: 168, height: 300)
            if spot == "bottom" || spot == "front" || spot == "back" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Livello").font(.footnote).foregroundStyle(.white.opacity(0.7))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(cyan)
                                .frame(width: geo.size.width * CGFloat(min(100, max(0, level))) / 100)
                        }
                    }
                    .frame(height: 10)
                }
                .frame(width: 180)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caption: String {
        switch spot {
        case "speaker": return "Altoparlante in basso"
        case "ear": return "Capsula in alto"
        case "bottom": return "Microfono in basso"
        case "front": return "Microfono in alto"
        case "back": return "Microfono dietro"
        default: return "Microfono"
        }
    }
}

private struct FacePlate: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            guard points.count > 40 else { return }
            var dots = Path()
            for point in points {
                let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
                dots.addEllipse(in: CGRect(x: center.x - 1.1, y: center.y - 1.1, width: 2.2, height: 2.2))
            }
            context.fill(dots, with: .color(.white))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            if points.count < 40 {
                Text("Avvicina il volto. I puntini girano con la testa.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(24)
            }
        }
    }
}

private struct KeyMark: View {
    let on: Bool
    let waiting: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 88, weight: .semibold))
                .foregroundStyle(on ? Color(red: 0.12, green: 0.66, blue: 0.48) : Color.white.opacity(0.35))
            Text(waiting)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LightBar: View {
    let level: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Luce vista dalla fotocamera")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(cyan)
                        .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, level)))))
                }
            }
            .frame(height: 18)
        }
    }
}

private struct VolumeCatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 200, height: 36))
        view.showsRouteButton = false
        view.alpha = 0.02
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct AccelPad: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color.white.opacity(0.04))
                Capsule().fill(model.edgeTop ? Color(red: 0.12, green: 0.66, blue: 0.48) : Color(red: 0.7, green: 0.16, blue: 0.18))
                    .frame(width: side * 0.62, height: 16)
                    .position(x: side / 2, y: 22)
                Capsule().fill(model.edgeBottom ? Color(red: 0.12, green: 0.66, blue: 0.48) : Color(red: 0.7, green: 0.16, blue: 0.18))
                    .frame(width: side * 0.62, height: 16)
                    .position(x: side / 2, y: side - 22)
                Capsule().fill(model.edgeLeft ? Color(red: 0.12, green: 0.66, blue: 0.48) : Color(red: 0.7, green: 0.16, blue: 0.18))
                    .frame(width: 16, height: side * 0.62)
                    .position(x: 22, y: side / 2)
                Capsule().fill(model.edgeRight ? Color(red: 0.12, green: 0.66, blue: 0.48) : Color(red: 0.7, green: 0.16, blue: 0.18))
                    .frame(width: 16, height: side * 0.62)
                    .position(x: side - 22, y: side / 2)
                Circle()
                    .fill(cyan)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .position(x: side / 2 + model.dotX * side * 0.32, y: side / 2 + model.dotY * side * 0.32)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GyroList: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        VStack(spacing: 8) {
            row("Fermo", model.gyroRest)
            row("Di lato", model.gyroTilt)
            row("Avanti e indietro", model.gyroPitch)
            row("Intorno a te", model.gyroYaw)
        }
    }

    private func row(_ title: String, _ on: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Text(on ? "Fatto" : "–").foregroundStyle(on ? cyan : .white.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Look.line, lineWidth: 1))
    }
}

private struct CompassRing: View {
    let marks: Set<Int>
    let heading: Double

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(marks.contains(index) ? cyan : Color.white.opacity(0.2))
                    .frame(width: 10, height: 22)
                    .offset(y: -108)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Text("↑")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(heading))
        }
        .frame(width: 260, height: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ForcePad: UIViewRepresentable {
    let onForce: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> ForceView {
        let view = ForceView()
        view.onForce = onForce
        view.backgroundColor = UIColor(white: 1, alpha: 0.06)
        view.layer.cornerRadius = 24
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: ForceView, context: Context) {
        uiView.onForce = onForce
    }
}

final class ForceView: UIView {
    var onForce: ((CGFloat, CGFloat) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches) }

    private func report(_ touches: Set<UITouch>) {
        for touch in touches {
            onForce?(touch.force, touch.maximumPossibleForce)
        }
    }
}
