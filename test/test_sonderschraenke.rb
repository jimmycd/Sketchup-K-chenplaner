# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/kp/generator'
require_relative '../lib/kp/tcn/exporter'

# Sonderschränke: Geschirrspüler, Spülenschrank, Herd/Backofen, Hochschrank mit Ofen, Eckschränke.
class TestSonderschraenke < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  AXES = { '+x' => [1, 0, 0], '-x' => [-1, 0, 0], '+y' => [0, 1, 0], '-y' => [0, -1, 0], '+z' => [0, 0, 1], '-z' => [0, 0, -1] }.freeze
  ALLE = %w[US-GS-VOLL US-GS-TEIL US-GS-FREI US-SPUE US-HERD-OFEN US-HERD-KF HS-OFEN ES-BLIND-L ES-BLIND-R ES-L-KARUSSELL ES-L-LEMANS].freeze

  def setup
    @projekt = JSON.parse(File.read(File.join(ROOT, 'examples/projekt_mueller.json')))
    @gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    @profil = JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json')))
  end

  def schrank(vorlage, inst = {}) = @gen.schrank({ 'pos' => 'B1', 'vorlage' => vorlage }.merge(inst))

  def teil(res, id) = res.teile.find { |t| t['teil_id'] == id }

  def ids(res) = res.teile.map { |t| t['teil_id'] }

  def ops(teil, praefix) = teil['bearbeitungen'].select { |o| o['id'].to_s.start_with?(praefix) }

  # Achsparallele Hülle eines Teils im Schrank-System (Teilachsen x Länge, y = z × x Breite, z Dicke)
  def huelle(t)
    x = AXES[t['lage']['ausrichtung']['x']]
    z = AXES[t['lage']['ausrichtung']['z']]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    f = t['fertigmass']
    p = t['lage']['position']
    ecken = [0, 1].product([0, 1], [0, 1]).map { |i, j, k| (0..2).map { |a| p[a] + i * f['l'] * x[a] + j * f['w'] * y[a] + k * f['d'] * z[a] } }
    [(0..2).map { |a| ecken.map { |q| q[a] }.min }, (0..2).map { |a| ecken.map { |q| q[a] }.max }]
  end

  def test_example_project_generates_all_special_cabinets
    projekt = JSON.parse(File.read(File.join(ROOT, 'examples/projekt_sonderschraenke.json')))
    gen = Kp::Generator.new(projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    codes = projekt['zeilen'].flat_map { |z| z['elemente'] }.map do |inst|
      refute_empty gen.schrank(inst).teile, inst['vorlage']
      inst['vorlage']
    end
    assert_equal ALLE.sort, codes.sort
  end

  # ---- alle Vorlagen ------------------------------------------------------------

  def test_no_part_overlaps_another
    ALLE.each do |code|
      res = schrank(code)
      boxen = res.teile.to_h { |t| [t['teil_id'], huelle(t)] }
      boxen.keys.combination(2).each do |a, b|
        d = (0..2).map { |k| [boxen[a][1][k], boxen[b][1][k]].min - [boxen[a][0][k], boxen[b][0][k]].max }
        refute d.all? { |v| v > 0.5 }, "#{code}: #{a} und #{b} überschneiden sich (#{d.map { |v| v.round(1) }})"
      end
    end
  end

  def test_all_generated_parts_export_to_tcn
    ALLE.each do |code|
      schrank(code).teile.each do |t|
        r = Kp::Tcn::Exporter.new(@profil).export(t)
        assert_empty r.fehler, "#{code} #{t['uid']}"
        refute_empty r.files
      end
    end
  end

  def test_every_part_has_ocl_and_dimensions
    ALLE.each do |code|
      schrank(code).teile.each do |t|
        assert t['ocl'] && t['masse'], "#{code} #{t['teil_id']}"
        assert_equal t['masse']['fraes']['l'] + 10, t['masse']['roh']['l'] # Rohmaß = Fräsmaß + 10
      end
    end
  end

  # ---- Geschirrspüler ------------------------------------------------------------

  def test_dishwasher_niche_has_only_struts_and_front
    res = schrank('US-GS-VOLL')
    assert_equal %w[tv th tu1], ids(res)
    assert_equal({ 'l' => 600.0, 'w' => 100.0, 'd' => 19.0 }, teil(res, 'tv')['fertigmass'])
    assert_empty teil(res, 'tv')['bearbeitungen'] # Schraubwinkel an den Nachbarseiten, keine Dübel
    assert_equal 769.0, teil(res, 'tu1')['fertigmass']['l']
    assert_empty(teil(res, 'tu1')['bearbeitungen']) # Front am Gerät, kein Topfband
    assert(res.warnungen.any? { |w| w.include?('Befestigung am Gerät') })
  end

  def test_dishwasher_semi_integrated_leaves_control_strip_open
    res = schrank('US-GS-TEIL')
    assert_equal 769.0 - 3 - 90, teil(res, 'tu1')['fertigmass']['l'] # Höhe − Fuge − Bedienblende 90
    res = schrank('US-GS-TEIL', 'overrides' => { 'parameter.bedienblende_h.default' => 110 })
    assert_equal 769.0 - 3 - 110, teil(res, 'tu1')['fertigmass']['l']
  end

  def test_dishwasher_free_standing_has_no_front
    assert_equal %w[tv th], ids(schrank('US-GS-FREI'))
  end

  def test_niche_check_warns_when_too_small
    res = schrank('US-GS-VOLL', 'breite' => 450, 'overrides' => { 'einbauten.0.geraet.nischenmass.0' => 598 })
    assert(res.warnungen.any? { |w| w.include?('lichte Breite') })
    assert(schrank('US-GS-VOLL', 'tiefe' => 500).warnungen.any? { |w| w.include?('Tiefe') })
  end

  # ---- Spülenschrank ---------------------------------------------------------------

  def test_sink_cabinet_parts_and_water_resistant_bottom
    res = schrank('US-SPUE', 'breite' => 900)
    assert_equal %w[sl sr bo tv th rw sk1f sk1b bl2], ids(res)
    assert_equal 'spano_wasserfest_19', teil(res, 'bo')['material']
    assert_equal 'spano_weiss_19', teil(res, 'sl')['material']
    assert_equal 130.0, teil(res, 'bl2')['fertigmass']['w']
    assert_equal 'blende', teil(res, 'bl2')['rolle']
    assert_equal 636.0, teil(res, 'sk1f')['fertigmass']['w'] # 772 − 3 − 3 − 130
    assert_empty ops(teil(res, 'sl'), 'r_lochreihe') # Frontauszug und US-SPUE: keine Lochreihe
  end

  def test_sink_cutouts_are_closed_contours_through_the_part
    res = schrank('US-SPUE')
    k = teil(res, 'rw')['bearbeitungen'].find { |o| o['typ'] == 'kontur' }
    assert k['geschlossen']
    assert_equal 10.0, k['tiefe'] # 8 mm HDF + 2 mm durch
    xs = k['pfad'].map { |p| p['x'] }
    assert_in_delta 300.0, xs.max - xs.min, 1e-6 # anschluss_b
    assert_in_delta 450.0, (xs.max + xs.min) / 2, 1e-6 # Mitte B/2
    assert(k['pfad'].any? { |p| p['bogen'] }, 'Eckradius 20')
    sk = teil(res, 'sk1b')['bearbeitungen'].find { |o| o['typ'] == 'kontur' }
    ys = sk['pfad'].map { |p| p['y'] }
    assert_in_delta teil(res, 'sk1b')['fertigmass']['w'], ys.max, 1e-6 # U-Ausschnitt reicht bis zur Hinterkante
  end

  def test_sink_cutout_parameters_editable_by_override
    res = schrank('US-SPUE', 'overrides' => { 'parameter.anschluss_b.default' => 420, 'parameter.anschluss_x.default' => 200 })
    xs = teil(res, 'rw')['bearbeitungen'].find { |o| o['typ'] == 'kontur' }['pfad'].map { |p| p['x'] }
    assert_in_delta 420.0, xs.max - xs.min, 1e-6
    assert_in_delta 200.0, (xs.max + xs.min) / 2, 1e-6
  end

  def test_sink_cabinet_all_widths
    [450, 500, 600, 800, 900, 1000, 1200].each do |b|
      res = schrank('US-SPUE', 'breite' => b)
      assert_equal b.to_f, teil(res, 'rw')['fertigmass']['l']
      assert_equal b - 3.0, teil(res, 'sk1f')['fertigmass']['l']
    end
  end

  # ---- Herd / Backofen -----------------------------------------------------------------

  def test_oven_base_cabinet
    res = schrank('US-HERD-OFEN')
    assert_equal %w[sl sr bo rw zb sk1f sk1b], ids(res) # keine Traversen
    zb = teil(res, 'zb')
    assert_equal 772.0 - 590 - 19, zb['lage']['position'][2]
    assert_equal 'zwischenboden', zb['rolle']
    assert_equal 157.0, teil(res, 'sk1f')['fertigmass']['w'] # Schublade unter der Nische
    # Seiten: Dübel nur am Bodenende, dazu 3 Gegenstück-Dübel für den Zwischenboden
    assert_equal 7, ops(teil(res, 'sl'), 'r_seite_duebel_nur_boden').size
    zd = ops(teil(res, 'sl'), 'r_zwischenboden_duebel1')
    assert_equal 3, zd.size
    assert(zd.all? { |o| (o['x'] - (163 + 9.5)).abs < 1e-6 })
    assert_equal 1, teil(res, 'rw')['bearbeitungen'].count { |o| o['typ'] == 'kontur' }
  end

  # Frontbefestigung der Schublade: bei niedriger Front (157 mm) nur die untere Lochpaarung, sonst vier Paare
  def test_low_drawer_front_gets_only_lower_fastening_holes
    low = teil(schrank('US-HERD-OFEN'), 'sk1f')['bearbeitungen'].select { |o| o['id'].start_with?('sk1f.') }
    assert_equal 4, low.size
    assert_equal [71.0, 103.0], low.map { |o| o['y'] }.uniq.sort # 69 und 101 ab Fräskante plus 2 mm Anleimer
    normal = @gen.schrank('pos' => 'A2', 'vorlage' => 'US-S2', 'breite' => 600).teile.find { |t| t['teil_id'] == 'sk1f' }
    assert_equal 8, normal['bearbeitungen'].count { |o| o['id'].start_with?('sk1f.') }
  end

  def test_cooktop_cabinet_with_downdraft_duct
    res = schrank('US-HERD-KF')
    assert_equal %w[sl sr bo tv rw sk1f sk1b sk2f sk2b], ids(res) # hintere Traverse entfällt
    assert_equal 390.0, teil(res, 'sk1b')['fertigmass']['w'] # NL 400 statt 550 wegen Kanaltiefe 120
    k = teil(res, 'bo')['bearbeitungen'].find { |o| o['typ'] == 'kontur' }
    refute_nil k
    ys = k['pfad'].map { |p| p['y'] }
    assert_in_delta 552.0, ys.max, 1e-6 # Kanal läuft an der Hinterkante des Bodens
    assert_in_delta 120.0, ys.max - ys.min, 1e-6
    wider = schrank('US-HERD-KF', 'overrides' => { 'parameter.kanal_t.default' => 200 })
    assert_equal 290.0, teil(wider, 'sk1b')['fertigmass']['w'] # NL 300
  end

  # ---- Hochschrank mit Ofen ----------------------------------------------------------------

  def test_tall_oven_cabinet_layout
    res = schrank('HS-OFEN')
    assert_equal 2100.0, teil(res, 'sl')['fertigmass']['l']
    assert_equal 2081.0, teil(res, 'dk')['lage']['position'][2]
    assert_equal 700.0, teil(res, 'zb1')['lage']['position'][2]
    assert_equal 700.0 + 19 + 600, teil(res, 'zb2')['lage']['position'][2]
    assert_equal %w[sk1f sk1b sk2f sk2b tu4], ids(res).grep(/\A(sk|tu)/)
    assert_equal 348.5, teil(res, 'sk1f')['fertigmass']['w']
    assert_equal 753.0, teil(res, 'tu4')['fertigmass']['l']
    eb = teil(res, 'eb1')
    assert eb['lage']['position'][2].between?(1338, 2081 - 19), "Einlegeboden im oberen Fach: #{eb['lage']['position'][2]}"
    assert_equal 0, (eb['lage']['position'][2] - (2 + 55)) % 32
  end

  def test_tall_cabinet_side_dowels_both_ends_and_shelves
    res = schrank('HS-OFEN')
    sl = teil(res, 'sl')
    assert_equal 14, ops(sl, 'r_seite_duebel_boden_deckel').size
    assert_equal 3, ops(sl, 'r_zwischenboden_duebel1').size
    assert_equal 3, ops(sl, 'r_zwischenboden_duebel2').size
    assert_empty ops(sl, 'r_seite_duebel_schraube.')
    assert_equal 6, teil(res, 'dk')['bearbeitungen'].size # stirnseitige Dübel
  end

  # ---- Eckschränke ---------------------------------------------------------------------------

  def test_blind_corner_door_and_blind_panel
    l = schrank('ES-BLIND-L')
    assert_equal 597.0, teil(l, 'tu1')['fertigmass']['w']
    assert_equal 397.0, teil(l, 'bl2')['fertigmass']['l']
    assert_equal({ 'x' => '+z', 'z' => '+y' }, teil(l, 'tu1')['lage']['ausrichtung'])
    assert_in_delta 1000 - 600 + 1.5, teil(l, 'tu1')['lage']['position'][0], 1e-6 # Tür rechts
    r = schrank('ES-BLIND-R')
    assert_equal({ 'x' => '-z', 'z' => '+y' }, teil(r, 'tu1')['lage']['ausrichtung'])
    assert_in_delta 1.5 + 597, teil(r, 'tu1')['lage']['position'][0], 1e-6 # Anschlag links: Position an der Scharnierkante
    assert_equal teil(l, 'tu1')['lage']['position'][2], teil(l, 'bl2')['lage']['position'][2] # gleiche Zeile
    wide = schrank('ES-BLIND-L', 'overrides' => { 'parameter.tuer_b.default' => 500 })
    assert_equal 497.0, teil(wide, 'tu1')['fertigmass']['w']
  end

  def test_l_corner_geometry
    %w[ES-L-KARUSSELL ES-L-LEMANS].each do |code|
      res = schrank(code)
      assert_equal %w[sl sv sa bo1 bo2 tv1 tv2 th tl rw ef1a ef1b], ids(res)
      lo, hi = res.teile.reject { |t| t['teil_id'].start_with?('ef') }.map { |t| huelle(t) }.transpose
      assert_equal [0.0, 0.0, 0.0], (0..2).map { |a| lo.map { |p| p[a] }.min }
      assert_equal [900.0, 900.0, 772.0], (0..2).map { |a| hi.map { |p| p[a] }.max }
      # nichts ragt in den Ausschnitt des L (x > Schenkeltiefe 560, y < T − 560 = 340); die Flügel liegen davor im Raum
      res.teile.reject { |t| t['teil_id'].start_with?('ef') }.each do |t|
        a, b = huelle(t)
        in_x = [b[0], 900].min - [a[0], 560].max
        in_y = [b[1], 340].min - [a[1], 0].max
        refute(in_x > 0.5 && in_y > 0.5, "#{t['teil_id']} ragt in den Ausschnitt")
      end
      assert(res.warnungen.any? { |w| w.include?('Faltscharniere') })
      assert(res.warnungen.any? { |w| w.include?('Verbindungsbohrungen') })
    end
  end

  def test_l_corner_front_leaves_meet_at_inner_corner
    res = schrank('ES-L-KARUSSELL')
    f1 = teil(res, 'ef1a')
    f2 = teil(res, 'ef1b')
    a1, b1 = huelle(f1)
    a2, b2 = huelle(f2)
    assert_equal 340.0, b1[1] # Flügel 1 liegt vor der Front des hinteren Schenkels (y = T − 560)
    assert_in_delta 561.5, a1[0], 1e-6
    assert_in_delta 898.5, b1[0], 1e-6 # Scharnierseite am Schenkelende
    assert_equal 560.0, a2[0] # Flügel 2 vor der Front des linken Schenkels (x = 560)
    assert b2[1] < a1[1], 'Flügel 2 endet vor Flügel 1'
    assert_equal 2, f1['bearbeitungen'].size # Topfbänder nur am äußeren Flügel
    assert_empty f2['bearbeitungen']
  end

  def test_l_corner_depth_and_leg_parameters
    res = schrank('ES-L-LEMANS', 'breite' => 1000, 'tiefe' => 1000)
    assert_equal 1000.0, teil(res, 'rw')['fertigmass']['l']
    assert_equal 1000.0 - 560 - 19, teil(res, 'tv1')['fertigmass']['l'] # B − S − Schenkeltiefe
    assert_equal 1000.0 - 8, teil(res, 'sl')['fertigmass']['w']
    schmal = schrank('ES-L-LEMANS', 'overrides' => { 'parameter.schenkel_t.default' => 500 })
    assert_equal 900.0 - 500 - 19, teil(schmal, 'tv1')['fertigmass']['l']
  end

  def test_corner_rules_leave_standard_cabinets_unchanged
    t1 = @gen.schrank('pos' => 'A1', 'vorlage' => 'US-T1', 'breite' => 450)
    assert_equal 13, t1.teile.find { |t| t['teil_id'] == 'sl' }['bearbeitungen'].count { |o| o['id'].start_with?('r_seite_duebel_schraube') }
  end
end
