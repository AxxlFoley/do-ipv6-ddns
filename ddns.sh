#!/bin/bash
set -euo pipefail

INTERFACE="${INTERFACE:-br0}"
HOSTNAME="${HOSTNAME:?HOSTNAME is required}"
DO_USER="${DO_USER:?DO_USER is required}"
DO_PASS="${DO_PASS:?DO_PASS is required}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"

STATE_FILE="${STATE_FILE:-/data/current-prefix}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

get_prefix() {
    local prefix

    if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
        log "ERROR: Interface '$INTERFACE' does not exist"
        return 1
    fi

    # The kernel creates a route for the delegated /64 on the LAN interface.
    # Reading the route is more reliable than trying to parse/compress an
    # IPv6 address ourselves.
    prefix="$(
        ip -6 route show dev "$INTERFACE" proto kernel 2>/dev/null \
        | awk '$1 ~ /\/64$/ && $1 !~ /^fe80:/ { print $1; exit }'
    )"

    if [[ -z "$prefix" ]]; then
        log "ERROR: No global IPv6 /64 found on interface '$INTERFACE'"
        return 1
    fi

    echo "$prefix"
}

update_do() {
    local prefix="$1"
    local response

    log "Updating do.de with prefix: $prefix"

    response="$(
        curl -fsS \
            -u "${DO_USER}:${DO_PASS}" \
            --get \
            --data-urlencode "hostname=${HOSTNAME}" \
            --data-urlencode "ip6lanprefix=${prefix}" \
            "https://ddns.do.de/"
    )"

    log "do.de response: $response"

    if [[ "$response" == good* ]]; then
        mkdir -p "$(dirname "$STATE_FILE")"
        printf '%s\n' "$prefix" > "$STATE_FILE"
        log "Prefix successfully updated"
        return 0
    fi

    log "ERROR: do.de did not confirm the update"
    return 1
}

check_prefix() {
    local prefix
    local last_prefix=""

    prefix="$(get_prefix)" || return 1

    log "Current prefix: $prefix"

    if [[ -f "$STATE_FILE" ]]; then
        last_prefix="$(cat "$STATE_FILE")"
        log "Last prefix:    $last_prefix"
    else
        log "Last prefix:    <none>"
    fi

    if [[ "$prefix" == "$last_prefix" ]]; then
        log "Prefix unchanged - no update required"
        return 0
    fi

    log "Prefix changed - updating do.de"
    update_do "$prefix"
}

log "Starting do-ipv6-ddns"
log "Interface:       $INTERFACE"
log "Hostname:        $HOSTNAME"
log "Check interval:  ${CHECK_INTERVAL}s"
log "State file:      $STATE_FILE"

while true; do
    check_prefix || true
    sleep "$CHECK_INTERVAL"
done
