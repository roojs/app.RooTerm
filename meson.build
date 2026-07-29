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
adw_dep = dependency('libadwaita-1', version: '>= 1.5')
vte_dep = dependency('vte-2.91-gtk4', version: '>= 0.70')
gee_dep = dependency('gee-0.8')
gcrypt_dep = dependency('libgcrypt')
yaml_dep = dependency('yaml-0.1')

json_dep = dependency('json-glib-1.0')
secret_dep = dependency('libsecret-1')

rooterm_resources = gnome.compile_resources(
  'rooterm-resources',
  'resources/gresources.xml',
  source_dir: 'resources',
  c_name: 'rooterm_resources',
)

executable('rooterm',
  files(
    'src/main.vala',
    'src/Application.vala',
    'src/MainWindow.vala',
    'src/Connection.vala',
    'src/HostTreeNodes.vala',
    'src/HostTreeNodesFlat.vala',
    'src/SessionState.vala',
    'src/Forward.vala',
    'src/ForwardDialog.vala',
    'src/KeyDialog.vala',
    'src/ConnDialog.vala',
    'src/Config.vala',
    'src/AsbruConfig.vala',
    'src/AsbruCipher.vala',
    'src/HostTree.vala',
    'src/HostSearchPulldown.vala',
    'src/SshTerminal.vala',
    'src/LocalTerminal.vala',
    'src/Terminal.vala',
    'src/SshStream.vala',
    'src/HostPage.vala',
    'src/HostStack.vala',
    'src/SessionController.vala',
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
  dependencies: [gtk_dep, adw_dep, vte_dep, gee_dep, gcrypt_dep, yaml_dep, json_dep, secret_dep],
  vala_args: [
    '--vapidir', meson.project_source_root() / 'vapi',
  ],
  install: true,
)

install_data(
  'data/icons/hicolor/scalable/apps/org.roojs.rooterm.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
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
