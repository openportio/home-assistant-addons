# Changelog

## 1.1.0

- Add the `custom_domain` option: serve Home Assistant on your own domain
  with a Let's Encrypt certificate that the add-on holds and terminates
  itself, so the openport servers only relay encrypted bytes they cannot
  read (end-to-end encryption).
- Bring your own certificate for the custom domain: the `certfile` and
  `keyfile` options serve a certificate from `/ssl` (where the Let's Encrypt
  add-on and others keep theirs) instead of the automatic Let's Encrypt one.
- Guided, hands-off setup: the add-on runs on the standard address, prints
  the exact CNAME record to create, watches DNS in the background, and
  switches to your domain automatically once the record propagates — no
  restart needed, and it never crash-loops while you wait.
- Openport client v2.3.0 (the first release with TLS-passthrough support),
  now installed from the signed apt repository at https://openport.io/apt
  instead of a bare GitHub release binary.

## 1.0.1

- Connect to Home Assistant over 127.0.0.1 instead of ::1, so only
  `127.0.0.1` needs to be in `http.trusted_proxies`.

## 1.0.0

- Initial release: openport http-forward tunnel to the Home Assistant
  frontend, with WebSocket support.
- Openport client v2.2.3.
