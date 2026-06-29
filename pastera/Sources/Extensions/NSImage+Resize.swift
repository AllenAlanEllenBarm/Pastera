//
//  NSImage+Resize.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/07/26.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa

extension NSImage {
    func resizeImage(_ width: CGFloat, _ height: CGFloat) -> NSImage? {
        guard width > 0, height > 0 else {
            return nil
        }

        let sourceBitmap = representations.compactMap { $0 as? NSBitmapImageRep }.first
        var proposedRect = NSRect(origin: .zero, size: size)
        let sourceCGImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        let origWidth = CGFloat(sourceBitmap?.pixelsWide ?? sourceCGImage?.width ?? Int(size.width.rounded()))
        let origHeight = CGFloat(sourceBitmap?.pixelsHigh ?? sourceCGImage?.height ?? Int(size.height.rounded()))
        guard origWidth > 0, origHeight > 0 else { return nil }

        let aspect = origWidth / origHeight
        let targetWidth = width
        let targetHeight = height
        var newWidth: CGFloat
        var newHeight: CGFloat

        if aspect >= 1 {
            newWidth = targetWidth
            newHeight = newWidth / aspect

            if targetHeight < newHeight {
                newHeight = targetHeight
                newWidth = targetHeight * aspect
            }
        } else {
            newHeight = targetHeight
            newWidth = targetHeight * aspect

            if targetWidth < newWidth {
                newWidth = targetWidth
                newHeight = targetWidth / aspect
            }
        }

        if origWidth < newWidth {
            newWidth = origWidth
        }
        if origHeight < newHeight {
            newHeight = origHeight
        }

        let pixelWidth = max(1, Int(newWidth.rounded()))
        let pixelHeight = max(1, Int(newHeight.rounded()))
        guard let resizedBitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        resizedBitmap.size = NSSize(width: newWidth, height: newHeight)

        let thumbnail = NSImage(size: NSSize(width: newWidth, height: newHeight))
        guard let context = NSGraphicsContext(bitmapImageRep: resizedBitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: newWidth, height: newHeight).fill()
        draw(
            in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        thumbnail.addRepresentation(resizedBitmap)
        return thumbnail
    }
}
