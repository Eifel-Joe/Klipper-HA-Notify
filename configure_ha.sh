#!/usr/bin/env bash
# configure_ha.sh — Home Assistant Verbindung für Klipper-HA-Notify ändern
# https://github.com/Eifel-Joe/Klipper-HA-Notify
set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-${HOME}/printer_data/scripts}"
NOTIFY_CONF="${NOTIFY_CONF:-${SCRIPTS_DIR}/klipper_ha_notify.conf}"

# ── Farben ────────────────────────────────────────────────────────────────────
C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'
C_DIM='\033[2m'

say()  { echo -e "$*"; }
ok()   { echo -e "  ${C_GREEN}✔${C_RESET} $*"; }
warn() { echo -e "  ${C_YELLOW}⚠${C_RESET} $*"; }
err()  { echo -e "  ${C_RED}✘${C_RESET} $*"; }
sep()  { echo -e "${C_DIM}────────────────────────────────────────────────────${C_RESET}"; }

# ── Konfig lesen ──────────────────────────────────────────────────────────────
read_conf() {
    HA_URL=""
    HA_TOKEN=""
    HA_SERVICE=""
    if [ -f "${NOTIFY_CONF}" ]; then
        HA_URL="$(grep    '^HA_URL='     "${NOTIFY_CONF}" | cut -d= -f2- || true)"
        HA_TOKEN="$(grep  '^HA_TOKEN='   "${NOTIFY_CONF}" | cut -d= -f2- || true)"
        HA_SERVICE="$(grep '^HA_SERVICE=' "${NOTIFY_CONF}" | cut -d= -f2- || true)"
    fi
}

# ── Konfig schreiben ─────────────────────────────────────────────────────────
write_conf() {
    mkdir -p "${SCRIPTS_DIR}"
    cat > "${NOTIFY_CONF}" << CONF
# Klipper-HA-Notify Konfiguration
# Generiert von configure_ha.sh — nicht in Git committen
HA_URL=${HA_URL}
HA_TOKEN=${HA_TOKEN}
HA_SERVICE=${HA_SERVICE}
CONF
    chmod 600 "${NOTIFY_CONF}"
    ok "Gespeichert: ${NOTIFY_CONF} (chmod 600)"
}

# ── Token maskieren ───────────────────────────────────────────────────────────
mask_token() {
    local t="$1"
    if [ -z "${t}" ]; then echo "(nicht gesetzt)"; return; fi
    local len=${#t}
    if [ "${len}" -le 8 ]; then echo "****"; return; fi
    echo "${t:0:4}…${t: -4} (${len} Zeichen)"
}

# ── Home Assistant suchen ─────────────────────────────────────────────────────
detect_ha() {
    DETECTED_HOST=""
    if ping -c1 -W2 homeassistant.local &>/dev/null 2>&1; then
        say "  ${C_GREEN}Home Assistant gefunden: homeassistant.local${C_RESET}"
        local _ip; _ip="$(getent hosts homeassistant.local 2>/dev/null | awk '{print $1; exit}')"
        if [ -n "${_ip}" ]; then
            DETECTED_HOST="${_ip}"
            say "  ${C_GREEN}IP-Adresse: ${_ip}${C_RESET}"
        else
            DETECTED_HOST="homeassistant.local"
        fi
    fi
}

# ── Notify-Services aus HA-API abrufen ────────────────────────────────────────
fetch_notify_services() {
    # Gibt Liste der verfügbaren notify.*-Services aus, je eine Zeile
    local url="$1" token="$2"
    if ! command -v curl &>/dev/null; then return 1; fi
    curl -sf -m 5 \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        "${url%/}/api/services" 2>/dev/null \
    | grep -o '"domain":"notify"[^}]*"service":"[^"]*"' \
    | grep -o '"service":"[^"]*"' \
    | cut -d'"' -f4 \
    | sort
}

# ════════════════════════════════════════════════════════════════════════════════
# Menü-Aktionen
# ════════════════════════════════════════════════════════════════════════════════

# ── 1. Verbindung (Host + Port) ───────────────────────────────────────────────
change_connection() {
    sep
    say "\n${C_BOLD}Verbindung ändern${C_RESET} (Host + Port)\n"

    detect_ha

    # Aktuelle Werte zerlegen
    local cur_host cur_port
    if [ -n "${HA_URL}" ]; then
        cur_host="$(echo "${HA_URL}" | sed 's|^https\?://||; s|:.*||')"
        cur_port="$(echo "${HA_URL}" | sed 's|.*:||; s|/.*||')"
    fi

    local default_host="${DETECTED_HOST:-${cur_host:-192.168.x.x}}"
    local default_port="${cur_port:-8123}"

    say "  Aktuell: ${C_CYAN}${HA_URL:-nicht gesetzt}${C_RESET}"
    say ""

    printf '  Hostname / IP (Enter = %s): ' "${default_host}"
    read -r _host || _host=""
    local new_host="${_host:-${default_host}}"
    if [ -z "${new_host}" ] || [ "${new_host}" = "192.168.x.x" ]; then
        err "Kein gültiger Hostname. Abbruch."; return
    fi

    printf '  Port (Enter = %s): ' "${default_port}"
    read -r _port || _port=""
    local new_port="${_port:-${default_port}}"

    HA_URL="http://${new_host}:${new_port}"
    say "  ${C_GREEN}Neue URL: ${HA_URL}${C_RESET}"
    write_conf
}

# ── 2. Token ──────────────────────────────────────────────────────────────────
change_token() {
    sep
    say "\n${C_BOLD}Token ändern${C_RESET}\n"
    say "  Aktuell: ${C_CYAN}$(mask_token "${HA_TOKEN}")${C_RESET}"
    say "  Neues Long-Lived Access Token eingeben (Eingabe wird nicht angezeigt):"
    printf '  Token: '
    read -rs _tok || _tok=""
    echo ""
    if [ -z "${_tok}" ]; then
        warn "Keine Eingabe — Token unverändert."; return
    fi
    HA_TOKEN="${_tok}"
    ok "Token aktualisiert."
    write_conf
}

# ── 3. Notify-Service ─────────────────────────────────────────────────────────
change_service() {
    sep
    say "\n${C_BOLD}Notify-Service ändern${C_RESET}\n"
    say "  Aktuell: ${C_CYAN}${HA_SERVICE:-nicht gesetzt}${C_RESET}"
    say ""

    # Automatische Erkennung nur wenn URL + Token vorhanden
    local services=()
    if [ -n "${HA_URL}" ] && [ -n "${HA_TOKEN}" ]; then
        say "  Suche verfügbare Notify-Services in Home Assistant…"
        local raw_services
        raw_services="$(fetch_notify_services "${HA_URL}" "${HA_TOKEN}" 2>/dev/null || true)"
        if [ -n "${raw_services}" ]; then
            while IFS= read -r svc; do
                [ -n "${svc}" ] && services+=("notify.${svc}")
            done <<< "${raw_services}"
        fi
    fi

    if [ "${#services[@]}" -gt 0 ]; then
        say "  Gefundene Services:"
        local i=1
        for svc in "${services[@]}"; do
            if [ "${svc}" = "${HA_SERVICE}" ]; then
                say "    ${C_BOLD}${i})${C_RESET} ${svc} ${C_GREEN}← aktuell${C_RESET}"
            else
                say "    ${i}) ${svc}"
            fi
            (( i++ ))
        done
        say "    ${i}) Direkt eingeben"
        say ""
        printf '  Auswahl (Enter = aktuell behalten): '
        read -r _sel || _sel=""

        if [ -z "${_sel}" ]; then
            warn "Unverändert: ${HA_SERVICE}"; return
        fi

        if [[ "${_sel}" =~ ^[0-9]+$ ]] && [ "${_sel}" -ge 1 ] && [ "${_sel}" -lt "${i}" ]; then
            HA_SERVICE="${services[$(( _sel - 1 ))]}"
        elif [[ "${_sel}" =~ ^[0-9]+$ ]] && [ "${_sel}" -eq "${i}" ]; then
            : # Direkteingabe unten
        else
            # Direkte Texteingabe auch erlaubt (z.B. "notify.xyz")
            HA_SERVICE="${_sel}"
            ok "Service gesetzt: ${HA_SERVICE}"
            write_conf
            return
        fi
    fi

    # Direkteingabe (kein API-Ergebnis oder Nutzerwahl "direkt")
    if [ "${#services[@]}" -eq 0 ] || [[ "${_sel:-}" =~ ^[0-9]+$ && "${_sel}" -eq $(( ${#services[@]} + 1 )) ]]; then
        say "  Beispiel: notify.mobile_app_mein_iphone"
        printf '  Notify-Service (Enter = behalten): '
        read -r _svc || _svc=""
        if [ -z "${_svc}" ]; then
            warn "Unverändert: ${HA_SERVICE}"; return
        fi
        HA_SERVICE="${_svc}"
    fi

    ok "Service gesetzt: ${HA_SERVICE}"
    write_conf
}

# ════════════════════════════════════════════════════════════════════════════════
# Hauptprogramm
# ════════════════════════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

read_conf

# Permissions auto-fix
if [ -f "${NOTIFY_CONF}" ]; then
    _perms="$(stat -c "%a" "${NOTIFY_CONF}" 2>/dev/null || echo "unknown")"
    if [ "${_perms}" != "600" ] && [ "${_perms}" != "unknown" ]; then
        chmod 600 "${NOTIFY_CONF}"
        warn "Berechtigungen korrigiert: ${NOTIFY_CONF} (jetzt 600)"
    fi
fi

while true; do
    say ""
    say "${C_BOLD}════════════════════════════════════════════════════${C_RESET}"
    say "${C_BOLD}  Klipper-HA-Notify — Verbindung konfigurieren${C_RESET}"
    say "${C_BOLD}════════════════════════════════════════════════════${C_RESET}"
    say ""
    say "  Aktuelle Einstellungen:"
    say "  ${C_DIM}URL:    ${C_RESET}${C_CYAN}${HA_URL:-nicht gesetzt}${C_RESET}"
    say "  ${C_DIM}Token:  ${C_RESET}${C_CYAN}$(mask_token "${HA_TOKEN}")${C_RESET}"
    say "  ${C_DIM}Service:${C_RESET}${C_CYAN}${HA_SERVICE:-nicht gesetzt}${C_RESET}"
    say ""
    say "  1) Verbindung ändern (Host + Port)"
    say "  2) Token ändern"
    say "  3) Notify-Service ändern"
    say "  0) Beenden"
    say ""
    printf '  Auswahl: '
    read -r _choice || _choice="0"

    case "${_choice}" in
        1) change_connection ;;
        2) change_token      ;;
        3) change_service    ;;
        0) say ""; say "  Tschüss!"; say ""; break ;;
        *) warn "Ungültige Auswahl." ;;
    esac
done

fi # end main
