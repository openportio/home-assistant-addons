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

- The public `https://<xxxxx>.u.openport.io` endpoint terminates TLS on the
  openport servers. The last hop to your Home Assistant travels through the
  encrypted tunnel, but the openport server sits in the middle of the
  connection and could technically read the traffic, including login
  credentials. Every hosted tunnel that presents a valid certificate on your
  behalf (Home Assistant Cloud, Cloudflare Tunnel) is in the same position;
  it is inherent to how these services work, not specific to openport.
- The [openport client is open source](https://github.com/openportio/openport-go).
  The server side is not.

If you want end-to-end encryption, where the tunnel only relays bytes it
cannot decrypt, the openport client also supports plain port forwarding:

1. Configure Home Assistant itself for TLS (`http.ssl_certificate` and
   `http.ssl_key` in `configuration.yaml`, or the NGINX SSL proxy app).
2. Forward that TLS port with the
   [standalone openport client](https://openport.io/download) in its default
   mode (without `--http-forward`). You then connect to an address like
   `openport.io:<port>`, and only your Home Assistant can decrypt the
   traffic. Expect a certificate warning unless your certificate covers the
   name you connect to.

This add-on always uses http-forward mode: that is what provides the stable
`u.openport.io` address and working WebSockets without any TLS setup on your
side.

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
