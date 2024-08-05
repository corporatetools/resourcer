# frozen_string_literal: true

require_relative "lib/resourcer/version"

Gem::Specification.new do |spec|
  spec.name = "resourcer"
  spec.version = Resourcer::VERSION
  spec.authors = ["Daniel Dailey"]
  spec.email = ["daniel@daileyhome.com"]

  spec.summary = "Efficiently manage and optimize ActiveRecord data retrieval and associations."
  spec.description = "The Resourcer gem preloads and indexes related data to eliminate N+1 queries and centralize data complexities, providing efficient and maintainable access to related data in Rails applications."
  spec.homepage = "https://github.com/corporatetools/resourcer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/corporatetools/resourcer"
  spec.metadata["changelog_uri"] = "https://github.com/corporatetools/resourcer/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "activerecord", "~> 6.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
