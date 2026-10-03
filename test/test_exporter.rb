# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/kp/tcn/exporter'

class TestExporter < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def profil(extra = {})
    base = JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json')))
    base['werkzeuge'].each do |t|
      t['nummer'] = { 'nutsaege_x' => 1161, 'nutsaege_y' => 1162, 'nutfraeser' => 5408 }[t['art']]
      t['d'] = 3.2 if t['art'].start_with?('nutsaege')
    end
    base.merge(extra)
  end

  def teil(ops, extra = {})
    { 'uid' => 'p/A1/t', 'rolle' => 'seite_l', 'material' => 'm',
      'fertigmass' => { 'l' => 720, 'w' => 560, 'd' => 19 }, 'bearbeitungen' => ops }.merge(extra)
  end

  def export(ops, prof = profil, extra = {})
    Kp::Tcn::Exporter.new(prof).export(teil(ops, extra))
  end

  def lines(file)
    file.content.split("\r\n")
  end

  def test_hole_on_top_face
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 9.5, 'y' => 34, 'd' => 8, 'tiefe' => 12 }])
    assert_empty r.fehler
    l = lines(r.files[0])
    assert_equal 'TPA\\ALBATROS\\EDICAD\\02.00:1224:r0w0h0s1', l[0]
    assert_equal '::SIDE=1;', l[1]
    assert_equal '::UNm DL=720 DH=560 DS=19', l[2]
    assert_includes l, 'SIDE#1{'
    assert_includes l, 'W#81{ ::WTp #1002=8 #1=9.5 #2=34 #3=-12 #8015=0 #201=1 #203=1 #1001=0 }W'
  end

  def test_bohrreihe_uses_fittingx
    r = export([{ 'id' => 'r', 'typ' => 'bohrreihe', 'flaeche' => 'F1', 'start' => [83, 37], 'richtung' => '+x',
                  'raster' => 32, 'anzahl' => 3, 'd' => 5, 'tiefe' => 12 }])
    assert_empty r.fehler
    row = lines(r.files[0]).grep(/W#1001/)[0]
    assert_equal 'W#1001{ ::WT2 #8098=..\\custom\\mcr\\fittingx.tmcr #6=1 #8508=0 #8509=0 #8510=83 #8511=147 ' \
                 '#8512=32 #8513=-12 #8517=0 #8518=37 #8520=1 #8521=1 #8522=5 #8525=0 }W', row
  end

  def test_bohrreihe_in_y_uses_fittingy_and_normalizes_direction
    r = export([{ 'typ' => 'bohrreihe', 'flaeche' => 'F1', 'start' => [20, 100], 'richtung' => '-y', 'raster' => 32,
                  'anzahl' => 3, 'd' => 8, 'tiefe' => 12 }])
    row = lines(r.files[0]).grep(/W#1003/)[0]
    assert_match(/fittingy\.tmcr .*#8510=36 #8511=100 #8512=32 #8513=-12 #8517=0 #8518=20 /, row)
  end

  def test_bohrreihe_ausgemittelt_edge_like_boden
    r = export([{ 'typ' => 'bohrreihe', 'flaeche' => 'F4', 'start' => [30, 9.5], 'richtung' => '+x', 'raster' => 150,
                  'ausgemittelt' => true, 'gerade_anzahl' => true, 'ende' => 528, 'd' => 8, 'tiefe' => 22 }])
    l = lines(r.files[0])
    assert_includes l, 'SIDE#5{'
    assert_match(/#8508=1 #8509=1 #8510=30 #8511=528 #8512=150 #8513=-22 #8517=0 #8518=9.5 #8520=1 #8521=1 #8522=8/,
                 l.grep(/W#1001/)[0])
  end

  def test_edge_hole_face_mapping_and_axes
    # Konzept F5 (links) -> TpaCAD 6; Position entlang y, Höhe z
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F5', 'y' => 34, 'z' => 9.5, 'd' => 8, 'tiefe' => 22 }])
    l = lines(r.files[0])
    assert_includes l, 'SIDE#6{'
    assert_includes l, 'W#81{ ::WTp #1002=8 #1=34 #2=9.5 #3=-22 #8015=0 #201=1 #203=1 #1001=0 }W'
    # F4 (hinten) -> 5, entlang x; F6 (rechts) -> 4
    r2 = export([{ 'typ' => 'bohrung', 'flaeche' => 'F4', 'x' => 100, 'd' => 8, 'tiefe' => 22 },
                 { 'typ' => 'bohrung', 'flaeche' => 'F6', 'y' => 100, 'd' => 8, 'tiefe' => 22 }])
    l2 = lines(r2.files[0])
    assert_includes l2, 'SIDE#5{'
    assert_includes l2, 'SIDE#4{'
    assert_includes l2, 'W#81{ ::WTp #1002=8 #1=100 #2=9.5 #3=-22 #8015=0 #201=1 #203=1 #1001=0 }W'
  end

  def test_f2_goes_to_second_setup_mirrored
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F2', 'x' => 100, 'y' => 100, 'd' => 35, 'tiefe' => 12.5 }])
    assert_equal ['p_A1_t.tcn', 'p_A1_t_B.tcn'], r.files.map(&:name) # A nur Formatieren, B = gewendet
    assert_includes lines(r.files.last), 'W#81{ ::WTp #1002=35 #1=100 #2=460 #3=-12.5 #8015=0 #201=1 #203=1 #1001=0 }W'
  end

  def test_through_hole_depth
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 50, 'y' => 50, 'd' => 5, 'tiefe' => 19, 'durch' => true }])
    assert_match(/#3=-20 /, lines(r.files[0]).grep(/W#81/)[0])
  end

  def test_groove_saw_x_left_reference
    r = export([{ 'typ' => 'nut', 'flaeche' => 'F1', 'von' => [0, 520], 'bis' => [720, 520], 'breite' => 8.5,
                  'tiefe' => 10, 'bezug' => 'links' }])
    assert_empty r.fehler
    w = lines(r.files[0]).grep(/W#1050/)[0]
    # Mittellinie y = 520 + 8.5/2, Breite > Sägeblatt -> #8503 = Nutbreite
    assert_includes w, '#8511=524.25'
    assert_includes w, '#8503=8.5'
    assert_includes w, '#8509=0 #8510=0 #8517=720'
    assert_includes w, '#8512=-10'
    assert_includes w, '#8516=1161'
  end

  def test_groove_saw_y
    r = export([{ 'typ' => 'nut', 'flaeche' => 'F1', 'von' => [100, 0], 'bis' => [100, 560], 'breite' => 3.2,
                  'tiefe' => 5 }])
    w = lines(r.files[0]).grep(/W#1051/)[0]
    assert_includes w, '#8509=1 #8510=100 #8511=0 #8518=560'
    assert_includes w, '#8503=0'
  end

  def test_groove_falls_back_to_mill_two_passes
    prof = profil
    prof['werkzeuge'].each { |t| t['nummer'] = nil if t['art'].start_with?('nutsaege') }
    r = export([{ 'typ' => 'nut', 'flaeche' => 'F1', 'von' => [0, 100], 'bis' => [720, 100], 'breite' => 8.5,
                  'tiefe' => 10, 'bezug' => 'mitte' }], prof)
    assert_empty r.fehler
    l = lines(r.files[0])
    assert_equal 2, l.grep(/W#89/).size
    assert_match(/#2=99.75/, l.grep(/W#89/)[0])
    assert_match(/#2=100.25/, l.grep(/W#89/)[1])
  end

  def test_missing_tool_reports_error_and_writes_nothing
    prof = JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json')))
    prof['werkzeuge'].each { |t| t['nummer'] = nil }
    r = Kp::Tcn::Exporter.new(prof)
                         .export(teil([{ 'id' => 'n', 'typ' => 'nut', 'flaeche' => 'F1', 'von' => [0, 1], 'bis' => [9, 1],
                                         'breite' => 8, 'tiefe' => 5 }]))
    assert_empty r.files
    assert_match(/nummer im Profil fehlt/, r.fehler.join)
  end

  def test_validation_errors
    r = export([{ 'id' => 'a', 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 900, 'y' => 10, 'd' => 5, 'tiefe' => 5 },
                { 'id' => 'b', 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 10, 'y' => 10, 'd' => 5, 'tiefe' => 18 }])
    assert_equal 2, r.fehler.size
    assert_empty r.files
  end

  # Kopfmaß = Fräsmaß = Fertigmaß - Anleimer; Koordinaten verschieben sich um Anleimer links/vorne
  def test_head_is_fraesmass_and_coordinates_shift
    band = { 'kantenstaerke' => { 'vorne' => 2, 'links' => 2, 'rechts' => 2 } }
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 10, 'y' => 10, 'd' => 5, 'tiefe' => 5 }], profil, band)
    l = lines(r.files[0])
    assert_equal '::UNm DL=716 DH=558 DS=19', l[2] # wie Seite.tcn bei Fertigmaß 720 x 560
    assert_includes l, 'W#81{ ::WTp #1002=5 #1=8 #2=8 #3=-5 #8015=0 #201=1 #203=1 #1001=0 }W'
  end

  def test_back_edge_reduces_size_without_shift
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 10, 'y' => 10, 'd' => 5, 'tiefe' => 5 }], profil,
               'kantenstaerke' => { 'hinten' => 2 })
    l = lines(r.files[0])
    assert_equal '::UNm DL=720 DH=558 DS=19', l[2]
    assert_includes l, 'W#81{ ::WTp #1002=5 #1=10 #2=10 #3=-5 #8015=0 #201=1 #203=1 #1001=0 }W'
  end

  def test_edge_hole_subtracts_band_of_that_edge
    # F5 = linke Kante (Anleimer links 2): Tiefe 22 -> 20; Position entlang y verschiebt um Anleimer vorne
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F5', 'y' => 34, 'z' => 9.5, 'd' => 8, 'tiefe' => 22 }], profil,
               'kantenstaerke' => { 'links' => 2, 'vorne' => 2 })
    assert_includes lines(r.files[0]), 'W#81{ ::WTp #1002=8 #1=32 #2=9.5 #3=-20 #8015=0 #201=1 #203=1 #1001=0 }W'
  end

  def test_wenden_uses_back_band_for_shift
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F2', 'x' => 100, 'y' => 100, 'd' => 35, 'tiefe' => 12.5 }], profil,
               'kantenstaerke' => { 'vorne' => 2, 'hinten' => 2 })
    # gespiegelt y' = 560 - 100 = 460, dann minus Anleimer hinten (jetzt vorne) = 458
    assert_includes lines(r.files.last), 'W#81{ ::WTp #1002=35 #1=100 #2=458 #3=-12.5 #8015=0 #201=1 #203=1 #1001=0 }W'
  end

  # Zeilen aus examples/tcn_referenz/T_rR.tcn und Boden.tcn werden über das Makro-Durchgriff exakt erzeugt
  def test_macro_passthrough_matches_reference_files
    r = export([{ 'typ' => 'makro', 'flaeche' => 'F1', 'nummer' => 1506, 'datei' => 'inge100',
                  'parameter' => { '8500' => 35, '8501' => 8, '8502' => 45, '8503' => '9,5', '8504' => 14, '8505' => 14,
                                   '8506' => 1, '8507' => '55+2+16', '8508' => 'y-21,5' } }])
    ref = File.read(File.join(ROOT, 'examples/tcn_referenz/T_rR.tcn')).split("\r\n").grep(/W#1506/)[0]
    got = lines(r.files[0]).grep(/W#1506/)[0]
    assert_equal ref.sub(/ WS=\d+ /, ' ').squeeze(' '), got.squeeze(' ')
  end

  def test_file_skeleton_matches_reference_layout
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F4', 'x' => 30, 'd' => 8, 'tiefe' => 22 }])
    l = lines(r.files[0])
    ref = File.read(File.join(ROOT, 'examples/tcn_referenz/Seite.tcn')).split("\r\n")
    sides = ->(a) { a.grep(/\ASIDE#|\A\}SIDE/) }
    assert_equal sides.call(ref), sides.call(l)
    assert_equal ref[ref.index('EXE{')..ref.index('}LINK')], l[l.index('EXE{')..l.index('}LINK')]
  end

  def test_formatieren_first_op_matches_reference
    prof = profil('formatieren' => { 'aktiv' => true, 'werkzeug' => 1037 })
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 10, 'y' => 10, 'd' => 5, 'tiefe' => 5 }], prof)
    l = lines(r.files[0])
    ref = File.read(File.join(ROOT, 'examples/tcn_referenz/Seite.tcn')).split("\r\n").grep(/W#1510/)[0]
    expected = ref.sub(/ WS=\d+ W\$=forma /, ' ').sub('#8502=1000', '#8502=1037').squeeze(' ')
    got = l.grep(/W#1510/)[0].squeeze(' ')
    assert_equal expected, got
    assert l.index(l.grep(/W#1510/)[0]) < l.index(l.grep(/W#81/)[0])
  end

  def test_formatieren_creates_file_even_without_other_ops
    r = export([], profil('formatieren' => { 'aktiv' => true, 'werkzeug' => 1037 }))
    assert_equal 1, r.files.size
  end

  def test_contour_arc
    r = export([{ 'typ' => 'kontur', 'flaeche' => 'F1', 'tiefe' => 5, 'korrektur' => 'links',
                  'pfad' => [{ 'x' => 0, 'y' => 0 }, { 'x' => 10, 'y' => 10, 'bogen' => { 'r' => 10, 'cw' => false } }] }],
               profil.tap { |p| p['werkzeuge'].find { |t| t['art'] == 'nutfraeser' }['d'] = 8 })
    arc = lines(r.files[0]).grep(/W#2101/)[0]
    assert_match(/#31=0 #32=10 #34=1/, arc)
  end
end
