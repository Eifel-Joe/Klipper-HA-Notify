# Klipper-HA-Notify

Klipper-Extra das Push-Benachrichtigungen an iPhone/Android via **Home Assistant** sendet — direkt als natives Klipper-Modul, ohne gcode_shell_command.

## Voraussetzungen

- Klipper mit Moonraker (Standard-Voron-Setup)
- [Home Assistant](https://www.home-assistant.io/) im lokalen Netzwerk mit Companion App auf dem Smartphone
- Python 3 auf dem Drucker-Pi (bereits vorhanden)

## Installation

```bash
cd ~
git clone https://github.com/Eifel-Joe/Klipper-HA-Notify.git
cd Klipper-HA-Notify
bash install.sh
```

Der Installer führt durch folgende Schritte:

1. **Klipper-Extra** — erstellt Symlink `~/klipper/klippy/extras/notify_ha.py → ~/Klipper-HA-Notify/notify_ha.py`
2. **HA-URL** — erkennt `homeassistant.local` automatisch, Bestätigung durch User
3. **Token** — Long-Lived Access Token aus HA (Profil → Sicherheit → Langlebige Zugriffstoken)
4. **Notify-Service** — Auswahl aus HA-Liste oder manuelle Eingabe
5. **Konfiguration** — schreibt Secrets-Datei, trägt Include in `printer.cfg` ein
6. **Moonraker update_manager** — optional, ermöglicht automatische Updates über Mainsail/Fluidd
7. **Firmware-Neustart** — optional, direkt über Moonraker

## Verwendung

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

| Datei | Pfad | Beschreibung |
|-------|------|--------------|
| Script | `~/Klipper-HA-Notify/notify_ha.py` | Klipper-Extra im Repo |
| Symlink | `~/klipper/klippy/extras/notify_ha.py` | Von Klipper geladen |
| Konfiguration | `~/printer_data/scripts/klipper_ha_notify.conf` | Secrets (nicht im Repo) |
| Config | `~/Klipper-HA-Notify/ha_notify.cfg` | Lädt das Extra (`[notify_ha]`) |
| Include | in `~/printer_data/config/printer.cfg` | eingetragen durch install.sh |

## Aktualisieren

Updates werden automatisch über Mainsail/Fluidd eingespielt (wenn update_manager aktiviert). Der Symlink sorgt dafür, dass Klipper nach dem nächsten Neustart automatisch die neue Version verwendet.

Manuell:
```bash
cd ~/Klipper-HA-Notify && git pull
```
Anschließend Firmware-Neustart in Mainsail/Fluidd.

## Deinstallieren

```bash
rm ~/klipper/klippy/extras/notify_ha.py
rm ~/printer_data/scripts/klipper_ha_notify.conf
rm -rf ~/Klipper-HA-Notify
# [include ~/Klipper-HA-Notify/ha_notify.cfg] aus printer.cfg entfernen
# [update_manager Klipper-HA-Notify] aus moonraker.conf entfernen
```
