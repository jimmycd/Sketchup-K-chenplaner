# frozen_string_literal: true

require 'json'

module Kp
  # Lädt Vorlagen, Regeln, Beschläge und Beschlag-Sets aus einem oder mehreren Katalogordnern
  # (Reihenfolge = Priorität: spätere Ordner überschreiben nichts, der erste Treffer gewinnt).
  class Katalog
    class Fehler < StandardError; end

    attr_reader :regeln

    def initialize(ordner)
      @ordner = Array(ordner)
      @vorlagen = {}
      @beschlaege = {}
      @sets = {}
      @regeln = []
      @ordner.each { |o| lade(o) }
      @regeln.sort_by! { |r| r['prioritaet'] || 100 }
    end

    def vorlage(code)
      roh = @vorlagen[code] or raise Fehler, "Vorlage #{code} nicht gefunden"
      kette = []
      cur = roh
      while cur
        raise Fehler, "Zyklus bei #{cur['code']}" if kette.include?(cur)

        kette.unshift(cur)
        cur = cur['basis'] && (@vorlagen[cur['basis']] or raise(Fehler, "Basis #{cur['basis']} fehlt"))
      end
      aufgeloest = kette.reduce({}) { |acc, v| self.class.mischen(acc, v) }
      aufgeloest['abstrakt'] = roh['abstrakt'] || false
      aufgeloest.delete('basis')
      aufgeloest
    end

    def beschlag(id) = @beschlaege[id]

    def beschlagset(id)
      set = @sets[id] or raise Fehler, "Beschlag-Set #{id} nicht gefunden"
      return set unless set['basis']

      self.class.mischen(beschlagset(set['basis']), set)
    end

    # Objekte tief mischen, Arrays komplett ersetzen (Konzept, Vererbung in drei Ebenen)
    def self.mischen(a, b)
      a.merge(b) { |_k, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? mischen(x, y) : y }
    end

    private

    def lade(ordner)
      Dir.glob(File.join(ordner, 'templates', '*.json')).sort.each { |f| (v = lese(f))['code'] && (@vorlagen[v['code']] ||= v) }
      Dir.glob(File.join(ordner, 'hardware', '*.json')).sort.each { |f| (b = lese(f)); @beschlaege[b['id']] ||= b }
      Dir.glob(File.join(ordner, 'hardware_sets', '*.json')).sort.each { |f| (s = lese(f)); @sets[s['id']] ||= s }
      Dir.glob(File.join(ordner, 'rules', '*.json')).sort.each do |f|
        lese(f).each { |r| @regeln << r unless @regeln.any? { |x| x['id'] == r['id'] } }
      end
    end

    def lese(pfad) = JSON.parse(File.read(pfad, encoding: 'utf-8'))
  end
end
