#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KLIPPER_EXTRAS="${HOME}/klipper/klippy/extras"
CONFIG_DIR="${HOME}/printer_data/config"
SCRIPTS_DIR="${HOME}/printer_data/scripts"
PRINTER_CFG="${CONFIG_DIR}/printer.cfg"
MOONRAKER_CFG="${CONFIG_DIR}/moonraker.conf"
NOTIFY_CONF="${SCRIPTS_DIR}/klipper_ha_notify.conf"
REPO_URL="https://github.com/Eifel-Joe/Klipper-HA-Notify.git"

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${CYAN}   Klipper-HA-Notify Installer          ${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo ""

# ── Schritt 1: Klipper-Extra Symlink ─────────────────────────────────────
echo -e "${CYAN}── Schritt 1: Klipper-Extra einbinden ──${NC}"
echo ""

if [ ! -d "${KLIPPER_EXTRAS}" ]; then
    echo -e "  ${RED}Fehler: Klipper-Verzeichnis nicht gefunden: ${KLIPPER_EXTRAS}${NC}"
    echo "  Ist Klipper korrekt installiert?"
    exit 1
fi

SYMLINK_TARGET="${KLIPPER_EXTRAS}/notify_ha.py"
if [ -L "${SYMLINK_TARGET}" ]; then
    echo -e "  ${GREEN}✓ Symlink bereits vorhanden${NC}"
elif [ -f "${SYMLINK_TARGET}" ]; then
    echo -e "  ${YELLOW}⚠ notify_ha.py existiert bereits (keine Symlink). Wird ersetzt.${NC}"
    rm "${SYMLINK_TARGET}"
    ln -s "${REPO_DIR}/notify_ha.py" "${SYMLINK_TARGET}"
    echo -e "  ${GREEN}✓ Symlink erstellt${NC}"
else
    ln -s "${REPO_DIR}/notify_ha.py" "${SYMLINK_TARGET}"
    echo -e "  ${GREEN}✓ Symlink erstellt: ${SYMLINK_TARGET}${NC}"
fi

echo ""

# ── Schritt 2: Home Assistant URL ────────────────────────────────────────
echo -e "${CYAN}── Schritt 2: Home Assistant URL ───────${NC}"
echo ""

DETECTED_HOST=""
if ping -c1 -W2 homeassistant.local &>/dev/null 2>&1; then
    DETECTED_HOST="homeassistant.local"
    echo -e "  ${GREEN}Home Assistant gefunden unter: homeassistant.local${NC}"
fi

DEFAULT_HOST="${DETECTED_HOST:-192.168.x.x}"
read -p "  Hostname / IP-Adresse [${DEFAULT_HOST}]: " input_host
HA_HOST="${input_host:-$DETECTED_HOST}"

if [ -z "$HA_HOST" ]; then
    echo -e "  ${RED}Fehler: Kein Hostname eingegeben. Abbruch.${NC}"
    exit 1
fi

read -p "  Port [8123]: " input_port
HA_PORT="${input_port:-8123}"
HA_URL="http://${HA_HOST}:${HA_PORT}"

echo ""
echo "  Verwende: ${HA_URL}"
echo ""
read -p "  Korrekt? [J/n] " confirm
if [[ "$confirm" =~ ^[nN]$ ]]; then
    echo "  Bitte starte den Installer neu und korrigiere die Angaben."
    exit 1
fi

echo ""

# ── Schritt 3: Token ─────────────────────────────────────────────────────
echo -e "${CYAN}── Schritt 3: Home Assistant Token ─────${NC}"
echo ""
echo "  Erstelle einen Long-Lived Access Token in Home Assistant:"
echo "  Profil → Sicherheit → Langlebige Zugriffstoken → Token erstellen"
echo ""
read -s -p "  Token (Eingabe wird nicht angezeigt): " HA_TOKEN
echo ""

if [ -z "$HA_TOKEN" ]; then
    echo -e "  ${RED}Fehler: Kein Token eingegeben. Abbruch.${NC}"
    exit 1
fi

echo -e "  ${GREEN}✓ Token übernommen${NC}"
echo ""

# ── Schritt 4: Notify-Service ─────────────────────────────────────────────
echo -e "${CYAN}── Schritt 4: Notify-Service ───────────${NC}"
echo ""
echo "  Wie soll der Notify-Service ausgewählt werden?"
echo "  1) Verfügbare Services aus HA abrufen und auswählen"
echo "  2) Service-Namen manuell eingeben"
echo ""
read -p "  Auswahl [1/2]: " service_choice

HA_SERVICE=""

if [ "$service_choice" = "1" ]; then
    echo ""
    echo "  Lade Services von ${HA_URL}..."
    services_raw=$(curl -s --max-time 10 \
        -H "Authorization: Bearer ${HA_TOKEN}" \
        -H "Content-Type: application/json" \
        "${HA_URL}/api/services" 2>/dev/null || echo "")

    if [ -z "$services_raw" ]; then
        echo -e "  ${YELLOW}⚠ HA nicht erreichbar oder Token ungültig. Bitte manuell eingeben.${NC}"
        read -p "  Service-Name (z.B. mobile_app_iphone): " HA_SERVICE
    else
        mapfile -t services < <(echo "$services_raw" | python3 -c "
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

        if [ ${#services[@]} -eq 0 ]; then
            echo -e "  ${YELLOW}⚠ Keine mobile_app_* Services gefunden. Bitte manuell eingeben.${NC}"
            read -p "  Service-Name: " HA_SERVICE
        else
            echo ""
            echo "  Verfügbare Notify-Services:"
            for i in "${!services[@]}"; do
                echo "    $((i+1))) ${services[$i]}"
            done
            echo ""
            while true; do
                read -p "  Nummer auswählen: " svc_idx
                if [[ "$svc_idx" =~ ^[0-9]+$ ]] && \
                   [ "$svc_idx" -ge 1 ] && \
                   [ "$svc_idx" -le "${#services[@]}" ]; then
                    HA_SERVICE="${services[$((svc_idx-1))]}"
                    break
                fi
                echo "  Ungültige Auswahl, bitte erneut eingeben."
            done
        fi
    fi
else
    echo ""
    read -p "  Service-Name (z.B. mobile_app_iphone): " HA_SERVICE
fi

if [ -z "$HA_SERVICE" ]; then
    echo -e "  ${RED}Fehler: Kein Service ausgewählt. Abbruch.${NC}"
    exit 1
fi

echo -e "  ${GREEN}✓ Service: ${HA_SERVICE}${NC}"
echo ""

# ── Schritt 5: Konfiguration und Include ─────────────────────────────────
echo -e "${CYAN}── Schritt 5: Konfiguration schreiben ──${NC}"
echo ""

mkdir -p "${SCRIPTS_DIR}"

# Secrets-Datei schreiben (liegt außerhalb des Repos)
cat > "${NOTIFY_CONF}" << CONF
# Klipper-HA-Notify Konfiguration
# Generiert von install.sh — nicht in Git committen
HA_URL=${HA_URL}
HA_TOKEN=${HA_TOKEN}
HA_SERVICE=${HA_SERVICE}
CONF
chmod 600 "${NOTIFY_CONF}"
echo -e "  ${GREEN}✓ Konfiguration  →  ${NOTIFY_CONF}${NC}"

# Include in printer.cfg eintragen
INCLUDE_LINE="[include ~/Klipper-HA-Notify/ha_notify.cfg]"
if grep -qF "ha_notify.cfg" "${PRINTER_CFG}" 2>/dev/null; then
    echo -e "  ${GREEN}✓ Include bereits in printer.cfg vorhanden${NC}"
else
    if grep -q "^\[include" "${PRINTER_CFG}" 2>/dev/null; then
        last_line=$(grep -n "^\[include" "${PRINTER_CFG}" | tail -1 | cut -d: -f1)
        sed -i "${last_line}a ${INCLUDE_LINE}" "${PRINTER_CFG}"
    else
        sed -i "1i ${INCLUDE_LINE}" "${PRINTER_CFG}"
    fi
    echo -e "  ${GREEN}✓ Include in printer.cfg eingetragen${NC}"
fi

echo ""

# ── Schritt 6: Moonraker update_manager ──────────────────────────────────
echo -e "${CYAN}── Schritt 6: Moonraker update_manager ─${NC}"
echo ""
echo "  Ein update_manager-Eintrag ermöglicht automatische Updates"
echo "  über Mainsail/Fluidd direkt aus dem GitHub-Repo."
echo ""
read -p "  Eintrag in moonraker.conf hinzufügen? [J/n] " moonraker_confirm
if [[ ! "$moonraker_confirm" =~ ^[nN]$ ]]; then
    if grep -q "Klipper-HA-Notify" "${MOONRAKER_CFG}" 2>/dev/null; then
        echo -e "  ${GREEN}✓ update_manager-Eintrag bereits vorhanden${NC}"
    else
        cat >> "${MOONRAKER_CFG}" << EOF

[update_manager Klipper-HA-Notify]
type: git_repo
path: ~/Klipper-HA-Notify
origin: ${REPO_URL}
primary_branch: master
is_system_service: False
managed_services: klipper
EOF
        echo -e "  ${GREEN}✓ update_manager in moonraker.conf eingetragen${NC}"
    fi
else
    echo "  Übersprungen — Updates müssen manuell per git pull eingespielt werden."
fi

echo ""

# ── Schritt 7: Firmware-Neustart ─────────────────────────────────────────
echo -e "${CYAN}── Schritt 7: Firmware-Neustart ────────${NC}"
echo ""
echo -e "  ${YELLOW}⚠ Ein Firmware-Neustart ist erforderlich, damit Klipper das neue${NC}"
echo -e "  ${YELLOW}  Extra lädt. Ohne Neustart ist NOTIFY nicht verfügbar.${NC}"
echo ""
read -p "  Firmware-Neustart jetzt auslösen (via Moonraker)? [j/N] " restart_confirm
if [[ "$restart_confirm" =~ ^[jJyY]$ ]]; then
    if curl -s -X POST http://localhost:7125/printer/firmware_restart > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Firmware-Neustart ausgelöst${NC}"
    else
        echo -e "  ${YELLOW}⚠ Moonraker nicht erreichbar — bitte manuell neu starten${NC}"
    fi
else
    echo "  Bitte führe in Mainsail oder Fluidd manuell einen Firmware-Neustart durch."
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${GREEN}   Installation abgeschlossen!          ${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo ""
echo "  Verwendung in Klipper-Macros:"
echo '  NOTIFY TITLE="Drucker" MESSAGE="Druck fertig"'
echo ""
