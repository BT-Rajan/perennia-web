"""
Persistence for config.json and knowledge_base.json.

Both files live in settings.DATA_DIR, which is never mounted as a static
directory by main.py — there is no URL that serves them directly. All
reads/writes go through this module so every access point gets the same
atomic-write and schema-default handling.
"""
import datetime
import hmac
import json
import os
import threading
import uuid
from pathlib import Path
from typing import Any

from app.config import settings
from app.security import decrypt_secret, encrypt_secret, hash_token

_lock = threading.Lock()

# Serializes the full "check availability, then write" sequence for
# appointment booking. Guarding writes alone isn't enough here, since the
# race is between the availability check and the later insert, not inside
# add_appointment() itself.
BOOKING_LOCK = threading.Lock()

CONFIG_PATH = settings.DATA_DIR / "config.json"
KB_PATH = settings.DATA_DIR / "knowledge_base.json"
APPT_PATH = settings.DATA_DIR / "appointments.json"
STATS_PATH = settings.DATA_DIR / "daily_stats.json"
STATS_RETENTION_DAYS = 90

DEFAULT_CONFIG: dict[str, Any] = {
    "provider": "anthropic",
    "model": "claude-sonnet-4-6",
    "baseUrl": "",
    "apiKeyEncrypted": "",   # Fernet-encrypted at rest; never plaintext on disk
    "tone": "",
    "knowledge": {},         # ck-about-en, ck-vision-en, ... (see frontend)
    "contact": {
        "ct-email": "info@perennia.com",
        "ct-phone": "+965 0000 0000",
        "ct-addr-en": "Kuwait",
        "ct-addr-ar": "الكويت",
        "ct-title-en": "Contact Us",
        "ct-title-ar": "تواصل معنا",
        "ct-intro-en": "We'd love to hear from you. Reach out any time and our team will get back to you shortly.",
        "ct-intro-ar": "يسعدنا تواصلك معنا في أي وقت، وسيقوم فريقنا بالرد عليك في أقرب وقت ممكن.",
    },
    # Every visible string on the public landing page lives here so an admin
    # can edit it without touching code. The frontend fetches this via
    # GET /api/landing-config; the values below are only used until an admin
    # saves their own (or if the fetch ever fails).
    "landing": {
        "brandName-en": "PERENNIA",
        "brandName-ar": "بيرينيا",
        "showLogo": False,  # top-left image logo hidden by default; brand name text used instead
        "welcomeText-en": "Welcome",
        "welcomeText-ar": "أهلاً بك",
        "tagline-en": "Visit our V-Lounge for more",
        "tagline-ar": "زوروا V-Lounge الخاص بنا لمزيد من المعلومات",
        "subHeading-en": "AI-POWERED TECHNOLOGY & INNOVATION",
        "subHeading-ar": "تكنولوجيا وابتكار مدعومة بالذكاء الاصطناعي",
        "chatHint-en": "Tap to start chatting",
        "chatHint-ar": "اضغط لبدء المحادثة",
        "placeholder-en": "Ask about our solutions, products, or anything…",
        "placeholder-ar": "اسألني عن حلولنا أو منتجاتنا أو أي شيء آخر…",
        "navOurWork-en": "Our Work",
        "navOurWork-ar": "أعمالنا",
        "navContact-en": "Contact Us",
        "navContact-ar": "تواصل معنا",
        # Shown on the button itself — it's a toggle, so its label is always
        # the *other* language's name for itself.
        "langToggleFromEn": "AR | عربي",
        "langToggleFromAr": "EN | English",
        "footerText-en": "© 2024 PERENNIA · بيرينيا",
        "footerText-ar": "© 2024 بيرينيا · PERENNIA",
        "backgroundColor": "#001030",
        "chips-en": [
            "What does Perennia do?",
            "Tell me about your products",
            "Which industries do you serve?",
            "What makes you different?",
        ],
        "chips-ar": [
            "ما الذي تقدمه بيرينيا؟",
            "أخبرني عن منتجاتكم",
            "ما القطاعات التي تخدمونها؟",
            "ما الذي يميزكم؟",
        ],
        "faq-en": [
            "Tell me about the company",
            "What services do you offer?",
            "How to contact you?",
        ],
        "faq-ar": [
            "أخبرني عن الشركة",
            "ما الخدمات التي تقدمونها؟",
            "كيف يمكنني التواصل معكم؟",
        ],
        "ourWorkUrl": "",  # if set, nav link opens this external URL instead of the built-in /our-work page
        "contactUrl": "",  # same, for /contact-us
    },
    # Content for the standalone /our-work page.
    "pages": {
        "ourWork-title-en": "Our Work",
        "ourWork-title-ar": "أعمالنا",
        "ourWork-body-en": (
            "We build AI-powered solutions across four areas: intelligent "
            "business tools, workflow automation, digital platforms, and "
            "personal productivity assistants. Every engagement starts with "
            "understanding the problem, not the technology."
        ),
        "ourWork-body-ar": (
            "نصمم حلولاً مدعومة بالذكاء الاصطناعي في أربعة مجالات: أدوات "
            "أعمال ذكية، أتمتة سير العمل، منصات رقمية، ومساعدات إنتاجية "
            "شخصية. تبدأ كل مبادرة بفهم المشكلة أولاً، لا بالتقنية."
        ),
    },
    # Admin login credentials. ADMIN_USERNAME/ADMIN_PASSWORD_HASH in .env
    # remain the bootstrap defaults; passwordHash here, once set via the
    # panel's "Forgot password?" flow, overrides the .env hash without
    # needing a server restart or manual .env edit. The reset token itself
    # is never stored — only its hash — so a leak of config.json alone
    # can't be replayed to reset the password.
    "admin": {
        "passwordHash": "",
        "resetTokenHash": "",
        "resetTokenExpiresAt": "",
    },
    # admin panel instead of only via .env — the service-account key is
    # encrypted at rest the same way the LLM API key is (see security.py),
    # and is never sent back to the browser once saved.
    "calendar": {
        "calendarId": "",
        "serviceAccountJsonEncrypted": "",
    },
    "booking": {
        "promptsEn": [
            "Would you like me to schedule a call with our Growth Strategist?",
            "Shall I book an appointment with our Growth Strategist for you?",
            "Interested in speaking with our Growth Strategist? I can set that up.",
            "Want to chat with our Growth Strategist? I can book a time.",
            "Would a call with our Growth Strategist be helpful?",
        ],
        "promptsAr": [
            "هل تود لي أن أحجز لك موعداً مع خبيرنا في النمو؟",
            "هل تود لي أن أحجز لك مكالمة مع خبيرنا في النمو؟",
            "هل تود التحدث مع خبيرنا في النمو؟ يمكنني ترتيب ذلك.",
            "هل مكالمة مع خبيرنا في النمو مفيدة لك؟",
            "هل ترغب في جدولة موعد مع خبيرنا في النمو؟",
        ],
        "enabled": True,
    },
}


def _atomic_write_json(path: Path, data: Any) -> None:
    tmp_path = path.with_suffix(path.suffix + f".tmp-{uuid.uuid4().hex}")
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_path, path)  # atomic on POSIX


def _merge_with_defaults(defaults: dict[str, Any], data: dict[str, Any]) -> dict[str, Any]:
    """One level of dict-in-dict merging: a saved config missing a brand-new
    nested key (e.g. a new "landing" field added after that config was last
    saved) still gets that key's default, instead of the whole "landing"
    dict being silently replaced by the older, incomplete saved one."""
    merged = dict(defaults)
    for key, value in data.items():
        if key in merged and isinstance(merged[key], dict) and isinstance(value, dict):
            nested = dict(merged[key])
            nested.update(value)
            merged[key] = nested
        else:
            merged[key] = value
    return merged


def load_config() -> dict[str, Any]:
    with _lock:
        if not CONFIG_PATH.exists():
            return dict(DEFAULT_CONFIG)
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            return dict(DEFAULT_CONFIG)
        return _merge_with_defaults(DEFAULT_CONFIG, data)


def save_config(config: dict[str, Any]) -> None:
    with _lock:
        _atomic_write_json(CONFIG_PATH, config)


def get_decrypted_api_key(config: dict[str, Any] | None = None) -> str:
    config = config or load_config()
    return decrypt_secret(config.get("apiKeyEncrypted", ""))


def set_api_key(config: dict[str, Any], plaintext_key: str) -> dict[str, Any]:
    config["apiKeyEncrypted"] = encrypt_secret(plaintext_key)
    return config


def get_decrypted_calendar_service_account(config: dict[str, Any] | None = None) -> str:
    config = config or load_config()
    return decrypt_secret((config.get("calendar") or {}).get("serviceAccountJsonEncrypted", ""))


def set_calendar_service_account(config: dict[str, Any], plaintext_json: str) -> dict[str, Any]:
    calendar_cfg = dict(config.get("calendar") or {})
    calendar_cfg["serviceAccountJsonEncrypted"] = encrypt_secret(plaintext_json)
    config["calendar"] = calendar_cfg
    return config


def get_admin_password_hash(config: dict[str, Any] | None = None) -> str:
    """The hash actually used to verify admin logins: a saved reset
    overrides the .env bootstrap value if one has been set."""
    config = config or load_config()
    return (config.get("admin") or {}).get("passwordHash") or settings.ADMIN_PASSWORD_HASH


def set_admin_password_hash(config: dict[str, Any], bcrypt_hash: str) -> dict[str, Any]:
    admin_cfg = dict(config.get("admin") or {})
    admin_cfg["passwordHash"] = bcrypt_hash
    admin_cfg["resetTokenHash"] = ""
    admin_cfg["resetTokenExpiresAt"] = ""
    config["admin"] = admin_cfg
    return config


def issue_password_reset_token(config: dict[str, Any], token: str, ttl_minutes: int = 30) -> dict[str, Any]:
    admin_cfg = dict(config.get("admin") or {})
    admin_cfg["resetTokenHash"] = hash_token(token)
    expires = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=ttl_minutes)
    admin_cfg["resetTokenExpiresAt"] = expires.isoformat()
    config["admin"] = admin_cfg
    return config


def verify_password_reset_token(config: dict[str, Any], token: str) -> bool:
    admin_cfg = config.get("admin") or {}
    stored_hash = admin_cfg.get("resetTokenHash") or ""
    expires_at = admin_cfg.get("resetTokenExpiresAt") or ""
    if not stored_hash or not expires_at or not token:
        return False
    try:
        if datetime.datetime.now(datetime.timezone.utc) > datetime.datetime.fromisoformat(expires_at):
            return False
    except ValueError:
        return False
    return hmac.compare_digest(hash_token(token), stored_hash)


def load_knowledge_base() -> list[dict[str, Any]]:
    with _lock:
        if not KB_PATH.exists():
            return []
        try:
            with open(KB_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            return []
        return data if isinstance(data, list) else []


def save_knowledge_base(entries: list[dict[str, Any]]) -> None:
    with _lock:
        _atomic_write_json(KB_PATH, entries)


# ═══════════════════════════════════════════════════════════════════
# Appointments
# ═══════════════════════════════════════════════════════════════════

def load_appointments() -> list[dict[str, Any]]:
    with _lock:
        if not APPT_PATH.exists():
            return []
        try:
            with open(APPT_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            return []
        return data if isinstance(data, list) else []


def save_appointments(entries: list[dict[str, Any]]) -> None:
    with _lock:
        _atomic_write_json(APPT_PATH, entries)


def add_appointment(entry: dict[str, Any]) -> dict[str, Any]:
    entries = load_appointments()
    entries.append(entry)
    save_appointments(entries)
    return entry


# ═══════════════════════════════════════════════════════════════════
# Daily interaction stats (admin analytics — no PII, just counters)
# ═══════════════════════════════════════════════════════════════════

def _load_stats() -> dict[str, Any]:
    with _lock:
        if not STATS_PATH.exists():
            return {}
        try:
            with open(STATS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            return {}
        return data if isinstance(data, dict) else {}


def _save_stats(data: dict[str, Any]) -> None:
    # Prune old days so this file can never grow unbounded.
    if len(data) > STATS_RETENTION_DAYS:
        for day in sorted(data.keys())[: len(data) - STATS_RETENTION_DAYS]:
            data.pop(day, None)
    with _lock:
        _atomic_write_json(STATS_PATH, data)


def record_interaction(date_str: str, session_id: str) -> None:
    data = _load_stats()
    day = data.setdefault(date_str, {"messages": 0, "sessions": []})
    day["messages"] += 1
    if session_id and session_id not in day["sessions"]:
        day["sessions"].append(session_id)
    _save_stats(data)


def record_appointment_stat(date_str: str) -> None:
    data = _load_stats()
    day = data.setdefault(date_str, {"messages": 0, "sessions": [], "appointments": 0})
    day["appointments"] = day.get("appointments", 0) + 1
    _save_stats(data)


def daily_summary(days: int = 14) -> list[dict[str, Any]]:
    """Newest-first list of {date, messages, sessions, appointments}."""
    data = _load_stats()
    dates = sorted(data.keys(), reverse=True)[:days]
    return [
        {
            "date": d,
            "messages": data[d].get("messages", 0),
            "sessions": len(data[d].get("sessions", [])),
            "appointments": data[d].get("appointments", 0),
        }
        for d in dates
    ]
