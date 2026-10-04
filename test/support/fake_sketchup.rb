# frozen_string_literal: true

# Minimale Attrappe der SketchUp-API, nur so weit wie plugin/kp_kuechenplaner/main.rb sie braucht.
# Sie prüft den Ablauf des Plugins, ersetzt aber keinen Test in SketchUp.
require 'tmpdir'

class Numeric
  def mm
    to_f / 25.4
  end
end

module Kernel
  def file_loaded?(_f)
    (@fake_loaded ||= {}).key?(_f)
  end

  def file_loaded(f)
    (@fake_loaded ||= {})[f] = true
  end
end

module Geom
  Point3d = Struct.new(:x, :y, :z) do
    def initialize(x = 0, y = 0, z = 0)
      super
    end
  end
  Vector3d = Struct.new(:x, :y, :z)
  class Transformation
    attr_reader :origin, :axes

    def initialize(origin = nil)
      @origin = origin
    end

    def self.axes(origin, x, y, z)
      t = new(origin)
      t.instance_variable_set(:@axes, [x, y, z])
      t
    end
  end
end

module Sketchup
  class Color
    attr_reader :red, :green, :blue

    def initialize(r, g, b)
      @red = r
      @green = g
      @blue = b
    end
  end

  class Material
    attr_reader :name
    attr_accessor :color

    def initialize(name) = @name = name
  end

  class Materials
    include Enumerable
    def initialize = @list = {}
    def [](name) = @list[name]
    def add(name) = @list[name] = Material.new(name)
    def each(&b) = @list.values.each(&b)
  end

  class Face
    attr_accessor :material
    attr_reader :normal

    def initialize(parent = nil)
      @parent = parent
      @normal = Struct.new(:x, :y, :z).new(0, 0, -1)
    end

    def reverse!
      @normal = Struct.new(:x, :y, :z).new(0, 0, 1)
    end

    # Nachbildung: Grundfläche wird zur Deckfläche, vier Seitenflächen und eine neue Bodenfläche entstehen
    def pushpull(d)
      @pushed = d
      @normal = Struct.new(:x, :y, :z).new(0, 0, 1)
      [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1]].each do |x, y, z|
        f = Face.new
        f.instance_variable_set(:@normal, Struct.new(:x, :y, :z).new(x, y, z))
        @parent&.items&.push(f)
      end
    end
    attr_reader :pushed
  end

  class Entities
    attr_reader :items

    def initialize
      @items = []
    end

    def add_group
      g = Group.new
      @items << g
      g
    end

    def add_face(*pts)
      f = Face.new(self)
      f.instance_variable_set(:@pts, pts)
      @items << f
      f
    end

    def add_instance(df, tr)
      i = Instance.new(df, tr)
      @items << i
      i
    end

    def grep(klass) = @items.grep(klass)
  end

  class Attrs
    def attrs = (@attrs ||= {})
    def set_attribute(d, k, v) = (attrs[[d, k]] = v)
    def get_attribute(d, k, default = nil) = attrs.fetch([d, k], default)
  end

  class Group < Attrs
    attr_accessor :name, :transformation
    attr_reader :entities, :erased

    def initialize
      @entities = Entities.new
    end

    def erase! = @erased = true
  end

  class Definition < Attrs
    attr_accessor :description
    attr_reader :name, :entities

    def initialize(name)
      @name = name
      @entities = Entities.new
    end
  end

  class Instance
    attr_accessor :name, :material
    attr_reader :definition, :transformation

    def initialize(df, tr)
      @definition = df
      @transformation = tr
    end
  end

  class Definitions
    include Enumerable
    def initialize = @list = []
    def add(name) = Definition.new(name).tap { |d| @list << d }
    def each(&b) = @list.each(&b)
  end

  class Model < Attrs
    attr_reader :entities, :definitions, :operations, :materials

    def initialize
      @entities = Entities.new
      @definitions = Definitions.new
      @materials = Materials.new
      @operations = []
    end

    def start_operation(name, *) = @operations << [:start, name]
    def commit_operation = @operations << [:commit]
    def abort_operation = @operations << [:abort]
  end

  @model = Model.new
  class << self
    attr_accessor :model

    def active_model = @model
    def register_extension(*) = true
    def extensions = []
    def read_default(sec, key, default = nil) = (@defaults ||= {}).fetch([sec, key], default)
    def write_default(sec, key, val) = ((@defaults ||= {})[[sec, key]] = val)
    def clear_defaults! = @defaults = {}
    def extensions = []
    def read_default(sec, key, default = nil) = (@defaults ||= {}).fetch([sec, key], default)
    def write_default(sec, key, val) = ((@defaults ||= {})[[sec, key]] = val)
    def clear_defaults! = @defaults = {}
    def reset! = (@model = Model.new)
  end
end

module UI
  class FakeMenu
    attr_reader :items

    def initialize = @items = []
    def add_submenu(name) = FakeMenu.new.tap { |m| (@items << [:submenu, name, m]) }
    def add_item(name, &blk) = @items << [:item, name, blk]
    def add_separator = @items << [:sep]
  end

  @menus = Hash.new { |h, k| h[k] = FakeMenu.new }
  @messages = []
  @answers = {}
  class << self
    attr_reader :messages, :menus
    attr_accessor :answers

    def menu(name) = @menus[name]
    def messagebox(text) = @messages << text
    def openpanel(*) = @answers[:openpanel]
    def select_directory(**) = @answers[:select_directory]
  end
end

# Platzhalter, damit require 'sketchup' / 'extensions' funktioniert
class SketchupExtension
  attr_accessor :description, :version, :creator
  attr_reader :name, :path

  def initialize(name, path)
    @name = name
    @path = path
  end
end
