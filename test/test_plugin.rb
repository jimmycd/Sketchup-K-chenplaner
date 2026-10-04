# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('support', __dir__))
require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'sketchup'
require_relative '../plugin/kp_kuechenplaner'
require_relative '../plugin/kp_kuechenplaner/main'

# Ablauf des Plugins mit einer SketchUp-Attrappe (siehe support/fake_sketchup.rb).
class TestPlugin < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  PROJEKT = File.join(ROOT, 'examples', 'projekt_mueller.json')

  def setup
    Sketchup.reset!
    UI.messages.clear
    UI.answers = { openpanel: PROJEKT }
  end

  def teile
    Sketchup.active_model.definitions.select { |d| d.get_attribute('kp_part', 'data') }
  end

  def test_extension_registered_and_menu_present
    assert_equal 'Küchenplaner', Kp::Plugin::EXT.name
    sub = UI.menu('Plugins').items.find { |i| i[0] == :submenu && i[1] == 'Küchenplaner' }
    namen = sub[2].items.select { |i| i[0] == :item }.map { |i| i[1] }
    assert_includes namen, 'Küche generieren'
    assert_includes namen, 'TCN exportieren…'
    assert_includes namen, 'Selbsttest'
  end

  def test_generate_builds_groups_and_parts
    Kp::Plugin.generieren
    model = Sketchup.active_model
    assert_equal [[:start, 'Küche generieren'], [:commit]], model.operations
    wurzel = model.entities.grep(Sketchup::Group).first
    assert_equal 'KP_Projekt', wurzel.name
    zeile = wurzel.entities.grep(Sketchup::Group).first
    schraenke = zeile.entities.grep(Sketchup::Group)
    assert_equal ['A1 US-T1', 'A2 US-S2'], schraenke.map(&:name)
    assert_equal 18, teile.size # 8 + 10 Teile
    daten = JSON.parse(teile.first.get_attribute('kp_part', 'data'))
    assert_match %r{\Akueche_mueller_2026/A1/}, daten['uid']
    # A2 steht rechts neben A1 (450 mm)
    assert_in_delta 450 / 25.4, schraenke[1].transformation.origin.x, 1e-6
  end

  def test_part_orientation_follows_axes
    Kp::Plugin.generieren
    zeile = Sketchup.active_model.entities.grep(Sketchup::Group).first.entities.grep(Sketchup::Group).first
    sl = zeile.entities.grep(Sketchup::Group).first.entities.grep(Sketchup::Instance).find { |i| i.name.include?('seite_l') }
    achsen = sl.transformation.axes
    assert_equal [[0, 0, 1], [0, -1, 0], [1, 0, 0]], achsen.map { |v| [v.x, v.y, v.z] } # x = +z, z = +x, y = z × x = -y
  end

  def test_regenerate_replaces_group
    Kp::Plugin.generieren
    Kp::Plugin.generieren
    gruppen = Sketchup.active_model.entities.grep(Sketchup::Group)
    assert_equal 1, gruppen.count { |g| !g.erased }
  end

  def test_tcn_export_writes_files
    Kp::Plugin.generieren
    Dir.mktmpdir do |dir|
      res = Kp::Plugin.tcn_exportieren(dir)
      assert_empty res[:fehler]
      assert_operator res[:anzahl], :>=, 18
      assert_equal res[:anzahl], Dir[File.join(dir, '*.tcn')].size
    end
  end

  def test_selbsttest_passes
    assert Kp::Plugin.selbsttest
    assert_match(/Selbsttest bestanden/, UI.messages.last)
  end

  def test_generation_error_is_reported_not_raised
    bad = File.join(Dir.tmpdir, "kp_bad_#{$PID}.json")
    File.write(bad, '{ kaputt')
    UI.answers = { openpanel: bad }
    Kp::Plugin.generieren
    assert_match(/Fehler beim Generieren/, UI.messages.last)
  ensure
    File.delete(bad) if bad && File.exist?(bad)
  end
end
