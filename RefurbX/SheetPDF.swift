import UIKit

enum BrandMark {
    static func image() -> UIImage? {
        if let named = UIImage(named: "Logo", in: .main, compatibleWith: nil), named.size.width > 1 {
            return named
        }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let file = UIImage(contentsOfFile: url.path), file.size.width > 1 {
            return file
        }
        return UIImage(named: "Mark", in: .main, compatibleWith: nil)
    }
}

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
        let ink = UIColor(red: 37.0 / 255, green: 61.0 / 255, blue: 78.0 / 255, alpha: 1)
        let mute = UIColor(red: 37.0 / 255, green: 61.0 / 255, blue: 78.0 / 255, alpha: 0.55)
        let when = formatted(facts.when)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                UIGraphicsPushContext(context.cgContext)
                var y = drawHeader(ink: ink, mute: mute, when: when, device: facts.device)
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

    private static func drawHeader(ink: UIColor, mute: UIColor, when: String, device: String) -> CGFloat {
        let headerHeight: CGFloat = 108
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: 595, height: headerHeight)).fill()
        let cyan = UIColor(red: 11.0 / 255, green: 169.0 / 255, blue: 237.0 / 255, alpha: 1)
        cyan.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: headerHeight - 2, width: 595, height: 2)).fill()

        let logoHeight: CGFloat = 78
        var textX: CGFloat = 36
        if let logo = BrandMark.image() {
            let ratio = logo.size.width / max(logo.size.height, 1)
            let logoWidth = logoHeight * ratio
            logo.draw(in: CGRect(x: 28, y: (headerHeight - logoHeight) / 2, width: logoWidth, height: logoHeight))
            textX = 28 + logoWidth + 14
        } else if let mark = UIImage(named: "Mark") {
            mark.draw(in: CGRect(x: 36, y: 22, width: 64, height: 64))
            textX = 116
        }

        let maxWidth = 595 - textX - 28
        let block = CGRect(x: textX, y: 28, width: maxWidth, height: 56)
        ("Scheda diagnostica" as NSString).draw(
            in: CGRect(x: block.minX, y: block.minY, width: maxWidth, height: 24),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: ink,
            ]
        )
        (when as NSString).draw(
            in: CGRect(x: block.minX, y: block.minY + 26, width: maxWidth, height: 14),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: mute,
            ]
        )
        (device as NSString).draw(
            in: CGRect(x: block.minX, y: block.minY + 40, width: maxWidth, height: 14),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: mute,
            ]
        )
        return headerHeight + 22
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
        if let logo = BrandMark.image() {
            let height: CGFloat = 28
            let ratio = logo.size.width / max(logo.size.height, 1)
            logo.draw(in: CGRect(x: 36, y: 16, width: height * ratio, height: height))
        }
        UIColor(red: 37.0 / 255, green: 61.0 / 255, blue: 78.0 / 255, alpha: 0.16).setFill()
        UIBezierPath(rect: CGRect(x: 36, y: 50, width: 523, height: 1)).fill()
        return 64
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
