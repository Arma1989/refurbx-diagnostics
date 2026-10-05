import SwiftUI

enum Look {
    static let navy = Color(red: 0.043, green: 0.059, blue: 0.145)
    static let cyan = Color(red: 0.48, green: 0.84, blue: 1)
    static let ink = Color.white.opacity(0.78)
    static let mute = Color.white.opacity(0.58)
    static let line = Color.white.opacity(0.12)
    static let card = Color.white.opacity(0.06)
    static let pass = Color(red: 0.12, green: 0.66, blue: 0.48)
    static let fail = Color(red: 0.86, green: 0.28, blue: 0.30)

    static func wash() -> some View {
        ZStack {
            navy
            RadialGradient(
                colors: [Color(red: 0.10, green: 0.22, blue: 0.38).opacity(0.85), navy],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct StepHeader: View {
    let index: Int
    let total: Int
    let group: String
    let title: String
    var message: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(index + 1), total: Double(max(total, 1)))
                .tint(Look.cyan)
            Text("\(group.uppercased())  ·  \(index + 1) / \(total)")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Look.cyan)
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 17))
                    .foregroundStyle(Look.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct BenchButton: View {
    enum Kind { case primary, secondary, danger }

    let title: String
    var kind: Kind = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(ink)
                .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var fill: Color {
        switch kind {
        case .primary: return Look.cyan
        case .secondary: return Color.white.opacity(0.08)
        case .danger: return Look.fail
        }
    }

    private var ink: Color {
        kind == .primary ? Look.navy : .white
    }
}

struct ActionBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Look.navy.opacity(0.96))
    }
}

struct BenchCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Look.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Look.line, lineWidth: 1)
            )
    }
}
