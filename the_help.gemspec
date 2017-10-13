# frozen_string_literal: true

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'the_help/version'

Gem::Specification.new do |spec|
  spec.name          = 'the_help'
  spec.version       = TheHelp::VERSION
  spec.authors       = ['John Wilger']
  spec.email         = ['john@johnwilger.com']

  spec.summary       = 'A service layer framework'
  spec.description   = 'A service layer framework'
  spec.homepage      = 'https://github.com/jwilger/the_help'
  spec.license       = 'MIT'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 0.50'
end
