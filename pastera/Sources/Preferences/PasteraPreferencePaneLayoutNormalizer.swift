//
//  PasteraPreferencePaneLayoutNormalizer.swift
//
//  Pastera
//

import AppKit
import KeyHolder

enum PasteraPreferencePaneLayoutNormalizer {
    @discardableResult
    static func adapt(to view: NSView, minimumGap: CGFloat) -> NSSize {
        view.layoutSubtreeIfNeeded()
        enforceTopLevelRowGap(in: view, minimumGap: minimumGap)
        guard let bounds = topLevelContentBounds(in: view) else {
            return view.frame.size
        }
        shiftTopLevelContent(in: view, by: NSPoint(x: -bounds.minX, y: -bounds.minY))
        let size = NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
        view.frame.size = size
        return size
    }

    private static func enforceTopLevelRowGap(in view: NSView, minimumGap: CGFloat) {
        var groups = rowGroups(in: view)
        guard groups.count > 1 else { return }

        var previousMinY = groups[0].bounds.minY
        for index in groups.indices.dropFirst() {
            let gap = previousMinY - groups[index].bounds.maxY
            if gap < minimumGap {
                let delta = gap - minimumGap
                groups[index].views.forEach { $0.frame.origin.y += delta }
                groups[index].bounds.origin.y += delta
            }
            previousMinY = groups[index].bounds.minY
        }

        let visibleSubviews = layoutParticipants(in: view)
        guard let minY = visibleSubviews.map(\.frame.minY).min(), minY < 0 else { return }
        view.frame.size.height += abs(minY)
        visibleSubviews.forEach { $0.frame.origin.y += abs(minY) }
    }

    private static func rowGroups(in view: NSView) -> [RowGroup] {
        let candidates = view.subviews
            .filter { !$0.isHidden && !$0.frame.isEmpty && $0.alphaValue > 0 }
            .sorted { lhs, rhs in
                if lhs.frame.maxY == rhs.frame.maxY {
                    return lhs.frame.minX < rhs.frame.minX
                }
                return lhs.frame.maxY > rhs.frame.maxY
            }

        return candidates.reduce(into: [RowGroup]()) { groups, subview in
            if let last = groups.indices.last,
               groups[last].bounds.intersectsVertically(with: subview.frame) {
                groups[last].views.append(subview)
                groups[last].bounds = groups[last].bounds.union(subview.frame)
            } else {
                groups.append(RowGroup(views: [subview], bounds: subview.frame))
            }
        }
    }

    private static func topLevelContentBounds(in view: NSView) -> NSRect? {
        layoutParticipants(in: view)
            .map(\.frame)
            .reduce(nil as NSRect?) { partial, rect in
                partial.map { $0.union(rect) } ?? rect
            }
    }

    private static func shiftTopLevelContent(in view: NSView, by offset: NSPoint) {
        layoutParticipants(in: view).forEach {
            $0.frame.origin.x += offset.x
            $0.frame.origin.y += offset.y
        }
    }

    private static func layoutParticipants(in view: NSView) -> [NSView] {
        view.subviews.filter {
            !$0.isHidden
                && !$0.frame.isEmpty
                && $0.alphaValue > 0
                && isLayoutParticipant($0)
        }
    }

    private static func isLayoutParticipant(_ view: NSView) -> Bool {
        switch view {
        case is NSBox:
            return true
        case is NSScrollView:
            return true
        case is NSStackView:
            return view.subviews.contains { !$0.isHidden && !$0.frame.isEmpty }
        case is PasteraSettingsPaneHost:
            return true
        case is PasteraSettingsSectionView:
            return true
        case is PasteraSettingsRowView:
            return true
        case let view where recordViews(in: view).isEmpty == false:
            return true
        case let textField as NSTextField:
            return !textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let control as NSControl:
            return control.isEnabled
        case let recordView as RecordView:
            return recordView.isEnabled
        case let textView as NSTextView:
            return textView.isEditable
        default:
            return false
        }
    }

    private static func recordViews(in view: NSView) -> [RecordView] {
        var values = view.subviews.compactMap { $0 as? RecordView }
        view.subviews.forEach { values.append(contentsOf: recordViews(in: $0)) }
        return values
    }

    private struct RowGroup {
        var views: [NSView]
        var bounds: NSRect
    }
}

private extension NSRect {
    func intersectsVertically(with rect: NSRect) -> Bool {
        minY <= rect.maxY + 1 && maxY >= rect.minY - 1
    }
}
