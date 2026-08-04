Name:           rooterm
Version:        %{?rooterm_version}%{!?rooterm_version:0.1.0}
Release:        2%{?dist}
Summary:        SSH host manager and terminal for GNOME
License:        LGPLv3+
URL:            https://github.com/roojs/app.RooTerm
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconfig
BuildRequires:  vala
BuildRequires:  desktop-file-utils
BuildRequires:  pkgconfig(gtk4) >= 4.14
BuildRequires:  pkgconfig(libadwaita-1) >= 1.5
BuildRequires:  pkgconfig(vte-2.91-gtk4) >= 0.78
BuildRequires:  pkgconfig(gee-0.8)
BuildRequires:  pkgconfig(libgcrypt)
BuildRequires:  pkgconfig(yaml-0.1)
BuildRequires:  pkgconfig(json-glib-1.0)
BuildRequires:  pkgconfig(libsecret-1)

Requires:       openssh-clients

%description
Roo Term is a thin SSH host manager and terminal for GNOME — a crossover
between Guake and Ásbrú Connection Manager.

It provides a host tree with per-host terminal tabs, libsecret-backed
passwords, optional Guake-style drop-down via a GNOME Shell extension,
Ásbrú config import, port forwards, and local PTY sessions.

%prep
%autosetup -n %{name}-%{version}

%build
%meson
%meson_build

%install
%meson_install

%files
%license LICENSE
%doc README.md
%{_bindir}/rooterm
%{_datadir}/applications/org.roojs.rooterm.desktop
%{_datadir}/icons/hicolor/scalable/apps/org.roojs.rooterm.svg

%changelog
* Tue Aug 04 2026 Alan Knowles <alan@roojs.com> - 0.1.0-2
- Drop system GNOME Shell extension path; app installs per-user from GResource.

* Sat Aug 01 2026 Alan Knowles <alan@roojs.com> - 0.1.0-1
- Initial RPM packaging.
