#!/bin/bash
set -euo pipefail

INTERFACE="${INTERFACE:-br0}"
HOSTNAME="${HOSTNAME:?HOSTNAME is required}"
DO_USER="${DO_USER:?DO_USER is required}"
DO_PASS="${DO_PASS:?DO_PASS is required}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"

STATE_FILE="/tmp/current-prefix"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

get_prefix() {
    ip -6 -o addr show dev "$INTERFACE" scope global \
        | awk '$4 ~ /^2a00:/ && $4 ~ /\/64$/ {print $4; exit}' \
        | cut -d: -f1-4 \
        | sed 's/$/::\/64/'
}

while true; do
    PREFIX="$(get_prefix || true)"

    if [[ -z "$PREFIX" ]]; then
        log "Kein globales IPv6-/64 auf $INTERFACE gefunden"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    LAST_PREFIX=""
    [[ -f "$STATE_FILE" ]] && LAST_PREFIX="$(cat "$STATE_FILE")"

    if [[ "$PREFIX" != "$LAST_PREFIX" ]]; then
        log "Neuer IPv6-Prefix erkannt: $PREFIX"

        RESPONSE="$(
            curl -fsS \
                -u "${DO_USER}:${DO_PASS}" \
                --get \
                --data-urlencode "hostname=${HOSTNAME}" \
                --data-urlencode "ip6lanprefix=${PREFIX}" \
                "https://ddns.do.de/"
        )"

        log "do.de: $RESPONSE"

        if [[ "$RESPONSE" == good* ]]; then
            printf '%s\n' "$PREFIX" > "$STATE_FILE"
            log "Prefix erfolgreich bei do.de aktualisiert"
        else
            log "FEHLER: do.de hat den Request nicht bestätigt"
        fi
    fi

    sleep "$CHECK_INTERVAL"
done