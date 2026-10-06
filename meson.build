project('singularity-spreadsheet', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-spreadsheet"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

cc       = meson.get_compiler('c')
gee_dep  = dependency('gee-0.8')
gio_dep  = dependency('gio-2.0')
xml_dep  = dependency('libxml-2.0')
zlib_dep = dependency('zlib')
math_dep = cc.find_library('m')
json_dep = dependency('json-glib-1.0')
soup_dep = dependency('libsoup-3.0')
sqlite_dep = dependency('sqlite3')

engine = files(
  'src/engine/value.vala',
  'src/engine/address.vala',
  'src/engine/formula.vala',
  'src/engine/workbook.vala',
  'src/engine/chart_model.vala',
  'src/engine/chart_resolve.vala',
  'src/engine/diagrams.vala',
  'src/engine/functions_image.vala',
  'src/engine/lambda.vala',
  'src/engine/tables.vala',
  'src/engine/comments.vala',
  'src/engine/revisions.vala',
  'src/engine/workbook_compare.vala',
  'src/engine/live_sheet.vala',
  'src/engine/calc_graph.vala',
  'src/engine/numformat.vala',
  'src/engine/evaluator.vala',
  'src/engine/functions.vala',
  'src/engine/functions_text.vala',
  'src/engine/functions_stats.vala',
  'src/engine/functions_lookup.vala',
  'src/engine/functions_date.vala',
  'src/engine/functions_eng.vala',
  'src/engine/functions_db.vala',
  'src/engine/functions_fin.vala',
  'src/engine/functions_math.vala',
  'src/engine/functions_web.vala',
  'src/engine/functions_dist.vala',
  'src/engine/functions_text2.vala',
  'src/engine/functions_array.vala',
  'src/engine/datamodel.vala',
  'src/engine/functions_matrix.vala',
  'src/engine/functions_lambda.vala',
  'src/engine/document.vala',
  'src/engine/layout.vala',
  'src/engine/protection.vala',
  'src/engine/validation.vala',
  'src/engine/outline.vala',
  'src/engine/cell_styles.vala',
  'src/engine/flashfill.vala',
  'src/engine/edit_tools.vala',
  'src/engine/sortfilter.vala',
  'src/engine/pivot.vala',
  'src/engine/whatif.vala',
  'src/engine/solver.vala',
  'src/engine/query.vala',
  'src/engine/analysis.vala',
  'src/engine/datatypes.vala',
  'src/engine/linked_types.vala',
  'src/engine/pagesetup.vala',
  'src/engine/audit.vala',
  'src/engine/script.vala',
  'src/engine/script_store.vala',
  'src/engine/script_recorder.vala',
  'src/engine/script_lib.vala',
  'src/engine/script_runner.vala',
)

io = files(
  'src/io/zip.vala',
  'src/io/xlsx.vala',
  'src/io/xlsx_writer.vala',
  'src/io/xlsx_tables.vala',
  'src/io/cond_xml.vala',
  'src/io/html.vala',
  'src/io/xlsx_parts.vala',
  'src/io/xlsx_extras.vala',
  'src/io/xlsx_drawing.vala',
  'src/io/csv.vala',
  'src/io/ods.vala',
  'src/io/ods_format.vala',
  'src/io/ods_extras.vala',
  'src/io/xls.vala',
  'src/io/xls_functions.vala',
  'src/io/xlsb.vala',
  'src/io/xls_writer.vala',
  'src/io/xlsb_writer.vala',
  'src/io/ods_drawing.vala',
  'src/io/edit_io.vala',
  'src/io/print_io.vala',
  'src/io/vba.vala',
  'src/io/cfb_writer.vala',
  'src/io/edit_ods.vala',
  'src/io/aes.vala',
  'src/io/office_crypto.vala',
  'src/io/analysis_io.vala',
  'src/io/pivot_xlsx.vala',
  'src/io/comments_io.vala',
  'src/io/revisions_io.vala',
)

gtk_dep = dependency('gtk4')
libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

engine_lib = static_library('spreadsheet-engine',
  engine + io,
  dependencies: [gee_dep, gio_dep, xml_dep, zlib_dep, math_dep, json_dep, soup_dep, sqlite_dep, gtk_dep, libsingularity_dep, dependency('pangocairo')],
  vala_args: ['--pkg', 'zlib'],
  c_args: ['-DSS_SYSCONFDIR="' + (get_option('prefix') / get_option('sysconfdir')) + '"'],
  pic: true,
)

engine_dep = declare_dependency(
  link_with: engine_lib,
  dependencies: [gee_dep, gio_dep, xml_dep, zlib_dep, math_dep, json_dep, soup_dep, sqlite_dep, gtk_dep, libsingularity_dep, dependency('pangocairo')],
)

io_test = executable('spreadsheet-io-test',
  files('tests/io_test.vala'),
  dependencies: [engine_dep],
  vala_args: ['--pkg', 'zlib'],
)
test('io', io_test)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

gnome = import('gnome')
resources = gnome.compile_resources(
  'singularity-spreadsheet-resources',
  'resources/dev.sinty.spreadsheet.gresource.xml',
  source_dir: meson.current_source_dir() / 'data' / 'icons',
)

ui = files(
  'src/ui/chart.vala',
  'src/ui/chart_dialog.vala',
  'src/ui/objects_ui.vala',
  'src/ui/grid.vala',
  'src/ui/popovers.vala',
  'src/ui/dialogs.vala',
  'src/ui/links.vala',
  'src/ui/print.vala',
  'src/ui/print_setup.vala',
  'src/ui/audit.vala',
  'src/ui/script_editor.vala',
  'src/ui/window.vala',
  'src/ui/template_gallery.vala',
  'src/ui/table_ui.vala',
  'src/ui/proofing.vala',
  'src/ui/versions.vala',
  'src/ui/cond_icons.vala',
  'src/ui/cond_rules.vala',
  'src/ui/templates_more.vala',
  'src/ui/app.vala',
  'src/ui/cloud_actions.vala',
  'src/ui/comments_ui.vala',
  'src/ui/review_ui.vala',
  'src/ui/live_ui.vala',
  'src/ui/outline_gutter.vala',
  'src/ui/edit_overlay.vala',
  'src/ui/edit_dialogs.vala',
  'src/ui/edit_actions.vala',
  'src/ui/filter_ui.vala',
  'src/ui/analysis_form.vala',
  'src/ui/analysis_ui.vala',
  'src/ui/datamodel_ui.vala',
  'src/ui/pivot_panel.vala',
  'src/ui/query_editor.vala',
  'src/ui/ribbon.vala',
)

executable('singularity-spreadsheet',
  ui + [resources],
  dependencies: [engine_dep, gtk_dep, libsingularity_dep, dependency('pangocairo')],
  vala_args: ['--pkg', 'zlib'],
  install: true
)

shared_module('singularity-spreadsheet-widget',
  files('widget/pinned_cell_widget.vala'),
  dependencies: [engine_dep, gtk_dep, dependency('gio-unix-2.0'), libsingularity_dep],
  vala_args: ['--pkg', 'zlib'],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)

install_data('widget/dev.sinty.spreadsheet.pinned-cell.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/dev.sinty.spreadsheet.open.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)

install_data('data/dev.sinty.spreadsheet.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.spreadsheet.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/dev.sinty.spreadsheet.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.spreadsheet.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

foreach t : ['engine', 'doc', 'calc', 'functions_a', 'functions_b', 'analysis', 'linked', 'fidelity', 'audit', 'edit', 'charts', 'comments', 'review', 'live', 'vba']
  exe = executable('spreadsheet-' + t.replace('_', '-') + '-test',
    files('tests/' + t + '_test.vala'),
    dependencies: [engine_dep],
    vala_args: ['--pkg', 'zlib'],
  )
  test(t == 'doc' ? 'document' : t, exe, timeout: 300)
endforeach

install_data('data/data-types.conf',
  install_dir: get_option('sysconfdir') / 'singularity' / 'spreadsheet'
)
