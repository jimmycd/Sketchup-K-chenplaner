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
      teile += einbauten(tmpl, ctx, pos, warn, teile)
      teile += fronten(tmpl, ctx, pos, warn, teile)
      regeln_anwenden(tmpl, teile, ctx, instanz, warn)
      teile.each { |t| t['wenden'] = t['bearbeitungen'].any? { |b| b['flaeche'] == 'F2' } }
      teile.each { |t| t['ocl'] = ocl_daten(t) }
      Ergebnis.new(teile: teile, warnungen: warn)
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

    def teil_ctx(ctx, l, w, d)
      ctx.merge(vars: ctx[:vars].merge('L' => l, 'W' => w, 'D' => d))
    end

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
          'lage' => { 'position' => t['position'].map { |v| Formel.auswerten(v, ctx).to_f },
                      'ausrichtung' => t['ausrichtung'] || { 'x' => '+x', 'z' => '+z' } }
        }
      end
    end

    # Einlegeböden: Länge = Innenbreite − Spiel, Tiefe = Korpustiefe − Abzug; Höhe auf das 32er-Raster der Seiten.
    def einbauten(tmpl, ctx, pos, warn, teile = [])
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
        z0 = (teile.find { |t| t['rolle'] == 'seite_r' }&.dig('kantenstaerke', 'links') || 0).to_f
        (1..n).map do |i|
          roh = s + frei * i / (n + 1.0)
          z = z0 + start + (((roh - z0 - start) / raster).round * raster)
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
            'lage' => { 'position' => [s + eb['spiel_breite'] / 2.0, eb['ruecksprung_vorne'], z],
                        'ausrichtung' => { 'x' => '+x', 'z' => '+z' } }
          }
        end
      end
    end

    # ---- Fronten (zunächst nur Türen) ---------------------------------------------
    # Aufschlagende Front: Breite = B - Fuge, Höhe verteilt nach Anteilen. Teilachsen so, dass F1 die Innenseite ist
    # und das Topfband bei hohem y sitzt (wie in den Maschinenbeispielen): DIN links x nach unten, DIN rechts x nach oben.
    def fronten(tmpl, ctx, pos, warn, teile = [])
      front = tmpl['front']
      return [] unless front && front['felder'] && front['typ'] != 'keine'

      cfg = @std['front'] || {}
      fuge = (cfg['fuge'] || 3).to_f
      felder = front['felder']
      b = ctx[:vars]['B']
      h_ges = ctx[:vars]['H'] - fuge + (cfg['ueberstand_unten'] || 0).to_f
      summe = felder.sum { |f| (f['anteil'] || 1).to_f }
      z = fuge / 2 - (cfg['ueberstand_unten'] || 0).to_f
      d = (cfg['staerke'] || 19).to_f
      felder.each_with_index.flat_map do |f, i|
        hoehe = (h_ges - fuge * (felder.size - 1)) * (f['anteil'] || 1).to_f / summe
        z0 = z
        z += hoehe + fuge
        case f['art']
        when 'tuer' then tuer(tmpl, ctx, pos, f, i + 1, b - fuge, hoehe, fuge / 2, z0, d, warn)
        when 'schublade', 'auszug' then schublade(tmpl, ctx, pos, f, i + 1, b - fuge, hoehe, fuge / 2, z0, d, warn, teile)
        else
          warn << "Frontfeld #{f['art']} noch nicht umgesetzt"
          []
        end
      end
    end

    def tuer(tmpl, ctx, pos, feld, nr, breite, hoehe, x0, z0, dicke, warn)
      cfg = @std['front']
      mat = material('P.front.material')
      kante = kante('P.front.kante')
      staerke = kante ? @std['kanten'][kante]['staerke'].to_f : 0.0
      links = feld['anschlag'] == 'links'
      tid = "tu#{nr}"
      teil = {
        'uid' => "#{@projekt['id']}/#{pos}/#{tid}", 'pos' => pos, 'teil_id' => tid, 'rolle' => 'front_tuer',
        'bezeichnung' => "#{pos} Tür #{nr} DIN #{links ? 'L' : 'R'}", 'material' => mat,
        'fertigmass' => { 'l' => hoehe.round(3), 'w' => breite.round(3), 'd' => dicke },
        'maserung' => 'laenge', 'kanten' => KANTEN.to_h { |k| [k, kante] },
        'kantenstaerke' => KANTEN.to_h { |k| [k, staerke] },
        'sichtseite' => 'F2', 'wenden' => false, 'bearbeitungen' => [],
        'herkunft' => { 'vorlage' => tmpl['code'], 'generator_version' => VERSION },
        'lage' => { 'position' => links ? [x0 + breite, -dicke, z0 + hoehe] : [x0, -dicke, z0],
                    'ausrichtung' => links ? { 'x' => '-z', 'z' => '+y' } : { 'x' => '+z', 'z' => '+y' } }
      }
      pctx = teil_ctx(ctx, hoehe, breite, dicke)
      set = @katalog.beschlagset(@std['beschlag_set'])['zuordnung']
      topfband_ops(teil, pctx, set, feld['beschlag'] || 'topfband', staerke, warn)
      griff_ops(teil, pctx, set, cfg['griff'], warn)
      [teil]
    end

    # Schublade (Blum LEGRABOX free): Front und Schubkastenboden werden gefräst, die Seiten bekommen die Schienenbohrungen.
    # Rückwand und Metallteile des Systems sind nicht Teil der CNC-Fertigung.
    def schublade(tmpl, ctx, pos, feld, nr, breite, hoehe, x0, z0, dicke, warn, teile)
      cfg = @std['schubkasten'] || {}
      mat = material('P.front.material')
      kante = kante('P.front.kante')
      staerke = kante ? @std['kanten'][kante]['staerke'].to_f : 0.0
      front = {
        'uid' => "#{@projekt['id']}/#{pos}/sk#{nr}f", 'pos' => pos, 'teil_id' => "sk#{nr}f", 'rolle' => 'front_schublade',
        'bezeichnung' => "#{pos} Schubladenfront #{nr}", 'material' => mat,
        'fertigmass' => { 'l' => breite.round(3), 'w' => hoehe.round(3), 'd' => dicke },
        'maserung' => 'laenge', 'kanten' => KANTEN.to_h { |k| [k, kante] },
        'kantenstaerke' => KANTEN.to_h { |k| [k, staerke] },
        'sichtseite' => 'F2', 'wenden' => false, 'bearbeitungen' => [],
        'herkunft' => { 'vorlage' => tmpl['code'], 'generator_version' => VERSION },
        # y nach oben (Ursprung unten), x von rechts nach links
        'lage' => { 'position' => [x0 + breite, -dicke, z0], 'ausrichtung' => { 'x' => '-x', 'z' => '+y' } }
      }
      fctx = teil_ctx(ctx, breite, hoehe, dicke)
      fctx = fctx.merge(vars: fctx[:vars].merge(kantenvariablen(front)))
      set = @katalog.beschlagset(@std['beschlag_set'])['zuordnung']
      griff_ops(front, fctx, set, @std['front']['griff'], warn, von_oben: true)
      return [front] unless cfg['material']

      hw = @katalog.beschlag('blum_legrabox_free') or (warn << 'Beschlag blum_legrabox_free fehlt' and return [front])
      params = hw['parameter'].to_h { |k, p| [k, p['default']] }
      beschlag_bohrbild(hw, 'sk_front', front, fctx, params, "sk#{nr}f")
      s = ctx[:vars]['S']
      tk = ctx['V']['tk'] || ctx[:vars]['T']
      lw = ctx['V']['innen_b'] || (ctx[:vars]['B'] - 2 * s)
      nl = cfg['nl'] || (((tk - 3) / 50).floor * 50)
      last = (cfg['last'] || 40).to_s
      klasse = nl_klasse(hw['schienenbilder'][last], nl)
      versaetze = hw['schienenbilder'][last][klasse || hw['schienenbilder'][last].keys.first]
      warn << "Schubkasten NL #{nl} bei #{last} kg nicht in der Blum-Tabelle, Bohrbild der Seite nur genähert" unless klasse
      bmat = material("P.schubkasten.material")
      boden = {
        'uid' => "#{@projekt['id']}/#{pos}/sk#{nr}b", 'pos' => pos, 'teil_id' => "sk#{nr}b", 'rolle' => 'sk_boden',
        'bezeichnung' => "#{pos} Schubkastenboden #{nr}", 'material' => bmat,
        'fertigmass' => { 'l' => (lw - (cfg['boden_breite_abzug'] || 35)).round(3), 'w' => (nl - (cfg['boden_laenge_abzug'] || 10)).round(3),
                          'd' => @std['materialien'][bmat]['staerke'].to_f },
        'maserung' => 'laenge', 'kanten' => KANTEN.to_h { |k| [k, nil] }, 'kantenstaerke' => KANTEN.to_h { |k| [k, 0.0] },
        'sichtseite' => 'F1', 'wenden' => false, 'bearbeitungen' => [],
        'herkunft' => { 'vorlage' => tmpl['code'], 'generator_version' => VERSION },
        'lage' => { 'position' => [s + 17.5, 0.0, z0 + 20.0], 'ausrichtung' => { 'x' => '+x', 'z' => '+z' } }
      }
      bctx = teil_ctx(ctx, boden['fertigmass']['l'], boden['fertigmass']['w'], boden['fertigmass']['d'])
      beschlag_bohrbild(hw, 'sk_boden', boden, bctx, params, "sk#{nr}")
      x_schiene = z0 + params['schiene_offset']
      teile.select { |t| %w[seite_l seite_r].include?(t['rolle']) }.each do |seite|
        sctx = teil_ctx(ctx, seite['fertigmass']['l'], seite['fertigmass']['w'], seite['fertigmass']['d'])
        sctx = sctx.merge(vars: sctx[:vars].merge(kantenvariablen(seite)))
        versaetze.each_with_index do |v, i|
          beschlag_bohrbild(hw, 'seite', seite, sctx, params.merge('x' => x_schiene, 'versatz' => v), "schiene#{nr}.#{i + 1}")
        end
      end
      [front, boden]
    end

    # Klasse "350", "400-500" usw. aus den Schlüsseln der Tabelle, in die die Nennlänge fällt
    def nl_klasse(tabelle, nl)
      tabelle.keys.find do |k|
        von, bis = k.split('-').map(&:to_i)
        nl.between?(von, bis || von)
      end
    end

    def beschlag_id(set, funktion, ctx)
      z = set[funktion] or return nil
      return z if z.is_a?(String)

      vctx = ctx.merge('V' => (ctx['V'] || {}).merge('oeffnungswinkel' => 110))
      z.find { |e| e['bedingung'].nil? || Formel.auswerten(e['bedingung'], vctx) }&.fetch('beschlag')
    end

    # Topfbänder: Anzahl nach Türhöhe (anzahl_tabelle), Randabstand, auf 32er-Raster einrasten, mittig verteilt.
    def topfband_ops(teil, pctx, set, funktion, band, warn)
      id = beschlag_id(set, funktion.sub('set:', ''), pctx) || funktion
      hw = @katalog.beschlag(id) or return warn << "Beschlag #{id} nicht im Katalog"
      l = teil['fertigmass']['l']
      v = hw['verteilung'] || {}
      n = (v['anzahl_tabelle'].find { |e| l <= e['bis'] } || v['anzahl_tabelle'].last)['anzahl']
      rand = Formel.auswerten(v['randabstand'] || 100, pctx)
      raster = v['raster_fangen'] ? @std['lochreihe']['raster'].to_f : nil
      abstand = (l - 2 * rand) / (n - 1)
      abstand = (abstand / raster).round * raster if raster
      erste = (l - abstand * (n - 1)) / 2.0
      params = (hw['parameter'] || {}).transform_values { |p| Formel.auswerten(p['default'], pctx) }
      (0...n).each do |i|
        # Makroparameter sind Fräsmaß-Koordinaten (TpaCAD): Anleimer am Teilanfang abziehen
        x = erste + abstand * i - teil['kantenstaerke']['links']
        beschlag_bohrbild(hw, 'front_tuer', teil, pctx, params.merge('x' => x), "topfband#{i + 1}")
      end
    end

    def griff_ops(teil, pctx, set, griff, warn, von_oben: false)
      return if griff.nil? || griff == 'grifflos'

      id = set[griff] || griff
      hw = @katalog.beschlag(id) or return warn << "Griff #{id} nicht im Katalog"
      params = (hw['parameter'] || {}).to_h { |k, p| [k, p['default']] }
      pctx = pctx.merge('V' => params.transform_values { |x| Formel.auswerten(x, pctx) })
      # Schubladenfront: Griff nahe der Oberkante (y von unten = Höhe - Kante)
      pctx['V']['kante'] = teil['fertigmass']['w'] - pctx['V']['kante'] if von_oben
      beschlag_bohrbild(hw, 'front_tuer', teil, pctx, pctx['V'], 'griff')
    end

    def beschlag_bohrbild(hw, rolle, teil, pctx, vars, kennung)
      ctx = pctx.merge('V' => vars)
      rolle = teil['rolle'] if rolle == 'seite'
      (hw['bohrbilder'] || []).select { |b| b['teil'] == rolle || (b['teil'] == 'seite' && %w[seite_l seite_r].include?(rolle)) }.each do |bb|
        bb['bearbeitungen'].each_with_index do |b, i|
          next if b['bedingung'] && !Formel.auswerten(b['bedingung'], ctx)

          op = b['typ'] == 'makro' ? makro_aufloesen(b, ctx) : aufloesen(b, ctx)
          op.delete('bedingung')
          op['flaeche'] ||= bb.dig('bezug', 'flaeche')
          op['id'] = "#{kennung}.#{i + 1}"
          op['quelle'] = { 'beschlag' => hw['id'] }
          spiegeln_y!(op, teil) if bb['y_ab'] == 'schrankfront'
          teil['bearbeitungen'] << op
        end
      end
    end

    # Makroparameter: Zahl/Formel auswerten; Text mit {Ausdruck} wird interpoliert (Zahl mit Komma, z. B. 'y-{V.tb+17.5}' -> 'y-21,5')
    def makro_aufloesen(b, ctx)
      params = b['parameter'].to_h do |k, v|
        w = if v.is_a?(String) && v.include?('{')
              v.gsub(/\{([^}]*)\}/) { zahl_komma(Formel.auswerten("=#{Regexp.last_match(1)}", ctx)) }
            else
              Formel.auswerten(v, ctx)
            end
        [k, w]
      end
      b.merge('parameter' => params)
    end

    def zahl_komma(v)
      (v == v.round ? v.round.to_s : v.to_s).tr('.', ',')
    end

    # Daten für OpenCutList: Materialname, Kantenmaterial je Seite (wird in SketchUp auf die Kantenflächen gelegt) und ein Text
    # für Etiketten mit den Kantenpositionen. OCL liest Material und Kanten aus SketchUp; Typ und Stärke der Materialien
    # werden einmalig in OCL gepflegt.
    def ocl_daten(teil)
      mat = @std['materialien'][teil['material']]
      kanten = KANTEN.to_h do |s|
        key = teil['kanten'][s]
        k = key && @std['kanten'][key]
        [s, k && (k['ocl_material'] || k['name'] || key)]
      end
      text = KANTEN.select { |s| kanten[s] }.map { |s| "#{s}: #{kanten[s]}" }.join(', ')
      {
        'material' => mat['ocl_material'] || mat['name'] || teil['material'],
        'farbe' => mat['farbe'],
        'kanten' => kanten,
        'beschreibung' => "Schrank #{teil['pos']} · #{teil['bezeichnung']} · #{teil['material']}" + (text.empty? ? ' · ohne Kanten' : " · Kanten #{text}")
      }
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
      pctx = pctx.merge(vars: pctx[:vars].merge(kantenvariablen(teil)))
      arten = (r['aussparen'] || []).flat_map { |a| a['art'] || [] }
      felder = tmpl.dig('front', 'felder') || []
      betroffen = felder.select { |f| arten.include?(f['art']) }
      # Regel entfällt, wenn alle Frontfelder ausgespart sind (wie Seiten_SK_L/R.tcn ohne Lochreihe); teilweise: Warnung
      return if !betroffen.empty? && betroffen.size == felder.size

      warn << "Regel #{r['id']}: Aussparung nur hinter einem Teil der Fronten noch nicht umgesetzt (#{teil['uid']})" unless betroffen.empty?
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

    # Kanten- und Fräsmaß-Variablen für Regeln. Regeln denken aus Sicht des Schranks (vorne = Schrankfront):
    # KV/KH Anleimer an Schrankfront/-rückseite, Y0/Y1/YM Fräsmaß-Kanten und -Mitte in Fertigmaß-Koordinaten (Abstand von vorne),
    # KL/KR Anleimer an den Teilenden, X0/X1/XM entsprechend entlang der Länge.
    def kantenvariablen(teil)
      k = teil['kantenstaerke']
      f = teil['fertigmass']
      kv, kh = y_nach_vorne?(teil['lage']['ausrichtung']) ? [k['hinten'], k['vorne']] : [k['vorne'], k['hinten']]
      y0 = kv
      y1 = f['w'] - kh
      x0 = k['links']
      x1 = f['l'] - k['rechts']
      { 'KV' => kv, 'KH' => kh, 'KL' => k['links'], 'KR' => k['rechts'],
        'Y0' => y0, 'Y1' => y1, 'YM' => (y0 + y1) / 2.0, 'X0' => x0, 'X1' => x1, 'XM' => (x0 + x1) / 2.0 }
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
      return unless y_nach_vorne?(teil['lage']['ausrichtung'])

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
