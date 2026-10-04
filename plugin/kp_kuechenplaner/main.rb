# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../../lib/kp/generator'
require_relative '../../lib/kp/tcn/exporter'

module Kp
  # Anbindung an die SketchUp-API. Die Rechenlogik liegt in lib/kp (ohne SketchUp lauffähig, getestet).
  # Dieser Teil ist ein erstes Gerüst und noch nicht in SketchUp ausprobiert.
  module Plugin
    DICT = 'kp_part'
    GRUPPE = 'KP_Projekt'
    AXES = {
      '+x' => [1, 0, 0], '-x' => [-1, 0, 0], '+y' => [0, 1, 0], '-y' => [0, -1, 0], '+z' => [0, 0, 1], '-z' => [0, 0, -1]
    }.freeze

    module_function

    def projekt_pfad
      Sketchup.active_model.get_attribute('kp_project', 'pfad')
    end

    def projekt_waehlen
      pfad = UI.openpanel('Projekt (projekt.json) wählen', '', 'JSON|*.json||')
      Sketchup.active_model.set_attribute('kp_project', 'pfad', pfad) if pfad
      pfad
    end

    def lade_projekt
      pfad = projekt_pfad || projekt_waehlen or return nil
      projekt = JSON.parse(File.read(pfad, encoding: 'utf-8'))
      basis = File.dirname(pfad)
      ordner = (projekt['kataloge'] || [File.join(ROOT, 'catalog')]).map { |k| File.expand_path(k, basis) }
      [projekt, Katalog.new(ordner), basis]
    end

    def mm(v) = v.to_f.mm

    # Alle Schränke aller Zeilen erzeugen; vorhandene Gruppe KP_Projekt wird ersetzt.
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
      UI.messagebox(meldungen.uniq.first(15).join("\n")) unless meldungen.empty?
    rescue StandardError => e
      model.abort_operation
      UI.messagebox("Fehler beim Generieren:\n#{e.message}")
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
        x += (inst['breite'] || res.teile.find { |t| t['rolle'] == 'rueckwand' }&.dig('fertigmass', 'l') || 0).to_f
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
      daten = JSON.generate(teil)
      df.set_attribute(DICT, 'data', daten)
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
    def tcn_exportieren
      projekt, _katalog, basis = lade_projekt
      return unless projekt

      profil_pfad = projekt.dig('standards', 'maschine', 'exporter_profil') or return UI.messagebox('Kein Exporter-Profil im Projekt')
      profil = JSON.parse(File.read(File.expand_path(profil_pfad, basis), encoding: 'utf-8'))
      ziel = UI.select_directory(title: 'Ausgabeordner für TCN-Dateien') or return
      exporter = Tcn::Exporter.new(profil)
      fehler = []
      anzahl = 0
      Sketchup.active_model.definitions.each do |d|
        json = d.get_attribute(DICT, 'data') or next
        res = exporter.export(JSON.parse(json))
        fehler.concat(res.fehler)
        res.files.each do |datei|
          File.binwrite(File.join(ziel, datei.name), datei.content)
          anzahl += 1
        end
      end
      text = "#{anzahl} TCN-Dateien geschrieben."
      text += "\n\nFehler (diese Teile wurden nicht exportiert):\n#{fehler.first(15).join("\n")}" unless fehler.empty?
      UI.messagebox(text)
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Plugins').add_submenu('Küchenplaner')
      menu.add_item('Projekt wählen…') { projekt_waehlen }
      menu.add_item('Küche generieren') { generieren }
      menu.add_item('TCN exportieren…') { tcn_exportieren }
      file_loaded(__FILE__)
    end
  end
end
