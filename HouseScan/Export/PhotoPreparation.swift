import ImageIO
import UIKit

enum PhotoPreparation {
    /// Enough to read a serial number on a label, at a fraction of the original's size.
    private static let longestEdge: CGFloat = 3000

    /// Redraws a photo as a plain JPEG. That bakes in its orientation and drops all metadata, so a photo picked from
    /// the library can't carry a GPS tag into an inventory.
    static func jpeg(from data: Data) -> Data? {
        UIImage(data: data).flatMap(jpeg)
    }

    static func jpeg(from image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, longestEdge / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// A small decoded copy, for lists and PDFs, without loading the whole photo.
    static func thumbnail(at url: URL, longestEdge: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: longestEdge]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }
}
