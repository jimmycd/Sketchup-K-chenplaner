#!/usr/bin/env ruby
# frozen_string_literal: true

# Aufruf: ruby tools/generate.rb projekt.json [zeile_id] [ausgabeordner]
# Erzeugt für alle Schränke der Zeile die Teile (JSON je Teil) und optional TCN-Dateien (Profil aus dem Projekt).
require 'json'
require 'fileutils'
require_relative '../lib/kp/generator'
require_relative '../lib/kp/tcn/exporter'

projekt_pfad, zeile_id, out = ARGV
abort 'Aufruf: generate.rb projekt.json [zeile_id] [ausgabeordner]' unless projekt_pfad

wurzel = File.dirname(File.expand_path(projekt_pfad))
projekt = JSON.parse(File.read(projekt_pfad, encoding: 'utf-8'))
katalog = Kp::Katalog.new((projekt['kataloge'] || [File.expand_path('../catalog', __dir__)]).map { |k| File.expand_path(k, wurzel) })
gen = Kp::Generator.new(projekt, katalog)
profil_pfad = projekt.dig('standards', 'maschine', 'exporter_profil')
profil = profil_pfad && JSON.parse(File.read(File.expand_path(profil_pfad, wurzel), encoding: 'utf-8'))

fehler = 0
(projekt['zeilen'] || []).select { |z| zeile_id.nil? || zeile_id == '-' || z['id'] == zeile_id }.each do |zeile|
  zeile['elemente'].each do |inst|
    res = gen.schrank(inst)
    res.warnungen.each { |w| warn "#{inst['pos']}: #{w}" }
    res.teile.each do |t|
      puts "#{t['uid']}  #{t['fertigmass'].values_at('l', 'w', 'd').join(' x ')}  #{t['bearbeitungen'].size} Bearbeitungen"
      next unless out

      FileUtils.mkdir_p(out)
      File.write(File.join(out, "#{t['uid'].tr('/', '_')}.json"), JSON.pretty_generate(t))
      next unless profil

      r = Kp::Tcn::Exporter.new(profil).export(t)
      r.fehler.each { |f| warn "FEHLER #{f}"; fehler += 1 }
      r.files.each { |f| File.binwrite(File.join(out, f.name), f.content) }
    end
  end
end
exit(fehler.zero? ? 0 : 1)
