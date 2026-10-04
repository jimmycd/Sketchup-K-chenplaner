# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('support', __dir__))
require 'minitest/autorun'
require 'sketchup'

# Dev-Lader: Neu laden darf nichts kaputt machen und muss Änderungen übernehmen.
class TestDevLoader < Minitest::Test
  def test_reload_keeps_plugin_working
    load File.expand_path('../dev/kp_dev_loader.rb', __dir__)
    assert Kp::Dev.reload
    assert_respond_to Kp::Plugin, :generieren
    assert_respond_to Kp::Plugin, :selbsttest
    assert Kp::Plugin.selbsttest
    sub = UI.menu('Plugins').items.map { |i| i[1] }
    assert_includes sub, 'Küchenplaner (Dev)'
  end

  def test_reload_picks_up_changes
    load File.expand_path('../dev/kp_dev_loader.rb', __dir__)
    datei = File.expand_path('../lib/kp/formel.rb', __dir__)
    alt = File.read(datei, encoding: 'utf-8')
    begin
      File.write(datei, alt.sub("'round' => ->(a, n = 0) { a.round(n) }", "'round' => ->(a, n = 0) { a.round(n) + 1000 }"))
      Kp::Dev.reload
      assert_equal 1003, Kp::Formel.auswerten('=round(3)', { vars: {} })
    ensure
      File.write(datei, alt)
      Kp::Dev.reload
    end
    assert_equal 3, Kp::Formel.auswerten('=round(3)', { vars: {} })
  end
end
