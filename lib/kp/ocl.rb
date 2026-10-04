# frozen_string_literal: true

require 'json'

module Kp
  # Daten für OpenCutList: Materialspezifikationen aus den Projektstandards, Abbildung auf OCL-Materialattribute
  # und Etikettentext (Maße, Kantenskizze). Reines Ruby, ohne SketchUp.
  module Ocl
    STANDARD = {
      'dictionary' => 'fr.lairdubois.opencutlist',
      'typen' => { 'platte' => 2, 'kante' => 4 },
      'einheit' => 'mm',
      'schluessel' => { 'typ' => 'type', 'staerke_platte' => 'std_thicknesses', 'staerke_kante' => 'std_thicknesses',
                        'hoehe_kante' => 'std_widths', 'maserung' => 'grained' }
    }.freeze

    module_function

    def mapping(pfad = nil)
      return STANDARD unless pfad && File.exist?(pfad)

      geladen = JSON.parse(File.read(pfad, encoding: 'utf-8'))
      STANDARD.merge(geladen) { |_k, a, b| a.is_a?(Hash) && b.is_a?(Hash) ? a.merge(b) : b }
    end

    # Spezifikationen aller Platten- und Kantenmaterialien der Standards; mit +namen+ nur die verwendeten.
    def materialien(standards, namen = nil)
      liste = []
      (standards['materialien'] || {}).each do |key, m|
        liste << { name: m['ocl_material'] || m['name'] || key, art: :platte, staerke: m['staerke'], maserung: m['maserung'], farbe: m['farbe'] }
      end
      (standards['kanten'] || {}).each do |key, k|
        liste << { name: k['ocl_material'] || k['name'] || key, art: :kante, staerke: k['staerke'], hoehe: k['hoehe'], farbe: k['farbe'] }
      end
      liste = liste.select { |s| namen.include?(s[:name]) } if namen
      liste.uniq { |s| s[:name] }
    end

    def laenge(wert, einheit)
      s = wert.to_f == wert.to_f.round ? wert.to_f.round.to_s : wert.to_f.to_s
      "#{s}#{einheit}"
    end

    # OCL-Attribute (Schlüssel => Wert) für ein Material
    def attribute(spec, map = STANDARD)
      s = map['schluessel']
      e = map['einheit']
      a = { s['typ'] => map['typen'].fetch(spec[:art].to_s) }
      if spec[:art] == :platte
        a[s['staerke_platte']] = laenge(spec[:staerke], e) if spec[:staerke]
        a[s['maserung']] = spec[:maserung] ? true : false unless spec[:maserung].nil?
      else
        a[s['staerke_kante']] = laenge(spec[:staerke], e) if spec[:staerke]
        a[s['hoehe_kante']] = laenge(spec[:hoehe], e) if spec[:hoehe]
      end
      a
    end

    # Skizze des Teils (Ansicht auf F1): Anleimer als doppelte Linie. unten = y 0, oben = y W, links = x 0, rechts = x L.
    def kantenskizze(kanten)
      b = ->(seite) { kanten[seite] ? true : false }
      oben = b.call('hinten') ? '═' : '─'
      unten = b.call('vorne') ? '═' : '─'
      links = b.call('links') ? '║' : '│'
      rechts = b.call('rechts') ? '║' : '│'
      ["+#{oben * 12}+", "#{links}#{' ' * 12}#{rechts}", "#{links}   Fläche 1 #{rechts}", "#{links}#{' ' * 12}#{rechts}", "+#{unten * 12}+"].join("\n")
    end

    def mass(m)
      "#{fmt(m['l'])} × #{fmt(m['w'])}" + (m['d'] ? " × #{fmt(m['d'])}" : '')
    end

    def fmt(v)
      v.to_f == v.to_f.round ? v.to_f.round.to_s : format('%.1f', v.to_f)
    end

    # Etikettentext: Schrank, Teil, Material, Roh-/Fräs-/Fertigmaß, Kanten mit Skizze
    def beschreibung(teil, material_name, kanten_namen)
      m = teil['masse']
      zeilen = ["Schrank #{teil['pos']} · #{teil['bezeichnung']}", "Material: #{material_name}"]
      if m
        zeilen << "Rohmaß: #{mass(m['roh'])}"
        zeilen << "Fräsmaß: #{mass(m['fraes'])}"
        zeilen << "Fertigmaß: #{mass(m['fertig'])}"
      end
      belegt = %w[vorne hinten links rechts].select { |s| kanten_namen[s] }
      zeilen << (belegt.empty? ? 'Kanten: keine' : "Kanten #{belegt.map { |s| "#{s}: #{kanten_namen[s]}" }.join(', ')}")
      zeilen << kantenskizze(kanten_namen) unless belegt.empty?
      zeilen.join("\n")
    end
  end
end
