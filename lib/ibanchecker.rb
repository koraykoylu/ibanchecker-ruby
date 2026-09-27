# frozen_string_literal: true

require_relative "ibanchecker/version"
require_relative "ibanchecker/errors"
require_relative "ibanchecker/models"
require_relative "ibanchecker/transport"
require_relative "ibanchecker/client"

# Official Ruby client for the ibanchecker.cash IBAN validation API.
#
#   require "ibanchecker"
#
#   client = IbanChecker::Client.new(ENV["IBANCHECKER_API_KEY"])
#   result = client.validate("DE89370400440532013000")
#   result.valid?      # => true
#   result.bank_name   # => "Commerzbank AG Cologne"
module IbanChecker
end
