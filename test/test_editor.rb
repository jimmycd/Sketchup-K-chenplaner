# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/kp/editor/sitzung'
require_relative '../lib/kp/generator'

# Editor-Logik ohne SketchUp: Schema-Prüfung, Speichern mit Sicherung, Neuzeichnen, Overrides.
class TestEditor < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @tmp = Dir.mktmpdir('kp_editor')
    FileUtils.cp_r(File.join(ROOT, 'catalog'), File.join(@tmp, 'catalog'))
    FileUtils.mkdir_p(File.join(@tmp, 'projekt'))
    @projekt = File.join(@tmp, 'projekt', 'projekt.json')
    doc = JSON.parse(File.read(File.join(ROOT, 'examples', 'projekt_mueller.json')))
    File.write(@projekt, JSON.pretty_generate(doc))
    @gezeichnet = []
    @sitzung = Kp::Editor::Sitzung.new(
      basis: ROOT, projekt_pfad: @projekt,
      zeichnen: ->(p, k, ordner) { @gezeichnet << [p, k, ordner]; ['Hinweis'] },
      waehlen: -> { @projekt }
    )
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def projekt = @sitzung.behandle('init')['projekt']['doc']

  def speichern(doc, **extra)
    @sitzung.behandle('speichern', { 'art' => 'projekt', 'pfad' => @projekt, 'doc' => doc }.merge(extra))
  end

  def test_pruefer_findet_fehler_mit_pfad
    p = projekt
    p['zeilen'][0]['elemente'][0]['breite'] = 'x'
    p['zeilen'][0]['elemente'][1].delete('vorlage')
    pfade = @sitzung.behandle('pruefen', { 'art' => 'projekt', 'doc' => p })['fehler'].map { |f| f['pfad'] }
    assert_includes pfade, 'zeilen.0.elemente.0.breite'
    assert_includes pfade, 'zeilen.0.elemente.1.vorlage'
  end

  def test_alle_katalogdateien_und_beispiel_sind_gueltig
    r = @sitzung.behandle('init')
    assert_empty @sitzung.behandle('pruefen', { 'art' => 'projekt', 'doc' => r['projekt']['doc'] })['fehler']
    r['katalog']['dateien'].each do |f|
      d = @sitzung.behandle('datei_laden', { 'pfad' => f['pfad'] })
      assert_empty @sitzung.behandle('pruefen', { 'art' => d['art'], 'doc' => d['doc'] })['fehler'], f['pfad']
    end
  end

  def test_init_liefert_katalog_und_vorlagen
    r = @sitzung.behandle('init')
    codes = r['katalog']['vorlagen'].map { |v| v['code'] }
    assert_includes codes, 'US-S2'
    assert r['katalog']['vorlagen'].find { |v| v['code'] == 'US-BASIS' }['abstrakt']
    assert_includes r['schemas'].keys, 'regeldatei.schema.json'
    assert(r['katalog']['dateien'].any? { |f| f['art'] == 'regeldatei' })
  end

  def test_speichern_schreibt_einmal_sicherung_und_zeichnet
    original = File.read(@projekt)
    p = projekt
    p['zeilen'][0]['elemente'][1]['breite'] = 800
    r = speichern(p, 'zeichnen' => true)
    assert r['gespeichert']
    assert r['gezeichnet']
    assert_equal ['Hinweis'], r['warnungen']
    assert_equal 800, @gezeichnet.last[0]['zeilen'][0]['elemente'][1]['breite']
    assert_equal original, File.read("#{@projekt}.bak")
    p['zeilen'][0]['elemente'][1]['breite'] = 900
    speichern(p)
    assert_equal original, File.read("#{@projekt}.bak"), 'Sicherung bleibt das Original'
    assert_equal 900, JSON.parse(File.read(@projekt))['zeilen'][0]['elemente'][1]['breite']
  end

  def test_ungueltiges_projekt_wird_nicht_gespeichert_oder_gezeichnet
    original = File.read(@projekt)
    p = projekt
    p['id'] = 'Bad ID'
    r = speichern(p, 'zeichnen' => true)
    refute r['gespeichert']
    refute r['gezeichnet']
    assert_equal 'id', r['fehler'].first['pfad']
    assert_equal original, File.read(@projekt)
    assert_empty @gezeichnet
  end

  def test_variable_anzahl_schubladen_per_override
    p = projekt
    felder = [{ 'art' => 'schublade', 'anteil' => 1 }, { 'art' => 'schublade', 'anteil' => 2 }, { 'art' => 'schublade', 'anteil' => 3 }]
    p['zeilen'][0]['elemente'][1]['overrides'] = { 'front.felder' => felder }
    assert speichern(p, 'zeichnen' => true)['gezeichnet']
    projekt_hash, katalog, = @gezeichnet.last
    teile = Kp::Generator.new(projekt_hash, katalog).schrank(projekt_hash['zeilen'][0]['elemente'][1]).teile
    assert_equal 3, teile.count { |t| t['rolle'] == 'front_schublade' }
  end

  def test_override_listen_werden_geprueft
    p = projekt
    p['zeilen'][0]['elemente'][1]['overrides'] = { 'front.felder' => [{ 'art' => 'quatsch' }] }
    fehler = @sitzung.behandle('pruefen', { 'art' => 'projekt', 'doc' => p })['fehler']
    assert_equal ['zeilen.0.elemente.1.overrides.front.felder.0.art'], fehler.map { |f| f['pfad'] }
  end

  def test_katalogdatei_speichern_zeichnet_mit_aktuellem_projekt
    d = @sitzung.behandle('datei_laden', { 'pfad' => File.join(@tmp, 'catalog', 'templates', 'US-S2.json') })
    assert_equal 'vorlage', d['art']
    d['doc']['front']['felder'] << { 'art' => 'schublade', 'anteil' => 1, 'beschlag' => 'schubkastensystem' }
    r = @sitzung.behandle('speichern', { 'art' => d['art'], 'pfad' => d['pfad'], 'doc' => d['doc'], 'zeichnen' => true, 'projekt' => projekt })
    assert r['gezeichnet']
    assert_equal 3, JSON.parse(File.read(d['pfad']))['front']['felder'].size
    assert(File.exist?("#{d['pfad']}.bak"))
  end

  def test_neue_vorlage_anlegen_und_speichern
    n = @sitzung.behandle('neu', { 'art' => 'vorlage', 'id' => 'US-S4', 'basis' => 'US-S2' })
    assert_equal 'US-S4', n['doc']['code']
    assert n['neu']
    r = @sitzung.behandle('speichern', { 'art' => 'vorlage', 'pfad' => n['pfad'], 'doc' => n['doc'] })
    assert r['gespeichert'], r.inspect
    assert_includes r['katalog']['vorlagen'].map { |v| v['code'] }, 'US-S4'
    assert @sitzung.behandle('neu', { 'art' => 'vorlage', 'id' => 'US-S4' })['fehler_text']
    assert @sitzung.behandle('neu', { 'art' => 'vorlage', 'id' => '../x' })['fehler_text']
  end

  def test_vorlage_aufgeloest_liefert_geerbte_felder
    v = @sitzung.behandle('vorlage', { 'code' => 'US-S2' })['vorlage']
    assert_equal 2, v['front']['felder'].size
    assert v['teile'], 'Teile werden von US-BASIS geerbt'
  end

  def test_regeldatei_wird_als_liste_geprueft
    pfad = File.join(@tmp, 'catalog', 'rules', 'standard.json')
    d = @sitzung.behandle('datei_laden', { 'pfad' => pfad })
    assert_equal 'regeldatei', d['art']
    d['doc'][0].delete('id')
    assert_equal ['0.id'], @sitzung.behandle('pruefen', { 'art' => 'regeldatei', 'doc' => d['doc'] })['fehler'].map { |f| f['pfad'] }
  end

  def test_unbekannte_aktion_und_fehler_werden_gemeldet
    assert @sitzung.behandle('gibtsnicht')['fehler_text']
    assert @sitzung.behandle('datei_laden', { 'pfad' => '/gibt/es/nicht.json' })['fehler_text']
  end
end
