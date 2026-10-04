# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('support', __dir__))
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'sketchup'

# Dev-Lader: Er wird in den Plugins-Ordner kopiert (also weit weg vom Projekt) und muss den Projektordner trotzdem finden.
class TestDevLoader < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  LOADER = File.join(ROOT, 'dev', 'kp_dev_loader.rb')

  def setup
    Sketchup.clear_defaults!
    UI.messages.clear
    UI.answers = {}
    ENV.delete('KP_SRC')
    @plugins = Dir.mktmpdir('plugins')
    @kopie = File.join(@plugins, 'kp_dev_loader.rb')
    FileUtils.cp(LOADER, @kopie)
    Kp::Dev.instance_variable_set(:@src, nil) if defined?(Kp::Dev)
  end

  def teardown
    ENV.delete('KP_SRC')
    FileUtils.remove_entry(@plugins)
  end

  def test_loader_in_plugins_folder_uses_env_variable
    ENV['KP_SRC'] = ROOT
    load @kopie
    assert_equal ROOT, Kp::Dev.src(false)
    assert Kp::Plugin.selbsttest
  end

  def test_loader_in_plugins_folder_asks_once_and_remembers
    UI.answers = { select_directory: ROOT }
    load @kopie
    assert_equal ROOT, Kp::Dev.src(false)
    assert_equal ROOT, Sketchup.read_default('Kuechenplaner', 'dev_src')
    # beim nächsten Start wird nicht mehr gefragt
    UI.answers = {}
    Kp::Dev.instance_variable_set(:@src, nil)
    load @kopie
    assert_equal ROOT, Kp::Dev.src(false)
  end

  def test_cancel_does_not_raise
    load @kopie
    refute Kp::Dev.reload
    assert_match(/Kein Projektordner/, UI.messages.last)
  end

  def test_wrong_folder_is_rejected
    UI.answers = { select_directory: @plugins }
    load @kopie
    assert_match(/nicht der Projektordner/, UI.messages.join("\n"))
    assert_nil Kp::Dev.src(false)
  end

  def test_reload_picks_up_changes
    ENV['KP_SRC'] = ROOT
    load @kopie
    datei = File.join(ROOT, 'lib', 'kp', 'formel.rb')
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
