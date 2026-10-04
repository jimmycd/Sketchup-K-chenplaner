# frozen_string_literal: true

require 'json'

module Kp
  # Füllt Projektstandards mit den Default-Werten aus projekt.schema.json auf.
  module Standards
    SCHEMA = File.expand_path('../../schemas/projekt.schema.json', __dir__)

    def self.mit_defaults(standards)
      props = JSON.parse(File.read(SCHEMA, encoding: 'utf-8')).dig('$defs', 'standards', 'properties')
      fuellen(props, Marshal.load(Marshal.dump(standards)))
    end

    def self.fuellen(props, hash)
      props.each do |name, spec|
        if spec['type'] == 'object' && spec['properties']
          sub = hash[name] || {}
          sub = fuellen(spec['properties'], sub)
          hash[name] = sub unless sub.empty?
        elsif !hash.key?(name) && spec.key?('default')
          hash[name] = spec['default']
        end
      end
      hash
    end
  end
end
