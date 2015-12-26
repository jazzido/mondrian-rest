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

  s.add_runtime_dependency 'mondrian-olap', ["~> 0.7.0"]
  s.add_runtime_dependency 'grape', ["~> 0.14.0"]
  s.add_runtime_dependency 'writeexcel', '~> 1.0', '>= 1.0.5'
  s.add_runtime_dependency "null_logger", ["~> 0.0.1"]

  s.add_development_dependency 'rake', '~> 10.4', '>= 10.4.2'
  s.add_development_dependency 'rspec', '~> 3.4', '>= 3.4.0'
  s.add_development_dependency 'jdbc-derby', '~> 10.11', '>= 10.11.1.1'
  s.add_development_dependency 'jdbc-sqlite3', '~> 3.8', '>= 3.8.11.2'
  s.add_development_dependency 'rack-test', '~> 0.6.3'
  s.add_development_dependency 'rubyzip', '~> 1.1', '>= 1.1.7'
end
