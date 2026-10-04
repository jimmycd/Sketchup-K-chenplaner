# frozen_string_literal: true

require 'json'

module Kp
  module Editor
    # Kleiner JSON-Schema-Prüfer (Draft 2020-12, nur die in schemas/ benutzten Schlüsselwörter), damit der Editor ohne
    # Zusatzpakete in SketchUp prüfen kann. Gibt Fehler mit Punkt-Pfad zurück (wie die Overrides: "front.felder.0.anteil").
    class SchemaPruefer
      Fehler = Struct.new(:pfad, :meldung)

      attr_reader :schemas

      # ordner: Verzeichnis mit *.schema.json
      def initialize(ordner)
        @schemas = {}
        Dir.glob(File.join(ordner, '*.schema.json')).sort.each do |f|
          doc = JSON.parse(File.read(f, encoding: 'utf-8'))
          @schemas[File.basename(f)] = doc
        end
      end

      # art: "projekt", "vorlage", ... (Dateiname ohne .schema.json)
      def pruefe(art, wert)
        wurzel = @schemas["#{art}.schema.json"] or raise ArgumentError, "Schema #{art} unbekannt"
        fehler = []
        pruefen(wurzel, wert, [], fehler, "#{art}.schema.json")
        fehler
      end

      # Wert gegen einen Schema-Verweis prüfen ("vorlage.schema.json#/$defs/frontfeld"); pfad: Pfadteile für die Fehlermeldungen
      def pruefe_ref(ref, wert, pfad)
        fehler = []
        pruefen({ '$ref' => ref }, wert, pfad, fehler, '')
        fehler
      end

      # Schema-Knoten (mit $ref aufgelöst) für den Editor
      def aufloesen(schema, datei)
        return [schema, datei] unless schema.is_a?(Hash) && schema['$ref']

        ref_datei, anker = schema['$ref'].split('#', 2)
        ziel_datei = ref_datei.empty? ? datei : ref_datei
        knoten = @schemas[ziel_datei] or raise ArgumentError, "Schema #{ziel_datei} fehlt"
        (anker || '').split('/').reject(&:empty?).each { |k| knoten = knoten[k] or raise ArgumentError, "Anker #{schema['$ref']} fehlt" }
        aufloesen(knoten, ziel_datei)
      end

      private

      def pruefen(schema, wert, pfad, fehler, datei)
        schema, datei = aufloesen(schema, datei)
        return unless schema.is_a?(Hash)

        melde = ->(text) { fehler << Fehler.new(pfad.join('.'), text) }
        typ_pruefen(schema, wert, melde)
        melde.call("Erlaubt: #{schema['enum'].join(', ')}") if schema['enum'] && !schema['enum'].include?(wert)
        melde.call("Muss #{schema['const'].inspect} sein") if schema.key?('const') && schema['const'] != wert
        text_zahl_pruefen(schema, wert, melde)
        liste_pruefen(schema, wert, pfad, fehler, datei, melde) if wert.is_a?(Array)
        objekt_pruefen(schema, wert, pfad, fehler, datei, melde) if wert.is_a?(Hash)
        kombination_pruefen(schema, wert, pfad, fehler, datei, melde)
      end

      def typ_pruefen(schema, wert, melde)
        typen = Array(schema['type'])
        return if typen.empty? || typen.any? { |t| typ?(t, wert) }

        melde.call("Falscher Typ (erwartet #{typen.join(' oder ')})")
      end

      def typ?(typ, wert)
        case typ
        when 'string' then wert.is_a?(String)
        when 'number' then wert.is_a?(Numeric)
        when 'integer' then wert.is_a?(Integer) || (wert.is_a?(Float) && wert == wert.floor)
        when 'boolean' then [true, false].include?(wert)
        when 'array' then wert.is_a?(Array)
        when 'object' then wert.is_a?(Hash)
        when 'null' then wert.nil?
        else true
        end
      end

      def text_zahl_pruefen(schema, wert, melde)
        melde.call("Entspricht nicht dem Muster #{schema['pattern']}") if wert.is_a?(String) && schema['pattern'] && wert !~ Regexp.new(schema['pattern'])
        return unless wert.is_a?(Numeric)

        melde.call("Mindestens #{schema['minimum']}") if schema['minimum'] && wert < schema['minimum']
        melde.call("Höchstens #{schema['maximum']}") if schema['maximum'] && wert > schema['maximum']
      end

      def liste_pruefen(schema, wert, pfad, fehler, datei, melde)
        melde.call("Mindestens #{schema['minItems']} Einträge") if schema['minItems'] && wert.size < schema['minItems']
        melde.call("Höchstens #{schema['maxItems']} Einträge") if schema['maxItems'] && wert.size > schema['maxItems']
        return unless schema['items']

        wert.each_with_index { |w, i| pruefen(schema['items'], w, pfad + [i.to_s], fehler, datei) }
      end

      def objekt_pruefen(schema, wert, pfad, fehler, datei, melde)
        (schema['required'] || []).each do |k|
          fehler << Fehler.new((pfad + [k]).join('.'), 'Pflichtfeld fehlt') unless wert.key?(k)
        end
        props = schema['properties'] || {}
        wert.each do |k, w|
          if schema['propertyNames']
            sub = []
            pruefen(schema['propertyNames'], k, pfad, sub, datei)
            sub.each { |f| fehler << Fehler.new((pfad + [k]).join('.'), "Name ungültig: #{f.meldung}") }
          end
          if props.key?(k)
            pruefen(props[k], w, pfad + [k], fehler, datei)
          elsif schema['additionalProperties'] == false
            melde.call("Unbekanntes Feld #{k}")
          elsif schema['additionalProperties'].is_a?(Hash)
            pruefen(schema['additionalProperties'], w, pfad + [k], fehler, datei)
          end
        end
      end

      def kombination_pruefen(schema, wert, pfad, fehler, datei, melde)
        if schema['oneOf']
          treffer = schema['oneOf'].count do |s|
            sub = []
            pruefen(s, wert, pfad, sub, datei)
            sub.empty?
          end
          melde.call('Passt zu keiner erlaubten Form') if treffer.zero?
        end
        (schema['allOf'] || []).each do |s|
          if s['if']
            sub = []
            pruefen(s['if'], wert, pfad, sub, datei)
            pruefen(s['then'], wert, pfad, fehler, datei) if sub.empty? && s['then']
          else
            pruefen(s, wert, pfad, fehler, datei)
          end
        end
      end
    end
  end
end
