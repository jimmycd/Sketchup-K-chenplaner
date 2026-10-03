# frozen_string_literal: true

require 'json'

module Kp
  module Tcn
    # Schreibt aus einem Teil (Schema 4, kp_part.data) TpaCAD-TCN-Dateien (Format 4).
    # Reines Ruby ohne SketchUp-Abhängigkeit. Spezifikation: docs/tpacad_format4_spec.pdf
    #
    # Teil-System (Konzept): x = Länge, y = Breite, z = Dicke, Ursprung links vorne unten.
    # TpaCAD-Stück: l = Länge, h = Breite, s = Dicke, gleiche Achsen und Ursprung.
    class Exporter
      Result = Struct.new(:files, :fehler, keyword_init: true)
      File = Struct.new(:name, :content, keyword_init: true)

      # Konzept-Fläche -> Kantenebene: [Achse entlang der Kante]
      EDGE_ALONG = { 'F3' => :x, 'F4' => :x, 'F5' => :y, 'F6' => :y }.freeze

      class Unsupported < StandardError; end

      def initialize(profil)
        @p = profil
        @tcn = { 'kopfzeile' => 'TPA\\ALBATROS\\EDICAD\\02.00:1224:r0w0h0s1', 'zeilenende' => 'crlf',
                 'tcn_version' => '2.6.14', 'bohrer_werkzeugtyp' => 0, 'saege_makro' => '..\\custom\\mcr\\lame.tmcr',
                 'durchbohr_zugabe' => 1 }.merge(profil['tcn'] || {})
      end

      def export(teil)
        fehler = []
        ctx = build_context(teil)
        setups = { 'A' => [], 'B' => [] } # A = Normallage, B = gewendet (F2 -> F1)
        teil['bearbeitungen'].each do |op|
          [op].each do |e|
            target = e['flaeche'] == 'F2' ? 'B' : 'A'
            begin
              setups[target].concat(emit(e, ctx, target == 'B'))
            rescue Unsupported, ArgumentError => err
              fehler << "#{teil['uid']} #{e['id'] || e['typ']}: #{err.message}"
            end
          end
        end
        return Result.new(files: [], fehler: fehler) unless fehler.empty?

        name = safe_name(teil['uid'])
        files = []
        files << render(teil, ctx, setups['A'], name) unless setups['A'].empty?
        files << render(teil, ctx, setups['B'], "#{name}_B") unless setups['B'].empty?
        Result.new(files: files, fehler: [])
      end

      private

      EDGE_BAND = { 'F3' => :vorne, 'F4' => :hinten, 'F5' => :links, 'F6' => :rechts }.freeze

      # Kopfmaße der TCN-Datei = Fräsmaß = Fertigmaß minus Anleimer (teil['kantenstaerke'] je Seite).
      # Koordinaten der Bearbeitungen sind Fertigmaß-Koordinaten und werden um links/vorne verschoben.
      def build_context(teil)
        f = teil['fertigmass']
        kb = teil['kantenstaerke'] || {}
        band = %i[vorne hinten links rechts].to_h { |k| [k, (kb[k.to_s] || 0).to_f] }
        { l: f['l'], w: f['w'], d: f['d'], band: band,
          dl: f['l'] - band[:links] - band[:rechts], dh: f['w'] - band[:vorne] - band[:hinten], ds: f['d'] }
      end

      # Koordinate entlang der Kantenfläche (Fertigmaß) -> Fräsmaß
      def edge_along(flaeche, pos, ctx)
        pos - (EDGE_ALONG.fetch(flaeche) == :x ? ctx[:band][:links] : ctx[:band][:vorne])
      end

      def edge_depth_axis(flaeche, ctx)
        EDGE_ALONG.fetch(flaeche) == :x ? ctx[:dh] : ctx[:dl]
      end

      # Tiefe ab Rohkante: Anleimer der bearbeiteten Kante zählt zur Fertigtiefe
      def edge_depth(flaeche, tiefe, ctx, id)
        eff = tiefe - ctx[:band][EDGE_BAND.fetch(flaeche)]
        raise ArgumentError, "Tiefe #{fmt(tiefe)} nicht größer als Anleimer #{fmt(ctx[:band][EDGE_BAND[flaeche]])}" if eff <= 0

        eff
      end

      def emit(op, ctx, gewendet)
        case op['typ']
        when 'bohrung' then drill(op, ctx, gewendet)
        when 'bohrreihe' then drill_row(op, ctx, gewendet)
        when 'nut' then groove(op, ctx, gewendet)
        when 'kontur' then contour(op, ctx, gewendet)
        when 'makro' then macro(op, gewendet)
        else raise Unsupported, "Bearbeitung '#{op['typ']}' noch nicht implementiert"
        end
      end

      # ---- Koordinaten --------------------------------------------------------

      def tpa_face(flaeche, gewendet)
        key = gewendet ? 'F1' : flaeche
        n = @p['flaechen'][key]
        raise Unsupported, "Fläche #{flaeche} ist an der Maschine nicht bearbeitbar" unless n

        n
      end

      def plane_xy(x, y, ctx, gewendet)
        y = ctx[:w] - y if gewendet && @p.dig('wenden', 'spiegeln') != 'x'
        x = ctx[:l] - x if gewendet && @p.dig('wenden', 'spiegeln') == 'x'
        spiegel_x = gewendet && @p.dig('wenden', 'spiegeln') == 'x'
        [x - (spiegel_x ? ctx[:band][:rechts] : ctx[:band][:links]),
         y - (gewendet && !spiegel_x ? ctx[:band][:hinten] : ctx[:band][:vorne])]
      end

      def check_inside(x, y, ctx, id)
        tol = 1e-6
        return if x.between?(-tol, ctx[:dl] + tol) && y.between?(-tol, ctx[:dh] + tol)

        raise ArgumentError, "Position (#{fmt(x)}; #{fmt(y)}) liegt außerhalb des Teils"
      end

      def check_depth(tiefe, durch, limit, id)
        return if durch

        rest = @p.dig('pruefungen', 'min_restwand') || 0
        return if tiefe <= limit - rest + 1e-6

        raise ArgumentError, "Tiefe #{fmt(tiefe)} lässt weniger als #{fmt(rest)} mm Restwand"
      end

      # ---- Bohrung ------------------------------------------------------------

      def drill(op, ctx, gewendet)
        id = op['id'] || 'bohrung'
        face = tpa_face(op['flaeche'], gewendet)
        durch = op['durch'] == true
        tiefe = op['tiefe'].to_f
        if face == 1
          check_depth(tiefe, durch, ctx[:d], id)
          x, y = plane_xy(op['x'], op['y'], ctx, gewendet)
          check_inside(x, y, ctx, id)
          z = durch ? ctx[:d] + @tcn['durchbohr_zugabe'] : tiefe
        else
          along = EDGE_ALONG.fetch(op['flaeche'])
          pos = op[along.to_s] || raise(ArgumentError, "Koordinate #{along} fehlt")
          x = edge_along(op['flaeche'], pos, ctx)
          y = op['z'] || ctx[:d] / 2.0
          depth_axis = edge_depth_axis(op['flaeche'], ctx)
          tiefe = edge_depth(op['flaeche'], tiefe, ctx, id) unless durch
          check_depth(tiefe, durch, depth_axis, id)
          z = durch ? depth_axis + @tcn['durchbohr_zugabe'] : tiefe
        end
        [w("W#81{ ::WTp #1002=#{fmt(op['d'])} #1=#{fmt(x)} #2=#{fmt(y)} #3=#{fmt(-z)} " \
           "#8015=0 #201=1 #203=1 #1001=#{@tcn['bohrer_werkzeugtyp']} }W", face)]
      end

      # ---- Bohrreihe -> Makro fittingx (W#1001) / fittingy (W#1003) --------------
      # Parameter abgeleitet aus den Beispieldateien, siehe docs/tpa_makros.md
      def drill_row(op, ctx, gewendet)
        id = op['id'] || 'bohrreihe'
        face = tpa_face(op['flaeche'], gewendet)
        durch = op['durch'] == true
        row_depth = op['tiefe'].to_f
        row_depth = edge_depth(op['flaeche'], row_depth, ctx, id) if face != 1 && !durch
        check_depth(row_depth, durch, face == 1 ? ctx[:d] : edge_depth_axis(op['flaeche'], ctx), id)
        richtung = op['richtung']
        along_x = %w[+x -x].include?(richtung)
        raise Unsupported, 'Bohrreihe auf Kantenfläche nur in Richtung x der Fläche' if face != 1 && !along_x

        ausgemittelt = op['ausgemittelt'] == true
        raise ArgumentError, 'anzahl fehlt' unless ausgemittelt || op['anzahl']
        raise ArgumentError, 'ende fehlt bei ausgemittelter Reihe' if ausgemittelt && op['ende'].nil?

        sx, sy = op['start']
        n = op['anzahl']
        if ausgemittelt
          ex = along_x ? op['ende'] : sx
          ey = along_x ? sy : op['ende']
        else
          sign = richtung.start_with?('-') ? -1 : 1
          ex = along_x ? sx + sign * (n - 1) * op['raster'] : sx
          ey = along_x ? sy : sy + sign * (n - 1) * op['raster']
        end
        if face == 1
          a = plane_xy(sx, sy, ctx, gewendet)
          b = plane_xy(ex, ey, ctx, gewendet)
          check_inside(*a, ctx, id)
          check_inside(*b, ctx, id)
          lo, hi = [a, b].map { |q| along_x ? q[0] : q[1] }.minmax
          cross = along_x ? a[1] : a[0]
        else
          lo, hi = [edge_along(op['flaeche'], sx, ctx), edge_along(op['flaeche'], ex, ctx)].minmax
          cross = sy
        end
        tiefe = durch ? (face == 1 ? ctx[:d] : edge_depth_axis(op['flaeche'], ctx)) + @tcn['durchbohr_zugabe'] : row_depth
        p = { 8510 => lo, 8511 => hi, 8512 => op['raster'], 8513 => -tiefe, 8518 => cross, 8522 => op['d'] }
        flags = "#8508=#{ausgemittelt ? 1 : 0} #8509=#{ausgemittelt && op['gerade_anzahl'] ? 1 : 0}"
        nr, datei = along_x ? [1001, 'fittingx'] : [1003, 'fittingy']
        [w("W##{nr}{ ::WT2 #8098=#{@tcn['makro_pfad'] || '..\\custom\\mcr\\'}#{datei}.tmcr #6=1 #{flags} " \
           "#8510=#{fmt(p[8510])} #8511=#{fmt(p[8511])} #8512=#{fmt(p[8512])} #8513=#{fmt(p[8513])} #8517=0 " \
           "#8518=#{fmt(p[8518])} #8520=1 #8521=1 #8522=#{fmt(p[8522])} #8525=0 }W", face)]
      end

      # ---- Makro (Maschinenmakros der Werkstatt, z. B. fittingx, inge100) -------

      # Reicht Parameter unverändert durch; Ausdrücke wie 'y-21,5' bleiben Strings (x, y, s = Flächenmaße).
      def macro(op, gewendet)
        face = tpa_face(op['flaeche'], gewendet)
        params = (op['parameter'] || {}).map { |k, v| "##{k}=#{v.is_a?(Numeric) ? fmt(v) : v}" }
        [w("W##{op['nummer']}{ ::WT2 #8098=#{@tcn['makro_pfad'] || '..\\custom\\mcr\\'}#{op['datei']}.tmcr " \
           "#{params.join(' ')} }W", face)]
      end

      # ---- Nut ----------------------------------------------------------------

      def groove(op, ctx, gewendet)
        id = op['id'] || 'nut'
        raise Unsupported, 'Nut nur auf F1 (F2 wird gewendet)' unless tpa_face(op['flaeche'], gewendet) == 1

        vx, vy = op['von']
        bx, by = op['bis']
        raise Unsupported, 'Nut nur achsparallel' unless (vx - bx).abs < 1e-9 || (vy - by).abs < 1e-9

        horizontal = (vy - by).abs < 1e-9
        # Mittellinie aus Bezug (Nutseite links/rechts in Fahrtrichtung)
        dirx = (bx - vx).zero? ? 0 : (bx - vx) <=> 0
        diry = (by - vy).zero? ? 0 : (by - vy) <=> 0
        shift = case op['bezug'] || 'mitte'
                when 'links' then op['breite'] / 2.0
                when 'rechts' then -op['breite'] / 2.0
                else 0.0
                end
        cx = vx + (-diry) * shift
        cy = vy + dirx * shift
        ex = bx + (-diry) * shift
        ey = by + dirx * shift
        a = plane_xy(cx, cy, ctx, gewendet)
        b = plane_xy(ex, ey, ctx, gewendet)
        check_depth(op['tiefe'], false, ctx[:d], id)

        saw = tool('nutsaege_x', 'nutsaege_y').find { |t| t['art'] == (horizontal ? 'nutsaege_x' : 'nutsaege_y') && t['nummer'] }
        use_saw = saw && op['ausfuehrung'] != 'fraeser' && saw_width_ok?(saw, op['breite'])
        raise Unsupported, 'Nut ausfuehrung=saege, aber keine passende Säge (nummer/d im Profil)' if op['ausfuehrung'] == 'saege' && !use_saw
        return saw_cut(saw, horizontal, a, b, op, ctx) if use_saw

        mill_groove(op, horizontal, a, b, id)
      end

      def tool(*arten)
        (@p['werkzeuge'] || []).select { |t| arten.include?(t['art']) }
      end

      def saw_width_ok?(saw, breite)
        saw['d'] && breite >= saw['d'] - 1e-6
      end

      def saw_cut(saw, horizontal, a, b, op, _ctx)
        width = op['breite'] - saw['d'] > 1e-6 ? op['breite'] : 0
        common = "#8098=#{@tcn['saege_makro']} #6=1 #8503=#{fmt(width)} #8504=subang"
        tech = "#8514=1 #8515=1 #8516=#{saw['nummer']} #8525=0 #8526=0 #8527=0"
        z = fmt(-op['tiefe'])
        if horizontal
          [w("W#1050{ ::WT2 #{common} #8509=0 #8510=#{fmt(a[0])} #8517=#{fmt(b[0])} #8511=#{fmt(a[1])} #8512=#{z} #{tech} }W")]
        else
          [w("W#1051{ ::WT2 #{common} #8509=1 #8510=#{fmt(a[0])} #8511=#{fmt(a[1])} #8518=#{fmt(b[1])} #8512=#{z} #{tech} }W")]
        end
      end

      def mill_groove(op, horizontal, a, b, id)
        mill = tool('nutfraeser', 'fraeser').find { |t| t['nummer'] && t['d'] && t['d'] <= op['breite'] + 1e-6 }
        raise Unsupported, "weder Säge noch Fräser (nummer im Profil fehlt)" unless mill

        extra = op['durchgehend'] == false ? 0 : mill['d'] / 2.0 + 1
        passes = op['breite'] - mill['d'] > 1e-6 ? [-(op['breite'] - mill['d']) / 2.0, (op['breite'] - mill['d']) / 2.0] : [0.0]
        out = []
        passes.each_with_index do |off, i|
          pa = a.dup
          pb = b.dup
          idx = horizontal ? 1 : 0
          pa[idx] += off
          pb[idx] += off
          ax = horizontal ? 0 : 1
          pa[ax] -= extra * (pb[ax] <=> a[ax]) if op['durchgehend'] != false
          pb[ax] += extra * (pb[ax] <=> a[ax]) if op['durchgehend'] != false
          pa, pb = pb, pa if i.odd?
          out << mill_setup(mill, pa[0], pa[1], op['tiefe'])
          out << w("W#2201{ ::WTl #1=#{fmt(pb[0])} #2=#{fmt(pb[1])} #3=#{fmt(-op['tiefe'])} }W")
        end
        out
      end

      def mill_setup(mill, x, y, tiefe, comp = 0)
        w("W#89{ ::WTs #8015=0 #1=#{fmt(x)} #2=#{fmt(y)} #3=#{fmt(-tiefe)} #201=1 #203=1 " \
          "#205=#{mill['nummer']} #1001=100 #40=#{comp} }W")
      end

      # ---- Kontur -------------------------------------------------------------

      def contour(op, ctx, gewendet)
        raise Unsupported, 'Kontur nur auf F1 (F2 wird gewendet)' unless tpa_face(op['flaeche'], gewendet) == 1

        mill = tool('fraeser', 'nutfraeser').find { |t| t['nummer'] }
        raise Unsupported, 'kein Fräser mit nummer im Profil' unless mill

        pts = op['pfad'].map { |q| plane_xy(q['x'], q['y'], ctx, gewendet).then { |x, y| q.merge('x' => x, 'y' => y) } }
        pts << pts.first.merge('bogen' => nil) if op['geschlossen']
        comp = { 'links' => 1, 'rechts' => 2 }.fetch(op['korrektur'] || 'keine', 0)
        out = [mill_setup(mill, pts[0]['x'], pts[0]['y'], op['tiefe'], comp)]
        pts.each_cons(2) do |p0, p1|
          if p1['bogen']
            cx, cy = arc_center(p0, p1, p1['bogen']['r'], p1['bogen']['cw'])
            out << w("W#2101{ ::WTa #1=#{fmt(p1['x'])} #2=#{fmt(p1['y'])} #3=#{fmt(-op['tiefe'])} " \
                     "#31=#{fmt(cx - p0['x'])} #32=#{fmt(cy - p0['y'])} #34=#{p1['bogen']['cw'] ? 0 : 1} }W")
          else
            out << w("W#2201{ ::WTl #1=#{fmt(p1['x'])} #2=#{fmt(p1['y'])} #3=#{fmt(-op['tiefe'])} }W")
          end
        end
        out
      end

      # Mittelpunkt eines Kreisbogens p0 -> p1 mit Radius r (cw = Uhrzeigersinn, kleiner Bogen)
      def arc_center(p0, p1, r, cw)
        dx = p1['x'] - p0['x']
        dy = p1['y'] - p0['y']
        len = Math.hypot(dx, dy)
        raise ArgumentError, 'Bogenradius kleiner als halbe Sehne' if r < len / 2.0 - 1e-9

        h = Math.sqrt([r * r - (len / 2.0)**2, 0].max)
        mx = (p0['x'] + p1['x']) / 2.0
        my = (p0['y'] + p1['y']) / 2.0
        nx = -dy / len
        ny = dx / len
        sign = cw ? -1 : 1 # Zentrum links der Sehne bei Gegenuhrzeigersinn
        [mx + sign * nx * h, my + sign * ny * h]
      end

      # ---- Ausgabe ------------------------------------------------------------

      # Arbeitsgang als [TpaCAD-Fläche, Zeile]
      def w(line, face = 1)
        [face, line]
      end

      RUMPF = [
        'EXE{', '#0=0', '#1=0', '#2=0', '#3=0', '#4=0', '}EXE',
        'OFFS{', '#0=0|0', '#1=0|0', '#2=0|0', '}OFFS',
        'VARV{', '#0=1|1', '#1=2|2', '#2=3|3', '#3=4|4', '#4=0|0', '#5=0|0', '#6=0|0', '#7=0|0', '}VARV',
        'VAR{', '}VAR', 'SPEC{', '}SPEC', 'INFO{', '}INFO',
        'OPTI{',
        ':: OPTDEF=1 OPTIMIZE=%;0 OPTMIN=0 OPT3=0 OPT0=0 OPTTOOL=0 OPT2=0 OPTX=0 OPTY=0 OPTR=0 OPT4=0 OPT6=0 OPT7=0 ' \
        'LSTCOD=0%1%2%3 LTOOLFR=0 LTOOLPN=0 OPTF1=0 OOO=0.5',
        '}OPTI', 'LINK{', '}LINK'
      ].freeze

      # Aufbau wie die Beispieldateien der Maschine (examples/tcn_referenz)
      def render(teil, ctx, workings, name)
        by_face = Hash.new { |h, k| h[k] = [] }
        workings.each { |face, line| by_face[face] << line }
        used = by_face.keys.sort.map { |f| "#{f};" }.join
        lines = [@tcn['kopfzeile'], "::SIDE=#{used}", "::UNm DL=#{fmt(ctx[:dl])} DH=#{fmt(ctx[:dh])} DS=#{fmt(ctx[:ds])}",
                 "'tcn version=#{@tcn['tcn_version']}", "'code=ansi", *RUMPF]
        [0, 1, 3, 4, 5, 6].each do |f|
          lines << "SIDE##{f}{" << "$=F ##{f}"
          lines.concat(by_face[f])
          lines << '}SIDE'
        end
        eol = @tcn['zeilenende'] == 'lf' ? "\n" : "\r\n"
        File.new(name: "#{name}.tcn", content: lines.join(eol) + eol)
      end

      def safe_name(uid)
        uid.gsub(%r{[^A-Za-z0-9_.-]}, '_')
      end

      def fmt(v)
        s = format('%.3f', v.to_f).sub(/0+\z/, '').sub(/\.\z/, '')
        s == '-0' ? '0' : s
      end
    end
  end
end
