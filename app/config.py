"""
Application settings, loaded from environment variables (.env in dev).
No secret ever has a hardcoded default that would work in production —
anything security-sensitive that's missing causes a startup failure
instead of silently running insecurely.
"""
import os
import sys
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def _get(name: str, default: str | None = None, required: bool = False) -> str:
    val = os.environ.get(name, default)
    if required and not val:
        print(f"FATAL: required environment variable {name} is not set. "
              f"See .env.example and scripts/gen_secrets.py.", file=sys.stderr)
        sys.exit(1)
    return val


class Settings:
    # Where config.json / knowledge_base.json live. MUST be outside of
    # any directory served as static files.
    DATA_DIR: Path = Path(_get("DATA_DIR", str(BASE_DIR / "data")))

    # Directory of static, public assets (site HTML, images). Nothing
    # secret is ever allowed to live under here.
    PUBLIC_DIR: Path = Path(_get("PUBLIC_DIR", str(BASE_DIR / "public")))

    PORT: int = int(_get("PORT", "443"))
    HOST: str = _get("HOST", "0.0.0.0")

    # SSL/TLS Certificate paths (HTTPS)
    SSL_CERT_FILE: str = _get("SSL_CERT_FILE", str(BASE_DIR / "certs" / "server.crt"))
    SSL_KEY_FILE: str = _get("SSL_KEY_FILE", str(BASE_DIR / "certs" / "server.key"))

    # Comma-separated list of origins allowed to call the API. Same-origin
    # browser requests don't need this, but keep it explicit rather than "*".
    ALLOWED_ORIGINS: list[str] = [
        o.strip() for o in _get("ALLOWED_ORIGINS", "").split(",") if o.strip()
    ]

    # Used to sign session cookies and CSRF tokens (itsdangerous).
    SECRET_KEY: str = _get("SECRET_KEY", required=True)

    # Used to encrypt the LLM API key at rest (Fernet / cryptography).
    # Generate with scripts/gen_secrets.py.
    ENCRYPTION_KEY: str = _get("ENCRYPTION_KEY", required=True)

    ADMIN_USERNAME: str = _get("ADMIN_USERNAME", "admin")
    # bcrypt hash, never a plaintext password. Generate with scripts/gen_secrets.py.
    ADMIN_PASSWORD_HASH: str = _get("ADMIN_PASSWORD_HASH", required=True)

    SESSION_TTL_SECONDS: int = int(_get("SESSION_TTL_SECONDS", "3600"))

    # Only set this true when actually serving over HTTPS (prod). Cookies
    # with Secure=True are silently dropped by browsers over plain HTTP,
    # so local http-only dev should set COOKIE_SECURE=false.
    COOKIE_SECURE: bool = _get("COOKIE_SECURE", "true").lower() == "true"

    # Basic anti-abuse limits (per IP).
    RATE_LIMIT_CHAT: str = _get("RATE_LIMIT_CHAT", "20/minute")
    RATE_LIMIT_LOGIN: str = _get("RATE_LIMIT_LOGIN", "5/minute")

    MAX_UPLOAD_IMAGE_BYTES: int = 4 * 1024 * 1024
    MAX_UPLOAD_DOC_BYTES: int = 8 * 1024 * 1024
    KB_MAX_CHARS_PER_DOC: int = 50_000
    KB_MAX_TOTAL_ENTRIES: int = 100

    # ── Chat session cap ──────────────────────────────────────────
    MAX_CHAT_EXCHANGES: int = int(_get("MAX_CHAT_EXCHANGES", "15"))

    # ── Appointment booking ────────────────────────────────────────
    APPT_TIMEZONE: str = _get("APPT_TIMEZONE", "Asia/Kuwait")
    APPT_SLOT_MINUTES: int = int(_get("APPT_SLOT_MINUTES", "30"))
    APPT_DAY_START_HOUR: int = int(_get("APPT_DAY_START_HOUR", "9"))
    APPT_DAY_END_HOUR: int = int(_get("APPT_DAY_END_HOUR", "17"))
    APPT_WORKDAYS: list[int] = [
        int(d) for d in _get("APPT_WORKDAYS", "0,1,2,3,4").split(",") if d.strip() != ""
    ]  # Mon=0 .. Sun=6
    APPT_MAX_DAYS_AHEAD: int = int(_get("APPT_MAX_DAYS_AHEAD", "30"))
    RATE_LIMIT_APPOINTMENT: str = _get("RATE_LIMIT_APPOINTMENT", "6/hour")

    # Google Calendar (optional — booking still works locally if unset,
    # it just won't sync to a calendar). Service-account file must be
    # shared ("make changes to events") with GOOGLE_CALENDAR_ID.
    GOOGLE_SERVICE_ACCOUNT_FILE: str = _get("GOOGLE_SERVICE_ACCOUNT_FILE", "")
    GOOGLE_CALENDAR_ID: str = _get("GOOGLE_CALENDAR_ID", "")


settings = Settings()
settings.DATA_DIR.mkdir(parents=True, exist_ok=True)
(settings.PUBLIC_DIR / "static" / "images").mkdir(parents=True, exist_ok=True)

# Fail fast at startup rather than on the first /api/chat or /api/appointment
# request. This also catches the case where the IANA tz database itself is
# missing (e.g. some minimal/Windows Python installs) — the "tzdata" package
# in requirements.txt covers that; if this still fails after installing
# dependencies, APPT_TIMEZONE in .env is misconfigured.
try:
    ZoneInfo(settings.APPT_TIMEZONE)
except ZoneInfoNotFoundError:
    print(
        f"FATAL: APPT_TIMEZONE={settings.APPT_TIMEZONE!r} could not be loaded. "
        f"Either it is not a valid IANA timezone name, or the tz database is "
        f"missing from this Python install (run: pip install tzdata).",
        file=sys.stderr,
    )
    sys.exit(1)

# A local, gitignored reference file with the current admin username and
# how to get in if the password is lost. The plaintext password itself is
# never written here (or anywhere, after the moment it's first chosen) —
# only its one-way bcrypt hash is ever stored, in .env or config.json.
try:
    (BASE_DIR / "admin_access.secret").write_text(
        "Perennia — Admin Access\n"
        f"Username: {settings.ADMIN_USERNAME}\n\n"
        "Password: not stored in plaintext anywhere in this system.\n"
        "  - Forgot it? Use \"Forgot password?\" on the /admin login screen —\n"
        "    it writes a reset link to password_reset.secret in this same\n"
        "    folder (also logged to the server console).\n"
        "  - Setting up for the first time? Run scripts/gen_secrets.py, which\n"
        "    writes admin_credentials.secret with the plaintext password you\n"
        "    just chose (the only point it's ever available in plaintext).\n",
        encoding="utf-8",
    )
except OSError:
    pass  # non-fatal — read-only filesystem or similar; not worth crashing startup over
