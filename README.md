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

Der Installer zeigt zunächst den aktuellen Installationsstatus aller Komponenten und führt dann die gewählten Schritte aus. Alle Schritte sind idempotent — ein erneutes Ausführen ist sicher.

1. **Klipper-Extra** — erstellt Symlink `~/klipper/klippy/extras/notify_ha.py → ~/Klipper-HA-Notify/klipper_extras/notify_ha.py`
2. **Konfiguration** — fragt HA-URL, Token und Notify-Service interaktiv ab; schreibt die Secrets-Datei mit `chmod 600`
3. **printer.cfg Include** — trägt `[include ~/Klipper-HA-Notify/ha_notify.cfg]` ein (SAVE_CONFIG-Block-sicher)
4. **Moonraker update_manager** — optional, ermöglicht automatische Updates über Mainsail/Fluidd
5. **Klipper-Neustart** — optional, via `sudo systemctl restart klipper`

Existiert die Secrets-Datei bereits mit falschen Berechtigungen, korrigiert der Installer sie automatisch auf `600`.

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

## Sicherheit

Die Datei `~/printer_data/scripts/klipper_ha_notify.conf` enthält den **Home Assistant Long-Lived Access Token** und wird vom Installer mit `chmod 600` abgesichert (nur für den eigenen Benutzer lesbar). Sie liegt bewusst außerhalb des Repos und wird nie per Git versioniert.

Ein erneutes `bash install.sh` prüft die Berechtigungen automatisch und korrigiert sie falls nötig.

## Installierte Dateien

| Datei | Pfad | Beschreibung |
|-------|------|--------------|
| Script | `~/Klipper-HA-Notify/klipper_extras/notify_ha.py` | Klipper-Extra im Repo |
| Symlink | `~/klipper/klippy/extras/notify_ha.py` | Von Klipper geladen |
| Konfiguration | `~/printer_data/scripts/klipper_ha_notify.conf` | Secrets — `chmod 600`, nicht im Repo |
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
