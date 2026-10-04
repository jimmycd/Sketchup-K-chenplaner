# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/kp/generator'
require_relative '../lib/kp/tcn/exporter'

class TestOberschrank < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @projekt = JSON.parse(File.read(File.join(ROOT, 'examples/projekt_oberschrank.json')))
    @gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
  end

  def schrank(inst = {})
    @gen.schrank({ 'pos' => 'O1', 'vorlage' => 'OS-T1', 'breite' => 600 }.merge(inst))
  end

  def teil(res, id) = res.teile.find { |t| t['teil_id'] == id }
  def ops(t, typ) = t['bearbeitungen'].select { |b| b['typ'] == typ }

  def test_parts_without_traversen
    res = schrank
    assert_equal %w[sl sr bo de rw eb1 tu1], res.teile.map { |t| t['teil_id'] }
    refute(res.teile.any? { |t| t['rolle'].start_with?('traverse') })
  end

  def test_sides_full_depth_boden_and_deckel_stop_at_rueckwand
    res = schrank
    assert_equal({ 'l' => 720.0, 'w' => 350.0, 'd' => 19.0 }, teil(res, 'sl')['fertigmass']) # Seiten über die volle Tiefe
    # Versatz 16 = Haken 14 + Luft 2; Boden/Deckel = 350 - 16 - 8
    assert_equal({ 'l' => 562.0, 'w' => 326.0, 'd' => 19.0 }, teil(res, 'bo')['fertigmass'])
    assert_equal teil(res, 'bo')['fertigmass'], teil(res, 'de')['fertigmass']
    assert_equal 701.0, teil(res, 'de')['lage']['position'][2]
  end

  # Rückwandvorderkante = Hinterkante von Boden und Deckel; Rückwand 8 mm zwischen 326 und 334 von vorne
  def test_rueckwand_offset_and_size
    res = schrank
    rw = teil(res, 'rw')
    assert_equal 334.0, rw['lage']['position'][1] # Rückseite 16 mm vor der Hinterkante der Seiten (350)
    assert_equal 326.0, rw['lage']['position'][1] - 8
    assert_equal teil(res, 'bo')['fertigmass']['w'], rw['lage']['position'][1] - 8
    assert_equal({ 'l' => 580.0, 'w' => 719.0, 'd' => 8.0 }, rw['fertigmass']) # Innenbreite 562 + 2 * (Nut 10 - Luft 1)
    assert_in_delta 10.0, rw['lage']['position'][0], 1e-9 # 9 mm in die Seite (19 - 9)
  end

  def test_nut_in_both_sides_matches_rueckwand
    res = schrank
    %w[sl sr].each do |id|
      s = teil(res, id)
      nuten = ops(s, 'nut')
      assert_equal 1, nuten.size
      n = nuten.first
      assert_equal [0.0, s['fertigmass']['l']], [n['von'][0], n['bis'][0]] # durchgehend: von oben einschiebbar
      assert_equal 10, n['tiefe']
      assert_equal 8.5, n['breite']
      # Nutbereich in Abstand von der Hinterkante: [versatz - 0,5, versatz + 8] (Rückwand 16..24)
      von = n['von'][1]
      bis = von + n['breite']
      hinten = id == 'sl' ? [von, bis] : [350.0 - bis, 350.0 - von] # sl: y von hinten, sr: y von vorne
      assert_in_delta 15.5, hinten[0], 1e-9
      assert_in_delta 24.0, hinten[1], 1e-9
    end
  end

  def test_rueckwand_screwed_to_boden
    res = schrank
    rw = ops(teil(res, 'rw'), 'bohrung')
    bo = ops(teil(res, 'bo'), 'bohrung').select { |b| b['flaeche'] == 'F4' }
    assert_equal 3, rw.size
    assert_equal 3, bo.size
    # gleiche Schrankposition: Rückwand-x + Versatz zur Seite = Boden-x + Seitenstärke
    assert_equal bo.map { |b| b['x'] + 19.0 }, rw.map { |b| b['x'] + teil(res, 'rw')['lage']['position'][0] }
    assert(rw.all? { |b| b['durch'] && b['y'] == 9.5 }) # Mitte der Bodenstärke
  end

  def test_aufhaenger_choice_sets_versatz
    assert(schrank.warnungen.any? { |w| w.include?('haefele_aufhaenger_unsichtbar') }) # Standard aus dem Beschlag-Set
    res = schrank('overrides' => { 'aufhaengung.beschlag' => 'haefele_aufhaenger_sichtbar' })
    assert(res.warnungen.any? { |w| w.include?('haefele_aufhaenger_sichtbar') })
    # Luft ändern: Haken 14 + Luft 8 = Versatz 22
    res = schrank('overrides' => { 'parameter.luft_aufhaenger.default' => 8 })
    assert_equal 350.0 - 22.0 - 8.0, teil(res, 'bo')['fertigmass']['w']
  end

  def test_versatz_freely_adjustable
    res = schrank('overrides' => { 'parameter.versatz.default' => 30 })
    assert_equal 312.0, teil(res, 'bo')['fertigmass']['w']
    assert_equal 320.0, teil(res, 'rw')['lage']['position'][1]
  end

  def test_side_joints_follow_boden_depth
    res = schrank
    sr = teil(res, 'sr')
    duebel = ops(sr, 'bohrung').select { |b| b['d'] == 8 }
    assert_equal 6, duebel.size
    # Abstand von vorne (rechte Seite: y zeigt nach hinten) endet 30 mm vor der Hinterkante von Boden/Deckel
    assert_equal [32.0, 164.0, 296.0], duebel.select { |b| b['x'] == 9.5 }.map { |b| b['y'] }.sort
    refute(sr['bearbeitungen'].any? { |b| b['y'].to_f > 326.0 && b['d'] == 8 })
  end

  def test_all_parts_export_to_tcn
    prof = JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json')))
    prof['werkzeuge'].each do |t|
      t['nummer'] = { 'nutsaege_x' => 1161, 'nutsaege_y' => 1162, 'nutfraeser' => 5408 }[t['art']] if t['nummer'].nil?
    end
    @projekt['zeilen'][0]['elemente'].each do |inst|
      @gen.schrank(inst).teile.each do |t|
        r = Kp::Tcn::Exporter.new(prof).export(t)
        assert_empty r.fehler, "#{t['uid']}: #{r.fehler}"
      end
    end
  end
end
