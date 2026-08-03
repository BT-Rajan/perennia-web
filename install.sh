#!/usr/bin/env bash
###############################################################################
# Perennia — end-to-end installer
# Target: Ubuntu 22.04/24.04 server already running CloudPanel
#
# What this does:
#   1. Installs every system dependency the app needs (python3-venv, pip,
#      node/npm, pm2) — nothing is assumed to be pre-installed.
#   2. Creates a venv and installs requirements.txt into it.
#   3. Generates .env (secrets are created once and preserved on re-run).
#   4. Starts the app under PM2 as a process named "web", bound ONLY to
#      127.0.0.1:<APP_PORT> (default 8001) — never to 0.0.0.0 — and enables
#      pm2 startup so it survives reboots.
#   5. Wires the app up to HTTPS on the standard port 443 by asking
#      CloudPanel's own Nginx (via `clpctl`) to create a reverse-proxy vhost
#      for your domain that forwards to 127.0.0.1:<APP_PORT>, then issues a
#      free Let's Encrypt certificate for it.
#
# Why this can't clash with CloudPanel:
#   - CloudPanel's admin UI has its own dedicated port, 8443, which this
#     script never touches.
#   - Ports 80/443 are already owned by CloudPanel's system Nginx, which
#     multiplexes every site on the box by domain name (SNI/vhosts). This
#     script never binds the app itself to 80/443/8443 — it only ever adds
#     ONE MORE vhost entry to the Nginx CloudPanel already runs, the exact
#     same mechanism CloudPanel itself uses for every other site on the
#     server. The app process only ever listens on 127.0.0.1:<APP_PORT>,
#     which is private to the box and invisible from the internet.
#
# Safe to re-run: existing secrets in .env are preserved unless --force is
# passed, so re-running this to pick up a code update does NOT invalidate
# admin sessions, the admin password, or the encrypted LLM API key. Existing
# CloudPanel sites/certificates are also left alone if already present.
###############################################################################

set -Eeuo pipefail

APP_NAME="web"
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${APP_DIR}/venv"
ENV_FILE="${APP_DIR}/.env"

cd "${APP_DIR}"

APP_HOST="127.0.0.1"
APP_PORT="8001"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=""
FORCE_REGEN=0
PORT_EXPLICIT=0

DOMAIN=""
LE_EMAIL=""
SITE_USER=""
SITE_USER_PASSWORD=""
SKIP_CLOUDPANEL=0
CLOUDPANEL_RESERVED_PORT="8443"

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

###############################################################################

GREEN="\033[32m"
RED="\033[31m"
BLUE="\033[36m"
YELLOW="\033[33m"
NC="\033[0m"

step() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}! $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

trap 'echo -e "${RED}Installer failed on line ${LINENO}. See the message above for details.${NC}"' ERR

###############################################################################
# Argument parsing
###############################################################################

usage() {
    cat <<EOF
Usage: sudo ./install.sh --domain app.example.com --email you@example.com [options]

Required for HTTPS on 443 (skip both to install app-only, no public HTTPS):
  --domain DOMAIN             Public domain/subdomain already pointed (A record)
                               at this server. A CloudPanel reverse-proxy site
                               + free Let's Encrypt cert is created for it.
  --email EMAIL                Email used for the Let's Encrypt certificate.

Optional:
  --port PORT                 Internal app port, 127.0.0.1 only (default: 8001).
                               Takes effect on every run, including re-installs
                               — an explicit --port always overwrites whatever
                               PORT is currently in .env.
  --site-user NAME             CloudPanel site user to own the vhost
                               (default: auto-derived from domain).
  --site-user-password PASS    CloudPanel site user password
                               (default: auto-generated and printed once).
  --admin-username NAME        App admin login username (default: admin,
                               only used on first install).
  --admin-password PASS        App admin login password (default:
                               auto-generated and printed once).
  --force                      Regenerate SECRET_KEY / ENCRYPTION_KEY /
                               ADMIN_PASSWORD_HASH even if .env exists. This
                               logs everyone out and makes any previously
                               saved LLM API key unrecoverable.
  --skip-cloudpanel             Only install/start the app; don't touch
                               CloudPanel/Nginx/SSL at all.
  -h, --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain) DOMAIN="$2"; shift 2 ;;
        --email) LE_EMAIL="$2"; shift 2 ;;
        --port) APP_PORT="$2"; PORT_EXPLICIT=1; shift 2 ;;
        --site-user) SITE_USER="$2"; shift 2 ;;
        --site-user-password) SITE_USER_PASSWORD="$2"; shift 2 ;;
        --admin-username) ADMIN_USERNAME="$2"; shift 2 ;;
        --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
        --force) FORCE_REGEN=1; shift ;;
        --skip-cloudpanel) SKIP_CLOUDPANEL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1 (see --help)" ;;
    esac
done

if [ "${APP_PORT}" = "${CLOUDPANEL_RESERVED_PORT}" ]; then
    fail "--port ${APP_PORT} is reserved for the CloudPanel admin UI. Choose a different internal port."
fi

###############################################################################

clear
echo
echo "============================================================"
echo "                PERENNIA INSTALLER"
echo "============================================================"
echo
echo "Application : ${APP_NAME}"
echo "Directory   : ${APP_DIR}"
echo "Server IP   : ${SERVER_IP:-unknown}"
echo "Domain      : ${DOMAIN:-<none — app-only install>}"
echo

###############################################################################
step "1/9 Installing System Dependencies"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null || fail "This step needs root or sudo. Re-run as root, or install sudo first."
    SUDO="sudo"
fi

if ! command -v python3 >/dev/null || ! python3 -m venv --help >/dev/null 2>&1 || ! command -v pip3 >/dev/null; then
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq python3 python3-venv python3-pip curl >/dev/null
fi
command -v python3 >/dev/null || fail "python3 install failed"
ok "python3 / venv / pip ready"

if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
    warn "Node.js/npm not found — installing Node.js 20.x LTS"
    curl -fsSL https://deb.nodesource.com/setup_20.x | ${SUDO} bash - >/dev/null 2>&1
    ${SUDO} apt-get install -y -qq nodejs >/dev/null
fi
command -v node >/dev/null || fail "Node.js install failed"
ok "node $(node --version) / npm $(npm --version) ready"

if ! command -v pm2 >/dev/null; then
    ${SUDO} npm install -g pm2 --silent
fi
command -v pm2 >/dev/null || fail "pm2 install failed"
ok "pm2 $(pm2 --version) ready"

###############################################################################
step "2/9 Checking For Port Clashes"

# The app must NEVER bind to 80, 443 or 8443 — those belong to CloudPanel's
# Nginx and the CloudPanel admin UI respectively. We only ever bind to
# 127.0.0.1 on an internal port, so we just confirm that internal port is
# actually free before pm2 tries to use it.
if command -v ss >/dev/null && ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${APP_PORT}\$"; then
    if pm2 describe "${APP_NAME}" >/dev/null 2>&1; then
        warn "Port ${APP_PORT} is in use — assuming it's this app's existing pm2 process, will be restarted."
    else
        fail "Port ${APP_PORT} is already in use by something else. Pick a different --port."
    fi
fi
ok "App will bind privately to 127.0.0.1:${APP_PORT} only (80/443/8443 left untouched for CloudPanel)"

###############################################################################
step "3/9 Creating Virtual Environment"

if [ ! -d "${VENV_DIR}" ]; then
    python3 -m venv "${VENV_DIR}" || fail "Could not create venv."
fi
source "${VENV_DIR}/bin/activate"
python --version
ok "Virtual environment ready"

###############################################################################
step "4/9 Installing Python Packages"

python -m pip install --upgrade pip -q
[ -f requirements.txt ] && pip install -r requirements.txt -q
ok "Dependencies installed"

###############################################################################
step "5/9 Generating Configuration (.env)"

GENERATED_PASSWORD_FILE="$(mktemp)"
trap 'rm -f "${GENERATED_PASSWORD_FILE}"' EXIT

FORCE_REGEN="${FORCE_REGEN}" \
ENV_FILE="${ENV_FILE}" \
IN_HOST="${APP_HOST}" \
IN_PORT="${APP_PORT}" \
PORT_EXPLICIT="${PORT_EXPLICIT}" \
IN_ADMIN_USERNAME="${ADMIN_USERNAME}" \
IN_ADMIN_PASSWORD="${ADMIN_PASSWORD}" \
IN_COOKIE_SECURE="$([ -n "${DOMAIN}" ] && echo true || echo true)" \
IN_ALLOWED_ORIGINS="$([ -n "${DOMAIN}" ] && echo "https://${DOMAIN}" || echo "")" \
OUT_PASSWORD_FILE="${GENERATED_PASSWORD_FILE}" \
python - <<'PYEOF'
import os
import secrets
import string

import bcrypt
from cryptography.fernet import Fernet

env_file = os.environ["ENV_FILE"]
force = os.environ.get("FORCE_REGEN") == "1"

existing = {}
if os.path.exists(env_file):
    with open(env_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            existing[k.strip()] = v.strip()

def get(key, default=""):
    return existing.get(key, default)

need_secret_key = force or not get("SECRET_KEY")
need_encryption_key = force or not get("ENCRYPTION_KEY")
need_admin_hash = force or not get("ADMIN_PASSWORD_HASH")

secret_key = secrets.token_urlsafe(48) if need_secret_key else get("SECRET_KEY")
encryption_key = Fernet.generate_key().decode() if need_encryption_key else get("ENCRYPTION_KEY")

generated_password = None
if need_admin_hash:
    admin_password = os.environ.get("IN_ADMIN_PASSWORD") or ""
    if not admin_password:
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_"
        admin_password = "".join(secrets.choice(alphabet) for _ in range(20))
        generated_password = admin_password
    admin_password_hash = bcrypt.hashpw(
        admin_password.encode("utf-8"), bcrypt.gensalt(rounds=12)
    ).decode()
else:
    admin_password_hash = get("ADMIN_PASSWORD_HASH")

host = get("HOST") or os.environ.get("IN_HOST", "127.0.0.1")

# An explicitly-passed --port must always win, even on a re-install where
# .env already has some (possibly stale/wrong) PORT value — otherwise
# --port is silently a no-op after the very first install, which is
# exactly the trap that cost a lot of debugging time in practice.
port_explicit = os.environ.get("PORT_EXPLICIT") == "1"
if port_explicit:
    port = os.environ.get("IN_PORT", "8001")
else:
    port = get("PORT") or os.environ.get("IN_PORT", "8001")
admin_username = get("ADMIN_USERNAME") or os.environ.get("IN_ADMIN_USERNAME", "admin")
allowed_origins = get("ALLOWED_ORIGINS") or os.environ.get("IN_ALLOWED_ORIGINS", "")
cookie_secure = get("COOKIE_SECURE") or os.environ.get("IN_COOKIE_SECURE", "true")

passthrough_keys = [
    "SESSION_TTL_SECONDS", "RATE_LIMIT_CHAT", "RATE_LIMIT_LOGIN",
    "MAX_CHAT_EXCHANGES", "APPT_TIMEZONE", "APPT_SLOT_MINUTES",
    "APPT_DAY_START_HOUR", "APPT_DAY_END_HOUR", "APPT_WORKDAYS",
    "APPT_MAX_DAYS_AHEAD", "RATE_LIMIT_APPOINTMENT",
    "GOOGLE_SERVICE_ACCOUNT_FILE", "GOOGLE_CALENDAR_ID",
]
passthrough = {k: existing[k] for k in passthrough_keys if k in existing}

lines = []
lines.append("#########################################")
lines.append("# Application")
lines.append("#########################################")
lines.append("")
lines.append(f"HOST={host}")
lines.append(f"PORT={port}")
lines.append(f"ALLOWED_ORIGINS={allowed_origins}")
lines.append("")
lines.append("#########################################")
lines.append("# Security")
lines.append("#########################################")
lines.append("")
lines.append(f"SECRET_KEY={secret_key}")
lines.append(f"ENCRYPTION_KEY={encryption_key}")
lines.append(f"ADMIN_USERNAME={admin_username}")
lines.append(f"ADMIN_PASSWORD_HASH={admin_password_hash}")
lines.append(f"COOKIE_SECURE={cookie_secure}")
lines.append(f"SESSION_TTL_SECONDS={passthrough.pop('SESSION_TTL_SECONDS', '3600')}")
lines.append("")
lines.append("#########################################")
lines.append("# Rate limits (per client IP)")
lines.append("#########################################")
lines.append("")
lines.append(f"RATE_LIMIT_CHAT={passthrough.pop('RATE_LIMIT_CHAT', '20/minute')}")
lines.append(f"RATE_LIMIT_LOGIN={passthrough.pop('RATE_LIMIT_LOGIN', '5/minute')}")
lines.append("")
lines.append("#########################################")
lines.append("# Chat session cap")
lines.append("#########################################")
lines.append("")
lines.append(f"MAX_CHAT_EXCHANGES={passthrough.pop('MAX_CHAT_EXCHANGES', '15')}")
lines.append("")
lines.append("#########################################")
lines.append("# Appointment booking")
lines.append("#########################################")
lines.append("")
lines.append(f"APPT_TIMEZONE={passthrough.pop('APPT_TIMEZONE', 'Asia/Kuwait')}")
lines.append(f"APPT_SLOT_MINUTES={passthrough.pop('APPT_SLOT_MINUTES', '30')}")
lines.append(f"APPT_DAY_START_HOUR={passthrough.pop('APPT_DAY_START_HOUR', '9')}")
lines.append(f"APPT_DAY_END_HOUR={passthrough.pop('APPT_DAY_END_HOUR', '17')}")
lines.append(f"APPT_WORKDAYS={passthrough.pop('APPT_WORKDAYS', '0,1,2,3,4')}")
lines.append(f"APPT_MAX_DAYS_AHEAD={passthrough.pop('APPT_MAX_DAYS_AHEAD', '30')}")
lines.append(f"RATE_LIMIT_APPOINTMENT={passthrough.pop('RATE_LIMIT_APPOINTMENT', '6/hour')}")
lines.append("")
lines.append("#########################################")
lines.append("# Google Calendar sync (optional)")
lines.append("#########################################")
lines.append("")
lines.append(f"GOOGLE_SERVICE_ACCOUNT_FILE={passthrough.pop('GOOGLE_SERVICE_ACCOUNT_FILE', '')}")
lines.append(f"GOOGLE_CALENDAR_ID={passthrough.pop('GOOGLE_CALENDAR_ID', '')}")
lines.append("")
lines.append("#########################################")
lines.append("# Environment")
lines.append("#########################################")
lines.append("")
lines.append("ENVIRONMENT=production")
lines.append("DEBUG=false")
lines.append("")

with open(env_file, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
os.chmod(env_file, 0o600)

if generated_password:
    with open(os.environ["OUT_PASSWORD_FILE"], "w", encoding="utf-8") as f:
        f.write(generated_password)
PYEOF

chmod 600 "${ENV_FILE}"
ok ".env written to ${ENV_FILE} (mode 600)"

if [ "${FORCE_REGEN}" = "1" ]; then
    warn "--force was set: SECRET_KEY, ENCRYPTION_KEY and ADMIN_PASSWORD_HASH were regenerated."
    warn "All admin sessions are now invalid, and any previously-saved LLM API key can no longer be decrypted."
fi

GENERATED_PASSWORD=""
if [ -s "${GENERATED_PASSWORD_FILE}" ]; then
    GENERATED_PASSWORD="$(cat "${GENERATED_PASSWORD_FILE}")"
fi
rm -f "${GENERATED_PASSWORD_FILE}"
trap - EXIT

###############################################################################
step "6/9 Creating Directories & Permissions"

mkdir -p logs uploads storage data
chmod +x ./*.sh 2>/dev/null || true
chmod 600 "${ENV_FILE}"
chmod 700 data logs uploads storage 2>/dev/null || true
ok "Directories created, permissions set (secrets + data private, venv untouched)"

###############################################################################
step "7/9 Starting Application Under PM2 (process: ${APP_NAME})"

pm2 delete "${APP_NAME}" >/dev/null 2>&1 || true

RUN_HOST="$(grep -E '^HOST=' "${ENV_FILE}" | cut -d= -f2-)"
RUN_PORT="$(grep -E '^PORT=' "${ENV_FILE}" | cut -d= -f2-)"

pm2 start \
"${VENV_DIR}/bin/python" \
--name "${APP_NAME}" \
--cwd "${APP_DIR}" \
-- \
-m uvicorn app.main:app \
--host "${RUN_HOST}" \
--port "${RUN_PORT}"

pm2 save
pm2 startup systemd -u "$(whoami)" --hp "$HOME" >/dev/null 2>&1 || true
pm2 save
ok "App running under pm2 as '${APP_NAME}' on ${RUN_HOST}:${RUN_PORT} (private, not internet-facing)"

###############################################################################
step "8/9 Wiring Up HTTPS on 443 via CloudPanel"

CLOUDPANEL_CONFIGURED=0
if [ "${SKIP_CLOUDPANEL}" = "1" ]; then
    warn "--skip-cloudpanel set: leaving CloudPanel/Nginx/SSL untouched."
elif [ -z "${DOMAIN}" ]; then
    warn "No --domain given: skipping HTTPS setup. App is only reachable on 127.0.0.1:${RUN_PORT} on the server itself."
    warn "Re-run with --domain your.domain.com --email you@example.com once DNS is pointed at ${SERVER_IP:-this server}."
elif ! command -v clpctl >/dev/null; then
    warn "clpctl not found — this doesn't look like a CloudPanel server. Skipping HTTPS wiring."
    warn "In CloudPanel: Sites > Add Site > Reverse Proxy, domain=${DOMAIN}, target=http://127.0.0.1:${RUN_PORT}, then request a Let's Encrypt cert."
else
    [ -n "${SITE_USER}" ] || SITE_USER="$(echo "${DOMAIN}" | tr -c 'a-zA-Z0-9' '-' | cut -c1-32 | sed 's/^-*//;s/-*$//')"
    [ -n "${SITE_USER_PASSWORD}" ] || SITE_USER_PASSWORD="$(python3 - <<'PY'
import secrets, string
print(''.join(secrets.choice(string.ascii_letters + string.digits + "!@#%^*-_") for _ in range(20)))
PY
)"

    if clpctl site:list 2>/dev/null | grep -qi "${DOMAIN}"; then
        ok "CloudPanel site for ${DOMAIN} already exists — leaving it as-is."
    else
        clpctl site:add:reverse-proxy \
            --domainName="${DOMAIN}" \
            --reverseProxyUrl="http://127.0.0.1:${RUN_PORT}" \
            --siteUser="${SITE_USER}" \
            --siteUserPassword="${SITE_USER_PASSWORD}" \
            && ok "CloudPanel reverse-proxy site created for ${DOMAIN} -> 127.0.0.1:${RUN_PORT}" \
            || warn "clpctl site:add:reverse-proxy failed — check DNS for ${DOMAIN} and create it manually in CloudPanel."
    fi

    if [ -n "${LE_EMAIL}" ]; then
        clpctl lets-encrypt:install:certificate --domainName="${DOMAIN}" \
            && ok "Let's Encrypt certificate installed for ${DOMAIN} (served on 443 by CloudPanel's Nginx)" \
            || warn "Certificate issuance failed — make sure ${DOMAIN} resolves to ${SERVER_IP:-this server} first, then run: clpctl lets-encrypt:install:certificate --domainName=${DOMAIN}"
    else
        warn "No --email given, skipped requesting a Let's Encrypt certificate. Run:"
        warn "  clpctl lets-encrypt:install:certificate --domainName=${DOMAIN}"
    fi
    CLOUDPANEL_CONFIGURED=1
fi

###############################################################################
step "9/9 Done"

pm2 status

RUN_ADMIN_USER="$(grep -E '^ADMIN_USERNAME=' "${ENV_FILE}" | cut -d= -f2-)"

echo
echo "============================================================"
echo "             INSTALLATION COMPLETED"
echo "============================================================"
echo
echo "Application  : ${APP_NAME} (pm2)"
echo "Directory    : ${APP_DIR}"
echo "Internal     : http://${RUN_HOST}:${RUN_PORT}  (private, localhost only)"
if [ "${CLOUDPANEL_CONFIGURED}" = "1" ]; then
echo "Public HTTPS : https://${DOMAIN}"
echo "CloudPanel admin UI stays on :8443, untouched by this install."
fi
echo
echo "Admin Login"
echo "-----------"
if [ "${CLOUDPANEL_CONFIGURED}" = "1" ]; then
echo "URL      : https://${DOMAIN}/admin"
else
echo "URL      : http://${RUN_HOST}:${RUN_PORT}/admin (put a domain + CloudPanel reverse proxy in front for HTTPS)"
fi
echo "Username : ${RUN_ADMIN_USER}"
if [ -n "${GENERATED_PASSWORD}" ]; then
    echo -e "Password : ${YELLOW}${GENERATED_PASSWORD}${NC}  (auto-generated — shown once, save it now)"
else
    echo "Password : unchanged from previous install (not shown). Use --force with --admin-password to reset it."
fi
if [ "${CLOUDPANEL_CONFIGURED}" = "1" ] && [ -n "${SITE_USER_PASSWORD}" ]; then
echo
echo "CloudPanel Site User (for SFTP/file manager on this vhost)"
echo "------------------------------------------------------------"
echo "User     : ${SITE_USER}"
echo -e "Password : ${YELLOW}${SITE_USER_PASSWORD}${NC}  (auto-generated — shown once, save it now)"
fi
echo
echo "Useful Commands"
echo "---------------"
echo "pm2 status"
echo "pm2 logs ${APP_NAME}"
echo "pm2 restart ${APP_NAME}"
echo "pm2 stop ${APP_NAME}"
echo
