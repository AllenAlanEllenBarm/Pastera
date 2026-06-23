import Cocoa

final class PasteraSetupGuideStepRowView: NSView {
    let step: PasteraSetupGuideStep

    private let marker = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let number: String

    init(step: PasteraSetupGuideStep, number: String, title: String, body: String) {
        self.step = step
        self.number = number
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        configureMarker(number: number)
        configureLabels(title: title, body: body)
        [marker, titleLabel, bodyLabel, statusLabel].forEach(addSubview)
        installConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with status: PasteraSetupGuideStepStatus) {
        layer?.cornerRadius = 0

        switch status {
        case .completed:
            layer?.backgroundColor = NSColor.clear.cgColor
            marker.stringValue = "✓"
            marker.textColor = .systemGreen
            marker.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
            statusLabel.stringValue = "已完成"
            statusLabel.textColor = .systemGreen
            statusLabel.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
        case .current:
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.09).cgColor
            marker.stringValue = number
            marker.textColor = .white
            marker.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            statusLabel.stringValue = "当前"
            statusLabel.textColor = .controlAccentColor
            statusLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        }

        titleLabel.textColor = .labelColor
        bodyLabel.textColor = .secondaryLabelColor
    }

    private func configureMarker(number: String) {
        marker.stringValue = number
        marker.alignment = .center
        marker.font = .systemFont(ofSize: 13, weight: .bold)
        marker.wantsLayer = true
        marker.layer?.cornerRadius = PasteraSetupGuideLayout.stepMarkerWidth / 2
        marker.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLabels(title: String, body: String) {
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.stringValue = body
        bodyLabel.font = .systemFont(ofSize: 12.5)
        bodyLabel.maximumNumberOfLines = 1
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 8
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func installConstraints() {
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            marker.centerYAnchor.constraint(equalTo: centerYAnchor),
            marker.widthAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.stepMarkerWidth),
            marker.heightAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.stepMarkerWidth),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: PasteraSetupGuideLayout.stepStatusWidth),
            statusLabel.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(
                equalTo: marker.trailingAnchor,
                constant: PasteraSetupGuideLayout.stepTextLeading
            ),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -16),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5)
        ])
    }
}
