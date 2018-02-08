lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "temporalis/version"

Gem::Specification.new do |spec|
  spec.name          = "temporalis"
  spec.version       = Temporalis::VERSION
  spec.authors       = ["Mark Abramov"]
  spec.email         = ["me@markabramov.me"]

  spec.summary       = "ActiveRecord plugin for persisting trees with history"
  spec.homepage      = "https://github.com/chloeandisabel/temporalis"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 4.2.10"
  spec.add_dependency "activerecord-import", "~> 0.22.0"
  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pry", "~> 0.11.3"
  spec.add_development_dependency "dotenv"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "pg", "~> 0.20"
  spec.add_development_dependency "mysql2"
end
