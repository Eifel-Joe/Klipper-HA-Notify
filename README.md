# Klipper-HA-Notify

Sendet Push-Benachrichtigungen an ein iPhone/Android-Gerät via **Home Assistant** aus Klipper-Macros heraus.

## Voraussetzungen

- Klipper mit Moonraker (Standard-Voron-Setup)
- [Home Assistant](https://www.home-assistant.io/) im lokalen Netzwerk
- HA Companion App auf dem Smartphone
- Python 3 auf dem Drucker-Pi (bereits vorhanden)
- `gcode_shell_command` Klipper-Erweiterung (wird bei Bedarf automatisch installiert)

## Installation

```bash
cd ~
git clone https://github.com/Eifel-Joe/Klipper-HA-Notify.git
cd Klipper-HA-Notify
bash install.sh
```

Der Installer führt durch folgende Schritte:

1. **gcode_shell_command** — prüft ob installiert, lädt es bei Bedarf nach (mit Bestätigung)
2. **HA-URL** — erkennt `homeassistant.local` automatisch, muss bestätigt werden
3. **Token** — Long-Lived Access Token aus HA (Profil → Sicherheit → Langlebige Zugriffstoken)
4. **Notify-Service** — Liste aus HA oder manuelle Eingabe
5. **Dateien** — kopiert Script und Config, trägt Include in `printer.cfg` ein
6. **Firmware-Neustart** — optional, direkt über Moonraker

## Verwendung

Nach der Installation steht das `NOTIFY`-Macro in allen Klipper-Macros zur Verfügung:

```
NOTIFY TITLE="Drucker" MESSAGE="Druck fertig"
```

Beide Parameter sind optional. Ohne `TITLE` wird `"Drucker"` verwendet.

### Beispiel: Integration in eigene Macros

```ini
[gcode_macro PRINT_END]
gcode:
    # ... bestehender Code ...
    NOTIFY TITLE="Drucker - Druck fertig" MESSAGE="Der Druck wurde erfolgreich abgeschlossen"

[gcode_macro PAUSE]
gcode:
    # ... bestehender Code ...
    NOTIFY TITLE="Drucker - Pause" MESSAGE="Bitte Filament wechseln und RESUME druecken"

[gcode_macro CANCEL_PRINT]
gcode:
    # ... bestehender Code ...
    NOTIFY TITLE="Drucker - Abgebrochen" MESSAGE="Der Druck wurde abgebrochen"
```

## Installierte Dateien

| Datei | Pfad |
|-------|------|
| Python-Script | `~/printer_data/scripts/notify_ha.py` |
| Klipper-Config | `~/printer_data/config/ha_notify.cfg` |
| Include | in `~/printer_data/config/printer.cfg` eingetragen |

## Aktualisieren

```bash
cd ~/Klipper-HA-Notify
git pull
bash install.sh
```

## Deinstallieren

```bash
rm ~/printer_data/scripts/notify_ha.py
rm ~/printer_data/config/ha_notify.cfg
# [include ha_notify.cfg] aus printer.cfg entfernen
```
