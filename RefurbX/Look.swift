import SwiftUI

enum Look {
    static let paper = Color(red: 246.0 / 255, green: 248.0 / 255, blue: 250.0 / 255)
    static let title = Color(red: 37.0 / 255, green: 61.0 / 255, blue: 78.0 / 255)
    static let cyan = Color(red: 11.0 / 255, green: 169.0 / 255, blue: 237.0 / 255)
    static let ink = Color(red: 37.0 / 255, green: 61.0 / 255, blue: 78.0 / 255).opacity(0.78)
    static let mute = Color(red: 37.0 / 255, green: 61.0 / 255, blue: 78.0 / 255).opacity(0.55)
    static let line = Color(red: 37.0 / 255, green: 61.0 / 255, blue: 78.0 / 255).opacity(0.12)
    static let card = Color.white
    static let navy = title
    static let banner = Color(red: 11.0 / 255, green: 169.0 / 255, blue: 237.0 / 255).opacity(0.14)
    static let pass = Color(red: 0.12, green: 0.66, blue: 0.48)
    static let fail = Color(red: 0.86, green: 0.28, blue: 0.30)

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("DM Sans", size: size).weight(weight)
    }

    static func wash() -> some View {
        paper.ignoresSafeArea()
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
            HStack(spacing: 8) {
                Text(group.uppercased())
                    .font(Look.text(12, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Look.cyan, in: Capsule())
                Text("\(index + 1) / \(total)")
                    .font(Look.text(13, .semibold))
                    .foregroundStyle(Look.mute)
            }
            Text(title)
                .font(Look.text(34, .semibold))
                .foregroundStyle(Look.title)
                .fixedSize(horizontal: false, vertical: true)
            if !message.isEmpty {
                Text(message)
                    .font(Look.text(17))
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
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Look.text(17, .semibold))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(ink)
                .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(kind == .secondary ? Look.line : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }

    private var fill: Color {
        switch kind {
        case .primary: return Look.cyan
        case .secondary: return Color.white
        case .danger: return Look.fail
        }
    }

    private var ink: Color {
        kind == .secondary ? Look.title : .white
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
        .background(Look.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(Look.line).frame(height: 1)
        }
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
