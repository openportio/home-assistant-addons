# Openport add-on

This add-on runs the [openport](https://openport.io) client with an
http-forward tunnel pointed at your Home Assistant. Your installation becomes
reachable on a stable public address like `https://abcde.u.openport.io`,
without any port forwarding or firewall changes. The tunnel supports
WebSockets, so the Home Assistant frontend and the companion apps work
normally.

## Setup

1. Create an account at [openport.io](https://openport.io) if you don't have
   one.
2. Go to <https://openport.io/user/keys> and copy your **key registration
   token**.
3. Install this add-on and paste the token into the
   `key_registration_token` option.
4. Allow proxied requests in Home Assistant: the tunnel reaches your
   installation through a local proxy, so `configuration.yaml` needs:

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 127.0.0.1
   ```

   Restart Home Assistant after adding this. Without it, requests through
   the tunnel fail with `400: Bad Request`.
5. Start the add-on and open the log. After a few seconds it prints your
   public address, e.g.:

   ```
   Now forwarding remote address abcde.u.openport.io to localhost
   ```

   Your Home Assistant is now reachable at `https://abcde.u.openport.io`.

6. Tell Home Assistant about its new external address: go to
   **Settings → System → Network** and set the **External URL** to
   `https://<xxxxx>.u.openport.io` (or set `homeassistant.external_url` in
   `configuration.yaml`). The companion apps can use this URL as their
   server address.

The address is tied to this add-on's stored session and key (kept in the
add-on's `/data`), so it stays the same across restarts, reboots, and add-on
updates. Uninstalling the add-on discards it.

## Options

### `key_registration_token` (required)

The token that links this machine to your openport account. Find it at
<https://openport.io/user/keys>. Registration happens once, on the first
start; the token itself is not stored on disk afterwards.

### `port`

The local port the tunnel forwards to. Default `8123`, the Home Assistant
frontend. You normally don't need to change this, but you can point the
tunnel at any other service running on the host.

### `key_name`

The name this machine gets in your key list on openport.io. Default
`home-assistant`.

### `keep_alive_seconds`

Interval between keep-alive messages on the tunnel. Default `120`.

### `use_websocket_transport`

Connect to the openport servers over the WebSocket protocol (port 443)
instead of SSH. Useful on networks that block outbound SSH. Default `false`.

### `custom_domain` (optional)

Your own domain, e.g. `ha.example.com`. When set, the add-on serves HTTPS
for that domain with its own Let's Encrypt certificate and **terminates TLS
inside the add-on**, so the openport servers only relay encrypted bytes they
cannot read. Leave it empty to use the standard `https://<xxxxx>.u.openport.io`
address (where TLS terminates on the openport servers). See
[Your own domain (end-to-end encryption)](#your-own-domain-end-to-end-encryption)
for the setup steps.

### `ip_link_protection` (optional)

When enabled, visitors must first click a secret link before they can reach
your Home Assistant. This adds a layer in front of the Home Assistant login
but can get in the way of the companion apps. When unset, the setting from
your openport.io profile applies.

### `verbose`

Enable debug logging of the openport client.

## Security considerations

- Your Home Assistant login page becomes reachable from the internet. Make
  sure every user has a strong password, and consider enabling
  [multi-factor authentication](https://www.home-assistant.io/docs/authentication/multi-factor-auth/).
- The tunnel endpoint is HTTPS; traffic between the openport server and your
  Home Assistant travels through the encrypted tunnel.
- `ip_link_protection` adds a shared-secret gate in front of everything, at
  the cost of app compatibility.

## Trust model

Be aware of what the tunnel can and cannot see:

- On the default `https://<xxxxx>.u.openport.io` address, TLS terminates on
  the openport servers. The last hop to your Home Assistant travels through
  the encrypted tunnel, but the openport server sits in the middle of the
  connection and could technically read the traffic, including login
  credentials. Every hosted tunnel that presents a valid certificate on your
  behalf (Home Assistant Cloud, Cloudflare Tunnel) is in the same position;
  it is inherent to how these services work, not specific to openport.
- With a [custom domain](#your-own-domain-end-to-end-encryption), TLS instead
  terminates inside this add-on, so the openport servers only relay encrypted
  bytes they cannot read. This is the end-to-end option.
- The [openport client is open source](https://github.com/openportio/openport-go).
  The server side is not.

## Your own domain (end-to-end encryption)

Set the `custom_domain` option to serve Home Assistant on your own domain
(e.g. `ha.example.com`) with a Let's Encrypt certificate that is obtained and
held **by this add-on**. The openport servers route your domain's traffic by
name without decrypting it, so they never see your traffic or your
certificate's private key.

Your domain has to point at this add-on's forwarding address, which you only
learn once the add-on is running — so the add-on guides you and switches
over on its own, no restart required:

1. **Set `custom_domain`** to your domain (e.g. `ha.example.com`) and start
   the add-on. It begins on the standard `u.openport.io` address and, once
   connected, prints your forwarding address and the exact DNS record to
   create:

   ```
   To serve https://ha.example.com with end-to-end encryption, create this DNS record:
       ha.example.com.   CNAME   abcde.u.openport.io.
   No restart needed: this will switch over automatically within a
   minute of the record propagating.
   ```

2. **Create that CNAME record** at your DNS provider (note the trailing dot
   where your provider expects one). Your Home Assistant stays reachable on
   the standard address the whole time.

3. **Wait.** The add-on watches DNS in the background. Within about a minute
   of the record propagating, it requests a Let's Encrypt certificate
   (validated through the tunnel — no extra ports or DNS credentials) and
   switches over automatically:

   ```
   Detected ha.example.com -> abcde.u.openport.io. Reconnecting to enable end-to-end encryption...
   Now forwarding https://ha.example.com to localhost:8123 (TLS terminates on this machine)
   ```

4. Set **Settings → System → Network → External URL** to
   `https://ha.example.com` and point the companion apps there.

If the record is already in place when the add-on starts (for example after
a reboot), it switches within a minute of connecting.

Notes for this mode:

- **Home Assistant must serve plain HTTP** on the `port` (the default 8123).
  The add-on terminates TLS and forwards plain HTTP to it; do not also enable
  TLS inside Home Assistant.
- **You do not need the `trusted_proxies` / `use_x_forwarded_for` settings**
  from step 4 of Setup in this mode. The trade-off is that Home Assistant
  sees requests coming from `127.0.0.1` rather than each visitor's real IP.
- **Harden issuance (recommended):** add a CAA record so only your own
  Let's Encrypt account can issue for the domain, in case the CNAME ever
  outlives this add-on:

  ```
  ha.example.com.   CAA   0 issue "letsencrypt.org"
  ```

- **Remove the CNAME when you stop using it.** A CNAME left pointing at a
  forwarding address you no longer hold could later route your domain to
  whoever is assigned that address.

## Troubleshooting

- **The log says the key registration failed**: check that the token was
  copied completely from <https://openport.io/user/keys>. Changing the token
  in the configuration triggers a new registration on the next start.
- **The address changed**: the session is stored in the add-on's private
  data. It survives restarts and updates, but uninstalling the add-on (or
  removing the session on openport.io) releases the address.
- **Connection refused errors in the log**: the add-on reaches Home Assistant
  on `localhost:<port>` via the host network; verify the `port` option
  matches the port Home Assistant actually listens on.
