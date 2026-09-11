# Changelog

## 0.1.0

First release.

- `validate`, `validate_bulk`, `extract`, `country_format` and `lookup_bic`
- Typed models for every response, with the raw body kept on `#raw`
- Typed errors for 400, 401, 404, 429, other statuses and transport failures;
  a malformed IBAN is a result with `valid?` false, never an error
- No runtime dependencies; ships a `net/http` transport and accepts anything
  responding to `call(method, url, headers, body)` instead
