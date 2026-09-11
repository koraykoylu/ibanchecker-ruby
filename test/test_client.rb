# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "ibanchecker"

# Records what it was asked for and replays a canned response.
class FakeTransport
  attr_reader :calls

  def initialize(status, body)
    @status = status
    @body = body.is_a?(String) ? body : JSON.generate(body)
    @calls = []
  end

  def call(method, url, headers, body)
    @calls << { method: method, url: url, headers: headers, body: body }
    IbanChecker::Transport::Response.new(@status, @body)
  end

  def last
    @calls.last
  end
end

class TestClient < Minitest::Test
  def client(transport, api_key = nil, base_url: IbanChecker::Client::DEFAULT_BASE_URL)
    IbanChecker::Client.new(api_key, base_url: base_url, transport: transport)
  end

  def test_validate_returns_a_populated_result
    transport = FakeTransport.new(200, {
                                    "valid" => true,
                                    "iban" => "DE89370400440532013000",
                                    "formatted" => "DE89 3704 0044 0532 0130 00",
                                    "country" => "DE",
                                    "country_name" => "Germany",
                                    "bank_name" => "Commerzbank AG Cologne",
                                    "bic" => "COBADEFFXXX",
                                    "bank_city" => "Köln",
                                    "sepa" => true,
                                    "national_check_valid" => true
                                  })

    result = client(transport).validate("DE89 3704 0044 0532 0130 00")

    assert_instance_of IbanChecker::ValidationResult, result
    assert result.valid?
    assert_equal "Germany", result.country_name
    assert_equal "COBADEFFXXX", result.bic
    assert_equal "Köln", result.bank_city
    assert_equal true, result.sepa
    assert_equal true, result.national_check_valid
    assert_equal "DE89370400440532013000", result.raw["iban"]

    call = transport.last
    assert_equal "POST", call[:method]
    assert_equal "#{IbanChecker::Client::DEFAULT_BASE_URL}/validate", call[:url]
    assert_equal({ "iban" => "DE89 3704 0044 0532 0130 00" }, JSON.parse(call[:body]))
    assert_equal "application/json", call[:headers]["Content-Type"]
  end

  def test_a_malformed_iban_is_a_result_not_an_error
    transport = FakeTransport.new(200, {
                                    "valid" => false,
                                    "iban" => "XX00",
                                    "country" => "XX",
                                    "error" => '"XX" is not a recognized IBAN country code.',
                                    "error_code" => "INVALID_COUNTRY"
                                  })

    result = client(transport).validate("XX00")

    refute result.valid?
    assert_equal "INVALID_COUNTRY", result.error_code
    assert_nil result.national_check_valid
    assert_nil result.bank_name
  end

  def test_api_key_becomes_a_bearer_header_and_is_omitted_without_one
    with_key = FakeTransport.new(200, { "valid" => true, "iban" => "DE89370400440532013000" })
    client(with_key, "iban_test_key").validate("DE89370400440532013000")
    assert_equal "Bearer iban_test_key", with_key.last[:headers]["Authorization"]

    without_key = FakeTransport.new(200, { "valid" => true, "iban" => "DE89370400440532013000" })
    client(without_key).validate("DE89370400440532013000")
    refute_includes without_key.last[:headers].keys, "Authorization"

    empty_key = FakeTransport.new(200, { "valid" => true, "iban" => "DE89370400440532013000" })
    client(empty_key, "").validate("DE89370400440532013000")
    refute_includes empty_key.last[:headers].keys, "Authorization"
  end

  def test_the_user_agent_carries_the_client_version
    transport = FakeTransport.new(200, { "valid" => true, "iban" => "DE89" })
    client(transport).validate("DE89")

    assert_equal "ibanchecker-ruby/#{IbanChecker::VERSION}", transport.last[:headers]["User-Agent"]
  end

  def test_validate_bulk_keeps_input_order_and_counts
    transport = FakeTransport.new(200, {
                                    "count" => 2,
                                    "valid_count" => 1,
                                    "invalid_count" => 1,
                                    "results" => [
                                      { "valid" => true, "iban" => "DE89370400440532013000" },
                                      { "valid" => false, "iban" => "XX00" }
                                    ]
                                  })

    batch = client(transport).validate_bulk(%w[DE89370400440532013000 XX00])

    assert_equal 2, batch.count
    assert_equal 1, batch.valid_count
    assert_equal 1, batch.invalid_count
    assert_equal 2, batch.size
    assert_equal %w[DE89370400440532013000 XX00], batch.map(&:iban)
    assert_equal 1, batch.results.count(&:valid?)
    assert_equal({ "ibans" => %w[DE89370400440532013000 XX00] }, JSON.parse(transport.last[:body]))
  end

  def test_validate_bulk_accepts_any_enumerable
    transport = FakeTransport.new(200, { "count" => 2, "results" => [] })
    client(transport).validate_bulk(%w[DE89 GB29].each)

    assert_equal({ "ibans" => %w[DE89 GB29] }, JSON.parse(transport.last[:body]))
  end

  def test_extract_reads_ibans_out_of_text
    transport = FakeTransport.new(200, {
                                    "count" => 1,
                                    "valid_count" => 1,
                                    "invalid_count" => 0,
                                    "results" => [
                                      { "valid" => true, "iban" => "DE89370400440532013000",
                                        "bank_name" => "Commerzbank AG Cologne" }
                                    ]
                                  })

    batch = client(transport).extract("Please wire to DE89 3704 0044 0532 0130 00 by Friday.")

    assert_equal 1, batch.size
    assert_equal "Commerzbank AG Cologne", batch.first.bank_name
    assert_equal "#{IbanChecker::Client::DEFAULT_BASE_URL}/extract", transport.last[:url]
  end

  def test_country_format_parses_bban_fields
    transport = FakeTransport.new(200, {
                                    "country_code" => "DE",
                                    "country_name" => "Germany",
                                    "length" => 22,
                                    "sepa" => true,
                                    "swift" => true,
                                    "format_string" => "DEkk nnnn nnnn nnnn nnnn nn",
                                    "example" => "DE89370400440532013000",
                                    "bban_fields" => [
                                      { "label" => "BLZ", "length" => 8, "type" => "numeric",
                                        "description" => "8-digit Bankleitzahl" },
                                      { "label" => "Account No.", "length" => 10, "type" => "numeric" }
                                    ]
                                  })

    format = client(transport).country_format("DE")

    assert_equal 22, format.length
    assert_equal true, format.sepa
    assert_equal 2, format.bban_fields.size
    assert_equal "BLZ", format.bban_fields[0].label
    assert_equal 8, format.bban_fields[0].length
    assert_nil format.bban_fields[1].description
    assert_equal "GET", transport.last[:method]
    assert transport.last[:url].end_with?("/formats/de"), transport.last[:url]
    assert_nil transport.last[:body]
  end

  def test_lookup_bic_uppercases_the_path
    transport = FakeTransport.new(200, {
                                    "bic" => "DEUTDEFFXXX",
                                    "bic8" => "DEUTDEFF",
                                    "bank_name" => "Deutsche Bank AG Frankfurt",
                                    "city" => "FRANKFURT AM MAIN",
                                    "sepa" => true,
                                    "type" => "private",
                                    "status" => "active"
                                  })

    bank = client(transport).lookup_bic("deutdeff")

    assert_equal "Deutsche Bank AG Frankfurt", bank.bank_name
    assert_equal "DEUTDEFF", bank.bic8
    assert_equal "active", bank.status
    assert transport.last[:url].end_with?("/swift/DEUTDEFF"), transport.last[:url]
  end

  def test_path_segments_are_percent_encoded
    transport = FakeTransport.new(200, { "bic" => "X" })
    client(transport).lookup_bic("de/../admin?x=1")

    assert transport.last[:url].end_with?("/swift/DE%2F..%2FADMIN%3FX%3D1"), transport.last[:url]
  end

  def test_error_statuses_map_to_typed_errors
    {
      400 => IbanChecker::BadRequestError,
      401 => IbanChecker::AuthenticationError,
      404 => IbanChecker::NotFoundError,
      429 => IbanChecker::RateLimitError,
      500 => IbanChecker::APIError,
      503 => IbanChecker::APIError
    }.each do |status, expected|
      transport = FakeTransport.new(status, { "error" => "nope", "error_code" => "SOME_CODE" })

      error = assert_raises(expected) { client(transport, "iban_test_key").lookup_bic("ZZZZZZZZ") }

      assert_kind_of IbanChecker::Error, error
      assert_equal status, error.status
      assert_equal "SOME_CODE", error.error_code
      assert_equal "nope", error.message
      assert_equal({ "error" => "nope", "error_code" => "SOME_CODE" }, error.response)
    end
  end

  def test_an_error_status_without_a_json_body_still_carries_the_status
    transport = FakeTransport.new(502, "<html>bad gateway</html>")

    error = assert_raises(IbanChecker::APIError) { client(transport).validate("DE89") }

    assert_equal "HTTP 502", error.message
    assert_equal 502, error.status
    assert_nil error.error_code
    assert_nil error.response
  end

  def test_a_non_json_body_on_a_successful_status_is_an_api_error
    transport = FakeTransport.new(200, "<html>maintenance</html>")

    error = assert_raises(IbanChecker::APIError) { client(transport).validate("DE89") }

    assert_equal "The API returned a body that is not a JSON object", error.message
  end

  def test_an_empty_body_on_a_successful_status_is_an_api_error
    transport = FakeTransport.new(200, "")

    error = assert_raises(IbanChecker::APIError) { client(transport).validate("DE89") }

    assert_equal "The API returned an empty body", error.message
  end

  def test_base_url_override_drops_a_trailing_slash
    transport = FakeTransport.new(200, { "valid" => true, "iban" => "DE89" })
    client(transport, nil, base_url: "https://example.test/v1/").validate("DE89")

    assert_equal "https://example.test/v1/validate", transport.last[:url]
  end

  def test_inspect_stays_short_and_says_what_happened
    transport = FakeTransport.new(200, {
                                    "valid" => true, "iban" => "DE89370400440532013000",
                                    "bank_name" => "Commerzbank AG Cologne",
                                    "raw_noise" => "x" * 500
                                  })

    text = client(transport).validate("DE89370400440532013000").inspect

    assert_includes text, "DE89370400440532013000"
    assert_includes text, "Commerzbank AG Cologne"
    refute_includes text, "x" * 100
  end
end

class TestNetHttpTransport < Minitest::Test
  def test_it_rejects_methods_the_api_does_not_use
    assert_raises(ArgumentError) do
      IbanChecker::Transport::NetHttp.new.call("DELETE", "https://example.test/", {}, nil)
    end
  end

  def test_a_connection_failure_is_a_transport_error
    transport = IbanChecker::Transport::NetHttp.new(timeout: 0.5)

    error = assert_raises(IbanChecker::TransportError) do
      # Reserved for documentation by RFC 2606, so it resolves nowhere.
      transport.call("GET", "https://ibanchecker.invalid/api/v1/formats/de", {}, nil)
    end

    assert_includes error.message, "failed"
  end
end
