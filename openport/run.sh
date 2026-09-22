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

CUSTOM_DOMAIN=""
if bashio::config.has_value 'custom_domain'; then
    CUSTOM_DOMAIN="$(bashio::config 'custom_domain')"
fi

# ---------------------------------------------------------------------------
# Supervisor.
#
# Without a custom domain this just runs the client. With one, it manages the
# switch to end-to-end encryption for you: it starts in the normal
# http-forward mode, watches DNS in the background, and the moment your CNAME
# points at this add-on's forwarding address it swaps the client over to
# TLS passthrough (a Let's Encrypt certificate held and terminated here). No
# restart needed -- set the option, create the CNAME whenever, and it flips
# itself over.
#
# We manage the client as a child process (not exec) so we can restart it in
# place; forward the stop signal so the add-on shuts down cleanly.
# ---------------------------------------------------------------------------
set +e

ADDR_FILE=/data/forwarding_address
OPENPORT_LOG=/data/.openport/openport.log
CLIENT_PID=""
SLEEP_PID=""

stop() {
    trap - TERM INT
    [ -n "${SLEEP_PID}" ] && kill "${SLEEP_PID}" 2>/dev/null
    [ -n "${CLIENT_PID}" ] && kill "${CLIENT_PID}" 2>/dev/null
    exit 0
}
trap stop TERM INT

# sleep that returns immediately when the add-on is asked to stop
poll_sleep() {
    sleep "$1" &
    SLEEP_PID=$!
    wait "${SLEEP_PID}" 2>/dev/null
    SLEEP_PID=""
}

start_client() {
    openport "${ARGS[@]}" "$@" "${SERVER_ARGS[@]}" "${VERBOSE_ARGS[@]}" &
    CLIENT_PID=$!
}

# The openport forwarding address (abcd.u...openport.io) from the client log,
# also persisted to /data so a later start knows it before connecting.
read_address() {
    local a=""
    [ -f "${ADDR_FILE}" ] && a="$(cat "${ADDR_FILE}")"
    if [ -z "${a}" ] && [ -f "${OPENPORT_LOG}" ]; then
        a="$(grep -oE '[a-z0-9]+\.u\.[a-z0-9.]*openport\.(io|xyz)' "${OPENPORT_LOG}" 2>/dev/null | tail -1)"
        [ -n "${a}" ] && echo "${a}" > "${ADDR_FILE}"
    fi
    echo "${a}"
}

# resolved IP for a name (follows CNAME); empty if it does not resolve yet
resolve_ip() {
    getent hosts "$1" 2>/dev/null | awk '{print $1; exit}'
}

# does the custom domain now point at our forwarding address?
cname_ready() {
    local addr="$1" dip aip
    [ -n "${addr}" ] || return 1
    dip="$(resolve_ip "${CUSTOM_DOMAIN}")"
    aip="$(resolve_ip "${addr}")"
    [ -n "${dip}" ] && [ "${dip}" = "${aip}" ]
}

# ---- No custom domain: plain http-forward, nothing to supervise. ----------
if [ -z "${CUSTOM_DOMAIN}" ]; then
    bashio::log.info "Starting the openport tunnel to localhost:${PORT}..."
    bashio::log.info "Your public address will appear in the log below (https://<xxxxx>.u.openport.io)."
    start_client
    wait "${CLIENT_PID}"
    exit $?
fi

# ---- Custom domain already routable at startup: go straight to passthrough.
if cname_ready "$(read_address)"; then
    bashio::log.info "Custom domain ${CUSTOM_DOMAIN} is routable."
    bashio::log.info "Serving HTTPS with a Let's Encrypt certificate that terminates inside this add-on."
    bashio::log.info "End-to-end encrypted: the openport servers cannot read your traffic."
    ARGS+=(--tls-passthrough --domain "${CUSTOM_DOMAIN}")
    start_client
    wait "${CLIENT_PID}"
    exit $?
fi

# ---- Custom domain set but not routable yet: run normally and wait. --------
bashio::log.info "Custom domain ${CUSTOM_DOMAIN} is configured but not routable yet."
bashio::log.info "Starting in standard mode and watching DNS; will switch automatically."
start_client

announced=false
while true; do
    # Keep the tunnel up if the client exited for any reason.
    if ! kill -0 "${CLIENT_PID}" 2>/dev/null; then
        start_client
    fi

    ADDR="$(read_address)"

    if [ -n "${ADDR}" ] && [ "${announced}" = false ]; then
        bashio::log.info "-----------------------------------------------------------------"
        bashio::log.info "To enable your custom domain ${CUSTOM_DOMAIN} (end-to-end encryption):"
        bashio::log.info "  Create this DNS record at your domain provider:"
        bashio::log.info "      ${CUSTOM_DOMAIN}.   CNAME   ${ADDR}."
        bashio::log.info "  No restart needed -- this add-on will switch over automatically"
        bashio::log.info "  within a minute of the record propagating."
        bashio::log.info "-----------------------------------------------------------------"
        announced=true
    fi

    if cname_ready "${ADDR}"; then
        bashio::log.info "Detected ${CUSTOM_DOMAIN} -> ${ADDR}. Switching to end-to-end encryption..."
        kill "${CLIENT_PID}" 2>/dev/null
        wait "${CLIENT_PID}" 2>/dev/null
        ARGS+=(--tls-passthrough --domain "${CUSTOM_DOMAIN}")
        start_client
        bashio::log.info "Now serving https://${CUSTOM_DOMAIN} with a Let's Encrypt certificate held by this add-on."
        break
    fi

    poll_sleep 20
done

wait "${CLIENT_PID}"
exit $?
