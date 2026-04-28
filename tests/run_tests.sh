#!/bin/bash
# Simulations-Testsuite für install.sh
# Sourced install.sh und testet alle status_*-Funktionen und Execution-Aktionen
# in einer isolierten Fake-Umgebung.
#
# Ausführen:  bash tests/run_tests.sh
# Auf dem Pi: bash tests/run_tests.sh   (alle Tests einschließlich Symlinks)

set -eu
REPO_DIR_REAL="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- Farben ----------
if [ -t 1 ]; then
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[1;33m'; C_CYAN='\033[0;36m'; C_RESET='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_RESET=''
fi

# ---------- Test-Framework ----------
PASS=0; FAIL=0; SKIP=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "${actual}" = "${expected}" ]; then
        printf '%b✔%b %s\n' "${C_GREEN}" "${C_RESET}" "${desc}"
        PASS=$((PASS+1))
    else
        printf '%b✘%b %s\n  erwartet: [%s]\n  erhalten: [%s]\n' \
            "${C_RED}" "${C_RESET}" "${desc}" "${expected}" "${actual}"
        FAIL=$((FAIL+1))
    fi
}

assert_file_contains() {
    local desc="$1" pattern="$2" file="$3"
    if grep -qE "${pattern}" "${file}" 2>/dev/null; then
        printf '%b✔%b %s\n' "${C_GREEN}" "${C_RESET}" "${desc}"
        PASS=$((PASS+1))
    else
        printf '%b✘%b %s\n  Muster [%s] nicht in %s\n' \
            "${C_RED}" "${C_RESET}" "${desc}" "${pattern}" "${file}"
        FAIL=$((FAIL+1))
    fi
}

assert_file_perms() {
    local desc="$1" expected="$2" file="$3"
    local actual; actual="$(stat -c "%a" "${file}" 2>/dev/null || echo "error")"
    assert_eq "${desc}" "${expected}" "${actual}"
}

skip() {
    printf '%b⊘%b %s (SKIP: %s)\n' "${C_YELLOW}" "${C_RESET}" "$1" "$2"
    SKIP=$((SKIP+1))
}

section() { printf '\n%b── %s%b\n' "${C_CYAN}" "$*" "${C_RESET}"; }

# ---------- Symlink-Fähigkeit erkennen ----------
# Prüft ob ln -s einen echten POSIX-Symlink erstellt ([ -L ] muss wahr sein).
# Auf Git Bash/Windows kehrt ln manchmal Exit 0 zurück, ohne einen echten Symlink
# zu erzeugen — daher reicht der Exit-Code allein nicht.
_sym_test_root="$(mktemp -d)"
mkdir -p "${_sym_test_root}/sub"
_real_source="${_sym_test_root}/real_file"
touch "${_real_source}"
if ln -s "${_real_source}" "${_sym_test_root}/sub/test_link" 2>/dev/null \
   && [ -L "${_sym_test_root}/sub/test_link" ]; then
    SYMLINKS_SUPPORTED=1
else
    SYMLINKS_SUPPORTED=0
fi
rm -rf "${_sym_test_root}"

# ---------- POSIX-Permissions erkennen ----------
_perm_test="$(mktemp)"
chmod 600 "${_perm_test}" 2>/dev/null
_perm_result="$(stat -c "%a" "${_perm_test}" 2>/dev/null || echo "error")"
[ "${_perm_result}" = "600" ] && PERMS_SUPPORTED=1 || PERMS_SUPPORTED=0
rm -f "${_perm_test}"

# ---------- Fake-Umgebung (einmalig für alle Tests) ----------
# Pro Abschnitt wird setup_section / teardown_section aufgerufen.
# Innerhalb eines Abschnitts wird der Zustand pro Test durch einfaches
# Löschen/Erstellen einzelner Dateien bereinigt — keine Re-Source nötig.

FAKE_ROOT=""

setup_section() {
    FAKE_ROOT="$(mktemp -d)"
    mkdir -p "${FAKE_ROOT}/klipper/klippy/extras"
    mkdir -p "${FAKE_ROOT}/printer_data/config"
    mkdir -p "${FAKE_ROOT}/printer_data/scripts"
    mkdir -p "${FAKE_ROOT}/repo/klipper_extras"
    # Fake-Source-Datei: Symlinks auf Windows-Pfade (/d/...) funktionieren
    # in Git Bash nicht, auf eine lokale Datei im tmpdir schon.
    touch "${FAKE_ROOT}/repo/klipper_extras/notify_ha.py"

    export KLIPPER_DIR="${FAKE_ROOT}/klipper"
    export PRINTER_CFG_DIR="${FAKE_ROOT}/printer_data/config"
    export SCRIPTS_DIR="${FAKE_ROOT}/printer_data/scripts"
    export MOONRAKER_CONF="${FAKE_ROOT}/printer_data/config/moonraker.conf"
    export KLIPPER_SERVICE="klipper"
    export REPO_DIR="${FAKE_ROOT}/repo"

    # install.sh einmalig sourcen — Main-Flow durch Guard blockiert
    # shellcheck disable=SC1090
    source "${REPO_DIR_REAL}/install.sh"

    # Pfade auf Fake-Umgebung setzen (nach Source, da install.sh sie sonst überschreibt)
    EXT_SOURCE="${FAKE_ROOT}/repo/klipper_extras/notify_ha.py"
    EXT_TARGET="${KLIPPER_DIR}/klippy/extras/notify_ha.py"
    NOTIFY_CONF="${SCRIPTS_DIR}/klipper_ha_notify.conf"
    PRINTER_CFG="${PRINTER_CFG_DIR}/printer.cfg"
}

teardown_section() {
    rm -rf "${FAKE_ROOT}"
    FAKE_ROOT=""
    export REPO_DIR="${REPO_DIR_REAL}"
}

# Hilfsfunktion: Zustand eines Tests bereinigen (Dateien innerhalb FAKE_ROOT)
clean_test() {
    rm -f "${EXT_TARGET}" "${NOTIFY_CONF}" "${PRINTER_CFG}" "${MOONRAKER_CONF}"
}

# ============================================================
# status_extension()
# ============================================================
section "status_extension()"
setup_section

clean_test
assert_eq "missing wenn kein Symlink/Datei" \
    "missing" "$(status_extension)"

if [ "${SYMLINKS_SUPPORTED}" = "1" ]; then
    clean_test
    ln -s "${EXT_SOURCE}" "${EXT_TARGET}"
    assert_eq "installed wenn korrekter Symlink" \
        "installed" "$(status_extension)"

    clean_test
    ln -s "/some/other/path/notify_ha.py" "${EXT_TARGET}"
    assert_eq "wrong_symlink wenn falsches Ziel" \
        "wrong_symlink:/some/other/path/notify_ha.py" "$(status_extension)"
else
    skip "installed wenn korrekter Symlink" "Symlinks nicht verfügbar (Windows ohne Dev Mode)"
    skip "wrong_symlink wenn falsches Ziel"  "Symlinks nicht verfügbar (Windows ohne Dev Mode)"
fi

clean_test
touch "${EXT_TARGET}"
assert_eq "regular_file wenn normale Datei statt Symlink" \
    "regular_file" "$(status_extension)"

teardown_section

# ============================================================
# status_conf()
# ============================================================
section "status_conf()"
setup_section

clean_test
assert_eq "missing wenn keine Conf-Datei" \
    "missing" "$(status_conf)"

clean_test
printf 'HA_URL=http://ha.local:8123\nHA_TOKEN=abc123\nHA_SERVICE=mobile_app_iphone\n' \
    > "${NOTIFY_CONF}"
assert_eq "complete wenn alle 3 Keys gesetzt" \
    "complete" "$(status_conf)"

clean_test
printf 'HA_URL=http://ha.local:8123\nHA_SERVICE=mobile_app_iphone\n' > "${NOTIFY_CONF}"
assert_eq "incomplete:HA_TOKEN wenn Token fehlt" \
    "incomplete:HA_TOKEN" "$(status_conf)"

clean_test
printf '# Kommentar\nHA_URL=http://ha.local:8123\n' > "${NOTIFY_CONF}"
assert_eq "incomplete:HA_TOKEN,HA_SERVICE wenn 2 Keys fehlen" \
    "incomplete:HA_TOKEN,HA_SERVICE" "$(status_conf)"

clean_test
printf '# nur Kommentare\n' > "${NOTIFY_CONF}"
assert_eq "incomplete:alle wenn Datei leer (nur Kommentare)" \
    "incomplete:HA_URL,HA_TOKEN,HA_SERVICE" "$(status_conf)"

teardown_section

# ============================================================
# status_conf_perms()
# ============================================================
section "status_conf_perms()"
setup_section

clean_test
assert_eq "no_file wenn keine Conf-Datei" \
    "no_file" "$(status_conf_perms)"

clean_test
printf 'HA_URL=x\nHA_TOKEN=y\nHA_SERVICE=z\n' > "${NOTIFY_CONF}"
if [ "${PERMS_SUPPORTED}" = "1" ]; then
    chmod 600 "${NOTIFY_CONF}"
    assert_eq "ok wenn chmod 600" "ok" "$(status_conf_perms)"
else
    skip "ok wenn chmod 600" "POSIX-Permissions nicht verfügbar (Windows/NTFS)"
fi

clean_test
printf 'HA_URL=x\nHA_TOKEN=y\nHA_SERVICE=z\n' > "${NOTIFY_CONF}"
if [ "${PERMS_SUPPORTED}" = "1" ]; then
    chmod 644 "${NOTIFY_CONF}"
    assert_eq "insecure:644 wenn chmod 644" "insecure:644" "$(status_conf_perms)"
else
    skip "insecure:644 wenn chmod 644" "POSIX-Permissions nicht verfügbar (Windows/NTFS)"
fi

teardown_section

# ============================================================
# status_printer_cfg_include()
# ============================================================
section "status_printer_cfg_include()"
setup_section

clean_test
assert_eq "no_printer_cfg wenn printer.cfg fehlt" \
    "no_printer_cfg" "$(status_printer_cfg_include)"

clean_test
printf '[include ~/Klipper-HA-Notify/ha_notify.cfg]\n' > "${PRINTER_CFG}"
assert_eq "present wenn Include vorhanden" \
    "present" "$(status_printer_cfg_include)"

clean_test
printf '[printer]\nkinematics: corexy\n' > "${PRINTER_CFG}"
assert_eq "missing wenn Include nicht in printer.cfg" \
    "missing" "$(status_printer_cfg_include)"

teardown_section

# ============================================================
# status_moonraker()
# ============================================================
section "status_moonraker()"
setup_section

clean_test
assert_eq "no_moonraker wenn moonraker.conf fehlt" \
    "no_moonraker" "$(status_moonraker)"

clean_test
printf '[update_manager Klipper-HA-Notify]\ntype: git_repo\n' > "${MOONRAKER_CONF}"
assert_eq "present wenn Eintrag vorhanden" \
    "present" "$(status_moonraker)"

clean_test
printf '[update_manager anderes_plugin]\ntype: git_repo\n' > "${MOONRAKER_CONF}"
assert_eq "missing wenn nur fremder update_manager vorhanden" \
    "missing" "$(status_moonraker)"

teardown_section

# ============================================================
# Execution: conf (Secrets-Datei schreiben)
# ============================================================
section "Execution: conf"
setup_section

clean_test
HA_URL="http://homeassistant.local:8123"
HA_TOKEN="mein_geheimer_token_abc"
HA_SERVICE="mobile_app_iphone_15_pro"
mkdir -p "${SCRIPTS_DIR}"
cat > "${NOTIFY_CONF}" << CONF
# Klipper-HA-Notify Konfiguration
HA_URL=${HA_URL}
HA_TOKEN=${HA_TOKEN}
HA_SERVICE=${HA_SERVICE}
CONF
chmod 600 "${NOTIFY_CONF}"
assert_file_contains "conf enthält HA_URL" \
    "^HA_URL=http://homeassistant.local:8123" "${NOTIFY_CONF}"
assert_file_contains "conf enthält HA_TOKEN" \
    "^HA_TOKEN=mein_geheimer_token_abc" "${NOTIFY_CONF}"
assert_file_contains "conf enthält HA_SERVICE" \
    "^HA_SERVICE=mobile_app_iphone_15_pro" "${NOTIFY_CONF}"
if [ "${PERMS_SUPPORTED}" = "1" ]; then
    assert_file_perms "conf hat Berechtigungen 600" "600" "${NOTIFY_CONF}"
    assert_eq "status_conf_perms erkennt 600" "ok" "$(status_conf_perms)"
else
    skip "conf hat Berechtigungen 600" "POSIX-Permissions nicht verfügbar (Windows/NTFS)"
    skip "status_conf_perms erkennt 600" "POSIX-Permissions nicht verfügbar (Windows/NTFS)"
fi
assert_eq "status_conf erkennt vollständige Conf" \
    "complete" "$(status_conf)"

teardown_section

# ============================================================
# Execution: inc (printer.cfg Include)
# ============================================================
section "Execution: inc — printer.cfg Include"
setup_section

# Test A: Ohne SAVE_CONFIG-Block — anhängen
clean_test
printf '[printer]\nkinematics: corexy\n' > "${PRINTER_CFG}"
cp -a "${PRINTER_CFG}" "${PRINTER_CFG}.bak.test"
printf '\n# Auto-eingefuegt\n%s\n' "${INCLUDE_LINE}" >> "${PRINTER_CFG}"
assert_file_contains "Include ohne SAVE_CONFIG: vorhanden" \
    'include ~/Klipper-HA-Notify/ha_notify\.cfg' "${PRINTER_CFG}"
assert_eq "status_printer_cfg_include: present nach Einfügen" \
    "present" "$(status_printer_cfg_include)"
rm -f "${PRINTER_CFG}.bak.test"

# Test B: Mit SAVE_CONFIG-Block — Include muss DAVOR stehen
clean_test
cat > "${PRINTER_CFG}" << 'EOF'
[printer]
kinematics: corexy

#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.
#*#
#*# [bed_mesh default]
#*# version = 1
EOF
cp -a "${PRINTER_CFG}" "${PRINTER_CFG}.bak.test"
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

_inc_line=$(grep -n 'ha_notify\.cfg' "${PRINTER_CFG}" | head -1 | cut -d: -f1)
_sc_line=$(grep -n 'SAVE_CONFIG' "${PRINTER_CFG}" | head -1 | cut -d: -f1)
assert_eq "Include steht VOR SAVE_CONFIG-Block" \
    "yes" "$([ "${_inc_line}" -lt "${_sc_line}" ] && echo yes || echo no)"
assert_file_contains "SAVE_CONFIG-Block bleibt erhalten" \
    '^#\*# <-+ SAVE_CONFIG' "${PRINTER_CFG}"
assert_eq "status_printer_cfg_include: present nach SAVE_CONFIG-Einfügen" \
    "present" "$(status_printer_cfg_include)"
rm -f "${PRINTER_CFG}.bak.test"

teardown_section

# ============================================================
# Security: chmod auto-fix
# ============================================================
section "Security: chmod auto-fix"
setup_section

# Simuliert den Auto-Fix-Code aus install.sh
if [ "${PERMS_SUPPORTED}" = "1" ]; then
    clean_test
    printf 'HA_URL=x\nHA_TOKEN=y\nHA_SERVICE=z\n' > "${NOTIFY_CONF}"
    chmod 644 "${NOTIFY_CONF}"
    S_PERMS="$(status_conf_perms)"
    [[ "${S_PERMS}" == insecure:* ]] && chmod 600 "${NOTIFY_CONF}"
    assert_file_perms "auto-fix korrigiert 644 → 600" "600" "${NOTIFY_CONF}"
    assert_eq "status_conf_perms: ok nach auto-fix" "ok" "$(status_conf_perms)"

    clean_test
    printf 'HA_URL=x\nHA_TOKEN=y\nHA_SERVICE=z\n' > "${NOTIFY_CONF}"
    chmod 600 "${NOTIFY_CONF}"
    S_PERMS="$(status_conf_perms)"
    [[ "${S_PERMS}" == insecure:* ]] && chmod 600 "${NOTIFY_CONF}" || true
    assert_file_perms "auto-fix lässt korrekte 600 unverändert" "600" "${NOTIFY_CONF}"
else
    skip "auto-fix korrigiert 644 → 600"          "POSIX-Permissions nicht verfügbar (Windows/NTFS)"
    skip "status_conf_perms: ok nach auto-fix"    "POSIX-Permissions nicht verfügbar (Windows/NTFS)"
    skip "auto-fix lässt korrekte 600 unverändert" "POSIX-Permissions nicht verfügbar (Windows/NTFS)"
fi

teardown_section

# ============================================================
# Ergebnis
# ============================================================
TOTAL=$((PASS+FAIL+SKIP))
printf '\n%b════════════════════════════════════%b\n' "${C_CYAN}" "${C_RESET}"
printf '  Tests: %d | ✔ %d | ✘ %d | ⊘ %d\n' "${TOTAL}" "${PASS}" "${FAIL}" "${SKIP}"
printf '%b════════════════════════════════════%b\n' "${C_CYAN}" "${C_RESET}"
if [ "${SYMLINKS_SUPPORTED}" = "0" ] || [ "${PERMS_SUPPORTED}" = "0" ]; then
    printf '%b!%b Übersprungene Tests auf dem Pi ausführen:\n' "${C_YELLOW}" "${C_RESET}"
    [ "${SYMLINKS_SUPPORTED}" = "0" ] && printf '    - Symlinks (ln -s)\n'
    [ "${PERMS_SUPPORTED}" = "0" ]    && printf '    - POSIX-Permissions (chmod)\n'
    printf '  → auf dem Pi: bash ~/Klipper-HA-Notify/tests/run_tests.sh\n'
fi

[ "${FAIL}" -eq 0 ]
