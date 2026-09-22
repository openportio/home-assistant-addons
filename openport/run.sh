#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -e

# Keep the openport identity key and session database on /data so the tunnel
# address (https://<xxxxx>.u.openport.io) survives restarts and updates.
export HOME=/data

# The openport client dials "localhost:<port>", which glibc resolves to ::1
# first. Home Assistant then sees the proxy as ::1, which is rarely in
# trusted_proxies. Strip "localhost" from the ::1 line in this container's
# /etc/hosts so the client connects over 127.0.0.1 instead. /etc/hosts is a
# bind mount, so rewrite it in place rather than letting sed rename it.
if grep -q "^::1.*localhost" /etc/hosts; then
    HOSTS_CONTENT="$(sed 's/^::1[[:blank:]].*/::1 ip6-localhost ip6-loopback/' /etc/hosts)"
    echo "${HOSTS_CONTENT}" > /etc/hosts
fi

TOKEN="$(bashio::config 'key_registration_token')"
PORT="$(bashio::config 'port')"
KEY_NAME="$(bashio::config 'key_name')"
KEEP_ALIVE="$(bashio::config 'keep_alive_seconds')"

if bashio::var.is_empty "${TOKEN}"; then
    bashio::log.fatal "No key_registration_token configured."
    bashio::log.fatal "Get your token at https://openport.io/user/keys and set it in the add-on configuration."
    bashio::exit.nok
fi

SERVER_ARGS=()
if bashio::config.has_value 'server'; then
    SERVER_ARGS+=(--server "$(bashio::config 'server')")
fi

VERBOSE_ARGS=()
if bashio::config.true 'verbose'; then
    VERBOSE_ARGS+=(--verbose)
fi

# Register the key once per token. The token itself is not stored on disk,
# only a hash to detect configuration changes.
TOKEN_HASH="$(echo -n "${TOKEN}" | sha256sum | cut -d' ' -f1)"
MARKER=/data/.registered_token_hash
if [ ! -f "${MARKER}" ] || [ "$(cat "${MARKER}")" != "${TOKEN_HASH}" ]; then
    bashio::log.info "Registering this Home Assistant with your openport account..."
    openport register-key \
        --token "${TOKEN}" \
        --name "${KEY_NAME}" \
        "${SERVER_ARGS[@]}" "${VERBOSE_ARGS[@]}"
    echo "${TOKEN_HASH}" > "${MARKER}"
    bashio::log.info "Key registered."
else
    bashio::log.info "Key already registered, skipping registration."
fi

ARGS=(--http-forward --local-port "${PORT}" --keep-alive "${KEEP_ALIVE}")

if bashio::config.true 'use_websocket_transport'; then
    ARGS+=(--ws)
fi

if bashio::config.has_value 'ip_link_protection'; then
    if bashio::config.true 'ip_link_protection'; then
        ARGS+=(--ip-link-protection True)
    else
        ARGS+=(--ip-link-protection False)
    fi
fi

# Custom domain: end-to-end encryption on your own domain. The client
# handles the setup itself -- it starts on the standard address, prints the
# CNAME record to create, watches DNS, and switches to a Let's Encrypt
# certificate it terminates here the moment the record resolves. No restart
# needed. See the add-on documentation.
if bashio::config.has_value 'custom_domain'; then
    ARGS+=(--tls-passthrough --domain "$(bashio::config 'custom_domain')")
    bashio::log.info "Custom domain configured; watch this log for the DNS record to create."
fi

bashio::log.info "Starting the openport tunnel to localhost:${PORT}..."

exec openport "${ARGS[@]}" "${SERVER_ARGS[@]}" "${VERBOSE_ARGS[@]}"
