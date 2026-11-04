import Foundation
import CoreGraphics

@main
struct TestTestPage {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for (width, height) in [(30.0, 40.0), (50, 70), (70, 100), (210, 297)] {
            guard let data = TestPage.pdf(widthMM: width, heightMM: height),
                  let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider), let page = document.page(at: 1) else {
                fatalError("Test PDF could not be parsed")
            }
            precondition(document.numberOfPages == 1)
            let box = page.getBoxRect(.mediaBox)
            precondition(abs(box.width * 25.4 / 72 - width) < 0.01)
            precondition(abs(box.height * 25.4 / 72 - height) < 0.01)
            let pixels = 160 * 200
            var bytes = [UInt8](repeating: 255, count: pixels)
            bytes.withUnsafeMutableBytes { storage in
                let context = CGContext(data: storage.baseAddress, width: 160, height: 200,
                    bitsPerComponent: 8, bytesPerRow: 160, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
                context.scaleBy(x: 160 / box.width, y: 200 / box.height)
                context.drawPDFPage(page)
            }
            precondition(bytes.contains(where: { $0 < 128 }), "Test page rendered blank")
            try data.write(to: output.appendingPathComponent("\(Int(width))x\(Int(height)).pdf"))
            print("PASS: one nonblank PDF page at \(width) x \(height) mm")
        }
        for width in [Double.nan, Double.infinity, -1, 0, Double.greatestFiniteMagnitude] {
            precondition(TestPage.pdf(widthMM: width, heightMM: 70) == nil)
        }
        print("PASS: invalid stock rejected")
    }
}
