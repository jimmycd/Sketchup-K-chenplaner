# frozen_string_literal: true

# SketchUp-Erweiterung "Küchenplaner": Registrierung. Die eigentliche Arbeit steht in kp_kuechenplaner/main.rb.
# Installation: dist/kp_kuechenplaner_<version>.rbz über SketchUp > Fenster > Erweiterungsmanager > Erweiterung installieren.
require 'sketchup'
require 'extensions'

module Kp
  module Plugin
    VERSION = '0.7.0'

    unless defined?(EXT)
      EXT = SketchupExtension.new('Küchenplaner', File.join(__dir__, 'kp_kuechenplaner', 'main'))
      EXT.description = 'Plant Küchen aus einem Standardkatalog und exportiert TCN-Dateien für die CNC.'
      EXT.version = VERSION
      EXT.creator = 'Jürgen Späder'
      Sketchup.register_extension(EXT, true)
    end
  end
end
