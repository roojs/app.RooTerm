# Changelog

All notable changes to Roo Term are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for git tags (`v0.1.0`, etc.).

Debian (`debian/changelog`), RPM (`%changelog`), and GitHub release notes are
generated from this file by `scripts/release/derive-changelogs.sh`.

## [Unreleased]

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

[Unreleased]: https://github.com/roojs/app.RooTerm/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/roojs/app.RooTerm/releases/tag/v0.1.0
