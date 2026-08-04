#!/usr/bin/env python3
"""
Generates/merges .env for the Windows installer (installer.bat).

Mirrors install.sh's behavior on Linux: existing values in .env are
preserved on re-run (so re-installing to pick up a code update doesn't
invalidate admin sessions or the encrypted LLM API key) unless --force is
passed. The one deliberate difference from install.sh's defaults is that
this generates a *plain-HTTP, localhost-only* config — HOST=127.0.0.1 and
COOKIE_SECURE=false — because a double-click Windows install has no
reverse proxy or TLS certificate in front of it. Cookies marked Secure are
silently dropped by browsers over plain HTTP, which would otherwise make
the admin panel login appear broken with no obvious cause.

Not meant to be run directly by a person — installer.bat calls this with
the venv's own Python after dependencies are installed.
"""
import argparse
import os
import re
import secrets
import string
import sys
from pathlib import Path

import bcrypt
from cryptography.fernet import Fernet

BASE_DIR = Path(__file__).resolve().parent.parent

_BCRYPT_RE = re.compile(r"^\$2[aby]\$\d{2}\$.{53}$")


def is_valid_fernet_key(value: str) -> bool:
    """True only if `value` actually works as a Fernet key — not just
    present. A hand-copied .env.example still has the literal placeholder
    text 'your-encryption-key-here-base64' in this field, which is
    non-empty but not a real key; trusting presence alone crashes the
    app on startup with a cryptic base64-padding error."""
    if not value:
        return False
    try:
        Fernet(value.encode("utf-8"))
        return True
    except Exception:
        return False


def is_valid_bcrypt_hash(value: str) -> bool:
    """True only if `value` looks like a real bcrypt hash (e.g.
    '$2b$12$...', 60 chars), not the .env.example placeholder text
    or something else that happens to be non-empty."""
    return bool(value) and bool(_BCRYPT_RE.match(value))


def is_usable_secret_key(value: str) -> bool:
    """SECRET_KEY has no fixed format, so this is just a sanity floor:
    non-empty, reasonably long, and not the literal example placeholder."""
    return bool(value) and len(value) >= 32 and "your-secret-key-here" not in value


def parse_env_file(path: Path) -> dict:
    existing = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            existing[k.strip()] = v.strip()
    return existing


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=str(BASE_DIR / ".env"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default="8001")
    parser.add_argument("--port-explicit", action="store_true",
                         help="If set, --port always overwrites any existing PORT in .env")
    parser.add_argument("--admin-username", default="admin")
    parser.add_argument("--admin-password", default="")
    parser.add_argument("--force", action="store_true",
                         help="Regenerate SECRET_KEY / ENCRYPTION_KEY / ADMIN_PASSWORD_HASH even if set")
    parser.add_argument("--out-password-file", default="",
                         help="If a password is auto-generated, it's written here (installer.bat reads it back)")
    parser.add_argument("--status-file", default="",
                         help="If set, HOST/PORT/ADMIN_USERNAME/REGENERATED are also written here as KEY=VALUE "
                              "lines, so a caller doesn't need to parse stdout")
    args = parser.parse_args()

    env_file = Path(args.env_file)
    existing = parse_env_file(env_file)

    def get(key, default=""):
        return existing.get(key, default)

    # An existing .env only counts as a genuine prior install (worth
    # preserving) if ALL THREE of its security-critical values are
    # actually usable. If even one is a placeholder or corrupt (e.g. a
    # hand-copied .env.example, or a partial/failed previous run), the
    # whole file is untrustworthy — including HOST/PORT/passthrough
    # values — rather than selectively trusting whichever individual
    # fields happen to look present. Mixing "trust the placeholder host
    # and port" with "generate a fresh key" is exactly what produced a
    # working-looking install that crashed on first launch.
    existing_is_genuine = (
        is_usable_secret_key(get("SECRET_KEY"))
        and is_valid_fernet_key(get("ENCRYPTION_KEY"))
        and is_valid_bcrypt_hash(get("ADMIN_PASSWORD_HASH"))
    )
    if existing and not existing_is_genuine:
        print(
            "WARNING: an existing .env was found but its saved secrets aren't valid "
            "(likely a hand-copied .env.example, or an incomplete previous setup) -- "
            "ignoring its contents entirely and generating a fresh configuration.",
            file=sys.stderr,
        )
        existing = {}

    need_secret_key = args.force or not get("SECRET_KEY")
    need_encryption_key = args.force or not get("ENCRYPTION_KEY")
    need_admin_hash = args.force or not get("ADMIN_PASSWORD_HASH")

    secret_key = secrets.token_urlsafe(48) if need_secret_key else get("SECRET_KEY")
    encryption_key = Fernet.generate_key().decode() if need_encryption_key else get("ENCRYPTION_KEY")

    generated_password = None
    if need_admin_hash:
        admin_password = args.admin_password or ""
        if not admin_password:
            alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_"
            admin_password = "".join(secrets.choice(alphabet) for _ in range(20))
            generated_password = admin_password
        admin_password_hash = bcrypt.hashpw(
            admin_password.encode("utf-8"), bcrypt.gensalt(rounds=12)
        ).decode()
    else:
        admin_password_hash = get("ADMIN_PASSWORD_HASH")

    host = get("HOST") or args.host
    port = args.port if args.port_explicit else (get("PORT") or args.port)
    admin_username = get("ADMIN_USERNAME") or args.admin_username

    # Anything else the app understands is preserved verbatim if already
    # present; otherwise the app's own built-in default applies by simply
    # not writing that key into .env at all.
    passthrough_keys = [
        "ALLOWED_ORIGINS", "COOKIE_SECURE", "SESSION_TTL_SECONDS",
        "RATE_LIMIT_CHAT", "RATE_LIMIT_LOGIN",
        "MAX_CHAT_EXCHANGES",
        "APPT_TIMEZONE", "APPT_SLOT_MINUTES", "APPT_DAY_START_HOUR",
        "APPT_DAY_END_HOUR", "APPT_WORKDAYS", "APPT_MAX_DAYS_AHEAD",
        "RATE_LIMIT_APPOINTMENT",
        "GOOGLE_SERVICE_ACCOUNT_FILE", "GOOGLE_CALENDAR_ID",
    ]
    passthrough = {k: existing[k] for k in passthrough_keys if k in existing}
    # Local, plain-HTTP install by default — see module docstring.
    cookie_secure = passthrough.pop("COOKIE_SECURE", "false")

    lines = []
    lines.append("#########################################")
    lines.append("# Application")
    lines.append("#########################################")
    lines.append("")
    lines.append(f"HOST={host}")
    lines.append(f"PORT={port}")
    lines.append(f"ALLOWED_ORIGINS={passthrough.pop('ALLOWED_ORIGINS', '')}")
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

    env_file.write_text("\n".join(lines), encoding="utf-8")
    try:
        os.chmod(env_file, 0o600)  # no-op on Windows, harmless; matches the Linux installers
    except OSError:
        pass

    # start-server.bat is regenerated on every install so it always
    # reflects the current HOST/PORT, and re-reads .env at launch time
    # (rather than baking values in) so a later hand-edit of .env is
    # picked up without re-running the installer.
    start_script = BASE_DIR / "start-server.bat"
    start_script.write_text(
        "@echo off\r\n"
        "cd /d \"%~dp0\"\r\n"
        "set \"HOST=127.0.0.1\"\r\n"
        "set \"PORT=8001\"\r\n"
        "for /f \"usebackq tokens=2 delims==\" %%a in (`findstr /b /c:\"HOST=\" .env`) do set \"HOST=%%a\"\r\n"
        "for /f \"usebackq tokens=2 delims==\" %%a in (`findstr /b /c:\"PORT=\" .env`) do set \"PORT=%%a\"\r\n"
        "echo.\r\n"
        "echo ============================================================\r\n"
        "echo   Starting Perennia on http://%HOST%:%PORT%\r\n"
        "echo   Admin panel: http://%HOST%:%PORT%/admin\r\n"
        "echo   Press Ctrl+C to stop the server.\r\n"
        "echo ============================================================\r\n"
        "echo.\r\n"
        "\"%~dp0venv\\Scripts\\python.exe\" -m uvicorn app.main:app --host %HOST% --port %PORT%\r\n"
        "pause\r\n",
        encoding="utf-8",
    )

    if generated_password and args.out_password_file:
        Path(args.out_password_file).write_text(generated_password, encoding="utf-8")

    status_lines = [
        f"HOST={host}",
        f"PORT={port}",
        f"ADMIN_USERNAME={admin_username}",
        f"REGENERATED={'yes' if (need_secret_key or need_encryption_key or need_admin_hash) else 'no'}",
    ]
    if args.status_file:
        Path(args.status_file).write_text("\n".join(status_lines) + "\n", encoding="utf-8")
    print("\n".join(status_lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
