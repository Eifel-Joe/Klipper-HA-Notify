#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

KLIPPER_EXTRAS="${HOME}/klipper/klippy/extras"
CONFIG_DIR="${HOME}/printer_data/config"
SCRIPTS_DIR="${HOME}/printer_data/scripts"
PRINTER_CFG="${CONFIG_DIR}/printer.cfg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CMD_URL="https://raw.githubusercontent.com/dw-0/kiauh/master/resources/gcode_shell_command.py"

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${CYAN}   Klipper-HA-Notify Installer          ${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo ""

# ── Schritt 1: gcode_shell_command ───────────────────────────────────────
echo -e "${CYAN}── Schritt 1: gcode_shell_command ──────${NC}"
if [ -f "${KLIPPER_EXTRAS}/gcode_shell_command.py" ]; then
    echo -e "${GREEN}✓ gcode_shell_command ist bereits installiert${NC}"
else
    echo -e "${YELLOW}⚠ gcode_shell_command ist nicht installiert.${NC}"
    echo ""
    echo "  Diese Klipper-Erweiterung wird benötigt, um Shell-Scripts aus"
    echo "  GCode-Macros heraus aufzurufen. Sie wird direkt von GitHub"
    echo "  (KIAUH-Projekt) heruntergeladen:"
    echo ""
    echo "  ${SHELL_CMD_URL}"
    echo ""
    read -p "  Jetzt herunterladen und installieren? [j/N] " confirm
    if [[ ! "$confirm" =~ ^[jJyY]$ ]]; then
        echo ""
        echo -e "${RED}Installation abgebrochen.${NC}"
        echo ""
        echo "  gcode_shell_command wird zwingend benötigt."
        echo "  Installiere es manuell über KIAUH (Option 4 → Extras)"
        echo "  oder lade die Datei selbst herunter:"
        echo "  ${SHELL_CMD_URL}"
        echo "  → ${KLIPPER_EXTRAS}/gcode_shell_command.py"
        echo ""
        exit 1
    fi
    echo ""
    echo "  Lade herunter..."
    curl -fsSL -o "${KLIPPER_EXTRAS}/gcode_shell_command.py" "${SHELL_CMD_URL}"
    echo -e "${GREEN}✓ gcode_shell_command installiert${NC}"
fi

echo ""

# ── Schritt 2: Home Assistant URL ────────────────────────────────────────
echo -e "${CYAN}── Schritt 2: Home Assistant URL ───────${NC}"
echo ""

# Versuche homeassistant.local aufzulösen
DETECTED_HOST=""
if ping -c1 -W2 homeassistant.local &>/dev/null 2>&1; then
    DETECTED_HOST="homeassistant.local"
    echo -e "  ${GREEN}Home Assistant gefunden unter: homeassistant.local${NC}"
fi

DEFAULT_HOST="${DETECTED_HOST:-192.168.x.x}"
read -p "  Hostname / IP-Adresse [${DEFAULT_HOST}]: " input_host
HA_HOST="${input_host:-$DETECTED_HOST}"

if [ -z "$HA_HOST" ]; then
    echo -e "${RED}Fehler: Kein Hostname eingegeben. Abbruch.${NC}"
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
    echo ""
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
    echo -e "${RED}Fehler: Kein Token eingegeben. Abbruch.${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ Token übernommen${NC}"
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
        echo -e "  ${YELLOW}⚠ HA nicht erreichbar oder Token ungültig.${NC}"
        echo "  Bitte Service-Namen manuell eingeben."
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
            echo -e "  ${YELLOW}⚠ Keine mobile_app_* Services gefunden.${NC}"
            read -p "  Service-Namen manuell eingeben: " HA_SERVICE
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
    echo -e "${RED}Fehler: Kein Service ausgewählt. Abbruch.${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ Service: ${HA_SERVICE}${NC}"
echo ""

# ── Schritt 5: Dateien installieren ──────────────────────────────────────
echo -e "${CYAN}── Schritt 5: Dateien installieren ─────${NC}"
echo ""

mkdir -p "${SCRIPTS_DIR}"

# notify_ha.py mit gesetzten Werten schreiben
sed -e "s|PLACEHOLDER_HA_URL|${HA_URL}|g" \
    -e "s|PLACEHOLDER_HA_TOKEN|${HA_TOKEN}|g" \
    -e "s|PLACEHOLDER_HA_SERVICE|${HA_SERVICE}|g" \
    "${SCRIPT_DIR}/notify_ha.py" > "${SCRIPTS_DIR}/notify_ha.py"
chmod +x "${SCRIPTS_DIR}/notify_ha.py"
echo -e "${GREEN}  ✓ notify_ha.py  →  ${SCRIPTS_DIR}/notify_ha.py${NC}"

# ha_notify.cfg kopieren
cp "${SCRIPT_DIR}/ha_notify.cfg" "${CONFIG_DIR}/ha_notify.cfg"
echo -e "${GREEN}  ✓ ha_notify.cfg  →  ${CONFIG_DIR}/ha_notify.cfg${NC}"

# Include in printer.cfg eintragen
if grep -q "ha_notify.cfg" "${PRINTER_CFG}" 2>/dev/null; then
    echo -e "${GREEN}  ✓ Include bereits in printer.cfg vorhanden${NC}"
elif grep -qE "^\[include \*\.cfg\]" "${PRINTER_CFG}" 2>/dev/null; then
    echo -e "${GREEN}  ✓ Wildcard-Include [include *.cfg] erkannt — ha_notify.cfg wird automatisch geladen${NC}"
else
    # Nach der letzten [include ...]-Zeile einfügen
    if grep -q "^\[include" "${PRINTER_CFG}" 2>/dev/null; then
        last_include_line=$(grep -n "^\[include" "${PRINTER_CFG}" | tail -1 | cut -d: -f1)
        sed -i "${last_include_line}a [include ha_notify.cfg]" "${PRINTER_CFG}"
    else
        sed -i "1i [include ha_notify.cfg]\n" "${PRINTER_CFG}"
    fi
    echo -e "${GREEN}  ✓ [include ha_notify.cfg] in printer.cfg eingetragen${NC}"
fi

echo ""

# ── Schritt 6: Firmware-Neustart ─────────────────────────────────────────
echo -e "${CYAN}── Schritt 6: Firmware-Neustart ────────${NC}"
echo ""
echo -e "  ${YELLOW}⚠ Ein Firmware-Neustart ist erforderlich, damit Klipper die neuen${NC}"
echo -e "  ${YELLOW}  Dateien lädt. Ohne Neustart ist NOTIFY nicht verfügbar.${NC}"
echo ""
read -p "  Firmware-Neustart jetzt auslösen (via Moonraker)? [j/N] " restart_confirm
if [[ "$restart_confirm" =~ ^[jJyY]$ ]]; then
    if curl -s -X POST http://localhost:7125/printer/firmware_restart > /dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Firmware-Neustart ausgelöst${NC}"
    else
        echo -e "${YELLOW}  ⚠ Moonraker nicht erreichbar — bitte manuell neu starten${NC}"
    fi
else
    echo ""
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
