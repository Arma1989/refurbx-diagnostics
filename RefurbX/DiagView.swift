import SwiftUI

struct DiagView: View {
    @StateObject private var model = DiagModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.06, blue: 0.16).ignoresSafeArea()
            switch model.phase {
            case "report":
                ReportScreen(model: model)
            case "run":
                if model.currentId == "display" {
                    DisplayPane(onPass: { model.settle("display", "pass", "Schermo confermato") }, onFail: { model.settle("display", "fail", "Difetti visibili") })
                } else {
                    RunScreen(model: model)
                }
            default:
                IntroScreen { model.begin() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            model.onScenePhase(phase)
        }
        .preferredColorScheme(.dark)
    }
}

private struct IntroScreen: View {
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RefurbX").font(.headline).foregroundStyle(Color(red: 0.48, green: 0.84, blue: 1))
            Text("Diagnostics").font(.largeTitle.weight(.semibold)).foregroundStyle(.white)
            Text("I test girano su questo iPhone. Alla fine invii la scheda. L'immagine a infrarossi di Face ID resta nel sistema.")
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Button(action: start) {
                Text("Inizia i test").frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.48, green: 0.84, blue: 1))
            .foregroundStyle(Color(red: 0.04, green: 0.06, blue: 0.16))
        }
        .padding(24)
    }
}

private struct RunScreen: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(model.index + 1) / \(Catalog.rows.count)").font(.footnote).foregroundStyle(.white.opacity(0.6))
            Text(Catalog.title(model.currentId)).font(.largeTitle.weight(.semibold)).foregroundStyle(.white)
            if !model.hint.isEmpty { Text(model.hint).foregroundStyle(.white.opacity(0.72)) }
            if !model.detail.isEmpty { Text(model.detail).foregroundStyle(Color(red: 0.48, green: 0.84, blue: 1)) }
            Group {
                if model.currentId == "touch" {
                    TouchPane { model.settle("touch", "pass", "Tutte le celle rispondono") }
                } else if model.currentId == "multitouch" {
                    MultiPane(count: model.fingers) { count in model.settle("multitouch", "pass", "\(count) dita") }
                } else if model.currentId == "force" {
                    ForcePane(label: $model.pressure) { model.settle("force", "pass", "La pressione cambia") }
                } else if model.currentId == "stylus" {
                    StylusPane { model.settle("stylus", "pass", "Tratto di Apple Pencil ricevuto") }
                } else if model.showCamera {
                    CameraPreview(session: model.camera.session).clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { position, act in
                Button(act.label) { model.onAction(act) }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .tint(position == 0 ? Color(red: 0.48, green: 0.84, blue: 1) : .white.opacity(0.16))
            }
        }
        .padding(20)
    }
}

private struct ReportScreen: View {
    @ObservedObject var model: DiagModel

    var body: some View {
        let mark = gradeOf(model.outcomes)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scheda").foregroundStyle(Color(red: 0.48, green: 0.84, blue: 1))
                Text("Grado \(mark.letter)").font(.largeTitle.weight(.semibold)).foregroundStyle(.white)
                Text("\(mark.label) · \(mark.score)/100").foregroundStyle(.white.opacity(0.72))
                ForEach(model.outcomes) { item in
                    Text("\(Catalog.title(item.id)) · \(statusIt(item.status))").foregroundStyle(.white)
                    if !item.note.isEmpty {
                        Text(item.note).font(.footnote).foregroundStyle(.white.opacity(0.65))
                    }
                }
                ShareLink(item: model.shareText()) {
                    Text("Invia scheda").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.48, green: 0.84, blue: 1))
                .padding(.top, 12)
            }
            .padding(20)
        }
    }
}

private struct DisplayPane: View {
    let onPass: () -> Void
    let onFail: () -> Void
    @State private var cursor = 0
    private let colors: [Color] = [.white, .black, .red, .green, .blue, Color(white: 0.5)]

    var body: some View {
        if cursor < colors.count {
            colors[cursor]
                .ignoresSafeArea()
                .overlay(Text(cursor == 0 ? "Tocca per il colore successivo" : "\(cursor + 1) / \(colors.count)").foregroundStyle(cursor == 0 || cursor == 5 ? .black : .white))
                .onTapGesture { cursor += 1 }
        } else {
            VStack(spacing: 16) {
                Text("Lo schermo è uniforme, senza pixel spenti, macchie o linee?").font(.title2).foregroundStyle(.white)
                Button("Schermo ok", action: onPass).buttonStyle(.borderedProminent)
                Button("Vedo difetti", action: onFail).foregroundStyle(.white)
            }
            .padding(24)
        }
    }
}

private struct TouchPane: View {
    let onPass: () -> Void
    @State private var hit = Array(repeating: false, count: 24)
    @State private var sent = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { column in
                        let cell = row * 4 + column
                        Rectangle()
                            .fill(hit[cell] ? Color(red: 0.12, green: 0.66, blue: 0.48) : Color(red: 0.14, green: 0.19, blue: 0.34))
                            .onTapGesture {
                                hit[cell] = true
                                if !sent && hit.allSatisfy({ $0 }) {
                                    sent = true
                                    onPass()
                                }
                            }
                    }
                }
            }
        }
    }
}

private struct MultiPane: View {
    let count: Int
    let onPass: (Int) -> Void
    @State private var maxFingers = 0
    @State private var sent = false

    var body: some View {
        Text("\(max(count, maxFingers))")
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
            .overlay(MultitouchReader { value in
                if value > maxFingers { maxFingers = value }
                if !sent && value >= 2 {
                    sent = true
                    onPass(value)
                }
            })
    }
}

private struct MultitouchReader: UIViewRepresentable {
    let onCount: (Int) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.onCount = onCount
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onCount = onCount
    }
}

final class TouchView: UIView {
    var onCount: ((Int) -> Void)?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(event) }
    private func report(_ event: UIEvent?) {
        let count = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        onCount?(count)
    }
}

private struct ForcePane: View {
    @Binding var label: String
    let onPass: () -> Void

    var body: some View {
        Text(label)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.14, green: 0.19, blue: 0.34))
            .overlay(ForceReader { low, high in
                label = String(format: "%.2f – %.2f", low, high)
                if high - low > 0.15 { onPass() }
            })
    }
}

private struct ForceReader: UIViewRepresentable {
    let onPressure: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> ForceView {
        let view = ForceView()
        view.onPressure = onPressure
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ForceView, context: Context) {
        uiView.onPressure = onPressure
    }
}

final class ForceView: UIView {
    var onPressure: ((CGFloat, CGFloat) -> Void)?
    private var low: CGFloat = 1
    private var high: CGFloat = 0
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            low = min(low, touch.force)
            high = max(high, touch.force)
        }
        onPressure?(low, high)
    }
}

private struct StylusPane: View {
    let onPass: () -> Void

    var body: some View {
        Text("In attesa di un tratto")
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.14, green: 0.19, blue: 0.34))
            .overlay(StylusReader(onPass: onPass))
    }
}

private struct StylusReader: UIViewRepresentable {
    let onPass: () -> Void

    func makeUIView(context: Context) -> PencilView {
        let view = PencilView()
        view.onPencil = onPass
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PencilView, context: Context) {
        uiView.onPencil = onPass
    }
}

final class PencilView: UIView {
    var onPencil: (() -> Void)?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { check(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { check(touches) }
    private func check(_ touches: Set<UITouch>) {
        if touches.contains(where: { $0.type == .pencil }) { onPencil?() }
    }
}
