# frozen_string_literal: true

require_relative "lib/ibanchecker/version"

Gem::Specification.new do |spec|
  spec.name = "ibanchecker"
  spec.version = IbanChecker::VERSION
  spec.authors = ["ibanchecker.cash"]
  spec.email = ["api@ibanchecker.cash"]

  spec.summary = "Official Ruby client for the ibanchecker.cash IBAN validation API"
  spec.description = "Validate IBANs across 92 countries, validate up to 100 IBANs per request, " \
                     "extract IBANs from free text, look up country format specifications and " \
                     "resolve SWIFT/BIC codes. No runtime dependencies."
  spec.homepage = "https://ibanchecker.cash"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata = {
    "homepage_uri" => "https://ibanchecker.cash",
    "documentation_uri" => "https://ibanchecker.cash/api-docs",
    "source_code_uri" => "https://github.com/koraykoylu/ibanchecker-ruby",
    "changelog_uri" => "https://github.com/koraykoylu/ibanchecker-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/koraykoylu/ibanchecker-ruby/issues",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }

  # Listed explicitly rather than from `git ls-files`, so the built gem does not
  # depend on where the build runs or on which files a checkout happens to have.
  spec.files = Dir["lib/**/*.rb"] + %w[README.md CHANGELOG.md LICENSE]
  spec.require_paths = ["lib"]
end
