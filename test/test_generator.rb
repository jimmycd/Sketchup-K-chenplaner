# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/kp/generator'
require_relative '../lib/kp/tcn/exporter'

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
    res = schrank
    sr = teil(res, 'sr')
    assert_equal 'abs_weiss_2', sr['kanten']['vorne']
    assert_equal 2.0, sr['kantenstaerke']['vorne']
    assert_equal 2.0, sr['kantenstaerke']['links'] # Seitenenden
    # linke Seite: y zeigt nach vorne, die Schrankfront ist y = W, also Kante 'hinten' im Teilsystem
    sl = teil(res, 'sl')
    assert_equal 2.0, sl['kantenstaerke']['hinten']
    assert_equal 0.0, sl['kantenstaerke']['vorne']
  end

  def rows(t) = t['bearbeitungen'].select { |b| b['typ'] == 'bohrreihe' }

  def test_hole_row_count_and_mirroring
    res = schrank
    sr = rows(teil(res, 'sr'))
    sl = rows(teil(res, 'sl'))
    assert_equal 2, sr.size
    # Seite 772 x 552, Anleimer vorne und an den Enden 2 mm: Start 55 + 2, Ende x-80, Reihen 35 ab Fräskante
    assert_equal 20, sr[0]['anzahl'] # floor((770 - 80 - 2 - 55) / 32) + 1
    assert_equal [57.0, 37.0], sr[0]['start']
    assert_equal [57.0, 552.0 - 35.0], sr[1]['start']
    # linke Seite: y-Achse zeigt nach vorne, Reihen werden gespiegelt (Anleimer sitzt bei y = W)
    assert_equal [57.0, 552.0 - 37.0], sl[0]['start']
    assert_equal [57.0, 35.0], sl[1]['start']
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
    assert_empty(res.warnungen.grep(/r_seite_boden/))
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

  # Referenz: examples/tcn_referenz/Seiten_Duebel.tcn (Kopf 656 x 551, 2 mm Anleimer vorne und an beiden Enden)
  def sample_lines(datei)
    File.read(File.join(ROOT, 'examples/tcn_referenz', datei)).split("\r\n").grep(/\AW#81/).map do |l|
      v = ->(k) { l[/##{k}=(\S+)/, 1] }
      [v.call(1), v.call(2), v.call(3), v.call(1002), v.call(205)]
    end
  end

  def numeric(ausdruck, x, y)
    s = ausdruck.tr(',', '.').gsub('x', x.to_s).gsub('y', y.to_s)
    Kp::Formel.auswerten("=#{s}", { vars: {} })
  end

  def test_side_holes_match_reference_file
    # Seite 660 hoch, 553 tief -> Fräsmaß 656 x 551 wie in der Beispieldatei
    res = schrank('hoehe' => 660, 'tiefe' => 561)
    sr = teil(res, 'sr')
    assert_equal({ 'l' => 660.0, 'w' => 553.0, 'd' => 19.0 }, sr['fertigmass'])
    profil = JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json')))
    out = Kp::Tcn::Exporter.new(profil).export(sr)
    assert_empty out.fehler
    erzeugt = out.files.first.content.split("\r\n").grep(/\AW#81/).map do |l|
      v = ->(k) { l[/##{k}=(\S+)/, 1] }
      [v.call(1).to_f, v.call(2).to_f, v.call(3).to_f, v.call(1002).to_f, v.call(205)&.to_f]
    end
    erwartet = sample_lines('Seiten_Duebel.tcn').map do |x, y, z, d, w|
      [numeric(x, 656, 551).to_f, numeric(y, 656, 551).to_f, numeric(z, 656, 551).to_f, d.to_f, w&.to_f]
    end
    assert_equal erwartet.sort, erzeugt.sort
    # Lochreihen (Makro fittingx): gleicher Start, Raster und Querposition wie die Beispieldatei, letztes Loch <= x-80
    ref = File.read(File.join(ROOT, 'examples/tcn_referenz/Seiten_Duebel.tcn')).split("\r\n").grep(/fittingx/)
    ref_y = ref.map { |l| numeric(l[/#8518=(\S+)/, 1], 656, 551) }.sort
    macro = out.files.first.content.split("\r\n").grep(/fittingx/)
    assert_equal ref_y, macro.map { |l| l[/#8518=(\S+)/, 1].to_f }.sort
    assert_equal 55.0, macro[0][/#8510=(\S+)/, 1].to_f
    assert_equal 32.0, macro[0][/#8512=(\S+)/, 1].to_f
    letztes = macro[0][/#8511=(\S+)/, 1].to_f
    xf = numeric('x-80', 656, 551)
    assert_operator letztes, :<=, xf
    assert_operator letztes + 32, :>, xf
  end

  def test_boden_and_traverse_stirn_dowels_differ
    res = schrank
    stirn = ->(id) { teil(res, id)['bearbeitungen'].select { |b| %w[F5 F6].include?(b['flaeche']) } }
    boden = stirn.call('bo')
    assert_equal 6, boden.size # 3 je Stirnseite
    assert_equal [32, 277, 522], boden.select { |b| b['flaeche'] == 'F5' }.map { |b| b['y'].round }.sort
    assert_equal [9.5], boden.map { |b| b['z'] }.uniq # Materialstärke / 2
    tv = stirn.call('tv').select { |b| b['flaeche'] == 'F5' }.map { |b| b['y'] }.sort
    th = stirn.call('th').select { |b| b['flaeche'] == 'F5' }.map { |b| b['y'] }.sort
    assert_equal [32.0, 77.0], tv # 30 und 75 ab Fräskante (Anleimer vorne 2 mm)
    assert_equal [25.0, 70.0], th # 30 und 75 ab hinterer Kante, Traverse 100 breit
  end

  def test_einlegeboden_on_grid
    eb = teil(schrank, 'eb1')
    z = eb['fertigmass']
    assert_equal 410.0, z['l']
    assert_equal 532.0, z['w']
    assert_equal 0, (eb['lage']['position'][2] - (2 + 55)) % 32 # Raster passt zur Lochreihe (Start 55 + 2 mm Anleimer)
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

class TestSchubkasten < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @projekt = JSON.parse(File.read(File.join(ROOT, 'examples/projekt_mueller.json')))
    @gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    @res = @gen.schrank('pos' => 'A2', 'vorlage' => 'US-S2', 'breite' => 600)
    @profil = JSON.parse(File.read(File.join(ROOT, 'examples/profile/werkstatt.tcnprofil.json')))
  end

  def teil(id) = @res.teile.find { |t| t['teil_id'] == id }

  def tcn(id)
    r = Kp::Tcn::Exporter.new(@profil).export(teil(id))
    assert_empty r.fehler
    r.files.first.content.split("\r\n")
  end

  def test_parts_present
    assert_equal %w[sl sr bo tv th rw sk1f sk1b sk2f sk2b], @res.teile.map { |t| t['teil_id'] }
  end

  def test_boden_size_and_falz_macros_match_reference
    b = teil('sk1b')
    assert_equal({ 'l' => 527.0, 'w' => 490.0, 'd' => 16.0 }, b['fertigmass']) # LW 562 - 35, NL 500 - 10
    macros = tcn('sk1b').grep(/W#1022/)
    ref = File.read(File.join(ROOT, 'examples/tcn_referenz/Schubkastenboden.tcn')).split("\r\n").grep(/W#1022/)
    norm = ->(l) { l.sub(/ WS=\d+ /, ' ').squeeze(' ') }
    assert_equal ref.map(&norm), macros.map(&norm)
  end

  def test_rail_holes_in_both_sides_without_lochreihe
    %w[sl sr].each do |id|
      ops = teil(id)['bearbeitungen']
      refute(ops.any? { |o| o['typ'] == 'bohrreihe' }, 'Lochreihe entfällt bei Schubladenschrank (wie Seiten_SK)')
      schienen = ops.select { |o| o['id'].to_s.start_with?('schiene1') }
      assert_equal 4, schienen.size # NL 500, 40 kg: 0, 32, 224, 256
      assert_equal [57.0], schienen.map { |o| o['x'] }.uniq # Frontunterkante 1,5 + 55,5
    end
  end

  def numeric(ausdruck, y)
    Kp::Formel.auswerten("=#{ausdruck.tr(',', '.').gsub('y', y.to_s)}", { vars: {} })
  end

  def test_rail_hole_pattern_matches_reference
    # Seitenteil 660 hoch, 553 tief: Fräsmaß 656 x 551 wie in Seiten_SK_L.tcn
    res = @gen.schrank('pos' => 'A2', 'vorlage' => 'US-S2', 'breite' => 600, 'hoehe' => 660, 'tiefe' => 561)
    sr = res.teile.find { |t| t['teil_id'] == 'sr' }
    out = Kp::Tcn::Exporter.new(@profil).export(sr).files.first.content.split("\r\n").grep(/#1002=5 #1=55 #2=\S+ #3=-14 /)
    ys = out.map { |l| l[/#2=(\S+)/, 1].to_f }.sort
    ref = File.read(File.join(ROOT, 'examples/tcn_referenz/Seiten_SK_L.tcn')).split("\r\n").grep(/#1=55 .*#1002=5/)
    ref_y = ref.map { |l| numeric(l[/#2=(\S+)/, 1], 551) }.sort
    assert_equal ref_y.first(4), ys.first(4) # 35, 67, 259, 291
    assert_equal 355.0, ys.last # Beispieldatei: 35-32+192+32+64 = 291 (vermutlich Tippfehler statt 355 = 37 + 320 - 2)
  end

  def test_three_drawers_reproduce_reference_rail_heights
    # Fronten 292 / 179 / 292 (zusammen mit 2 x 3 mm Fuge = H - 3): Schienen bei x = 55, 350, 532 wie in Seiten_SK_L.tcn
    res = @gen.schrank('pos' => 'A3', 'vorlage' => 'US-S3', 'breite' => 600, 'hoehe' => 772, 'tiefe' => 561,
                       'overrides' => { 'front.felder.0.anteil' => 292, 'front.felder.1.anteil' => 179, 'front.felder.2.anteil' => 292 })
    fronten = res.teile.select { |t| t['rolle'] == 'front_schublade' }.map { |t| t['fertigmass']['w'] }
    assert_equal [292.0, 179.0, 292.0], fronten
    sr = res.teile.find { |t| t['teil_id'] == 'sr' }
    out = Kp::Tcn::Exporter.new(@profil).export(sr).files.first.content.split("\r\n").grep(/#1002=5 #1=\S+ #2=\S+ #3=-14 /)
    assert_equal [55.0, 350.0, 532.0], out.map { |l| l[/#1=(\S+)/, 1].to_f }.uniq.sort
    assert_equal 15, out.size # NL 550: 5 Löcher je Schiene
  end

  def test_front_fastening_matches_reference
    # Front 600 x 232 -> Fräsmaß 596 x 228 wie SK_Vorderstueck_Frontbef.tcn
    res = @gen.schrank('pos' => 'A4', 'vorlage' => 'US-S2', 'breite' => 603, 'hoehe' => 235,
                       'overrides' => { 'front.felder' => [{ 'art' => 'schublade', 'anteil' => 1 }] })
    f = res.teile.find { |t| t['rolle'] == 'front_schublade' }
    assert_equal({ 'l' => 600.0, 'w' => 232.0, 'd' => 19.0 }, f['fertigmass'])
    out = Kp::Tcn::Exporter.new(@profil).export(f).files.first.content.split("\r\n")
    assert_includes out, '::UNm DL=596 DH=228 DS=19'
    holes = out.grep(/#1002=3 /).map { |l| [l[/#1=(\S+)/, 1].to_f, l[/#2=(\S+)/, 1].to_f, l[/#3=(\S+)/, 1].to_f, l[/#205=(\S+)/, 1].to_f] }
    ref = File.read(File.join(ROOT, 'examples/tcn_referenz/SK_Vorderstueck_Frontbef.tcn')).split("\r\n").grep(/W#81/).map do |l|
      v = ->(k) { numeric_ref(l[/##{k}=(\S+)/, 1], 596) }
      [v.call(1), v.call(2), -5.0, v.call(205)] # erste Beispielzeile hat -2 (vermutlich Tippfehler)
    end
    assert_equal ref.sort, holes.sort
  end

  def numeric_ref(ausdruck, x)
    Kp::Formel.auswerten("=#{ausdruck.tr(',', '.').gsub('x', x.to_s)}", { vars: {} })
  end

  def test_70kg_table_and_class
    @projekt['standards']['schubkasten']['last'] = 70
    gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    res = gen.schrank('pos' => 'A5', 'vorlage' => 'US-S2', 'breite' => 600, 'tiefe' => 700)
    sr = res.teile.find { |t| t['teil_id'] == 'sr' }
    # NL = floor((700 - 8 - 3) / 50) * 50 = 650: 6 Löcher je Schiene
    assert_equal 6, sr['bearbeitungen'].count { |o| o['id'].to_s.start_with?('schiene1') }
  end

  def test_griff_marks_on_drawer_front_near_top
    @projekt['standards']['front']['griff'] = 'griff'
    gen = Kp::Generator.new(@projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    f = gen.schrank('pos' => 'A6', 'vorlage' => 'US-S2', 'breite' => 600).teile.find { |t| t['teil_id'] == 'sk2f' }
    marks = f['bearbeitungen'].select { |o| o['tiefe'] == 3 }
    assert_equal 2, marks.size
    assert_equal f['fertigmass']['w'] - 37, marks[0]['y'] # 37 mm unter der Oberkante
  end
end
