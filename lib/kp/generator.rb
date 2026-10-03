# frozen_string_literal: true

require_relative 'formel'
require_relative 'katalog'
require_relative 'standards'

module Kp
  # Erzeugt aus Projekt, Katalog und einer Schrank-Instanz die Fertigungsteile (Schema 4).
  # Reines Ruby ohne SketchUp-Abhängigkeit.
  #
  # Noch nicht umgesetzt (meldet Warnungen): Verbindungsregeln (Kontakterkennung + Beschlagbohrbilder),
  # Front/Türen/Schubkästen, Vererbung per Typcode-Parser.
  class Generator
    VERSION = '0.1.0'
    Ergebnis = Struct.new(:teile, :warnungen, keyword_init: true)
    KANTEN = %w[vorne hinten links rechts].freeze

    def initialize(projekt, katalog)
      @projekt = projekt
      @katalog = katalog
      @std = Standards.mit_defaults(projekt['standards'])
    end

    def schrank(instanz)
      warn = []
      tmpl = Katalog.new([]).class.mischen(@katalog.vorlage(instanz['vorlage']), {}) # tiefe Kopie
      tmpl = override(tmpl, instanz['overrides'] || {})
      raise Katalog::Fehler, "Vorlage #{instanz['vorlage']} ist abstrakt" if tmpl['abstrakt']

      ctx = basis_kontext(tmpl, instanz)
      ctx['V'] = {}
      (tmpl['variablen'] || {}).each { |k, v| ctx['V'][k] = Formel.auswerten(v, ctx) }
      pos = instanz['pos'] || 'A1'

      teile = (tmpl['teile'] || []).flat_map { |t| teil(t, tmpl, ctx, pos) }.compact
      teile += einbauten(tmpl, ctx, pos, warn)
      regeln_anwenden(tmpl, teile, ctx, instanz, warn)
      warn << 'Front/Türen/Schubkästen werden noch nicht erzeugt (Roadmap 2)' if tmpl['front'] && tmpl['front']['felder']
      teile.each { |t| t['wenden'] = t['bearbeitungen'].any? { |b| b['flaeche'] == 'F2' } }
      Ergebnis.new(teile: teile.map { |t| t.reject { |k, _| k.start_with?('_') } }, warnungen: warn)
    end

    private

    def basis_kontext(tmpl, instanz)
      p = tmpl['parameter'] || {}
      ctx = { 'P' => @std, vars: {} }
      ctx[:vars]['S'] = @std['korpus']['staerke'].to_f
      ctx[:vars]['SR'] = @std['rueckwand']['staerke'].to_f
      { 'breite' => 'B', 'hoehe' => 'H', 'tiefe' => 'T' }.each do |param, var|
        wert = instanz[param] || (p[param] && p[param]['default']) or raise Katalog::Fehler, "Parameter #{param} fehlt"
        ctx[:vars][var] = Formel.auswerten(wert, ctx).to_f
      end
      ctx
    end

    # Overrides: Punkt-Pfad -> Wert (Zahlen im Pfad = Arrayindex)
    def override(tmpl, overrides)
      overrides.each do |pfad, wert|
        schluessel = pfad.split('.').map { |k| k =~ /\A\d+\z/ ? k.to_i : k }
        ziel = schluessel[0..-2].reduce(tmpl) { |o, k| o[k] }
        ziel[schluessel.last] = wert
      end
      tmpl
    end

    def teil_ctx(ctx, l, w, d) = ctx.merge(vars: ctx[:vars].merge('L' => l, 'W' => w, 'D' => d))

    def material(ref)
      key = ref.start_with?('P.') ? ref[2..].split('.').reduce(@std) { |o, k| o[k] } : ref
      @std['materialien'][key] or raise Katalog::Fehler, "Material #{key} unbekannt"
      key
    end

    def kante(ref)
      return nil if ref.nil?

      key = ref.start_with?('P.') ? ref[2..].split('.').reduce(@std) { |o, k| o[k] } : ref
      return nil if key.nil?

      @std['kanten'][key] or raise Katalog::Fehler, "Kante #{key} unbekannt"
      key
    end

    def teil(t, tmpl, ctx, pos)
      return [] if t['bedingung'] && !Formel.auswerten(t['bedingung'], ctx)

      anzahl = Formel.auswerten(t['anzahl'] || 1, ctx).to_i
      (1..anzahl).map do |n|
        mat = material(t['material'] || 'P.korpus.material')
        d = t['abmessungen']['dicke'] ? Formel.auswerten(t['abmessungen']['dicke'], ctx) : @std['materialien'][mat]['staerke']
        l = Formel.auswerten(t['abmessungen']['laenge'], ctx).to_f
        w = Formel.auswerten(t['abmessungen']['breite'], ctx).to_f
        kanten = KANTEN.to_h { |s| [s, kante((t['kanten'] || {})[s])] }
        tid = anzahl > 1 ? "#{t['id']}#{n}" : t['id']
        {
          'uid' => "#{@projekt['id']}/#{pos}/#{tid}", 'pos' => pos, 'teil_id' => tid, 'rolle' => t['rolle'],
          'bezeichnung' => "#{pos} #{t['name'] || t['rolle']}".strip, 'material' => mat,
          'fertigmass' => { 'l' => l.round(3), 'w' => w.round(3), 'd' => d.to_f },
          'maserung' => t['maserung'] || 'laenge', 'kanten' => kanten,
          'kantenstaerke' => KANTEN.to_h { |s| [s, kanten[s] ? @std['kanten'][kanten[s]]['staerke'].to_f : 0.0] },
          'sichtseite' => 'F1', 'wenden' => false, 'bearbeitungen' => [],
          'herkunft' => { 'vorlage' => tmpl['code'], 'generator_version' => VERSION },
          '_position' => t['position'].map { |v| Formel.auswerten(v, ctx).to_f },
          '_ausrichtung' => t['ausrichtung'] || { 'x' => '+x', 'z' => '+z' }
        }
      end
    end

    # Einlegeböden: Länge = Innenbreite − Spiel, Tiefe = Korpustiefe − Abzug; Höhe auf das 32er-Raster der Seiten.
    def einbauten(tmpl, ctx, pos, warn)
      (tmpl['einbauten'] || []).flat_map do |e|
        next warn.push("Einbau #{e['art']} noch nicht umgesetzt") && [] unless e['art'] == 'einlegeboden'

        eb = @std['einlegeboden']
        n = Formel.auswerten(e['anzahl'] || 1, ctx).to_i
        s = ctx[:vars]['S']
        tk = ctx['V']['tk'] || ctx[:vars]['T']
        innen_b = ctx['V']['innen_b'] || (ctx[:vars]['B'] - 2 * s)
        raster = @std['lochreihe']['raster']
        start = @std['lochreihe']['start']
        frei = ctx[:vars]['H'] - s - s
        (1..n).map do |i|
          roh = frei * i / (n + 1.0)
          z = s + start + (((roh - start) / raster).round * raster)
          mat = material(eb['material'] || 'P.korpus.material')
          {
            'uid' => "#{@projekt['id']}/#{pos}/eb#{i}", 'pos' => pos, 'teil_id' => "eb#{i}", 'rolle' => 'einlegeboden',
            'bezeichnung' => "#{pos} Einlegeboden #{i}", 'material' => mat,
            'fertigmass' => { 'l' => (innen_b - eb['spiel_breite']).round(3), 'w' => (tk - eb['abzug_tiefe']).round(3),
                              'd' => @std['materialien'][mat]['staerke'].to_f },
            'maserung' => 'laenge', 'kanten' => KANTEN.to_h { |k| [k, k == 'vorne' ? kante('P.korpus.kante_sichtbar') : nil] },
            'kantenstaerke' => KANTEN.to_h { |k| [k, k == 'vorne' ? @std['kanten'][kante('P.korpus.kante_sichtbar')]['staerke'].to_f : 0.0] },
            'sichtseite' => 'F1', 'wenden' => false, 'bearbeitungen' => [],
            'herkunft' => { 'vorlage' => tmpl['code'], 'generator_version' => VERSION },
            '_position' => [s + eb['spiel_breite'] / 2.0, eb['ruecksprung_vorne'], z],
            '_ausrichtung' => { 'x' => '+x', 'z' => '+z' }
          }
        end
      end
    end

    # ---- Regeln --------------------------------------------------------------

    def regeln_anwenden(tmpl, teile, ctx, instanz, warn)
      ausgeschlossen = (tmpl['regeln'] || []).select { |r| r.start_with?('-') }.map { |r| r[1..] }
      @katalog.regeln.each do |r|
        next if ausgeschlossen.include?(r['id']) || !gilt?(r, tmpl, ctx)

        if r['art'] == 'verbindung'
          warn << "Regel #{r['id']}: Verbindungen (Kontakterkennung und Beschlagbohrbilder) noch nicht umgesetzt"
        else
          teile.each { |t| teilregel(r, t, tmpl, ctx, warn) if r['rollen'].include?(t['rolle']) }
        end
      end
    end

    def gilt?(r, tmpl, ctx)
      g = r['gilt_fuer'] || {}
      return false if g['kategorien'] && !g['kategorien'].include?(tmpl['kategorie'])
      return false if g['bauweise'] && !g['bauweise'].include?(@std['bauweise'])
      return false if (g['vorlagen_ausser'] || []).include?(tmpl['code'])

      r['bedingung'].nil? || Formel.auswerten(r['bedingung'], ctx)
    end

    def teilregel(r, teil, tmpl, ctx, warn)
      pctx = teil_ctx(ctx, teil['fertigmass']['l'], teil['fertigmass']['w'], teil['fertigmass']['d'])
      if (r['aussparen'] || []).any? && (tmpl.dig('front', 'felder') || []).any? { |f| r['aussparen'].any? { |a| (a['art'] || []).include?(f['art']) } }
        warn << "Regel #{r['id']}: Aussparung hinter Schubkästen noch nicht umgesetzt (#{teil['uid']})"
      end
      r['bearbeitungen'].each_with_index do |b, i|
        next if b['bedingung'] && !Formel.auswerten(b['bedingung'], pctx)

        op = aufloesen(b, pctx)
        op.delete('bedingung')
        op['id'] = "#{r['id']}.#{i + 1}"
        op['quelle'] = { 'regel' => r['id'] }
        spiegeln_y!(op, teil)
        teil['bearbeitungen'] << op
      end
    end

    def aufloesen(wert, ctx)
      case wert
      when Hash then wert.transform_values { |v| aufloesen(v, ctx) }
      when Array then wert.map { |v| aufloesen(v, ctx) }
      else Formel.auswerten(wert, ctx)
      end
    end

    # Regeln beschreiben y als Abstand von vorne. Zeigt die Teil-y-Achse nach vorne (Seite links), wird gespiegelt.
    def spiegeln_y!(op, teil)
      return unless y_nach_vorne?(teil['_ausrichtung'])

      w = teil['fertigmass']['w']
      case op['typ']
      when 'bohrreihe'
        op['start'][1] = w - op['start'][1]
        op['richtung'] = { '+y' => '-y', '-y' => '+y' }.fetch(op['richtung'], op['richtung'])
      when 'bohrung' then op['y'] = w - op['y'] if op['y']
      end
    end

    AXES = { '+x' => [1, 0, 0], '-x' => [-1, 0, 0], '+y' => [0, 1, 0], '-y' => [0, -1, 0], '+z' => [0, 0, 1], '-z' => [0, 0, -1] }.freeze

    def y_nach_vorne?(ausrichtung)
      x = AXES.fetch(ausrichtung['x'])
      z = AXES.fetch(ausrichtung['z'])
      y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]] # y = z × x
      y == [0, -1, 0]
    end
  end
end
