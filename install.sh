#!/bin/bash
# Interaktiver Installer für Klipper-HA-Notify.
#
# Zeigt den aktuellen Installationsstatus aller Komponenten und führt
# dann die gewählten Schritte aus. Jeder Schritt ist idempotent.
#
# Pfade können via Umgebungsvariablen überschrieben werden:
#   KLIPPER_DIR          (default: ~/klipper)
#   PRINTER_CFG_DIR      (default: ~/printer_data/config)
#   SCRIPTS_DIR          (default: ~/printer_data/scripts)
#   MOONRAKER_CONF       (default: ~/printer_data/config/moonraker.conf)
#   KLIPPER_SERVICE      (default: klipper)

set -eu

KLIPPER_DIR="${KLIPPER_DIR:-${HOME}/klipper}"
PRINTER_CFG_DIR="${PRINTER_CFG_DIR:-${HOME}/printer_data/config}"
SCRIPTS_DIR="${SCRIPTS_DIR:-${HOME}/printer_data/scripts}"
MOONRAKER_CONF="${MOONRAKER_CONF:-${PRINTER_CFG_DIR}/moonraker.conf}"
KLIPPER_SERVICE="${KLIPPER_SERVICE:-klipper}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")" && pwd)}"
REPO_URL="https://github.com/Eifel-Joe/Klipper-HA-Notify.git"

EXT_SOURCE="${REPO_DIR}/klipper_extras/notify_ha.py"
EXT_TARGET="${KLIPPER_DIR}/klippy/extras/notify_ha.py"
NOTIFY_CONF="${SCRIPTS_DIR}/klipper_ha_notify.conf"
PRINTER_CFG="${PRINTER_CFG_DIR}/printer.cfg"
INCLUDE_LINE="[include ~/Klipper-HA-Notify/ha_notify.cfg]"
INCLUDE_PATTERN='^\s*\[include[[:space:]]*~/Klipper-HA-Notify/ha_notify\.cfg\]'

# ---------- Farben ----------
if [ -t 1 ]; then
    C_BOLD='\033[1m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[1;33m'; C_CYAN='\033[0;36m'; C_RESET='\033[0m'
else
    C_BOLD=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_RESET=''
fi

say()  { printf '%b\n' "$*"; }
ok()   { printf '%b✔%b %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
miss() { printf '%b✘%b %s\n' "${C_RED}"   "${C_RESET}" "$*"; }
warn() { printf '%b!%b %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
hr()   { printf '%b--------------------------------------------------------------------%b\n' "${C_CYAN}" "${C_RESET}"; }

ask_yn() {
    local prompt="$1" default="${2:-n}" yn
    if [ "$default" = "y" ]; then
        printf '%b?%b %s [Y/n]: ' "${C_CYAN}" "${C_RESET}" "$prompt"
    else
        printf '%b?%b %s [y/N]: ' "${C_CYAN}" "${C_RESET}" "$prompt"
    fi
    read -r yn || yn=""
    yn="${yn:-$default}"
    case "$yn" in [yY]|[yY][eE][sS]|[jJ]|[jJ][aA]) return 0 ;; *) return 1 ;; esac
}

# ---------- Status ermitteln ----------

status_extension() {
    if [ -L "${EXT_TARGET}" ]; then
        local link; link="$(readlink "${EXT_TARGET}")"
        if [ "${link}" = "${EXT_SOURCE}" ]; then echo "installed"
        else echo "wrong_symlink:${link}"; fi
    elif [ -e "${EXT_TARGET}" ]; then echo "regular_file"
    else echo "missing"; fi
}

status_conf() {
    [ -f "${NOTIFY_CONF}" ] || { echo "missing"; return; }
    local url="" token="" svc="" k v
    while IFS='=' read -r k v; do
        k="${k## }"; k="${k%% }"; v="${v## }"; v="${v%% }"
        case "$k" in
            HA_URL)     url="$v"   ;;
            HA_TOKEN)   token="$v" ;;
            HA_SERVICE) svc="$v"   ;;
        esac
    done < <(grep -v '^\s*#' "${NOTIFY_CONF}" 2>/dev/null | grep '=' || true)
    local missing=""
    [ -z "$url"   ] && missing="${missing}HA_URL,"
    [ -z "$token" ] && missing="${missing}HA_TOKEN,"
    [ -z "$svc"   ] && missing="${missing}HA_SERVICE,"
    missing="${missing%,}"
    if [ -z "$missing" ]; then echo "complete"
    else echo "incomplete:${missing}"; fi
}

status_printer_cfg_include() {
    [ -f "${PRINTER_CFG}" ] || { echo "no_printer_cfg"; return; }
    if grep -qE "${INCLUDE_PATTERN}" "${PRINTER_CFG}"; then echo "present"
    else echo "missing"; fi
}

status_conf_perms() {
    [ -f "${NOTIFY_CONF}" ] || { echo "no_file"; return; }
    local perms; perms="$(stat -c "%a" "${NOTIFY_CONF}" 2>/dev/null || echo "unknown")"
    if [ "${perms}" = "600" ]; then echo "ok"
    else echo "insecure:${perms}"; fi
}

status_moonraker() {
    [ -f "${MOONRAKER_CONF}" ] || { echo "no_moonraker"; return; }
    if grep -qE '^\s*\[update_manager\s+Klipper-HA-Notify\]' "${MOONRAKER_CONF}"; then echo "present"
    else echo "missing"; fi
}

# ---------- Main (nur wenn direkt ausgeführt, nicht wenn gesourced) ----------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then

# ---------- Preflight ----------

if [ ! -f "${EXT_SOURCE}" ]; then
    say "${C_RED}FEHLER:${C_RESET} ${EXT_SOURCE} nicht gefunden."
    say "Script im Repo-Root ausführen."
    exit 1
fi

if [ ! -d "${KLIPPER_DIR}/klippy/extras" ]; then
    say "${C_RED}FEHLER:${C_RESET} ${KLIPPER_DIR}/klippy/extras existiert nicht."
    say "Ist Klipper installiert? KLIPPER_DIR=<pfad> ./install.sh falls anderer Pfad."
    exit 1
fi

# ---------- Banner + Status ----------

hr
say "${C_BOLD}Klipper-HA-Notify Installer${C_RESET}"
hr
say "Repo:          ${REPO_DIR}"
say "Klipper:       ${KLIPPER_DIR}"
say "Printer-Cfg:   ${PRINTER_CFG_DIR}"
say "Scripts:       ${SCRIPTS_DIR}"
say "Moonraker:     ${MOONRAKER_CONF}"
say "Klipper-Svc:   ${KLIPPER_SERVICE}"
hr
say "${C_BOLD}Aktueller Zustand:${C_RESET}"
echo ""

S_EXT="$(status_extension)"
case "${S_EXT}" in
    installed)       ok  "Extension-Symlink: ${EXT_TARGET}" ;;
    missing)         miss "Extension-Symlink fehlt: ${EXT_TARGET}" ;;
    wrong_symlink:*) warn "Extension-Symlink zeigt auf ${S_EXT#wrong_symlink:} (erwartet: ${EXT_SOURCE})" ;;
    regular_file)    warn "${EXT_TARGET} existiert als normale Datei (kein Symlink)" ;;
esac

S_CONF="$(status_conf)"
case "${S_CONF}" in
    complete)        ok  "Konfiguration vollständig: ${NOTIFY_CONF}" ;;
    incomplete:*)    warn "Konfiguration unvollständig — fehlt: ${S_CONF#incomplete:}" ;;
    missing)         miss "Konfiguration fehlt: ${NOTIFY_CONF}" ;;
esac

S_PERMS="$(status_conf_perms)"
case "${S_PERMS}" in
    ok)          ok  "Secrets-Datei gesichert (chmod 600)" ;;
    insecure:*)  warn "Secrets-Datei unsicher (${S_PERMS#insecure:}) — enthält HA-Token, wird auf 600 korrigiert" ;;
    no_file)     : ;;
esac

S_INC="$(status_printer_cfg_include)"
case "${S_INC}" in
    present)         ok  "printer.cfg enthält [include ha_notify.cfg]" ;;
    missing)         miss "printer.cfg: [include ha_notify.cfg] fehlt" ;;
    no_printer_cfg)  warn "${PRINTER_CFG} nicht gefunden" ;;
esac

S_MR="$(status_moonraker)"
case "${S_MR}" in
    present)         ok  "moonraker.conf enthält [update_manager Klipper-HA-Notify]" ;;
    missing)         miss "moonraker.conf: [update_manager Klipper-HA-Notify] fehlt (optional)" ;;
    no_moonraker)    warn "${MOONRAKER_CONF} nicht gefunden (Update-Manager übersprungen)" ;;
esac

# Berechtigungen automatisch korrigieren — erfordert keinen Klipper-Neustart
if [[ "${S_PERMS}" == insecure:* ]]; then
    chmod 600 "${NOTIFY_CONF}"
    ok "Berechtigungen korrigiert: ${NOTIFY_CONF} (jetzt 600)"
fi

echo ""
hr
say "${C_BOLD}Auswahl der Schritte:${C_RESET}"
echo ""

# ---------- Menü ----------

ACTIONS=""

printf '%b?%b Alle fehlenden Schritte auf einmal ausführen? [j/N]: ' "${C_CYAN}" "${C_RESET}"
read -r ALL_YN || ALL_YN=""
case "${ALL_YN:-n}" in [jJ]|[yY]|[jJ][aA]|[yY][eE][sS]) AUTO_ALL=1 ;; *) AUTO_ALL=0 ;; esac

# Hilfe: überspringt "bereits erledigt"; fragt nur wenn AUTO_ALL=0
want() {
    local status="$1" prompt="$2"
    case "$status" in installed|present|complete) return 1 ;; esac
    [ "${AUTO_ALL}" = "1" ] && return 0
    ask_yn "${prompt}" y
}

# 1) Extension-Symlink
if want "${S_EXT}" "Extension-Symlink ${EXT_TARGET} anlegen/korrigieren"; then
    ACTIONS="${ACTIONS} ext"
fi

# 2) Konfiguration (Secrets — immer interaktiv)
#    want() bestimmt ob wir konfigurieren; die eigentliche Eingabe ist immer interaktiv.
HA_URL="" HA_TOKEN="" HA_SERVICE=""
CONF_NEEDED=0

case "${S_CONF}" in
    complete)
        # Bereits konfiguriert — im nicht-AUTO_ALL-Modus Option zur Neukonfiguration
        if [ "${AUTO_ALL}" = "0" ] && ask_yn "Konfiguration bereits vorhanden — neu konfigurieren?" n; then
            CONF_NEEDED=1
        fi
        ;;
    missing|incomplete:*)
        if [ "${AUTO_ALL}" = "1" ]; then
            CONF_NEEDED=1
        elif ask_yn "Konfiguration (HA-URL, Token, Service) eingeben" y; then
            CONF_NEEDED=1
        fi
        ;;
esac

if [ "${CONF_NEEDED}" = "1" ]; then
    echo ""
    hr
    say "${C_BOLD}Konfiguration eingeben:${C_RESET}"
    echo ""

    # Bestehende Werte laden (als Defaults)
    existing_url="" existing_token="" existing_svc=""
    if [ -f "${NOTIFY_CONF}" ]; then
        existing_url="$(grep '^HA_URL='     "${NOTIFY_CONF}" | cut -d= -f2- || true)"
        existing_token="$(grep '^HA_TOKEN='  "${NOTIFY_CONF}" | cut -d= -f2- || true)"
        existing_svc="$(grep '^HA_SERVICE=' "${NOTIFY_CONF}" | cut -d= -f2- || true)"
    fi

    # ── HA-URL ──────────────────────────────────────────────────────────────
    DETECTED_HOST=""
    if ping -c1 -W2 homeassistant.local &>/dev/null 2>&1; then
        DETECTED_HOST="homeassistant.local"
        say "  ${C_GREEN}Home Assistant gefunden unter: homeassistant.local${C_RESET}"
    fi

    # Aus bestehender URL Host und Port extrahieren
    existing_host="" existing_port="8123"
    if [ -n "${existing_url}" ]; then
        _tmp="${existing_url#http://}"; _tmp="${_tmp#https://}"
        existing_host="${_tmp%%:*}"
        existing_port="${_tmp##*:}"
    fi

    DEFAULT_HOST="${existing_host:-${DETECTED_HOST:-192.168.x.x}}"
    DEFAULT_PORT="${existing_port:-8123}"

    printf '  Hostname / IP [%s]: ' "${DEFAULT_HOST}"
    read -r _host || _host=""
    HA_HOST="${_host:-${DEFAULT_HOST}}"
    if [ -z "${HA_HOST}" ] || [ "${HA_HOST}" = "192.168.x.x" ]; then
        say "${C_RED}Fehler: Kein Hostname eingegeben. Abbruch.${C_RESET}"
        exit 1
    fi
    printf '  Port [%s]: ' "${DEFAULT_PORT}"
    read -r _port || _port=""
    HA_PORT="${_port:-${DEFAULT_PORT}}"
    HA_URL="http://${HA_HOST}:${HA_PORT}"
    say "  → ${HA_URL}"
    echo ""

    # ── Token ───────────────────────────────────────────────────────────────
    say "  Long-Lived Access Token: HA → Profil → Sicherheit → Langlebige Zugriffstoken"
    if [ -n "${existing_token}" ]; then
        printf '  Token [Enter = bestehenden behalten]: '
        read -rs _token || _token=""
        echo ""
        HA_TOKEN="${_token:-${existing_token}}"
    else
        printf '  Token (Eingabe wird nicht angezeigt): '
        read -rs HA_TOKEN || HA_TOKEN=""
        echo ""
        if [ -z "${HA_TOKEN}" ]; then
            say "${C_RED}Fehler: Kein Token eingegeben. Abbruch.${C_RESET}"
            exit 1
        fi
    fi
    ok "Token übernommen."
    echo ""

    # ── Notify-Service ───────────────────────────────────────────────────────
    say "  Notify-Service:"
    say "  1) Verfügbare Services aus HA abrufen"
    say "  2) Service-Namen manuell eingeben"
    [ -n "${existing_svc}" ] && say "  Aktuell konfiguriert: ${existing_svc}"
    printf '  Auswahl [1/2, default 1]: '
    read -r _svc_choice || _svc_choice=""
    _svc_choice="${_svc_choice:-1}"

    if [ "${_svc_choice}" = "1" ]; then
        say "  Lade Services von ${HA_URL}..."
        _services_raw="$(curl -s --max-time 10 \
            -H "Authorization: Bearer ${HA_TOKEN}" \
            -H "Content-Type: application/json" \
            "${HA_URL}/api/services" 2>/dev/null || echo "")"

        if [ -z "${_services_raw}" ]; then
            warn "HA nicht erreichbar oder Token ungültig. Bitte manuell eingeben."
            printf '  Service-Name (z.B. mobile_app_iphone): '
            read -r HA_SERVICE || HA_SERVICE=""
        else
            mapfile -t _services < <(echo "${_services_raw}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    notify = next((d for d in data if d['domain'] == 'notify'), None)
    if notify:
        for k in sorted(notify['services'].keys()):
            if k.startswith('mobile_app_'):
                print(k)
except Exception:
    pass
" 2>/dev/null)

            if [ ${#_services[@]} -eq 0 ]; then
                warn "Keine mobile_app_* Services gefunden. Bitte manuell eingeben."
                printf '  Service-Name: '
                read -r HA_SERVICE || HA_SERVICE=""
            else
                say "  Verfügbare Notify-Services:"
                for _i in "${!_services[@]}"; do
                    say "    $((_i+1))) ${_services[$_i]}"
                done
                echo ""
                while true; do
                    printf '  Nummer auswählen: '
                    read -r _idx || _idx=""
                    if [[ "${_idx}" =~ ^[0-9]+$ ]] && \
                       [ "${_idx}" -ge 1 ] && \
                       [ "${_idx}" -le "${#_services[@]}" ]; then
                        HA_SERVICE="${_services[$((_idx-1))]}"
                        break
                    fi
                    say "  Ungültige Auswahl."
                done
            fi
        fi
    else
        printf '  Service-Name (z.B. mobile_app_iphone): '
        read -r HA_SERVICE || HA_SERVICE=""
    fi

    if [ -z "${HA_SERVICE}" ]; then
        if [ -n "${existing_svc}" ]; then
            HA_SERVICE="${existing_svc}"
            say "  Behalte bestehenden Service: ${HA_SERVICE}"
        else
            say "${C_RED}Fehler: Kein Service ausgewählt. Abbruch.${C_RESET}"
            exit 1
        fi
    fi
    ok "Service: ${HA_SERVICE}"
    ACTIONS="${ACTIONS} conf"
fi

# 3) printer.cfg Include
if [ -f "${PRINTER_CFG}" ] && want "${S_INC}" "[include ha_notify.cfg] in printer.cfg eintragen"; then
    ACTIONS="${ACTIONS} inc"
fi

# 4) Moonraker update_manager (optional — auch im AUTO_ALL-Modus immer fragen)
if [ "${S_MR}" != "no_moonraker" ] && [ "${S_MR}" != "present" ]; then
    echo ""
    if ask_yn "[update_manager Klipper-HA-Notify] in moonraker.conf ergänzen (optional, für Auto-Update)" n; then
        ACTIONS="${ACTIONS} mr"
    fi
fi

# Klipper-Restart?
RESTART=0
if [ -n "${ACTIONS}" ]; then
    echo ""
    if [ "${AUTO_ALL}" = "1" ] || ask_yn "Klipper nach den Änderungen neu starten (sudo systemctl restart ${KLIPPER_SERVICE})" y; then
        RESTART=1
    fi
fi

if [ -z "${ACTIONS}" ] && [ "${RESTART}" = "0" ]; then
    hr
    ok "Nichts zu tun — alles ist bereits eingerichtet."
    exit 0
fi

echo ""
hr
say "${C_BOLD}Führe aus:${ACTIONS}${C_RESET}"
hr
echo ""

# ---------- Ausführung ----------

for _ACT in ${ACTIONS}; do
    case "${_ACT}" in
        ext)
            if [ -e "${EXT_TARGET}" ] && [ ! -L "${EXT_TARGET}" ]; then
                warn "${EXT_TARGET} ist eine normale Datei. Backup: ${EXT_TARGET}.bak"
                mv "${EXT_TARGET}" "${EXT_TARGET}.bak"
            fi
            ln -sf "${EXT_SOURCE}" "${EXT_TARGET}"
            ok "Extension-Symlink gesetzt: ${EXT_TARGET} → ${EXT_SOURCE}"
            ;;
        conf)
            mkdir -p "${SCRIPTS_DIR}"
            cat > "${NOTIFY_CONF}" << CONF
# Klipper-HA-Notify Konfiguration
# Generiert von install.sh — nicht in Git committen
HA_URL=${HA_URL}
HA_TOKEN=${HA_TOKEN}
HA_SERVICE=${HA_SERVICE}
CONF
            chmod 600 "${NOTIFY_CONF}"
            ok "Konfiguration geschrieben: ${NOTIFY_CONF} (chmod 600)"
            ;;
        inc)
            cp -a "${PRINTER_CFG}" "${PRINTER_CFG}.bak.$(date +%Y%m%d-%H%M%S)"
            # SAVE_CONFIG-Block muss am Dateiende bleiben — Include davor einfügen.
            if grep -qE '^#\*# <-+[[:space:]]*SAVE_CONFIG[[:space:]]*-+>' "${PRINTER_CFG}"; then
                awk -v line="${INCLUDE_LINE}" '
                    /^#\*# <-+[[:space:]]*SAVE_CONFIG[[:space:]]*-+>/ && !inserted {
                        print ""
                        print "# Auto-eingefuegt durch Klipper-HA-Notify installer"
                        print line
                        print ""
                        inserted = 1
                    }
                    { print }
                ' "${PRINTER_CFG}" > "${PRINTER_CFG}.tmp"
                mv "${PRINTER_CFG}.tmp" "${PRINTER_CFG}"
                ok "[include ha_notify.cfg] VOR SAVE_CONFIG-Block eingefügt (Backup erstellt)."
            else
                printf '\n# Auto-eingefuegt durch Klipper-HA-Notify installer\n%s\n' "${INCLUDE_LINE}" >> "${PRINTER_CFG}"
                ok "[include ha_notify.cfg] an printer.cfg angehängt (Backup erstellt)."
            fi
            ;;
        mr)
            cp -a "${MOONRAKER_CONF}" "${MOONRAKER_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
            cat >> "${MOONRAKER_CONF}" << EOF

# Auto-eingefügt durch Klipper-HA-Notify installer
[update_manager Klipper-HA-Notify]
type: git_repo
path: ${REPO_DIR}
origin: ${REPO_URL}
primary_branch: master
is_system_service: False
managed_services: ${KLIPPER_SERVICE}
EOF
            ok "Moonraker-Update-Manager-Eintrag ergänzt (Backup erstellt)."
            ;;
    esac
done

if [ "${RESTART}" = "1" ]; then
    echo ""
    if ! sudo -n true 2>/dev/null; then
        warn "Für den Klipper-Restart wird sudo benötigt."
    fi
    if sudo systemctl restart "${KLIPPER_SERVICE}"; then
        ok "Klipper-Service neu gestartet."
    else
        warn "Klipper-Restart fehlgeschlagen — manuell prüfen: sudo systemctl status ${KLIPPER_SERVICE}"
    fi
fi

# ---------- Abschluss ----------

echo ""
hr
say "${C_BOLD}Fertig.${C_RESET}"
hr
say "Was gemacht wurde:"
for _ACT in ${ACTIONS}; do
    case "${_ACT}" in
        ext)  say "  - Extension-Symlink: ${EXT_TARGET} → ${EXT_SOURCE}" ;;
        conf) say "  - Konfiguration geschrieben: ${NOTIFY_CONF}" ;;
        inc)  say "  - [include ha_notify.cfg] in printer.cfg eingetragen (Backup: ${PRINTER_CFG}.bak.*)" ;;
        mr)   say "  - [update_manager Klipper-HA-Notify] in moonraker.conf ergänzt (Backup: ${MOONRAKER_CONF}.bak.*)" ;;
    esac
done
[ "${RESTART}" = "1" ] && say "  - Klipper-Service neu gestartet."
echo ""
say "${C_BOLD}Verwendung in Klipper-Macros:${C_RESET}"
say '  NOTIFY TITLE="Drucker" MESSAGE="Druck fertig"'
echo ""

fi # end main
