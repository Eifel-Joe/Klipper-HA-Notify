# Klipper extra: Home Assistant push notifications
# https://github.com/Eifel-Joe/Klipper-HA-Notify
#
# Konfiguration (Secrets) in:
#   ~/printer_data/scripts/klipper_ha_notify.conf
#
# In printer.cfg einbinden:
#   [notify_ha]

import logging
import os
import json
import threading
import urllib.request
import urllib.error

CONF_PATH = os.path.expanduser(
    "~/printer_data/scripts/klipper_ha_notify.conf"
)

class NotifyHA:
    def __init__(self, config):
        self.printer  = config.get_printer()
        self.gcode    = self.printer.lookup_object('gcode')
        self.ha_url   = ""
        self.ha_token = ""
        self.ha_service = ""
        self._load_conf()
        self.gcode.register_command(
            'NOTIFY', self.cmd_NOTIFY, desc=self.cmd_NOTIFY_help
        )

    def _load_conf(self):
        try:
            with open(CONF_PATH) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#') or '=' not in line:
                        continue
                    k, v = line.split('=', 1)
                    k, v = k.strip(), v.strip()
                    if   k == 'HA_URL':     self.ha_url     = v
                    elif k == 'HA_TOKEN':   self.ha_token   = v
                    elif k == 'HA_SERVICE': self.ha_service = v
        except FileNotFoundError:
            logging.warning(
                "Klipper-HA-Notify: Konfigurationsdatei nicht gefunden: %s"
                " — install.sh erneut ausfuehren.", CONF_PATH
            )

    cmd_NOTIFY_help = "Push-Benachrichtigung via Home Assistant senden"

    def cmd_NOTIFY(self, gcmd):
        title   = gcmd.get('TITLE',   "Drucker")
        message = gcmd.get('MESSAGE', "")
        threading.Thread(
            target=self._send, args=(title, message), daemon=True
        ).start()

    def _send(self, title, message):
        if not all([self.ha_url, self.ha_token, self.ha_service]):
            logging.error(
                "Klipper-HA-Notify: Konfiguration unvollstaendig, "
                "Benachrichtigung nicht gesendet."
            )
            return
        payload = json.dumps(
            {"title": title, "message": message}
        ).encode()
        req = urllib.request.Request(
            f"{self.ha_url}/api/services/notify/{self.ha_service}",
            data=payload,
            headers={
                "Authorization": f"Bearer {self.ha_token}",
                "Content-Type":  "application/json",
            }
        )
        try:
            urllib.request.urlopen(req, timeout=5)
        except urllib.error.URLError as e:
            logging.error("Klipper-HA-Notify: Senden fehlgeschlagen: %s", e)

def load_config(config):
    return NotifyHA(config)
