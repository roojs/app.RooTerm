project('rooterm', 'vala', 'c',
  version: '0.1.0',
  license: 'LGPL-3.0-or-later',
  default_options: [
    'warning_level=1',
    'prefix=/usr',
  ]
)

gnome = import('gnome')

gtk_dep = dependency('gtk4', version: '>= 4.14')
gtk_wayland_dep = dependency('gtk4-wayland')
gtk_x11_dep = dependency('gtk4-x11')
adw_dep = dependency('libadwaita-1', version: '>= 1.5')
vte_dep = dependency('vte-2.91-gtk4', version: '>= 0.70')
gee_dep = dependency('gee-0.8')
gcrypt_dep = dependency('libgcrypt')
yaml_dep = dependency('yaml-0.1')

json_dep = dependency('json-glib-1.0')
secret_dep = dependency('libsecret-1')

# OLLMchat pattern: one gresource prefix per directory, bare <file> names,
# matching --sourcedir entries (see OLLMchat/libollmchat/meson.build).
rooterm_resources = gnome.compile_resources(
  'rooterm-resources',
  'resources/gresources.xml',
  source_dir: [
    meson.project_source_root() / 'resources',
    meson.project_source_root() / 'resources' / 'extension',
    meson.project_source_root() / 'resources' / 'extension' / 'schemas',
  ],
  c_name: 'rooterm_resources',
)

executable('rooterm',
  files(
    'src/main.vala',
    'src/Application.vala',
    'src/DBus.vala',
    'src/GnomeShell.vala',
    'src/MainWindow.vala',
    'src/Host/Connection.vala',
    'src/Host/TreeNodes.vala',
    'src/Host/TreeNodesFlat.vala',
    'src/Session/State.vala',
    'src/Host/Forward.vala',
    'src/Dialog/Forward.vala',
    'src/Dialog/Key.vala',
    'src/Dialog/Connection.vala',
    'src/Config.vala',
    'src/Dialog/Preferences.vala',
    'src/Asbru/Config.vala',
    'src/Asbru/Cipher.vala',
    'src/Host/Tree.vala',
    'src/Host/TreeMenu.vala',
    'src/Host/SearchPulldown.vala',
    'src/Terminal/Ssh.vala',
    'src/Terminal/Local.vala',
    'src/Terminal/Base.vala',
    'src/Terminal/Stream.vala',
    'src/Host/Page.vala',
    'src/Host/TabBar.vala',
    'src/Host/Stack.vala',
    'src/Session/Controller.vala',
    'src/Jobs/Job.vala',
    'src/Jobs/SshLogin.vala',
    'src/Jobs/SudoLogin.vala',
    'src/Jobs/SetupKey.vala',
    'src/Jobs/ReplaceKey.vala',
    'src/Jobs/RetireKey.vala',
    'src/Jobs/FetchHosts.vala',
    'src/Jobs/OpenSession.vala',
  ),
  rooterm_resources,
  dependencies: [
    gtk_dep,
    gtk_wayland_dep,
    gtk_x11_dep,
    adw_dep,
    vte_dep,
    gee_dep,
    gcrypt_dep,
    yaml_dep,
    json_dep,
    secret_dep,
  ],
  vala_args: [
    '--vapidir', meson.project_source_root() / 'vapi',
    '--pkg', 'posix',
    '--pkg', 'gtk4-wayland',
    '--pkg', 'gtk4-x11',
  ],
  install: true,
)

install_data(
  'data/icons/hicolor/scalable/apps/org.roojs.rooterm.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

install_subdir(
  'resources/extension',
  install_dir: get_option('datadir') / 'gnome-shell' / 'extensions' / 'rooterm@roojs.com',
  strip_directory: true,
)

desktop_conf = configuration_data()
desktop_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/org.roojs.rooterm.desktop.in',
  output: 'org.roojs.rooterm.desktop',
  configuration: desktop_conf,
  install_dir: get_option('datadir') / 'applications',
)

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
