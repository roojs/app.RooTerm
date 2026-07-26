project('rooterm', 'vala', 'c',
  version: '0.1.0',
  license: 'LGPL-3.0-or-later',
  default_options: [
    'warning_level=1',
    'prefix=/usr',
  ]
)

fs = import('fs')

gtk_dep = dependency('gtk4', version: '>= 4.14')
adw_dep = dependency('libadwaita-1', version: '>= 1.5')
vte_dep = dependency('vte-2.91-gtk4', version: '>= 0.70')
gee_dep = dependency('gee-0.8')
gcrypt_dep = dependency('libgcrypt')
yaml_dep = dependency('yaml-0.1')

# Local VTE GTK4 extract when the system -dev package is missing:
#   export PKG_CONFIG_PATH=$PWD/.deps/prefix/usr/lib/x86_64-linux-gnu/pkgconfig
vala_args = [
  '--vapidir', meson.project_source_root() / 'vapi',
]
local_vapi = meson.project_source_root() / '.deps/prefix/usr/share/vala/vapi'
if fs.is_dir(local_vapi)
  vala_args += ['--vapidir', local_vapi]
endif

executable('rooterm',
  files(
    'src/main.vala',
    'src/Application.vala',
    'src/MainWindow.vala',
    'src/Connection.vala',
    'src/AsbruConfig.vala',
    'src/AsbruCipher.vala',
    'src/HostTree.vala',
  ),
  dependencies: [gtk_dep, adw_dep, vte_dep, gee_dep, gcrypt_dep, yaml_dep],
  vala_args: vala_args,
  install: true,
)
