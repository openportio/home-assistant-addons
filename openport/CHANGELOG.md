# Changelog

## 1.1.0

- Add the `custom_domain` option: serve Home Assistant on your own domain
  with a Let's Encrypt certificate that the add-on holds and terminates
  itself, so the openport servers only relay encrypted bytes they cannot
  read (end-to-end encryption). The add-on guides the CNAME setup in the log
  and stays on the standard address until the domain resolves, so it never
  crash-loops while DNS propagates.
- Requires the openport client's TLS-passthrough support.

## 1.0.1

- Connect to Home Assistant over 127.0.0.1 instead of ::1, so only
  `127.0.0.1` needs to be in `http.trusted_proxies`.

## 1.0.0

- Initial release: openport http-forward tunnel to the Home Assistant
  frontend, with WebSocket support.
- Openport client v2.2.3.
