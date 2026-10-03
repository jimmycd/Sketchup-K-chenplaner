# frozen_string_literal: true

module Kp
  # Auswerter für Formeln wie "=B-2*S", "=floor((L-2*S)/P.lochreihe.raster)+1" und
  # Bedingungen wie "=P.rueckwand.art=='aufgesetzt' and B>=600".
  #
  # Variablen: B H T S SR L W D (Zahlen aus dem Kontext), P.<pfad> (Projektstandards), V.<name> (Vorlagenvariablen).
  # Operatoren: + - * / ( ) < > <= >= == != and or not; Funktionen: min max round floor ceil.
  class Formel
    class Fehler < StandardError; end

    TOKEN = /\s*(?:(\d+(?:\.\d+)?)|('[^']*')|([A-Za-z_][A-Za-z0-9_.]*)|(>=|<=|==|!=|[-+*\/()<>,]))/
    FUNKTIONEN = {
      'min' => ->(*a) { a.min }, 'max' => ->(*a) { a.max },
      'round' => ->(a, n = 0) { a.round(n) }, 'floor' => ->(a) { a.floor }, 'ceil' => ->(a) { a.ceil }
    }.freeze

    # kontext: { vars: {'B'=>600,...}, 'P' => {...}, 'V' => {...} }
    def self.auswerten(wert, kontext)
      return wert unless wert.is_a?(String) && wert.start_with?('=')

      new(wert[1..], kontext).auswerten
    end

    def initialize(text, kontext)
      @ctx = kontext
      @t = tokenize(text)
      @i = 0
    end

    def auswerten
      v = oder
      raise Fehler, "Unerwartetes Zeichen '#{@t[@i]}'" if @i < @t.size

      v
    end

    private

    def tokenize(text)
      pos = 0
      out = []
      while pos < text.size
        m = TOKEN.match(text, pos)
        raise Fehler, "Ungültig bei '#{text[pos..]}' in '#{text}'" unless m && m.begin(0) == pos

        out << (m[1] ? m[1].to_f : m[2] ? [:str, m[2][1..-2]] : m[3] || m[4])
        pos = m.end(0)
        pos += 1 while text[pos] == ' '
      end
      out
    end

    def peek = @t[@i]
    def nimm = @t[(@i += 1) - 1]

    def oder
      v = und
      v = (v || und) while peek == 'or' && nimm
      v
    end

    def und
      v = nicht
      while peek == 'and'
        nimm
        r = nicht
        v = v && r
      end
      v
    end

    def nicht
      return !(nimm && nicht) if peek == 'not'

      vergleich
    end

    def vergleich
      l = summe
      while %w[< > <= >= == !=].include?(peek)
        op = nimm
        r = summe
        l = case op
            when '==' then gleich(l, r)
            when '!=' then !gleich(l, r)
            else l.public_send(op, r)
            end
      end
      l
    end

    def gleich(a, b)
      a.is_a?(Numeric) && b.is_a?(Numeric) ? (a - b).abs < 1e-9 : a == b
    end

    def summe
      v = produkt
      while %w[+ -].include?(peek)
        op = nimm
        r = produkt
        v = v.public_send(op, r)
      end
      v
    end

    def produkt
      v = einstellig
      while %w[* /].include?(peek)
        op = nimm
        r = einstellig
        raise Fehler, 'Division durch 0' if op == '/' && r.zero?

        v = v.public_send(op, r)
      end
      v
    end

    def einstellig
      if peek == '-'
        nimm
        return -einstellig
      end
      grund
    end

    def grund
      t = nimm
      case t
      when Float then t
      when Array then t[1]
      when '('
        v = oder
        raise Fehler, "')' fehlt" unless nimm == ')'

        v
      when String then bezeichner(t)
      else raise Fehler, 'Ausdruck unvollständig'
      end
    end

    def bezeichner(name)
      return funktion(name) if peek == '('
      return true if name == 'true'
      return false if name == 'false'

      wert_von(name)
    end

    def funktion(name)
      f = FUNKTIONEN[name] or raise Fehler, "Unbekannte Funktion #{name}"
      nimm
      args = []
      until peek == ')'
        args << oder
        nimm if peek == ','
        raise Fehler, "')' fehlt" if peek.nil?
      end
      nimm
      f.call(*args)
    end

    def wert_von(name)
      teile = name.split('.')
      wurzel = teile.shift
      basis = if %w[P V].include?(wurzel) then @ctx[wurzel] else @ctx[:vars] end
      raise Fehler, "Unbekannt: #{name}" if basis.nil?

      if %w[P V].include?(wurzel)
        teile.each { |k| basis = basis.is_a?(Hash) && basis.key?(k) ? basis[k] : raise(Fehler, "Unbekannt: #{name}") }
        # Werte, die selbst Formeln sind, werden rekursiv aufgelöst
        self.class.auswerten(basis, @ctx)
      else
        raise Fehler, "Unbekannte Variable #{name}" unless teile.empty? && basis.key?(wurzel)

        basis[wurzel]
      end
    end
  end
end
