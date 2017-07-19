# coding: utf-8
Gem::Specification.new do |s|
  s.name        = "mondrian-rest"
  s.version     = '0.7.0'
  s.authors     = ["Manuel Aristarán"]
  s.email       = ["manuel@jazzido.com"]
  s.homepage    = "https://github.com/jazzido/mondrian-rest"
  s.summary     = %q{A REST interface for Mondrian ROLAP server}
  s.description = %q{A REST interface for Mondrian ROLAP server}
  s.license     = 'MIT'

  s.platform = 'java'

  s.files         = `git ls-files`.split("\n").reject { |f| f =~ /^spec\// }
  s.require_paths = ["lib", "lib/jars"]

  s.requirements << 'jar no.ssb.jsonstat:json-stat-java, 0.2.2'

  s.add_runtime_dependency 'mondrian-olap', ["~> 0.8.0"]
  s.add_runtime_dependency 'grape', ["~> 1.0.0"]
  s.add_runtime_dependency 'writeexcel', '~> 1.0', '>= 1.0.5'

  s.add_development_dependency "jar-dependencies", "~> 0.3.2"
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'jdbc-derby'
  s.add_development_dependency 'jdbc-sqlite3'
  s.add_development_dependency 'rack-test'
  s.add_development_dependency 'rubyzip'
end
