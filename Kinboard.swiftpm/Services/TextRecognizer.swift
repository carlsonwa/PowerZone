import UIKit
import Vision

/// Reads the text in a photo of a flyer or a screenshot of a message, on the device.
enum TextRecognizer {
    static func text(in images: [UIImage]) async throws -> String {
        var pages: [String] = []
        for image in images {
            let lines = try await lines(in: image)
            if !lines.isEmpty { pages.append(MessageExtractor.reflow(lines)) }
        }
        return pages.joined(separator: "\n\n")
    }

    static func lines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    // Top to bottom, then left to right. Vision's coordinates start at the
                    // bottom-left, so a larger y is higher on the page.
                    let sorted = observations.sorted { a, b in
                        let rowA = Int((1 - a.boundingBox.midY) * 120)
                        let rowB = Int((1 - b.boundingBox.midY) * 120)
                        return rowA != rowB ? rowA < rowB : a.boundingBox.minX < b.boundingBox.minX
                    }
                    let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
