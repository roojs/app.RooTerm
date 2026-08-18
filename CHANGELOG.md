# Changelog

All notable changes to Roo Term are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for git tags (`v0.1.0`, etc.).

Debian (`debian/changelog`), RPM (`%changelog`), and GitHub release notes are
generated from this file by `scripts/release/derive-changelogs.sh` in CI.
Humans tag a release with `scripts/release.sh` after stamping `[Unreleased]`
as `## [X.Y.Z] - YYYY-MM-DD` and setting `meson.build` to the same version
(see [BUILD.md](BUILD.md)).

## [Unreleased]

## [0.1.2] - 2026-08-16

### Added

- Auto-fill SSH TOTP verification codes (liboath); dialog to type a code or store the authenticator secret

## [0.1.2] - 2026-08-16

### Added

- Preferences as its own process (`rooterm --preferences`); live updates on main via D-Bus
- Keyboard shortcuts page (toggle, search, new terminal / SSH, tabs, copy / paste, …)
- VTE colour themes: background category, foreground theme, live preview
- Font page: monospace family (or system) and size, with live preview
- Work-area full screen (tab strip on top, animated; session-only until you exit)
- Restore local terminal tabs on startup (cwd in `connections.json`; skip missing dirs)
- Remember last tab per GNOME workspace (on show after hide; optional, default on)
- VTE right-click menu (copy, paste, select all, full screen, quit, …)
- `Ctrl+Shift+T` always a local terminal; `Ctrl+Shift+S` a new SSH tab for the focused host
- Double-click empty tab-bar space for a new local terminal
- Add group from the tree; default **All** group on a blank install
- Confirm quit when terminals are still open
- Tab close countdown with cancel (selected or background)
- RPM and AppImage packaging alongside the existing Debian workflow

### Changed

- GNOME Shell extension owns show / hide / stacking for main and preferences
- Chrome settings live in `config.json`; hosts stay in `connections.json`
- Tab strip chrome and close behaviour

### Fixed

- Copy and paste in the terminal
- Duplicate Localhost rows on load
- Drop-down show / hide reliability (X11 and Wayland)
- Preferences startup and live `config_update`
- Closing tabs and tab-bar width feedback

## [0.1.1] - 2026-08-06

### Added

- Initial packaging

## [0.1.0] - 2026-08-01

### Added

- GTK4 + Libadwaita + VTE SSH host manager and terminal (Vala)
- Host tree with per-host terminal tabs and per-tab session icons
- Multi-connection tab bar for several sessions to the same host
- Guake-style drop-down via optional GNOME Shell extension (global toggle,
  panel menu)
- libsecret-backed passwords and SSH key passphrases
- JSON config under `~/.config/rooterm/`; Ásbrú `asbru.yml` import on first run
- Host search pulldown (`Ctrl+Shift+O`)
- Local port forwards; SSH key create / install / replace / retire helpers
- Local PTY tabs; optional `sudo -i` (and LXC-host helpers) after login
- Debian packaging (`debian/`) and GitHub Actions release workflow for `.deb`
  builds on `v*` tags

[Unreleased]: https://github.com/roojs/app.RooTerm/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/roojs/app.RooTerm/releases/tag/v0.1.2
[0.1.1]: https://github.com/roojs/app.RooTerm/releases/tag/v0.1.1
[0.1.0]: https://github.com/roojs/app.RooTerm/releases/tag/v0.1.0
