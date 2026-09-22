import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Verkleinert Fotos vor dem Upload auf höchstens 1200 px Kante als JPEG —
/// der Bucket erlaubt 3 MB, und die Karte zeigt ohnehin nur eine Vorschau.
enum EventPhotoResizer {
    static let maxSide: CGFloat = 1200

    static func jpeg(from data: Data, maxSide: CGFloat = EventPhotoResizer.maxSide) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat.default(); f.scale = 1; return f }())
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.82)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        #else
        return data
        #endif
    }

    static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        NSImage(data: data).map(Image.init(nsImage:))
        #else
        nil
        #endif
    }
}
