import Foundation

@main
struct TestLabelRoute {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let cases = [
            ("tsc", "TSC TTP-244 Pro", "/Library/Printers/TSC/Filter/rastertobarcodetspl"),
            ("xprinter", "XP-D463B", "rastertosnailtspl-xprinter")
        ]
        for (name, model, vendor) in cases {
            let original = """
            *PPD-Adobe: "4.3"
            *FormatVersion: "4.3"
            *FileVersion: "1.0"
            *LanguageVersion: English
            *LanguageEncoding: ISOLatin1
            *PCFileName: "LABEL.PPD"
            *Manufacturer: "Test"
            *Product: "(\(model))"
            *ModelName: "\(model)"
            *ShortNickName: "\(model)"
            *NickName: "\(model)"
            *PSVersion: "(3010.000) 0"
            *LanguageLevel: "3"
            *ColorDevice: False
            *DefaultColorSpace: Gray
            *FileSystem: False
            *LandscapeOrientation: Plus90
            *TTRasterizer: Type42
            *cupsVersion: 1.4
            *cupsManualCopies: True
            *cupsFilter: "application/vnd.cups-raster 0 \(vendor)"
            *HWMargins: 0 0 0 0
            *VariablePaperSize: True
            *CustomPageSize True: "pop pop pop <</PageSize[5 -2 roll]/ImagingBBox null>>setpagedevice"
            *ParamCustomPageSize Width: 1 points 1 306.14
            *ParamCustomPageSize Height: 2 points 1 6480
            *ParamCustomPageSize WidthOffset: 3 points 0 0
            *ParamCustomPageSize HeightOffset: 4 points 0 0
            *ParamCustomPageSize Orientation: 5 int 0 0
            *OpenUI *PageSize/Stock: PickOne
            *OrderDependency: 10 AnySetup *PageSize
            *DefaultPageSize: psz300x400-30x40
            *PageSize psz300x400-30x40/30 x 40 mm: "<</PageSize[85.04 113.39]/ImagingBBox null>>setpagedevice"
            *PageSize psz400x300-barcode/40 x 30 mm: "<</PageSize[113.39 85.04]/ImagingBBox null>>setpagedevice"
            *PageSize psz500x700-50x70/50 x 70 mm: "<</PageSize[141.73 198.43]/ImagingBBox null>>setpagedevice"
            *CloseUI: *PageSize
            *OpenUI *PageRegion/Stock: PickOne
            *OrderDependency: 10 AnySetup *PageRegion
            *DefaultPageRegion: psz300x400-30x40
            *PageRegion psz300x400-30x40/30 x 40 mm: "<</PageSize[85.04 113.39]/ImagingBBox null>>setpagedevice"
            *PageRegion psz400x300-barcode/40 x 30 mm: "<</PageSize[113.39 85.04]/ImagingBBox null>>setpagedevice"
            *PageRegion psz500x700-50x70/50 x 70 mm: "<</PageSize[141.73 198.43]/ImagingBBox null>>setpagedevice"
            *CloseUI: *PageRegion
            *DefaultImageableArea: psz300x400-30x40
            *ImageableArea psz300x400-30x40: "0 0 85.04 113.39"
            *ImageableArea psz400x300-barcode: "0 0 113.39 85.04"
            *ImageableArea psz500x700-50x70: "0 0 141.73 198.43"
            *DefaultPaperDimension: psz300x400-30x40
            *PaperDimension psz300x400-30x40: "85.04 113.39"
            *PaperDimension psz400x300-barcode: "113.39 85.04"
            *PaperDimension psz500x700-50x70: "141.73 198.43"
            *OpenUI *Resolution/Resolution: PickOne
            *DefaultResolution: 203dpi
            *Resolution 203dpi/203 DPI: "<</HWResolution[203 203]/cupsBitsPerColor 8/cupsColorSpace 3/cupsRowCount 8>>setpagedevice"
            *CloseUI: *Resolution
            *DefaultFont: Courier
            *Font Courier: Standard "(001.007)" Standard ROM

            """
            guard let changed = LabelPrintFilter.transform(ppd: original) else { fatalError("supported driver not routed") }
            assert(LabelPrintFilter.transform(ppd: changed) == changed, "route must be idempotent")
            assert(changed.contains("*cupsFilter: \"application/vnd.cups-raster 0 \(vendor)\""), "vendor route retained")
            assert(changed.contains("image/urf application/vnd.cups-raw 0 \(LabelPrintFilter.directory)/label-urf"))
            assert(changed.contains("application/pdf application/vnd.cups-raw 0 \(LabelPrintFilter.directory)/label-pdf"))
            assert(changed.contains("*DefaultPageSize: psz300x400-30x40"), "default must not change")
            assert(LabelPrintFilter.transform(ppd: original + "*cupsFilter2: \"application/pdf application/pdf 0 -\"\n") == nil, "unknown route must not be overwritten")
            assert(LabelPrintFilter.transform(ppd: original.replacingOccurrences(of: model, with: "Other printer")) == nil, "other printers must not change")
            try original.write(to: output.appendingPathComponent("\(name)-original.ppd"), atomically: true, encoding: .utf8)
            try changed.write(to: output.appendingPathComponent("\(name)-routed.ppd"), atomically: true, encoding: .utf8)
            let before = PageSizeInstaller.validationComplaints(of: output.appendingPathComponent("\(name)-original.ppd").path, ignoreFilterFiles: true)
            let after = PageSizeInstaller.validationComplaints(of: output.appendingPathComponent("\(name)-routed.ppd").path, ignoreFilterFiles: true)
            assert(after.subtracting(before).isEmpty, "route introduces PPD errors: \(after.subtracting(before))")
        }
        let script = LabelPrintFilter.installScript(
            source: output.appendingPathComponent("Payloads with spaces"), stage: output,
            targets: ["TSC_TTP_244_Pro", "Xprinter_XP_D463B"], id: "test-backup")
        let scriptURL = output.appendingPathComponent("label-install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        assert(Shell.run("/bin/bash", ["-n", scriptURL.path]).ok, "administrator script must parse")
        assert(script.contains("trap restore_ppds ERR"), "failure must attempt PPD restoration")
        assert(script.contains(".printerstudio-label-backup"), "original PPD must be recoverable")
        assert(script.contains("-o root -g wheel -m 555"), "filters require protected ownership and mode")
        assert(!script.contains("cupsd") && !script.contains("cupsctl"), "label setup must not restart CUPS or change global sharing")
        for queue in ["TSC_TTP_244_Pro", "Xprinter_XP_D463B"] {
            assert(script.contains("-p '\(queue)' -P "), "only the named queues should be updated")
        }
        print("PASS: generated administrator script syntax, backups, rollback, ownership and queue scope")
        try TestPage.pdf(widthMM: 50, heightMM: 70)!.write(to: output.appendingPathComponent("synthetic.pdf"))
        print("PASS: both label PPD routes, idempotence, vendor/default preservation, scope and validation")
    }
}
