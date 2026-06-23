# Security Policy

Pastera handles clipboard data locally, so security and privacy reports are
important even when they do not involve a network service.

## Supported Versions

Security fixes target the latest public beta release and the current `develop`
branch. Older beta builds may not receive separate patch releases.

## Reporting A Vulnerability

If the report can be discussed publicly without exposing user data or an active
exploit, open a GitHub issue with clear reproduction steps.

For sensitive reports, do not post exploit details publicly. Contact a
maintainer privately through GitHub and share only the minimum information
needed to start triage.

Useful report details include:

- macOS version and Pastera version or commit.
- Whether Accessibility, automatic paste, or sync was enabled.
- The smallest reproduction steps.
- What clipboard data type was involved: text, image, file, URL, RTF, or PDF.
- Whether user data could be read, modified, leaked, or pasted unexpectedly.

## Security Boundaries

Pastera should not:

- Upload clipboard data to a hosted Pastera service.
- Collect clipboard telemetry without explicit user-facing consent.
- Enable automatic paste without the user opting in.
- Bypass macOS Gatekeeper, Transparency Consent and Control, or Accessibility
  permission flows.
- Store signing certificates, tokens, passwords, or notarization credentials in
  the repository.

Known distribution limitation: current beta builds are unsigned and not
notarized. That is a trust and distribution gap, not an intentional bypass.
Future trusted releases require Developer ID signing and Apple notarization.
