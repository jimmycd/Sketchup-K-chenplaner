# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/kp/generator'

class TestOcl < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def projekt
    JSON.parse(File.read(File.join(ROOT, 'examples/projekt_mueller.json')))
  end

  def test_material_specs_from_standards
    specs = Kp::Ocl.materialien(projekt['standards'])
    platte = specs.find { |s| s[:name] == 'Spanplatte melaminbeschichtet weiß' }
    assert_equal :platte, platte[:art]
    assert_equal 19, platte[:staerke]
    kante = specs.find { |s| s[:name] == 'ABS weiß 2 mm' }
    assert_equal :kante, kante[:art]
    assert_equal [2, 23], [kante[:staerke], kante[:hoehe]]
  end

  def test_only_used_materials
    specs = Kp::Ocl.materialien(projekt['standards'], ['HDF weiß', 'ABS weiß 2 mm'])
    assert_equal ['ABS weiß 2 mm', 'HDF weiß'], specs.map { |s| s[:name] }.sort
  end

  def test_attributes_follow_mapping_file
    map = Kp::Ocl.mapping(File.join(ROOT, 'catalog', 'ocl.json'))
    platte = Kp::Ocl.attribute({ art: :platte, staerke: 19, maserung: false }, map)
    assert_equal({ 'type' => 2, 'std_thicknesses' => '19mm', 'grained' => false }, platte)
    kante = Kp::Ocl.attribute({ art: :kante, staerke: 2, hoehe: 23 }, map)
    assert_equal({ 'type' => 4, 'std_thicknesses' => '2mm', 'std_widths' => '23mm' }, kante)
    # Anpassung ohne Codeänderung: andere Schlüssel/Einheit
    map2 = map.merge('einheit' => 'cm', 'schluessel' => map['schluessel'].merge('hoehe_kante' => 'width'))
    assert_equal 'width', Kp::Ocl.attribute({ art: :kante, staerke: 2, hoehe: 23 }, map2).keys.last
  end

  def test_edge_sketch_marks_banded_sides
    s = Kp::Ocl.kantenskizze('vorne' => 'x', 'hinten' => nil, 'links' => 'x', 'rechts' => nil).split("\n")
    assert_equal '+────────────+', s.first # oben (hinten) ohne Kante
    assert_equal '+════════════+', s.last  # unten (vorne) mit Kante
    assert s[1].start_with?('║') && s[1].end_with?('│')
  end

  def test_sizes_on_part_and_label
    gen = Kp::Generator.new(projekt, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    sr = gen.schrank('pos' => 'A1', 'vorlage' => 'US-T1', 'breite' => 450).teile.find { |t| t['teil_id'] == 'sr' }
    assert_equal({ 'l' => 772.0, 'w' => 552.0, 'd' => 19.0 }, sr['masse']['fertig'])
    assert_equal({ 'l' => 768.0, 'w' => 550.0, 'd' => 19.0 }, sr['masse']['fraes']) # Anleimer links+rechts je 2, vorne 2
    assert_equal sr['masse']['fraes'], sr['masse']['roh'] # Aufmaß Standard 0
    text = sr['ocl']['beschreibung']
    assert_includes text, 'Rohmaß: 768 × 550 × 19'
    assert_includes text, 'Fräsmaß: 768 × 550 × 19'
    assert_includes text, 'Fertigmaß: 772 × 552 × 19'
    assert_includes text, '═' # Skizze
  end

  def test_rohmass_aufmass_setting
    p = projekt
    p['standards']['zuschnitt'] = { 'aufmass' => 4 }
    gen = Kp::Generator.new(p, Kp::Katalog.new(File.join(ROOT, 'catalog')))
    bo = gen.schrank('pos' => 'A1', 'vorlage' => 'US-T1', 'breite' => 450).teile.find { |t| t['teil_id'] == 'bo' }
    assert_equal 412.0 + 4, bo['masse']['roh']['l']
    assert_equal 550.0 + 4, bo['masse']['roh']['w']
  end
end
