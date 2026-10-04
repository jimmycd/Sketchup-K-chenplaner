#!/usr/bin/env ruby
# frozen_string_literal: true

# Aufruf: ruby tools/export_tcn.rb teil.json profil.json ausgabeordner
require 'json'
require 'fileutils'
require_relative '../lib/kp/tcn/exporter'

teil_path, profil_path, out = ARGV
abort 'Aufruf: export_tcn.rb teil.json profil.json ausgabeordner' unless out

result = Kp::Tcn::Exporter.new(JSON.parse(File.read(profil_path))).export(JSON.parse(File.read(teil_path)))
unless result.fehler.empty?
  warn result.fehler
  exit 1
end
FileUtils.mkdir_p(out)
result.files.each do |f|
  File.binwrite(File.join(out, f.name), f.content)
  puts File.join(out, f.name)
end
