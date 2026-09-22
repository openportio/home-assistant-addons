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

# ---------------------------------------------------------------------------
# Custom domain / end-to-end encryption.
#
# With a custom domain the add-on terminates TLS itself (Let's Encrypt),
# instead of on the openport servers, so the tunnel only relays bytes it
# cannot decrypt. That needs a CNAME from your domain to this add-on's
# forwarding address -- which you only learn after the first connection --
# so the flow is: start once, read the address below, create the CNAME, set
# the option, restart. Until the CNAME resolves we keep running in the normal
# http-forward mode rather than failing, so the add-on never crash-loops.
# ---------------------------------------------------------------------------
ADDR_FILE=/data/forwarding_address
OPENPORT_LOG=/data/.openport/openport.log

# first non-empty field of getent (the resolved IP), or empty
resolve_ip() {
    getent hosts "$1" 2>/dev/null | awk '{print $1; exit}'
}

# Persist the forwarding address the client logs, so the next start can
# verify the CNAME against it. Runs in the background and exits once found.
# When a custom domain is set but not yet routable, it also prints the exact
# CNAME line once the address is known.
capture_address() {
    local want_domain="$1" a
    for _ in $(seq 1 90); do
        if [ -f "${OPENPORT_LOG}" ]; then
            a="$(grep -oE '[a-z0-9]+\.u\.[a-z0-9.]*openport\.(io|xyz)' "${OPENPORT_LOG}" 2>/dev/null | tail -1)"
            if [ -n "${a}" ]; then
                echo "${a}" > "${ADDR_FILE}"
                if [ -n "${want_domain}" ]; then
                    bashio::log.info "-----------------------------------------------------------------"
                    bashio::log.info "To finish enabling your custom domain ${want_domain}:"
                    bashio::log.info "  1. Create this DNS record at your domain provider:"
                    bashio::log.info "       ${want_domain}.   CNAME   ${a}."
                    bashio::log.info "  2. Wait a few minutes for it to propagate."
                    bashio::log.info "  3. Restart this add-on to request a Let's Encrypt certificate."
                    bashio::log.info "-----------------------------------------------------------------"
                fi
                return
            fi
        fi
        sleep 2
    done
}

PASSTHROUGH=false
CUSTOM_DOMAIN=""
if bashio::config.has_value 'custom_domain'; then
    CUSTOM_DOMAIN="$(bashio::config 'custom_domain')"
    STORED_ADDR=""
    [ -f "${ADDR_FILE}" ] && STORED_ADDR="$(cat "${ADDR_FILE}")"

    if [ -n "${STORED_ADDR}" ]; then
        DOMAIN_IP="$(resolve_ip "${CUSTOM_DOMAIN}")"
        ADDR_IP="$(resolve_ip "${STORED_ADDR}")"
        if [ -n "${DOMAIN_IP}" ] && [ "${DOMAIN_IP}" = "${ADDR_IP}" ]; then
            PASSTHROUGH=true
        fi
    fi

    if [ "${PASSTHROUGH}" = true ]; then
        ARGS+=(--tls-passthrough --domain "${CUSTOM_DOMAIN}")
        bashio::log.info "Custom domain ${CUSTOM_DOMAIN} is routable."
        bashio::log.info "Serving HTTPS with a Let's Encrypt certificate that terminates inside this add-on."
        bashio::log.info "End-to-end encrypted: the openport servers cannot read your traffic."
    else
        bashio::log.warning "-----------------------------------------------------------------"
        bashio::log.warning "Custom domain ${CUSTOM_DOMAIN} is set but not routable yet."
        if [ -n "${STORED_ADDR}" ]; then
            bashio::log.warning "Create this DNS record, wait for it to propagate, then restart:"
            bashio::log.warning "    ${CUSTOM_DOMAIN}.   CNAME   ${STORED_ADDR}."
        else
            bashio::log.warning "The add-on's forwarding address will be printed below shortly;"
            bashio::log.warning "create a CNAME from ${CUSTOM_DOMAIN} to it, then restart."
        fi
        bashio::log.warning "Running in standard mode (openport-terminated TLS) until then."
        bashio::log.warning "-----------------------------------------------------------------"
    fi
fi

# Keep the forwarding address current for the next start; when a domain is
# set but not yet verified, also print the CNAME instructions once known.
if [ "${PASSTHROUGH}" = true ]; then
    capture_address "" &
else
    capture_address "${CUSTOM_DOMAIN}" &
fi

if [ "${PASSTHROUGH}" = true ]; then
    bashio::log.info "Starting the openport tunnel for https://${CUSTOM_DOMAIN} (local port ${PORT})..."
else
    bashio::log.info "Starting the openport tunnel to localhost:${PORT}..."
    bashio::log.info "Your public address will appear in the log below (https://<xxxxx>.u.openport.io)."
fi

exec openport "${ARGS[@]}" "${SERVER_ARGS[@]}" "${VERBOSE_ARGS[@]}"
