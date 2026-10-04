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
                    DisplayPane(
                        onPass: { model.settle("display", "pass", "Schermo confermato") },
                        onFail: { model.settle("display", "fail", "Difetti visibili") },
                        onSkip: { model.settle("display", "skip", "Non eseguito") }
                    )
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
                    TouchPane(onProgress: { model.touchProgress($0, $1) }, onPass: { model.settle("touch", "pass", "Tutte le celle rispondono") })
                } else if model.currentId == "multitouch" {
                    MultiPane(count: model.fingers, onCount: { model.fingers = $0 }, onPass: { model.settle("multitouch", "pass", "\($0) dita") })
                } else if model.showCamera {
                    CameraPreview(session: model.camera.session).clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.actions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(model.actions.enumerated()), id: \.element.id) { position, act in
                        Button(act.label) { model.onAction(act) }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .buttonStyle(.borderedProminent)
                            .tint(position == 0 ? Color(red: 0.48, green: 0.84, blue: 1) : .white.opacity(0.16))
                            .foregroundStyle(position == 0 ? Color(red: 0.04, green: 0.06, blue: 0.16) : .white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(red: 0.04, green: 0.06, blue: 0.16))
            }
        }
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
                ForEach(Catalog.rows, id: \.id) { row in
                    let item = model.outcomes.first { $0.id == row.id }
                    Text("\(row.title) · \(statusIt(item?.status ?? "skip"))").foregroundStyle(.white)
                    if let note = item?.note, !note.isEmpty {
                        Text(note).font(.footnote).foregroundStyle(.white.opacity(0.65))
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
    let onSkip: () -> Void
    @State private var cursor = 0
    private let colors: [Color] = [.white, .black, .red, .green, .blue, Color(white: 0.5)]

    var body: some View {
        if cursor < colors.count {
            ZStack {
                colors[cursor].ignoresSafeArea()
                TapCatcher { cursor += 1 }.ignoresSafeArea()
                Text(cursor == 0 ? "Tocca per il colore successivo" : "\(cursor + 1) / \(colors.count)")
                    .foregroundStyle(cursor == 0 || cursor == 5 ? .black : .white)
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
            VStack(spacing: 16) {
                Text("Lo schermo è uniforme, senza pixel spenti, macchie o linee?").font(.title2).foregroundStyle(.white)
                Button("Schermo ok", action: onPass).buttonStyle(.borderedProminent)
                Button("Vedo difetti", action: onFail).foregroundStyle(.white)
                Button("Salta", action: onSkip).foregroundStyle(.white.opacity(0.7))
            }
            .padding(24)
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

private struct TouchPane: View {
    let onProgress: (Int, Int) -> Void
    let onPass: () -> Void

    var body: some View {
        TouchGrid(onProgress: onProgress, onPass: onPass)
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
    private let columns = 4
    private let rows = 6
    private var hit = Array(repeating: false, count: 24)
    private var sent = false

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { paint(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { paint(touches) }

    private func paint(_ touches: Set<UITouch>) {
        guard bounds.width > 1, bounds.height > 1 else { return }
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
        guard bounds.width > 1, bounds.height > 1 else { return }
        let width = bounds.width / CGFloat(columns)
        let height = bounds.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let filled = hit[row * columns + column]
                let color = filled
                    ? UIColor(red: 0.12, green: 0.66, blue: 0.48, alpha: 1)
                    : UIColor(red: 0.14, green: 0.19, blue: 0.34, alpha: 1)
                color.setFill()
                let box = CGRect(x: CGFloat(column) * width + 2, y: CGFloat(row) * height + 2, width: width - 4, height: height - 4)
                UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
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
                Text("\(count)")
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

    private func report(_ event: UIEvent?) {
        let count = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        onCount?(count)
        if !sent && count >= 2 {
            sent = true
            onPass?(count)
        }
    }
}
