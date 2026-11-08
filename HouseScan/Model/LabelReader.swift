import ImageIO
import Vision

/// Reads a label photo with Vision, on the phone. Apple: "all of this happens on the device" (WWDC19, session 234).
enum LabelReader {
    /// Tries the photo upright, then turned, since serial labels are often stuck on sideways.
    static func read(jpeg: Data) -> LabelReading {
        var best = LabelReading()
        for orientation in [CGImagePropertyOrientation.up, .right, .left, .down] {
            guard let (lines, codes) = try? recognize(jpeg, orientation) else { continue }
            let reading = LabelReading(lines: lines, barcodes: codes)
            if !reading.isEmpty { return reading }
            if best.make.isEmpty { best = reading }
        }
        return best
    }

    private static func recognize(_ jpeg: Data, _ orientation: CGImagePropertyOrientation) throws -> ([String], [String]) {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        // Language correction "fixes" serial numbers into words.
        text.usesLanguageCorrection = false
        let codes = VNDetectBarcodesRequest()
        // Not UPC, EAN or QR, which carry product codes and links rather than serial numbers.
        codes.symbologies = [.code128, .code39, .code93, .dataMatrix]
        let handler = VNImageRequestHandler(data: jpeg, orientation: orientation)
        try handler.perform([text])
        // Separately, so a barcode failure (the simulator can't run that model at all) doesn't lose the text.
        try? handler.perform([codes])
        let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return (lines, (codes.results ?? []).compactMap(\.payloadStringValue))
    }
}
