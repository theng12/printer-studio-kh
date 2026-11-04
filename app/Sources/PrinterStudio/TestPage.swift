import Foundation

/// One compact PDF page, using the selected stock rather than a Letter sample.
enum TestPage {
    static func pdf(widthMM: Double, heightMM: Double) -> Data? {
        guard widthMM.isFinite, heightMM.isFinite,
              widthMM > 0, heightMM > 0 else { return nil }
        let width = widthMM * 72 / 25.4
        let height = heightMM * 72 / 25.4
        guard width.isFinite, height.isFinite else { return nil }
        let scale = min(width / 160, height / 100)
        func number(_ value: Double) -> String { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value) }
        let drawing = """
        q
        \(number(scale)) 0 0 \(number(scale)) \(number((width - 160 * scale) / 2)) \(number((height - 100 * scale) / 2)) cm
        0 G 1 w 8 8 144 84 re S
        BT /F1 12 Tf 16 70 Td (Printer Studio KH) Tj ET
        BT /F1 9 Tf 16 53 Td (One page - one label) Tj ET
        16 24 12 16 re f 32 24 3 16 re f 39 24 6 16 re f 49 24 2 16 re f
        55 24 9 16 re f 68 24 3 16 re f 75 24 5 16 re f 84 24 2 16 re f
        Q
        """
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(number(width)) \(number(height))] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(drawing.utf8.count) >>\nstream\n\(drawing)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ]
        var document = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(document.utf8.count)
            document += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = document.utf8.count
        document += "xref\n0 6\n0000000000 65535 f \n"
        for offset in offsets { document += String(format: "%010d 00000 n \n", offset) }
        document += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(document.utf8)
    }
}
