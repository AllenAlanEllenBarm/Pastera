# Governance

Pastera is maintained as an open-source macOS app under the `pastera-app`
GitHub organization.

## Maintainer Responsibilities

Maintainers are responsible for:

- Reviewing issues and pull requests.
- Protecting user clipboard data and permission transparency.
- Keeping release artifacts, signing status, and installation limitations clear.
- Preserving the MIT license and upstream Clipy attribution.
- Deciding whether a proposed change fits the fork roadmap.
- Managing project funds transparently if fiscal hosting is approved.

## Decision Process

Most decisions are made through public GitHub issues and pull requests. Small
bug fixes and documentation improvements can be reviewed directly in a pull
request. Larger changes should start with an issue that explains the user
problem, expected behavior, risks, and test plan.

Maintainers prefer consensus, but a maintainer can make the final decision when
there is disagreement or when a release needs to move forward. Decisions should
be based on user safety, implementation clarity, maintenance cost, and alignment
with the project roadmap.

## Project Scope

Pastera focuses on:

- macOS clipboard history, snippets, search, and pasteback.
- Clear settings for privacy-sensitive features such as automatic paste.
- Non-destructive folder-based sync.
- Reliable direct distribution through DMG, Homebrew Cask metadata, and future
  notarized releases.

Pastera does not currently aim to provide a hosted cloud service, collect
clipboard telemetry, or bypass macOS Gatekeeper and privacy permission systems.

## Admins And Continuity

The project should have more than one trusted administrator where possible.
Admins should have enough context to review releases, recover repository access,
and keep fiscal-hosting or signing responsibilities from depending on one
person.

If leadership changes, the outgoing maintainer should transfer GitHub,
distribution, fiscal-hosting, and signing responsibilities through documented
organization roles rather than private credential sharing.

## Funding Decisions

If Open Source Collective fiscal hosting is approved, funds should be used only
for project-related needs. Expected spending categories include Apple Developer
Program membership, Developer ID signing and notarization, build and release
infrastructure, test devices, design assets, documentation, and maintenance
work.

Expenses should be described clearly in Open Collective before payment or
reimbursement. Private credentials, certificates, and Apple account access must
not be shared as a substitute for proper organization roles.
