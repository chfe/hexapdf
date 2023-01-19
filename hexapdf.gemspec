require './lib/hexapdf/version'

PKG_FILES = Dir.glob([
                       'bin/*',
                       'lib/**/*.rb',
                       'data/**/*',
                     ])
description = 'HexaPDF local development version only'

if ENV['REAL_GEM']
  PKG_FILES.concat(Dir.glob(['Rakefile', 'LICENSE', 'agpl-3.0.txt', 'README.md', 'CHANGELOG.md',
                             'VERSION', 'CONTRIBUTERS', 'man/man1/hexapdf.1',
                             'examples/*', 'test/**/*']))
end

Gem::Specification.new do |s|
  s.name = 'hexapdf'
  s.version = HexaPDF::VERSION
  s.summary = "HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby"
  s.description = description
  s.licenses = ['AGPL-3.0', 'Nonstandard']

  s.files = PKG_FILES

  s.require_path = 'lib'
  s.executables = ['hexapdf']
  #s.add_dependency('cmdparse', '~> 3.0', '>= 3.0.3')
  #s.add_dependency('geom2d', '~> 0.3')
  s.add_dependency('openssl', '>= 2.2.1')
  s.add_development_dependency('kramdown', '~> 2.3')
  s.add_development_dependency('minitest', '~> 5.16')
  s.add_development_dependency('reline', '~> 0.1')
  s.add_development_dependency('rubocop', '~> 1.0')
  s.add_development_dependency('webrick')
  s.add_development_dependency('rake')
  s.add_development_dependency('simplecov')
  s.required_ruby_version = '>= 1.9.3'

  s.author = 'Thomas Leitner'
  s.email = 't_leitner@gmx.at'
  s.homepage = "https://hexapdf.gettalong.org"
end
