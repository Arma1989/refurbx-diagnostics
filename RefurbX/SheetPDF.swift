import UIKit

struct SheetFacts {
    let grade: String
    let title: String
    let line: String
    let when: Date
    let device: String
    let cable: Bool
    let box: Bool
    let rows: [(group: String, title: String, status: String, note: String)]
}

enum SheetPDF {
    static let disclaimer = "Raccomandazione. Uno o più passaggi di questo test possono essere stati saltati o interrotti. Prima di vendere, acquistare o consegnare il dispositivo, ricontrolla le funzioni che contano per te. Questa scheda descrive solo ciò che è stato provato in questa sessione: non è una certificazione né una garanzia di RefurbX e non sostituisce un controllo diretto."

    static func write(_ facts: SheetFacts) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RefurbX-scheda.pdf")
        let navy = UIColor(red: 0.043, green: 0.059, blue: 0.145, alpha: 1)
        let ink = UIColor(red: 0.12, green: 0.14, blue: 0.2, alpha: 1)
        let mute = UIColor(red: 0.35, green: 0.38, blue: 0.46, alpha: 1)
        let when = formatted(facts.when)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                UIGraphicsPushContext(context.cgContext)
                var y = drawHeader(navy: navy, when: when, device: facts.device)
                y = drawBlock("GRADO ESTETICO", facts.grade, facts.title, facts.line, y: y, ink: ink, mute: mute)
                y += 16
                y = ensure(y, gap: 28, context: context, page: page)
                draw("PROVA FUNZIONALE", UIFont.systemFont(ofSize: 11, weight: .semibold), mute, x: 36, y: &y, width: 523)
                y += 8
                var group = ""
                for row in facts.rows {
                    if row.group != group {
                        group = row.group
                        y = ensure(y, gap: 22, context: context, page: page)
                        draw(group.uppercased(), UIFont.systemFont(ofSize: 10, weight: .semibold), mute, x: 36, y: &y, width: 523)
                        y += 4
                    }
                    let status = statusIt(row.status)
                    y = ensure(y, gap: row.note.isEmpty ? 22 : 36, context: context, page: page)
                    let titleFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
                    (row.title as NSString).draw(at: CGPoint(x: 36, y: y), withAttributes: [.font: titleFont, .foregroundColor: ink])
                    let statusFont = UIFont.systemFont(ofSize: 12, weight: .regular)
                    let statusWidth = (status as NSString).size(withAttributes: [.font: statusFont]).width
                    (status as NSString).draw(at: CGPoint(x: 559 - statusWidth, y: y), withAttributes: [.font: statusFont, .foregroundColor: mute])
                    y += 16
                    if !row.note.isEmpty {
                        draw(String(row.note.prefix(140)), UIFont.systemFont(ofSize: 10, weight: .regular), mute, x: 36, y: &y, width: 523)
                        y += 4
                    }
                }
                y += 12
                y = ensure(y, gap: 36, context: context, page: page)
                let kit = "Cavo \(facts.cable ? "presente" : "assente") · Scatola \(facts.box ? "presente" : "assente")"
                draw(kit, UIFont.systemFont(ofSize: 12, weight: .regular), ink, x: 36, y: &y, width: 523)
                y += 18
                let footerHeight: CGFloat = 92
                if y > page.height - footerHeight - 28 {
                    UIGraphicsPopContext()
                    context.beginPage()
                    UIGraphicsPushContext(context.cgContext)
                    y = 36
                }
                let box = CGRect(x: 36, y: y, width: 523, height: footerHeight)
                UIColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1).setFill()
                UIBezierPath(roundedRect: box, cornerRadius: 10).fill()
                var textY = box.minY + 10
                draw(disclaimer, UIFont.systemFont(ofSize: 9, weight: .regular), mute, x: 48, y: &textY, width: 499)
                UIGraphicsPopContext()
            }
            return url
        } catch {
            return nil
        }
    }

    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func drawHeader(navy: UIColor, when: String, device: String) -> CGFloat {
        navy.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: 595, height: 108)).fill()
        if let mark = UIImage(named: "Mark") {
            mark.draw(in: CGRect(x: 36, y: 28, width: 52, height: 52))
        }
        let white = UIColor.white
        let cyan = UIColor(red: 0.48, green: 0.84, blue: 1, alpha: 1)
        ("REFURBX" as NSString).draw(at: CGPoint(x: 100, y: 30), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: cyan,
        ])
        ("Scheda diagnostica" as NSString).draw(at: CGPoint(x: 100, y: 48), withAttributes: [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: white,
        ])
        (when as NSString).draw(at: CGPoint(x: 100, y: 76), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8),
        ])
        (device as NSString).draw(at: CGPoint(x: 320, y: 76), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8),
        ])
        return 128
    }

    private static func drawBlock(_ kicker: String, _ grade: String, _ title: String, _ line: String, y: CGFloat, ink: UIColor, mute: UIColor) -> CGFloat {
        var cursor = y
        draw(kicker, UIFont.systemFont(ofSize: 11, weight: .semibold), mute, x: 36, y: &cursor, width: 523)
        cursor += 4
        (grade as NSString).draw(at: CGPoint(x: 36, y: cursor), withAttributes: [
            .font: UIFont.systemFont(ofSize: 42, weight: .semibold),
            .foregroundColor: ink,
        ])
        (title as NSString).draw(at: CGPoint(x: 130, y: cursor + 14), withAttributes: [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: ink,
        ])
        cursor += 52
        draw(line, UIFont.systemFont(ofSize: 12, weight: .regular), mute, x: 36, y: &cursor, width: 523)
        return cursor
    }

    private static func ensure(_ y: CGFloat, gap: CGFloat, context: UIGraphicsPDFRendererContext, page: CGRect) -> CGFloat {
        if y + gap < page.height - 36 { return y }
        UIGraphicsPopContext()
        context.beginPage()
        UIGraphicsPushContext(context.cgContext)
        return 36
    }

    private static func draw(_ text: String, _ font: UIFont, _ color: UIColor, x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: 800), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        (text as NSString).draw(with: CGRect(x: x, y: y, width: width, height: ceil(bounds.height) + 2), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        y += ceil(bounds.height)
    }
}
