import Foundation

@main
struct TestSelectedMedia {
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let original = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            precondition(original.hasPrefix("*PPD-Adobe:"), "Fixture is not a PPD")
            let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let size = StickerSize(name: "50x70", widthMM: 50, heightMM: 70)
            let transformed = PageSizeInstaller.transform(ppd: original, adding: [size])
            let filters: (String) -> [String] = { $0.components(separatedBy: .newlines).filter { $0.hasPrefix("*cupsFilter:") || $0.hasPrefix("*Resolution ") || $0.hasPrefix("*ColorOption ") } }
            precondition(filters(original) == filters(transformed), "Vendor filter/render settings must be preserved")
            precondition(PageSizeInstaller.choices(ppd: transformed).contains(where: { $0.key == size.key }))
            try transformed.write(to: output.appendingPathComponent("transformed.ppd"), atomically: true, encoding: .utf8)
            try TestPage.pdf(widthMM: 50, heightMM: 70)!.write(to: output.appendingPathComponent("test.pdf"))
            print("PASS: actual vendor PPD accepts 50x70 choice without changing its filter or raster settings")
        }
        let ppd = """
        *OpenUI *PageSize/Media: PickOne
        *DefaultPageSize: Native
        *PageSize Native/Original stock: "<</PageSize[288 432]>>setpagedevice"
        *CloseUI: *PageSize
        *OpenUI *PageRegion/Region: PickOne
        *DefaultPageRegion: Native
        *PageRegion Native/Original stock: "<</PageSize[288 432]>>setpagedevice"
        *CloseUI: *PageRegion
        *ImageableArea Native: "0 0 288 432"
        *PaperDimension Native: "288 432"
        """
        let label = StickerSize(name: "50x70", widthMM: 50, heightMM: 70)
        let transformed = PageSizeInstaller.transform(ppd: ppd, adding: [label])
        let choices = PageSizeInstaller.choices(ppd: transformed)
        precondition(choices.count == 2)
        let custom = choices.first { $0.key == label.key }!
        precondition(abs(custom.widthMM - 50) < 0.01 && abs(custom.heightMM - 70) < 0.01)
        precondition(custom.label.contains("50x70") && custom.label.contains("mm"))
        precondition(PageSizeInstaller.defaultKey(ppd: transformed) == "Native")
        let selected = transformed.replacingOccurrences(of: "*DefaultPageSize: Native", with: "*DefaultPageSize: \(label.key)")
        precondition(PageSizeInstaller.defaultKey(ppd: selected) == label.key)
        let removed = PageSizeInstaller.transform(ppd: selected, adding: [])
        precondition(PageSizeInstaller.defaultKey(ppd: removed) == "Native")
        precondition(PageSizeInstaller.choices(ppd: removed).count == 1)
        precondition(PageSizeInstaller.defaultKey(ppd: "*DefaultPageSize: missing") == "")
        precondition(PageSizeInstaller.choices(ppd: "*PaperDimension Invalid: \"nan -1\"").isEmpty)
        precondition(!PageSizeInstaller.setDefault(queue: "__printerstudio_missing_fixture__", key: "invalid").ok)
        for name in ["", "   ", "name\nnewline", String(repeating: "a", count: 64)] {
            precondition(!CUPS.rename("__printerstudio_missing_fixture__", to: name).ok)
        }
        print("PASS: custom/native choices, exact 50x70 geometry, server PPD default, removal fallback, invalid media/name rejection")
    }
}
