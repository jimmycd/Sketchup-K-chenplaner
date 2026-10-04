# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/kp/generator'

class TestGenerator < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @projekt = JSON.parse(File.read(File.join(ROOT, 'examples/projekt_mueller.json')))
    @gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
  end

  def schrank(inst = {})
    @gen.schrank({ 'pos' => 'A1', 'vorlage' => 'US-T1', 'breite' => 450 }.merge(inst))
  end

  def teil(res, id) = res.teile.find { |t| t['teil_id'] == id }

  def test_parts_and_dimensions
    res = schrank
    assert_equal %w[sl sr bo tv th rw eb1 tu1], res.teile.map { |t| t['teil_id'] }
    assert_equal({ 'l' => 772.0, 'w' => 552.0, 'd' => 19.0 }, teil(res, 'sl')['fertigmass']) # H 772, Tiefe 560 - 8
    assert_equal({ 'l' => 412.0, 'w' => 552.0, 'd' => 19.0 }, teil(res, 'bo')['fertigmass']) # B - 2S
    assert_equal({ 'l' => 450.0, 'w' => 772.0, 'd' => 8.0 }, teil(res, 'rw')['fertigmass'])
    assert_equal 'kueche_mueller_2026/A1/sl', teil(res, 'sl')['uid']
  end

  def test_edge_thickness_resolved
    t = teil(schrank, 'sl')
    assert_equal 'abs_weiss_2', t['kanten']['vorne']
    assert_equal 2.0, t['kantenstaerke']['vorne']
    assert_equal 0.0, t['kantenstaerke']['links']
  end

  def test_hole_row_count_and_mirroring
    res = schrank
    sr = teil(res, 'sr')['bearbeitungen']
    sl = teil(res, 'sl')['bearbeitungen']
    assert_equal 2, sr.size
    assert_equal 19, sr[0]['anzahl'] # floor((772-38-64-64)/32)+1
    assert_equal [83.0, 37.0], sr[0]['start']
    assert_equal [83.0, 552.0 - 37.0], sr[1]['start']
    # linke Seite: y-Achse zeigt nach vorne, Reihen werden gespiegelt
    assert_equal [83.0, 552.0 - 37.0], sl[0]['start']
    assert_equal [83.0, 37.0], sl[1]['start']
  end

  def test_no_groove_rule_for_aufgesetzte_rueckwand
    res = schrank
    refute(res.teile.any? { |t| t['bearbeitungen'].any? { |b| b['typ'] == 'nut' } })
  end

  def test_groove_rule_when_genutet
    @projekt['standards']['rueckwand']['art'] = 'genutet'
    gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    res = gen.schrank('pos' => 'A1', 'vorlage' => 'US-T1', 'breite' => 450)
    nuten = res.teile.flat_map { |t| t['bearbeitungen'] }.select { |b| b['typ'] == 'nut' }
    assert_equal 3, nuten.size # Seite links, Seite rechts, Boden
    assert_equal 'links', nuten[0]['bezug']
  end

  def test_abstract_template_rejected
    assert_raises(Kp::Katalog::Fehler) { @gen.schrank('vorlage' => 'US-BASIS', 'breite' => 600) }
  end

  def test_override_and_warnings
    res = schrank('overrides' => { 'front.felder.0.anschlag' => 'links' })
    assert(res.warnungen.any? { |w| w.include?('r_seite_boden') })
  end

  def tuer(res) = teil(res, 'tu1')

  def test_door_size_edges_and_orientation
    t = tuer(schrank('breite' => 450))
    assert_equal({ 'l' => 769.0, 'w' => 447.0, 'd' => 19.0 }, t['fertigmass']) # H 772 - Fuge 3, B 450 - Fuge 3
    assert_equal 2.0, t['kantenstaerke']['links'] # Frontkante abs_lack_2 rundum
    assert_equal({ 'x' => '+z', 'z' => '+y' }, t['lage']['ausrichtung']) # Vorlage US-T1: Anschlag rechts
    links = tuer(schrank('overrides' => { 'front.felder.0.anschlag' => 'links' }))
    assert_equal({ 'x' => '-z', 'z' => '+y' }, links['lage']['ausrichtung'])
    assert_includes links['bezeichnung'], 'DIN L'
  end

  def test_door_hinges_use_macro_with_32_raster
    ops = tuer(schrank)['bearbeitungen']
    assert_equal 2, ops.size
    assert(ops.all? { |o| o['typ'] == 'makro' && o['nummer'] == 1506 && o['datei'] == 'inge100' })
    xs = ops.map { |o| o['parameter']['8507'] }
    assert_equal 576.0, xs[1] - xs[0] # Vielfaches von 32 (18 x 32)
    assert_equal 'y-21,5', ops[0]['parameter']['8508'] # Topfmitte 17,5 + tb 4
    assert_equal 35, ops[0]['parameter']['8500']
    assert_in_delta 94.5, xs[0], 1e-6 # (769 - 576) / 2 = 96,5 minus Anleimer 2
  end

  def test_handle_marks_from_griff_parameters
    @projekt['standards']['front']['griff'] = 'griff'
    gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    ops = tuer(gen.schrank('pos' => 'A1', 'vorlage' => 'US-T1', 'breite' => 450))['bearbeitungen'].select { |o| o['typ'] == 'bohrung' }
    assert_equal 2, ops.size
    assert_equal 160.0, ops[1]['x'] - ops[0]['x']
    assert_equal [3, 3], ops.map { |o| o['tiefe'] }
    assert_equal 37.0, ops[0]['y']
  end

  def test_einlegeboden_on_grid
    eb = teil(schrank, 'eb1')
    z = eb['fertigmass']
    assert_equal 410.0, z['l']
    assert_equal 532.0, z['w']
    assert_equal 0, (((19 + 64) - 83) % 32) # Raster passt zur Lochreihe
  end

  def test_generated_parts_export_to_tcn
    require_relative '../lib/kp/tcn/exporter'
    profil = JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json')))
    schrank.teile.each do |t|
      r = Kp::Tcn::Exporter.new(profil).export(t)
      assert_empty r.fehler, t['uid']
      refute_empty r.files
    end
  end
end
