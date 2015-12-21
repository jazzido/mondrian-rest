# coding: utf-8
Gem::Specification.new do |s|
  s.name        = "mondrian-rest"
  s.version     = '0.5.0'
  s.authors     = ["Manuel Aristarán"]
  s.email       = ["manuel@jazzido.com"]
  s.homepage    = "https://github.com/jazzido/mondrian-rest"
  s.summary     = %q{A REST interface for Mondrian ROLAP server}
  s.description = %q{A REST interface for Mondrian ROLAP server}
  s.license     = 'MIT'

  s.platform = 'java'

  s.files         = `git ls-files`.split("\n").reject { |f| f =~ /^spec\// }
  s.require_paths = ["lib"]

  s.add_runtime_dependency "mondrian-olap", ["~> 0.7.0"]
  s.add_runtime_dependency "grape", ["~> 0.14.0"]
  s.add_runtime_dependency "spreadsheet", ["~> 1.1.0"]
  s.add_runtime_dependency "null_logger", ["~> 0.0.1"]

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'jdbc-derby'
  s.add_development_dependency 'jdbc-sqlite3'
  s.add_development_dependency 'rack-test'
  s.add_development_dependency 'rubyzip'
end
