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
    assert_equal 'TPA\\ALBATROS\\EDICAD\\01.00', l[0]
    assert_equal '::UNm DL=720 DH=560 DS=19', l[2]
    assert_includes l, 'SIDE#1{'
    assert_includes l, 'W#81{ ::WTp #1002=8 #1=9.5 #2=34 #3=-12 #8015=0 #1001=1 }W'
  end

  def test_bohrreihe_expands_and_maps_face
    r = export([{ 'id' => 'r', 'typ' => 'bohrreihe', 'flaeche' => 'F1', 'start' => [83, 37], 'richtung' => '+x',
                  'raster' => 32, 'anzahl' => 3, 'd' => 5, 'tiefe' => 12 }])
    holes = lines(r.files[0]).grep(/W#81/)
    assert_equal 3, holes.size
    assert_match(/#1=147 #2=37/, holes[2])
  end

  def test_edge_hole_face_mapping_and_axes
    # Konzept F5 (links) -> TpaCAD 6; Position entlang y, Höhe z
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F5', 'y' => 34, 'z' => 9.5, 'd' => 8, 'tiefe' => 22 }])
    l = lines(r.files[0])
    assert_includes l, 'SIDE#6{'
    assert_includes l, 'W#81{ ::WTp #1002=8 #1=34 #2=9.5 #3=-22 #8015=0 #1001=1 }W'
    # F4 (hinten) -> 5, entlang x; F6 (rechts) -> 4
    r2 = export([{ 'typ' => 'bohrung', 'flaeche' => 'F4', 'x' => 100, 'd' => 8, 'tiefe' => 22 },
                 { 'typ' => 'bohrung', 'flaeche' => 'F6', 'y' => 100, 'd' => 8, 'tiefe' => 22 }])
    l2 = lines(r2.files[0])
    assert_includes l2, 'SIDE#5{'
    assert_includes l2, 'SIDE#4{'
    assert_includes l2, 'W#81{ ::WTp #1002=8 #1=100 #2=9.5 #3=-22 #8015=0 #1001=1 }W'
  end

  def test_f2_goes_to_second_setup_mirrored
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F2', 'x' => 100, 'y' => 100, 'd' => 35, 'tiefe' => 12.5 }])
    assert_equal ['p_A1_t_B.tcn'], r.files.map(&:name)
    assert_includes lines(r.files[0]), 'W#81{ ::WTp #1002=35 #1=100 #2=460 #3=-12.5 #8015=0 #1001=1 }W'
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
    r = Kp::Tcn::Exporter.new(JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json'))))
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

  def test_offset_to_zuschnittmass
    assert_equal({ x: 1.0, y: 1.0 }, Kp::Tcn::Exporter.offset({ 'l' => 720, 'w' => 560 }, { 'l' => 722, 'w' => 562 }))
    prof = profil('bearbeitung_auf' => 'zuschnittmass')
    r = export([{ 'typ' => 'bohrung', 'flaeche' => 'F1', 'x' => 10, 'y' => 10, 'd' => 5, 'tiefe' => 5 }], prof,
               'zuschnittmass' => { 'l' => 722, 'w' => 562, 'd' => 19 })
    l = lines(r.files[0])
    assert_equal '::UNm DL=722 DH=562 DS=19', l[2]
    assert_includes l, 'W#81{ ::WTp #1002=5 #1=11 #2=11 #3=-5 #8015=0 #1001=1 }W'
  end

  def test_contour_arc
    r = export([{ 'typ' => 'kontur', 'flaeche' => 'F1', 'tiefe' => 5, 'korrektur' => 'links',
                  'pfad' => [{ 'x' => 0, 'y' => 0 }, { 'x' => 10, 'y' => 10, 'bogen' => { 'r' => 10, 'cw' => false } }] }],
               profil.tap { |p| p['werkzeuge'].find { |t| t['art'] == 'nutfraeser' }['d'] = 8 })
    arc = lines(r.files[0]).grep(/W#2101/)[0]
    assert_match(/#31=0 #32=10 #34=1/, arc)
  end
end
