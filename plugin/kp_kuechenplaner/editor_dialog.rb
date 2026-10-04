# frozen_string_literal: true

require 'json'

module Kp
  module Plugin
    EDITOR_ORDNER = File.join(__dir__, 'editor')

    module_function

    # Editor für Projekt und Katalog als HtmlDialog (Oberfläche in editor/). Die Logik steckt in Kp::Editor::Sitzung.
    def editor_oeffnen
      if @editor&.visible?
        @editor.bring_to_front
        return @editor
      end

      sitzung = Editor::Sitzung.new(
        basis: BASE, projekt_pfad: projekt_pfad,
        zeichnen: ->(projekt, katalog, _ordner) { zeichne_projekt(projekt, katalog, 'Küche live').uniq.first(15) },
        waehlen: -> { projekt_waehlen }
      )
      dlg = UI::HtmlDialog.new(
        dialog_title: 'Küchenplaner – Editor', preferences_key: 'kp_editor', scrollable: false, resizable: true,
        width: 1100, height: 760, min_width: 700, min_height: 450, style: UI::HtmlDialog::STYLE_DIALOG
      )
      dlg.add_action_callback('kp') do |_ctx, json|
        anfrage = JSON.parse(json)
        antwort = sitzung.behandle(anfrage['aktion'], anfrage['daten'])
        dlg.execute_script("kpAntwort(#{anfrage['id'].to_i}, #{JSON.generate(antwort).to_json})")
      end
      dlg.set_file(File.join(EDITOR_ORDNER, 'index.html'))
      dlg.show
      @editor = dlg
    end
  end
end
