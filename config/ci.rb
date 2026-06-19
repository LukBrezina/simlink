# The signoff pipeline. Run it before you push or deploy:
#
#   bin/ci
#
# Lint + dependency/security audits + Brakeman + the full test suite, then a
# local signoff. No external services or accounts required.

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby (RuboCop)", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Tests: Rails", "bin/rails test"

  if success?
    step "Signoff", %(echo "All systems go — lint, security and tests passed. Safe to deploy.")
  else
    failure "Signoff: CI failed.", "Fix the issues above and re-run bin/ci."
  end
end
