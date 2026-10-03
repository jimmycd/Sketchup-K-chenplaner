# frozen_string_literal: true

# SketchUp-Erweiterung "Küchenplaner" (Entwicklungsstand, NICHT in SketchUp getestet).
# Laden zum Testen in der Ruby-Konsole:  load '/pfad/zum/repo/plugin/kp_kuechenplaner.rb'
require 'sketchup'
require 'extensions'

module Kp
  module Plugin
    ROOT = File.expand_path('..', __dir__)
    EXT = SketchupExtension.new('Küchenplaner', File.join(__dir__, 'kp_kuechenplaner', 'main'))
    EXT.description = 'Plant Küchen aus einem Standardkatalog und exportiert TCN-Dateien für die CNC.'
    EXT.version = '0.1.0'
    EXT.creator = 'Jürgen Späder'
    Sketchup.register_extension(EXT, true)
  end
end
