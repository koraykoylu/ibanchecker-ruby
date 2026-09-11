# frozen_string_literal: true

module IbanChecker
  # One segment of a country's BBAN, in the order it appears in the IBAN.
  class BbanField
    attr_reader :label, :length, :type, :description

    # The untouched field object from the API response.
    attr_reader :raw

    def initialize(label: nil, length: nil, type: nil, description: nil, raw: {})
      @label = label
      @length = length
      @type = type
      @description = description
      @raw = raw
    end

    def self.from_api(data)
      new(
        label: data["label"],
        length: data["length"],
        type: data["type"],
        description: data["description"],
        raw: data
      )
    end
  end

  # The result of validating one IBAN.
  #
  # +valid?+ is the primary flag. When it is false only +iban+, +formatted+,
  # +country+, +country_name+, +error+ and +error_code+ are populated.
  #
  # +valid?+ is the only predicate method here because it is the only field
  # that is always a boolean. +sepa+ and +national_check_valid+ can each be
  # nil, so they are plain readers and nil means "not known for this IBAN".
  class ValidationResult
    ATTRIBUTES = %i[
      iban formatted check_digits bban country country_name
      bank_name bank_type bic bank_city bank_code branch_code account_number
      national_check_valid currency currency_name transfer_type sepa flag
      error error_code
    ].freeze

    attr_reader(*ATTRIBUTES)

    # The untouched response body.
    attr_reader :raw

    def initialize(valid:, iban:, raw: {}, **rest)
      @valid = valid
      @iban = iban
      @raw = raw
      ATTRIBUTES.each do |name|
        next if name == :iban

        instance_variable_set("@#{name}", rest[name])
      end
    end

    # True when the IBAN passes the ISO 13616 check digit, the country's
    # length and the country's BBAN structure.
    def valid?
      @valid
    end

    def self.from_api(data)
      new(
        valid: data["valid"] == true,
        iban: data["iban"].to_s,
        formatted: data["formatted"],
        check_digits: data["check_digits"],
        bban: data["bban"],
        country: data["country"],
        country_name: data["country_name"],
        bank_name: data["bank_name"],
        bank_type: data["bank_type"],
        bic: data["bic"],
        bank_city: data["bank_city"],
        bank_code: data["bank_code"],
        branch_code: data["branch_code"],
        account_number: data["account_number"],
        national_check_valid: data["national_check_valid"],
        currency: data["currency"],
        currency_name: data["currency_name"],
        transfer_type: data["transfer_type"],
        sepa: data["sepa"],
        flag: data["flag"],
        error: data["error"],
        error_code: data["error_code"],
        raw: data
      )
    end

    # Kept short on purpose: the default would print the whole raw body, which
    # makes an irb session unreadable.
    def inspect
      detail = valid? ? "valid #{bank_name || 'bank not in directory'}" : "invalid #{error_code}"
      "#<#{self.class} #{iban} #{detail}>"
    end
  end

  # The result of a bulk validation or a text extraction.
  #
  # The object is enumerable: iterating it walks the per-IBAN results in input
  # order. +count+ is the API's own count rather than Enumerable#count, so use
  # +results.count { ... }+ if you want the block form.
  class BatchResult
    include Enumerable

    attr_reader :count, :valid_count, :invalid_count, :results

    # The untouched response body.
    attr_reader :raw

    def initialize(count: 0, valid_count: 0, invalid_count: 0, results: [], raw: {})
      @count = count
      @valid_count = valid_count
      @invalid_count = invalid_count
      @results = results
      @raw = raw
    end

    def each(&block)
      @results.each(&block)
    end

    def size
      @results.size
    end

    def self.from_api(data)
      rows = data["results"]
      results = rows.is_a?(Array) ? rows.select { |row| row.is_a?(Hash) }.map { |row| ValidationResult.from_api(row) } : []

      new(
        count: data["count"] || 0,
        valid_count: data["valid_count"] || 0,
        invalid_count: data["invalid_count"] || 0,
        results: results,
        raw: data
      )
    end
  end

  # The IBAN format specification for one country.
  class FormatSpec
    attr_reader :country_code, :country_name, :length, :currency, :currency_name,
                :sepa, :swift, :format_string, :example, :bban_fields

    # The untouched response body.
    attr_reader :raw

    def initialize(bban_fields: [], raw: {}, **rest)
      @bban_fields = bban_fields
      @raw = raw
      %i[country_code country_name length currency currency_name sepa swift
         format_string example].each do |name|
        instance_variable_set("@#{name}", rest[name])
      end
    end

    def self.from_api(data)
      fields = data["bban_fields"]
      bban_fields = fields.is_a?(Array) ? fields.select { |f| f.is_a?(Hash) }.map { |f| BbanField.from_api(f) } : []

      new(
        country_code: data["country_code"],
        country_name: data["country_name"],
        length: data["length"],
        currency: data["currency"],
        currency_name: data["currency_name"],
        sepa: data["sepa"],
        swift: data["swift"],
        format_string: data["format_string"],
        example: data["example"],
        bban_fields: bban_fields,
        raw: data
      )
    end
  end

  # The institution behind a SWIFT/BIC code.
  class BankRecord
    ATTRIBUTES = %i[
      bic bic8 bank_code country_code location_code branch_code
      bank_name city country_name sepa type status
    ].freeze

    attr_reader(*ATTRIBUTES)

    # The untouched response body.
    attr_reader :raw

    def initialize(raw: {}, **rest)
      @raw = raw
      ATTRIBUTES.each { |name| instance_variable_set("@#{name}", rest[name]) }
    end

    def self.from_api(data)
      new(
        bic: data["bic"],
        bic8: data["bic8"],
        bank_code: data["bank_code"],
        country_code: data["country_code"],
        location_code: data["location_code"],
        branch_code: data["branch_code"],
        bank_name: data["bank_name"],
        city: data["city"],
        country_name: data["country_name"],
        sepa: data["sepa"],
        type: data["type"],
        status: data["status"],
        raw: data
      )
    end
  end
end
