# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'schema_pruefer'
require_relative '../katalog'

module Kp
  module Editor
    # Logik hinter dem Editor-Dialog (ohne SketchUp, getestet): Dateien lesen/prüfen/schreiben und bei Bedarf die Küche neu zeichnen.
    # Der Dialog schickt Aktionen mit Nutzlast (Hash), die Sitzung antwortet mit einem Hash.
    class Sitzung
      # Art -> Unterordner im Katalog; Schema-Name = Art (Regeldateien enthalten Listen: Schema "regeldatei")
      ORDNER = { 'vorlage' => 'templates', 'beschlag' => 'hardware', 'beschlagset' => 'hardware_sets', 'regeldatei' => 'rules' }.freeze

      attr_reader :projekt_pfad

      # basis: Paketordner (enthält schemas/ und catalog/)
      # zeichnen: ->(projekt_hash, katalog, basisordner) { [warnungen] } oder nil
      # waehlen: -> { pfad oder nil } (Dateidialog für das Projekt)
      def initialize(basis:, projekt_pfad: nil, zeichnen: nil, waehlen: nil)
        @basis = basis
        @projekt_pfad = projekt_pfad
        @zeichnen = zeichnen
        @waehlen = waehlen
        @pruefer = SchemaPruefer.new(File.join(basis, 'schemas'))
        @pruefer.schemas['regeldatei.schema.json'] = {
          'title' => 'Regeldatei', 'type' => 'array', 'items' => { '$ref' => 'regel.schema.json' }
        }
        @gesichert = {}
      end

      def behandle(aktion, nutzlast = {})
        nutzlast ||= {}
        case aktion
        when 'init' then init
        when 'datei_laden' then datei_laden(nutzlast['pfad'])
        when 'pruefen' then { 'fehler' => fehler_liste(nutzlast['art'], nutzlast['doc']) }
        when 'speichern' then speichern(nutzlast)
        when 'vorlage' then vorlage(nutzlast['code'], nutzlast['projekt'])
        when 'neu' then neu(nutzlast)
        when 'projekt_waehlen' then projekt_waehlen
        else { 'fehler_text' => "Unbekannte Aktion #{aktion}" }
        end
      rescue StandardError => e
        { 'fehler_text' => "#{e.class}: #{e.message}" }
      end

      def katalogordner(projekt = nil)
        if @projekt_pfad
          projekt ||= lese(@projekt_pfad)
          (projekt['kataloge'] || [File.join(@basis, 'catalog')]).map { |k| File.expand_path(k, File.dirname(@projekt_pfad)) }
        else
          [File.join(@basis, 'catalog')]
        end
      end

      private

      def init
        antwort = { 'schemas' => @pruefer.schemas, 'katalog' => katalog_info, 'projekt' => nil }
        if @projekt_pfad && File.exist?(@projekt_pfad)
          doc = lese(@projekt_pfad)
          antwort['projekt'] = { 'pfad' => @projekt_pfad, 'art' => 'projekt', 'doc' => doc }
          antwort['katalog'] = katalog_info(doc)
        end
        antwort
      end

      def katalog_info(projekt = nil)
        ordner = katalogordner(projekt)
        dateien = ordner.flat_map { |o| dateien_in(o) }
        vorlagen = Katalog.new(ordner).vorlagen.map do |v|
          { 'code' => v['code'], 'name' => v['name'], 'abstrakt' => v['abstrakt'] || false, 'kategorie' => v['kategorie'] }
        end
        { 'ordner' => ordner, 'dateien' => dateien, 'vorlagen' => vorlagen.sort_by { |v| v['code'] } }
      end

      def dateien_in(ordner)
        ORDNER.flat_map do |art, unter|
          Dir.glob(File.join(ordner, unter, '*.json')).sort.map do |pfad|
            { 'art' => art, 'pfad' => pfad, 'titel' => File.basename(pfad, '.json') }
          end
        end
      end

      def datei_laden(pfad)
        { 'pfad' => pfad, 'art' => art_von(pfad), 'doc' => lese(pfad) }
      end

      def art_von(pfad)
        return 'projekt' if pfad == @projekt_pfad

        ORDNER.each { |art, unter| return art if File.basename(File.dirname(pfad)) == unter }
        'projekt'
      end

      # Listen, die ein Element per Override ersetzt, prüft das Projekt-Schema nicht; hier gegen die Schemata der Vorlage prüfen
      OVERRIDE_LISTEN = { 'front.felder' => 'vorlage.schema.json#/$defs/frontfeld', 'einbauten' => 'vorlage.schema.json#/$defs/einbau' }.freeze

      def fehler_liste(art, doc)
        fehler = @pruefer.pruefe(art, doc)
        fehler += override_fehler(doc) if art == 'projekt' && doc.is_a?(Hash)
        fehler.map { |f| { 'pfad' => f.pfad, 'meldung' => f.meldung } }
      end

      def override_fehler(projekt)
        (projekt['zeilen'] || []).each_with_index.flat_map do |z, zi|
          (z['elemente'] || []).each_with_index.flat_map do |e, ei|
            OVERRIDE_LISTEN.flat_map do |pfad, ref|
              liste = (e['overrides'] || {})[pfad]
              basis = ['zeilen', zi.to_s, 'elemente', ei.to_s, 'overrides'] + pfad.split('.')
              next [] if liste.nil?
              next [SchemaPruefer::Fehler.new(basis.join('.'), 'Muss eine Liste sein')] unless liste.is_a?(Array)

              liste.each_with_index.flat_map { |w, i| @pruefer.pruefe_ref(ref, w, basis + [i.to_s]) }
            end
          end
        end
      end

      def speichern(np)
        art = np['art']
        fehler = fehler_liste(art, np['doc'])
        return { 'gespeichert' => false, 'fehler' => fehler, 'gezeichnet' => false } unless fehler.empty?

        schreibe(np['pfad'], np['doc'])
        @projekt_pfad = np['pfad'] if art == 'projekt'
        antwort = { 'gespeichert' => true, 'fehler' => [], 'gezeichnet' => false, 'warnungen' => [] }
        antwort.merge!(zeichnen(art, np)) if np['zeichnen'] && @zeichnen
        antwort['katalog'] = katalog_info(art == 'projekt' ? np['doc'] : np['projekt'])
        antwort
      end

      # Projekt (aus dem Dialog, sonst von der Platte) mit dem Katalog neu zeichnen. Ungültige Projekte werden nicht gezeichnet.
      def zeichnen(art, np)
        projekt = art == 'projekt' ? np['doc'] : (np['projekt'] || (@projekt_pfad && lese(@projekt_pfad)))
        return { 'gezeichnet' => false, 'hinweis' => 'Kein Projekt zum Zeichnen' } unless projekt
        return { 'gezeichnet' => false, 'hinweis' => 'Projekt ist ungültig, nicht gezeichnet' } unless fehler_liste('projekt', projekt).empty?

        katalog = Katalog.new(katalogordner(projekt))
        warnungen = @zeichnen.call(projekt, katalog, @projekt_pfad ? File.dirname(@projekt_pfad) : @basis) || []
        { 'gezeichnet' => true, 'warnungen' => warnungen }
      end

      # Mit der Vorlage vererbte Werte, damit man im Projekt sieht, was überschrieben wird (z. B. front.felder)
      def vorlage(code, projekt)
        { 'vorlage' => Katalog.new(katalogordner(projekt)).vorlage(code) }
      end

      def neu(np)
        art = np['art']
        id = np['id'].to_s.strip
        return { 'fehler_text' => 'Bitte eine Kennung angeben' } if id.empty? || id =~ %r{[/\\]}

        pfad = File.join(np['ordner'] || katalogordner.first, ORDNER.fetch(art), "#{id}.json")
        return { 'fehler_text' => "#{pfad} existiert schon" } if File.exist?(pfad)

        doc = case art
              when 'vorlage' then { 'code' => id, 'name' => id, 'basis' => (np['basis'] unless np['basis'].to_s.empty?), 'kategorie' => kategorie_von(np['basis']) }.compact
              when 'beschlag' then { 'id' => id, 'name' => id }
              when 'beschlagset' then { 'id' => id, 'name' => id, 'zuordnung' => {} }
              else []
              end
        { 'pfad' => pfad, 'art' => art, 'doc' => doc, 'neu' => true }
      end

      def kategorie_von(basis)
        v = basis && !basis.empty? && Katalog.new(katalogordner).vorlagen.find { |x| x['code'] == basis }
        (v && v['kategorie']) || 'unterschrank'
      end

      def projekt_waehlen
        pfad = @waehlen&.call
        return { 'abgebrochen' => true } unless pfad

        @projekt_pfad = pfad
        init
      end

      def lese(pfad)
        JSON.parse(File.read(pfad, encoding: 'utf-8'))
      end

      # Vor dem ersten Überschreiben in dieser Sitzung eine .bak-Kopie des Originals anlegen
      def schreibe(pfad, doc)
        FileUtils.mkdir_p(File.dirname(pfad))
        if File.exist?(pfad) && !@gesichert[pfad]
          FileUtils.cp(pfad, "#{pfad}.bak")
          @gesichert[pfad] = true
        end
        File.write(pfad, "#{JSON.pretty_generate(doc)}\n", encoding: 'utf-8')
      end
    end
  end
end
