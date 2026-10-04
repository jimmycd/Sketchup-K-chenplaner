# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tmpdir'

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
require File.join(Kp::Plugin::BASE, 'lib', 'kp', 'ocl')
require File.join(Kp::Plugin::BASE, 'lib', 'kp', 'editor', 'sitzung')

module Kp
  module Plugin
    VERSION = '0.5.0' unless defined?(VERSION)
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

      meldungen = zeichne_projekt(projekt, katalog)
      meldung(meldungen.uniq.first(15).join("\n")) unless meldungen.empty?
    rescue StandardError => e
      meldung("Fehler beim Generieren:\n#{e.message}\n#{e.backtrace.first(3).join("\n")}")
    end

    # Zeichnet das übergebene Projekt (Hash) neu und gibt die Meldungen zurück. Wird vom Editor auch bei jeder Live-Änderung genutzt.
    def zeichne_projekt(projekt, katalog, vorgang = 'Küche generieren')
      model = Sketchup.active_model
      meldungen = []
      model.start_operation(vorgang, true)
      model.entities.grep(Sketchup::Group).select { |g| g.name == GRUPPE }.each(&:erase!)
      wurzel = model.entities.add_group
      wurzel.name = GRUPPE
      gen = Generator.new(projekt, katalog)
      (projekt['zeilen'] || []).each { |zeile| zeile_bauen(zeile, gen, wurzel, meldungen) }
      model.commit_operation
      meldungen
    rescue StandardError
      model&.abort_operation
      raise
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
      ocl_setzen(df, teil['ocl']) if teil['ocl']
      pos = teil['lage']['position'].map { |v| mm(v) }
      x = AXES.fetch(teil['lage']['ausrichtung']['x'])
      z = AXES.fetch(teil['lage']['ausrichtung']['z'])
      y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
      tr = Geom::Transformation.axes(Geom::Point3d.new(*pos), Geom::Vector3d.new(*x), Geom::Vector3d.new(*y), Geom::Vector3d.new(*z))
      inst = entities.add_instance(df, tr)
      inst.name = teil['bezeichnung']
      inst.material = material_holen(teil['ocl']['material'], teil['ocl']['farbe']) if teil['ocl']
      inst
    end

    # Material mit diesem Namen holen oder anlegen (Farbe nur beim Anlegen). Typ und Stärke pflegt man einmalig in OpenCutList.
    def material_holen(name, farbe = nil)
      mats = Sketchup.active_model.materials
      vorhanden = mats[name]
      return vorhanden if vorhanden

      m = mats.add(name)
      if farbe =~ /\A#(\h{2})(\h{2})(\h{2})\z/
        m.color = Sketchup::Color.new(Regexp.last_match(1).hex, Regexp.last_match(2).hex, Regexp.last_match(3).hex)
      end
      m
    end

    NORMALEN = { 'vorne' => [0, -1, 0], 'hinten' => [0, 1, 0], 'links' => [-1, 0, 0], 'rechts' => [1, 0, 0] }.freeze

    # OpenCutList erkennt Anleimer am Material der schmalen Seitenflächen des Teils. Beschreibung: Text für Etiketten.
    def ocl_setzen(df, ocl)
      df.description = ocl['beschreibung'] if ocl['beschreibung']
      flaechen = df.entities.grep(Sketchup::Face)
      (ocl['kanten'] || {}).each do |seite, name|
        next unless name

        n = NORMALEN.fetch(seite)
        flaeche = flaechen.find do |f|
          v = f.normal
          (v.x - n[0]).abs < 1e-6 && (v.y - n[1]).abs < 1e-6 && (v.z - n[2]).abs < 1e-6
        end
        flaeche.material = material_holen(name) if flaeche
      end
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

    # Namen der Materialien (Platten und Kanten), die die erzeugten Teile verwenden
    def verwendete_materialnamen
      namen = []
      Sketchup.active_model.definitions.each do |d|
        json = d.get_attribute(DICT, 'data')
        next unless json

        ocl = JSON.parse(json)['ocl'] || {}
        namen << ocl['material']
        namen.concat((ocl['kanten'] || {}).values)
      end
      namen.compact.uniq
    end

    # Legt die verwendeten Materialien an (falls nötig) und setzt ihre OpenCutList-Eigenschaften (Typ, Stärke, Kantenhöhe, Maserung).
    # Bevorzugt über die OCL-eigene Klasse (falls vorhanden), sonst direkt in das OCL-Attributverzeichnis. Siehe catalog/ocl.json.
    def ocl_materialien_anlegen
      projekt, = lade_projekt
      return unless projekt

      namen = verwendete_materialnamen
      specs = Ocl.materialien(projekt['standards'], namen.empty? ? nil : namen)
      map = Ocl.mapping(File.join(BASE, 'catalog', 'ocl.json'))
      ergebnisse = specs.map do |spec|
        mat = material_holen(spec[:name], spec[:farbe])
        ocl_schreiben(mat, spec, map)
      end
      zeilen = ergebnisse.map do |e|
        "#{e[:name]} (#{e[:art] == :platte ? 'Platte' : 'Kante'}): #{e[:weg] == :api ? 'über OCL' : 'direkt'}" +
          (e[:fehlend].empty? ? '' : " – nicht gesetzt: #{e[:fehlend].join(', ')}")
      end
      meldung("OCL-Materialien (#{ergebnisse.size}):\n#{zeilen.join("\n")}\n\nBitte in OpenCutList unter Materialien prüfen. " \
              'Weicht die Anzeige ab: Menü OCL-Attribute anzeigen und das Ergebnis schicken.')
      ergebnisse
    end

    def ocl_klasse
      return nil unless defined?(::Ladb::OpenCutList::MaterialAttributes)

      ::Ladb::OpenCutList::MaterialAttributes
    end

    def ocl_schreiben(mat, spec, map)
      attribute = Ocl.attribute(spec, map)
      fehlend = []
      weg = :attribute
      klasse = ocl_klasse
      if klasse
        begin
          obj = klasse.new(mat)
          attribute.each do |k, v|
            setter = "#{k}="
            obj.respond_to?(setter) ? obj.public_send(setter, v) : fehlend << k
          end
          if obj.respond_to?(:write_to_attributes)
            obj.write_to_attributes
            weg = :api
          else
            fehlend = []
          end
        rescue StandardError => e
          puts "[Küchenplaner] OCL-Klasse nicht nutzbar (#{e.class}: #{e.message}), schreibe direkt"
          fehlend = []
        end
      end
      if weg == :attribute
        attribute.each { |k, v| mat.set_attribute(map['dictionary'], k, v) }
      end
      { name: spec[:name], art: spec[:art], weg: weg, fehlend: fehlend }
    end

    # Schreibt die OCL-Attribute der verwendeten Materialien (und die Methoden der OCL-Klasse) in eine Textdatei, damit man sehen
    # kann, wie OpenCutList seine Daten tatsächlich ablegt.
    def ocl_diagnose
      map = Ocl.mapping(File.join(BASE, 'catalog', 'ocl.json'))
      zeilen = ["Küchenplaner #{VERSION}", "OCL-Klasse: #{ocl_klasse ? ocl_klasse.name : 'nicht gefunden'}"]
      zeilen << "Methoden: #{ocl_klasse.instance_methods(false).sort.join(', ')}" if ocl_klasse
      Sketchup.active_model.materials.each do |mat|
        dict = mat.attribute_dictionary(map['dictionary'])
        next unless dict

        zeilen << "Material #{mat.name}:"
        dict.each_pair { |k, v| zeilen << "  #{k} = #{v.inspect}" }
      end
      zeilen << '(keine Materialien mit OCL-Attributen)' if zeilen.size <= 3 && !ocl_klasse
      pfad = File.join(Dir.tmpdir, 'kp_ocl_diagnose.txt')
      File.write(pfad, zeilen.join("\n"), encoding: 'utf-8')
      puts zeilen.join("\n")
      meldung("#{zeilen.first(12).join("\n")}\n\nVollständig in: #{pfad}")
      pfad
    end

    # Prüft die Installation, ohne das Modell zu verändern: Dateien, Katalog, Generator, Exporter.
    def selbsttest
      zeilen = ["Küchenplaner #{VERSION}", "Basis: #{BASE}", "Ruby #{RUBY_VERSION}"]
      ok = true
      %w[lib/kp/generator.rb lib/kp/formel.rb lib/kp/tcn/exporter.rb schemas/teil.schema.json catalog/templates/US-BASIS.json
         examples/projekt_mueller.json examples/profile/werkstatt.tcnprofil.json catalog/ocl.json lib/kp/editor/sitzung.rb].each do |rel|
        da = File.exist?(File.join(BASE, rel))
        ok &&= da
        zeilen << "#{da ? 'OK    ' : 'FEHLT '}#{rel}"
      end
      da = %w[index.html editor.js editor.css].all? { |f| File.exist?(File.join(EDITOR_ORDNER, f)) }
      ok &&= da
      zeilen << "#{da ? 'OK    ' : 'FEHLT '}Editor-Oberfläche (editor/)"
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

    require_relative 'editor_dialog'

    unless file_loaded?(__FILE__)
      menu = UI.menu('Plugins').add_submenu('Küchenplaner')
      menu.add_item('Projekt wählen…') { projekt_waehlen }
      menu.add_item('Beispielprojekt wählen') { beispielprojekt_laden }
      menu.add_item('Editor…') { editor_oeffnen }
      menu.add_item('Küche generieren') { generieren }
      menu.add_item('TCN exportieren…') { tcn_exportieren }
      menu.add_item('OCL-Materialien anlegen') { ocl_materialien_anlegen }
      menu.add_separator
      menu.add_item('OCL-Attribute anzeigen') { ocl_diagnose }
      menu.add_item('Selbsttest') { selbsttest }
      file_loaded(__FILE__)
    end
  end
end
