#!/usr/bin/env swift

import AppKit
import Foundation

private let arguments = CommandLine.arguments

guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: render_dmg_install_guide.swift OUTPUT_PNG ICON_PNG\n".utf8))
    exit(2)
}

private let outputURL = URL(fileURLWithPath: arguments[1])
private let iconURL = URL(fileURLWithPath: arguments[2])
private let canvasSize = NSSize(width: 860, height: 540)
private let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

private func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()

    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left,
    lineSpacing: CGFloat = 2
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = lineSpacing

    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}

private func drawStep(number: String, title: String, detail: String, rect: NSRect) {
    drawRoundedRect(rect, radius: 18, fill: .white, stroke: color(222, 229, 239))

    let badgeRect = NSRect(x: rect.minX + 16, y: rect.maxY - 42, width: 26, height: 26)
    drawRoundedRect(badgeRect, radius: 13, fill: color(17, 121, 255))
    drawText(
        number,
        in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 3, width: badgeRect.width, height: 20),
        font: .systemFont(ofSize: 14, weight: .bold),
        color: .white,
        alignment: .center,
        lineSpacing: 0
    )

    drawText(
        title,
        in: NSRect(x: rect.minX + 52, y: rect.maxY - 42, width: rect.width - 68, height: 24),
        font: .systemFont(ofSize: 15, weight: .semibold),
        color: color(25, 35, 52),
        lineSpacing: 1
    )
    drawText(
        detail,
        in: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 36, height: 42),
        font: .systemFont(ofSize: 11, weight: .regular),
        color: color(84, 96, 116),
        lineSpacing: 1
    )
}

guard let bitmap else {
    FileHandle.standardError.write(Data("Failed to allocate DMG install guide bitmap.\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

color(246, 248, 252).setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let topPanel = NSRect(x: 38, y: 402, width: 784, height: 100)
drawRoundedRect(topPanel, radius: 24, fill: .white, stroke: color(223, 230, 241))

if let logo = NSImage(contentsOf: iconURL) {
    logo.draw(in: NSRect(x: 64, y: 426, width: 52, height: 52))
}

drawText(
    "安装 Pastera",
    in: NSRect(x: 132, y: 456, width: 420, height: 34),
    font: .systemFont(ofSize: 28, weight: .semibold),
    color: color(20, 29, 45),
    lineSpacing: 0
)
drawText(
    "Install Pastera, then grant permissions from macOS System Settings.",
    in: NSRect(x: 132, y: 430, width: 520, height: 22),
    font: .systemFont(ofSize: 13, weight: .regular),
    color: color(91, 103, 123),
    lineSpacing: 0
)
drawText(
    "拖到 Applications",
    in: NSRect(x: 324, y: 288, width: 212, height: 28),
    font: .systemFont(ofSize: 20, weight: .semibold),
    color: color(17, 121, 255),
    alignment: .center,
    lineSpacing: 0
)

let guideLine = NSBezierPath()
guideLine.move(to: NSPoint(x: 318, y: 255))
guideLine.line(to: NSPoint(x: 542, y: 255))
guideLine.lineWidth = 6
guideLine.lineCapStyle = .round
color(17, 121, 255).setStroke()
guideLine.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 542, y: 255))
arrowHead.line(to: NSPoint(x: 520, y: 270))
arrowHead.move(to: NSPoint(x: 542, y: 255))
arrowHead.line(to: NSPoint(x: 520, y: 240))
arrowHead.lineWidth = 6
arrowHead.lineCapStyle = .round
color(17, 121, 255).setStroke()
arrowHead.stroke()

drawRoundedRect(NSRect(x: 130, y: 181, width: 160, height: 148), radius: 28, fill: color(235, 241, 251), stroke: color(218, 227, 242))
drawRoundedRect(NSRect(x: 570, y: 181, width: 160, height: 148), radius: 28, fill: color(235, 241, 251), stroke: color(218, 227, 242))

drawStep(
    number: "1",
    title: "拖到 Applications",
    detail: "Drag Pastera.app to the Applications shortcut.",
    rect: NSRect(x: 48, y: 54, width: 238, height: 112)
)
drawStep(
    number: "2",
    title: "如出现“无法验证”",
    detail: "Open Privacy & Security, then click Open Anyway.",
    rect: NSRect(x: 311, y: 54, width: 238, height: 112)
)
drawStep(
    number: "3",
    title: "允许辅助功能",
    detail: "Enable Pastera in Accessibility, then restart if needed.",
    rect: NSRect(x: 574, y: 54, width: 238, height: 112)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to render DMG install guide PNG.\n".utf8))
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: outputURL)
} catch {
    FileHandle.standardError.write(Data("Failed to write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
