# frozen_string_literal: true

require "json"

module IbanChecker
  # Client for the ibanchecker.cash IBAN validation API.
  #
  # Validate IBANs across 92 countries, validate up to 100 IBANs per request,
  # extract IBANs from free text, look up country format specifications and
  # resolve SWIFT/BIC codes.
  #
  # Every call except country_format needs an API key; without one the API
  # answers 401 and AuthenticationError is raised. That includes lookup_bic,
  # which used to work without a key. The free key from
  # https://ibanchecker.cash/api-docs covers validate only, 100 requests a
  # month. validate_bulk and lookup_bic need the Basic plan or above, and
  # extract the Growth plan or above. A key whose email address has a verified
  # account at https://ibanchecker.cash/dashboard can try the calls its plan
  # lacks (validate_bulk up to 10 IBANs, extract up to 5,000 characters per
  # call). A call outside the key's plan gets a 403 with error_code
  # "PLAN_REQUIRED", raised as APIError; its #response carries required_plan
  # and upgrade_url.
  #
  # country_format works without a key, limited to 100 requests an hour per
  # IP. That hourly limit applies to country_format only.
  #
  #   client = IbanChecker::Client.new(ENV["IBANCHECKER_API_KEY"])   # or .new("iban_your_key")
  #   result = client.validate("DE89 3704 0044 0532 0130 00")
  #   puts "#{result.bank_name} #{result.bic}" if result.valid?
  class Client
    DEFAULT_BASE_URL = "https://ibanchecker.cash/api/v1"

    ERRORS_BY_STATUS = {
      400 => BadRequestError,
      401 => AuthenticationError,
      404 => NotFoundError,
      429 => RateLimitError
    }.freeze

    # Everything outside the unreserved set of RFC 3986 is percent-encoded
    # before it goes into a path segment.
    RESERVED = /[^A-Za-z0-9\-._~]/.freeze

    attr_reader :base_url

    def initialize(api_key = nil, base_url: DEFAULT_BASE_URL, timeout: 10.0, transport: nil)
      key = api_key.to_s
      @api_key = key.empty? ? nil : key
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @transport = transport || Transport::NetHttp.new(timeout: timeout)
    end

    # Validate a single IBAN.
    #
    # A malformed IBAN is not an error: the result comes back with +valid?+
    # false and an +error+ plus +error_code+ explaining why.
    #
    # Needs an API key; the free key covers it. Counts one request.
    def validate(iban)
      ValidationResult.from_api(request("POST", "/validate", "iban" => iban.to_s))
    end

    # Validate up to 100 IBANs in one request. Results come back in the same
    # order as the input.
    #
    # Needs an API key on the Basic plan or above, or a trial of up to 10 IBANs
    # per call for a key with a verified account. Counts one request per IBAN.
    def validate_bulk(ibans)
      BatchResult.from_api(
        request("POST", "/validate/bulk", "ibans" => Array(ibans).map(&:to_s))
      )
    end

    # Scan free text (emails, invoices) for IBAN-shaped strings and validate
    # each candidate. Up to 50,000 characters per request.
    #
    # Needs an API key on the Growth plan or above, or a trial of up to 5,000
    # characters per call for a key with a verified account. Counts one request
    # per IBAN found, with at least one per call.
    def extract(text)
      BatchResult.from_api(request("POST", "/extract", "text" => text.to_s))
    end

    # The IBAN format specification for an ISO 3166-1 alpha-2 country code,
    # for example "DE".
    #
    # Named country_format rather than format because Kernel#format is
    # sprintf, and shadowing it inside this class would be a trap.
    #
    # The only call that works without a key, limited to 100 requests an hour
    # per IP.
    def country_format(country)
      FormatSpec.from_api(request("GET", "/formats/#{escape(country.to_s.downcase)}"))
    end

    # Resolve an 8 or 11 character ISO 9362 BIC to a bank record.
    #
    # Needs an API key on the Basic plan or above, or a trial for a key with a
    # verified account. Without a key the API answers 401 and
    # AuthenticationError is raised; it no longer works keyless. Counts one
    # request.
    def lookup_bic(bic)
      BankRecord.from_api(request("GET", "/swift/#{escape(bic.to_s.upcase)}"))
    end

    private

    def request(method, path, payload = nil)
      headers = {
        "Accept" => "application/json",
        "User-Agent" => "ibanchecker-ruby/#{VERSION}"
      }
      headers["Authorization"] = "Bearer #{@api_key}" if @api_key

      body = nil
      if payload
        body = JSON.generate(payload)
        headers["Content-Type"] = "application/json"
      end

      response = @transport.call(method, @base_url + path, headers, body)
      status = response.status.to_i
      raw = response.body.to_s
      data = parse(raw)

      raise error_for(status, data) if status >= 400
      return data if data

      raise APIError.new(
        raw.strip.empty? ? "The API returned an empty body" : "The API returned a body that is not a JSON object",
        status: status
      )
    end

    # Returns the decoded object, or nil when the body was empty, unparseable
    # or not a JSON object. The caller decides what that means: on an error
    # status it just means there is no message to quote.
    def parse(raw)
      return nil if raw.strip.empty?

      decoded = JSON.parse(raw)
      decoded.is_a?(Hash) ? decoded : nil
    rescue JSON::ParserError
      nil
    end

    def error_for(status, data)
      message = data && data["error"].is_a?(String) ? data["error"] : "HTTP #{status}"
      code = data && data["error_code"].is_a?(String) ? data["error_code"] : nil

      ERRORS_BY_STATUS.fetch(status, APIError).new(
        message, status: status, error_code: code, response: data
      )
    end

    def escape(value)
      value.gsub(RESERVED) { |char| char.each_byte.map { |byte| format("%%%02X", byte) }.join }
    end
  end
end
