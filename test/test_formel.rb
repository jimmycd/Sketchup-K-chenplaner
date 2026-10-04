# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/kp/formel'

class TestFormel < Minitest::Test
  def ctx
    { vars: { 'B' => 600.0, 'H' => 720.0, 'S' => 19.0, 'L' => 720.0 },
      'P' => { 'lochreihe' => { 'raster' => 32, 'start' => 64, 'aktiv' => true },
               'rueckwand' => { 'art' => 'aufgesetzt', 'staerke' => 8 },
               'hoehen' => { 'a' => 910, 'b' => '=P.hoehen.a-10' } },
      'V' => { 'innen_b' => '=B-2*S' } }
  end

  def ev(s) = Kp::Formel.auswerten(s, ctx)

  def test_arithmetic_and_precedence
    assert_equal 562, ev('=B-2*S+0')
    assert_equal 12, ev('=2+(3+1)*2+2')
    assert_in_delta(-5, ev('=-5'))
  end

  def test_functions
    assert_equal 4, ev('=max(1,4,2)')
    assert_equal 1, ev('=min(3,1)')
    assert_equal 18, ev('=floor((L-2*S-P.lochreihe.start-64)/P.lochreihe.raster)+1')
    assert_equal 3, ev('=ceil(2.1)')
    assert_equal 2.5, ev('=round(2.46,1)')
  end

  def test_paths_and_nested_formulas
    assert_equal 32, ev('=P.lochreihe.raster')
    assert_equal 562, ev('=V.innen_b')
    assert_equal 900, ev('=P.hoehen.b')
  end

  def test_conditions
    assert ev("=P.rueckwand.art=='aufgesetzt'")
    refute ev("=P.rueckwand.art=='genutet'")
    assert ev("=P.rueckwand.art!='genutet' and B>=600")
    assert ev("=P.rueckwand.art=='genutet' or P.lochreihe.aktiv")
    assert ev('=not (B<600)')
    assert ev('=P.lochreihe.aktiv')
  end

  def test_numbers_pass_through_and_errors
    assert_equal 7, ev(7)
    assert_equal 'abc', ev('abc')
    assert_raises(Kp::Formel::Fehler) { ev('=P.gibt.es.nicht') }
    assert_raises(Kp::Formel::Fehler) { ev('=B/0') }
    assert_raises(Kp::Formel::Fehler) { ev('=B+') }
    assert_raises(Kp::Formel::Fehler) { ev('=foo(1)') }
  end
end
