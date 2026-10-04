# frozen_string_literal: true

# Entwicklungs-Lader: lädt den Küchenplaner direkt aus dem Repository, ohne Installation.
# Änderungen an den .rb-Dateien (nach git pull oder Bearbeiten) gelten nach Plugins > Küchenplaner (Dev) > Neu laden,
# ein Neustart von SketchUp ist nicht nötig. In der Ruby-Konsole: Kp::Dev.reload
#
# Eingerichtet wird er durch tools/setup-windows.ps1 (legt eine kleine Datei in den SketchUp-Plugins-Ordner,
# die diese Datei lädt). Nicht zusammen mit der installierten .rbz-Erweiterung verwenden (zuerst deaktivieren).
require 'sketchup'

module Kp
  module Dev
    SRC = File.expand_path('..', __dir__)

    module_function

    def dateien
      Dir[File.join(SRC, 'lib', '**', '*.rb')].sort + [File.join(SRC, 'plugin', 'kp_kuechenplaner', 'main.rb')]
    end

    # Lädt alle Quelldateien neu (load statt require). Konstanten-Warnungen werden unterdrückt.
    def reload(melden = false)
      alt = $VERBOSE
      $VERBOSE = nil
      begin
        dateien.each { |f| load f }
      ensure
        $VERBOSE = alt
      end
      text = "Küchenplaner neu geladen (#{dateien.size} Dateien) aus\n#{SRC}"
      puts "[Küchenplaner Dev] #{text}"
      UI.messagebox(text) if melden
      true
    rescue Exception => e # rubocop:disable Lint/RescueException
      msg = "Fehler beim Laden:\n#{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      puts "[Küchenplaner Dev] #{msg}"
      UI.messagebox(msg)
      false
    end

    def installierte_erweiterung?
      Sketchup.extensions.any? { |e| e.name == 'Küchenplaner' }
    rescue StandardError
      false
    end
  end
end

if Kp::Dev.installierte_erweiterung?
  puts '[Küchenplaner Dev] Achtung: die installierte Erweiterung "Küchenplaner" ist aktiv; bitte im Erweiterungsmanager deaktivieren.'
end

Kp::Dev.reload

unless file_loaded?(__FILE__)
  menu = UI.menu('Plugins').add_submenu('Küchenplaner (Dev)')
  menu.add_item('Neu laden') { Kp::Dev.reload(true) }
  menu.add_item('Selbsttest') { Kp::Plugin.selbsttest }
  menu.add_item('Quellpfad anzeigen') { UI.messagebox(Kp::Dev::SRC) }
  file_loaded(__FILE__)
end
