# frozen_string_literal: true

require 'json'
require 'fileutils'

module Kp
  # Anbindung an die SketchUp-API. Die Rechenlogik liegt in lib/kp (ohne SketchUp lauffähig und getestet).
  module Plugin
    # Im Paket (.rbz) liegen lib, schemas, catalog und examples neben main.rb; im Repository zwei Ebenen höher.
    BASE = begin
      hier = File.expand_path(__dir__)
      File.exist?(File.join(hier, 'lib', 'kp', 'generator.rb')) ? hier : File.expand_path('../..', hier)
    end
  end
end

require File.join(Kp::Plugin::BASE, 'lib', 'kp', 'generator')
require File.join(Kp::Plugin::BASE, 'lib', 'kp', 'tcn', 'exporter')

module Kp
  module Plugin
    VERSION = '0.2.0' unless defined?(VERSION)
    DICT = 'kp_part'
    GRUPPE = 'KP_Projekt'
    AXES = {
      '+x' => [1, 0, 0], '-x' => [-1, 0, 0], '+y' => [0, 1, 0], '-y' => [0, -1, 0], '+z' => [0, 0, 1], '-z' => [0, 0, -1]
    }.freeze

    module_function

    def mm(v)
      v.to_f.mm
    end

    def projekt_pfad
      Sketchup.active_model.get_attribute('kp_project', 'pfad')
    end

    def projekt_waehlen
      pfad = UI.openpanel('Projekt (projekt.json) wählen', '', 'JSON|*.json||')
      Sketchup.active_model.set_attribute('kp_project', 'pfad', pfad) if pfad
      pfad
    end

    def beispielprojekt_laden
      pfad = File.join(BASE, 'examples', 'projekt_mueller.json')
      Sketchup.active_model.set_attribute('kp_project', 'pfad', pfad)
      UI.messagebox("Beispielprojekt gewählt:\n#{pfad}")
      pfad
    end

    # Pfade im Projekt gelten relativ zur Projektdatei. Fehlt "kataloge", wird der mitgelieferte Katalog verwendet.
    def lade_projekt
      pfad = projekt_pfad || projekt_waehlen
      return nil unless pfad

      projekt = JSON.parse(File.read(pfad, encoding: 'utf-8'))
      basis = File.dirname(pfad)
      ordner = (projekt['kataloge'] || [File.join(BASE, 'catalog')]).map { |k| File.expand_path(k, basis) }
      [projekt, Katalog.new(ordner), basis]
    end

    def meldung(text)
      puts "[Küchenplaner] #{text}"
      UI.messagebox(text)
    end

    # Alle Schränke aller Zeilen erzeugen; eine vorhandene Gruppe KP_Projekt wird ersetzt.
    def generieren
      projekt, katalog, = lade_projekt
      return unless projekt

      model = Sketchup.active_model
      meldungen = []
      model.start_operation('Küche generieren', true)
      model.entities.grep(Sketchup::Group).select { |g| g.name == GRUPPE }.each(&:erase!)
      wurzel = model.entities.add_group
      wurzel.name = GRUPPE
      gen = Generator.new(projekt, katalog)
      (projekt['zeilen'] || []).each { |zeile| zeile_bauen(zeile, gen, wurzel, meldungen) }
      model.commit_operation
      meldung(meldungen.uniq.first(15).join("\n")) unless meldungen.empty?
    rescue StandardError => e
      model&.abort_operation
      meldung("Fehler beim Generieren:\n#{e.message}\n#{e.backtrace.first(3).join("\n")}")
    end

    def zeile_bauen(zeile, gen, wurzel, meldungen)
      gruppe = wurzel.entities.add_group
      gruppe.name = zeile['name'] || zeile['id']
      meldungen << "Zeile #{zeile['id']}: richtung_grad wird noch nicht ausgewertet" if zeile['richtung_grad'].to_f != 0
      start = zeile['start'] || [0, 0, 0]
      x = start[0].to_f
      zeile['elemente'].each do |inst|
        x += inst['abstand_links'].to_f
        res = gen.schrank(inst)
        meldungen.concat(res.warnungen.map { |w| "#{inst['pos']}: #{w}" })
        schrank = gruppe.entities.add_group
        schrank.name = "#{inst['pos']} #{inst['vorlage']}"
        res.teile.each { |teil| teil_bauen(teil, schrank.entities) }
        schrank.transformation = Geom::Transformation.new(Geom::Point3d.new(mm(x), mm(start[1]), mm(start[2])))
        rw = res.teile.find { |t| t['rolle'] == 'rueckwand' }
        x += (inst['breite'] || (rw && rw['fertigmass']['l']) || 0).to_f
      end
    end

    # Jedes Fertigungsteil bekommt eine eigene Komponentendefinition (OpenCutList behandelt jede Definition als Teil).
    def teil_bauen(teil, entities)
      model = Sketchup.active_model
      f = teil['fertigmass']
      df = model.definitions.add(teil['bezeichnung'])
      face = df.entities.add_face([0, 0, 0], [mm(f['l']), 0, 0], [mm(f['l']), mm(f['w']), 0], [0, mm(f['w']), 0])
      face.reverse! if face.normal.z < 0
      face.pushpull(mm(f['d']))
      df.set_attribute(DICT, 'data', JSON.generate(teil))
      pos = teil['lage']['position'].map { |v| mm(v) }
      x = AXES.fetch(teil['lage']['ausrichtung']['x'])
      z = AXES.fetch(teil['lage']['ausrichtung']['z'])
      y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
      tr = Geom::Transformation.axes(Geom::Point3d.new(*pos), Geom::Vector3d.new(*x), Geom::Vector3d.new(*y), Geom::Vector3d.new(*z))
      inst = entities.add_instance(df, tr)
      inst.name = teil['bezeichnung']
      inst
    end

    # Alle Teile (Definitionen mit kp_part) als TCN-Dateien schreiben.
    def tcn_exportieren(ziel = nil)
      projekt, _katalog, basis = lade_projekt
      return unless projekt

      profil_pfad = projekt.dig('standards', 'maschine', 'exporter_profil')
      return meldung('Kein Exporter-Profil im Projekt') unless profil_pfad

      profil = JSON.parse(File.read(File.expand_path(profil_pfad, basis), encoding: 'utf-8'))
      ziel ||= UI.select_directory(title: 'Ausgabeordner für TCN-Dateien')
      return unless ziel

      exporter = Tcn::Exporter.new(profil)
      fehler = []
      anzahl = 0
      Sketchup.active_model.definitions.each do |d|
        json = d.get_attribute(DICT, 'data')
        next unless json

        res = exporter.export(JSON.parse(json))
        fehler.concat(res.fehler)
        res.files.each do |datei|
          File.binwrite(File.join(ziel, datei.name), datei.content)
          anzahl += 1
        end
      end
      text = "#{anzahl} TCN-Dateien geschrieben nach\n#{ziel}"
      text += "\n\nFehler (diese Teile wurden nicht exportiert):\n#{fehler.first(15).join("\n")}" unless fehler.empty?
      meldung(text)
      { anzahl: anzahl, fehler: fehler }
    end

    # Prüft die Installation, ohne das Modell zu verändern: Dateien, Katalog, Generator, Exporter.
    def selbsttest
      zeilen = ["Küchenplaner #{VERSION}", "Basis: #{BASE}", "Ruby #{RUBY_VERSION}"]
      ok = true
      %w[lib/kp/generator.rb lib/kp/formel.rb lib/kp/tcn/exporter.rb schemas/teil.schema.json catalog/templates/US-BASIS.json
         examples/projekt_mueller.json examples/profile/werkstatt.tcnprofil.json].each do |rel|
        da = File.exist?(File.join(BASE, rel))
        ok &&= da
        zeilen << "#{da ? 'OK    ' : 'FEHLT '}#{rel}"
      end
      begin
        pfad = File.join(BASE, 'examples', 'projekt_mueller.json')
        projekt = JSON.parse(File.read(pfad, encoding: 'utf-8'))
        katalog = Katalog.new(File.expand_path('../catalog', File.dirname(pfad)))
        profil = JSON.parse(File.read(File.join(File.dirname(pfad), projekt['standards']['maschine']['exporter_profil']), encoding: 'utf-8'))
        gen = Generator.new(projekt, katalog)
        teile = 0
        dateien = 0
        fehler = []
        projekt['zeilen'].each do |z|
          z['elemente'].each do |inst|
            gen.schrank(inst).teile.each do |t|
              teile += 1
              r = Tcn::Exporter.new(profil).export(t)
              dateien += r.files.size
              fehler.concat(r.fehler)
            end
          end
        end
        zeilen << "Beispielprojekt: #{teile} Teile, #{dateien} TCN-Dateien, #{fehler.size} Fehler"
        ok &&= fehler.empty? && teile.positive?
        zeilen.concat(fehler.first(5))
      rescue StandardError => e
        ok = false
        zeilen << "FEHLER: #{e.class}: #{e.message}"
      end
      zeilen << (ok ? 'Selbsttest bestanden.' : 'Selbsttest NICHT bestanden.')
      meldung(zeilen.join("\n"))
      ok
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Plugins').add_submenu('Küchenplaner')
      menu.add_item('Projekt wählen…') { projekt_waehlen }
      menu.add_item('Beispielprojekt wählen') { beispielprojekt_laden }
      menu.add_item('Küche generieren') { generieren }
      menu.add_item('TCN exportieren…') { tcn_exportieren }
      menu.add_separator
      menu.add_item('Selbsttest') { selbsttest }
      file_loaded(__FILE__)
    end
  end
end
