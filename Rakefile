# frozen_string_literal: true

# bundler/gem_tasks gives build, install and release. `rake release` is what
# the publish workflow runs: it builds the gem, pushes the version tag and
# pushes to RubyGems over OIDC. See PUBLISHING.md.
require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
  t.warning = true
end

task default: :test
