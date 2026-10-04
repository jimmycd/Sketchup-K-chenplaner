# frozen_string_literal: true

# Entwicklungs-Lader: lädt den Küchenplaner direkt aus dem Projektordner (Git-Klon), ohne Installation.
# Änderungen an den .rb-Dateien (nach git pull oder Bearbeiten) gelten nach
# Erweiterungen > Küchenplaner (Dev) > Neu laden, ein Neustart von SketchUp ist nicht nötig.
# In der Ruby-Konsole: Kp::Dev.reload
#
# Diese Datei darf auch einfach in den SketchUp-Plugins-Ordner kopiert werden. Den Projektordner findet sie so:
#   1. Umgebungsvariable KP_SRC
#   2. gemerkter Pfad (Menü: Quellpfad ändern…)
#   3. der Ordner, in dem diese Datei liegt (wenn sie im Projekt liegt)
#   4. E:/sketchup - küchenplaner
#   5. sonst fragt sie einmalig nach dem Ordner und merkt ihn sich
# Nicht zusammen mit der installierten .rbz-Erweiterung verwenden (zuerst deaktivieren).
require 'sketchup'

module Kp
  module Dev
    HAUPTDATEI = File.join('plugin', 'kp_kuechenplaner', 'main.rb') unless const_defined?(:HAUPTDATEI)
    STANDARDPFADE = ['E:/sketchup - küchenplaner', 'E:/sketchup - kuechenplaner'].freeze unless const_defined?(:STANDARDPFADE)

    module_function

    def pruefe(ordner)
      ordner && File.exist?(File.join(ordner, HAUPTDATEI))
    end

    def kandidaten
      [ENV['KP_SRC'], Sketchup.read_default('Kuechenplaner', 'dev_src'), File.expand_path('..', __dir__), *STANDARDPFADE]
    end

    # Liefert den Projektordner oder fragt danach. nil, wenn nichts Gültiges gefunden oder gewählt wurde.
    def src(fragen = true)
      return @src if @src && pruefe(@src)

      @src = kandidaten.compact.map { |c| c.to_s.tr('\\', '/') }.find { |c| pruefe(c) }
      return @src if @src

      fragen ? quellpfad_aendern : nil
    end

    def quellpfad_aendern
      ordner = UI.select_directory(title: 'Projektordner des Küchenplaners wählen (enthält plugin\\kp_kuechenplaner)')
      return nil unless ordner

      ordner = ordner.to_s.tr('\\', '/')
      unless pruefe(ordner)
        UI.messagebox("Das ist nicht der Projektordner:\n#{ordner}\n\nEs fehlt #{HAUPTDATEI}.")
        return nil
      end
      Sketchup.write_default('Kuechenplaner', 'dev_src', ordner)
      @src = ordner
    end

    def dateien
      return [] unless @src

      Dir[File.join(@src, 'lib', '**', '*.rb')].sort + [File.join(@src, HAUPTDATEI)]
    end

    # Lädt alle Quelldateien neu (load statt require). Konstanten-Warnungen werden unterdrückt.
    def reload(melden = false)
      unless src
        UI.messagebox('Küchenplaner (Dev): Kein Projektordner gewählt. Menü: Erweiterungen > Küchenplaner (Dev) > Quellpfad ändern…')
        return false
      end
      alt = $VERBOSE
      $VERBOSE = nil
      begin
        dateien.each { |f| load f }
      ensure
        $VERBOSE = alt
      end
      text = "Küchenplaner neu geladen (#{dateien.size} Dateien) aus\n#{@src}"
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

unless file_loaded?(__FILE__)
  menu = UI.menu('Plugins').add_submenu('Küchenplaner (Dev)')
  menu.add_item('Neu laden') { Kp::Dev.reload(true) }
  menu.add_item('Selbsttest') { Kp::Plugin.selbsttest }
  menu.add_item('Quellpfad ändern…') do
    Kp::Dev.quellpfad_aendern
    Kp::Dev.reload(true)
  end
  menu.add_item('Quellpfad anzeigen') { UI.messagebox(Kp::Dev.src(false).to_s) }
  file_loaded(__FILE__)
end

Kp::Dev.reload
