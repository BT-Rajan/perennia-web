"""
Google Calendar sync for appointment bookings.

Uses a service account (no browser OAuth flow, no admin login to Google
needed). The service account's own email must be added as an editor on
the target calendar.

Credentials are configured from the admin panel (Calendar ID + the
service-account JSON key file, pasted or uploaded) and stored encrypted
in config.json, the same way the LLM API key is (see security.py). The
legacy .env variables GOOGLE_SERVICE_ACCOUNT_FILE / GOOGLE_CALENDAR_ID
are still honored as a fallback when nothing has been saved from the
admin panel yet. If neither is configured, every function here is a
silent no-op — appointments still get recorded locally, they just won't
appear on a calendar.
"""
import datetime
import json
import logging
import threading
from typing import Optional

from app.config import settings

log = logging.getLogger("perennia.gcal")

_service = None
_service_load_attempted = False
_calendar_id_cache: Optional[str] = None
_service_lock = threading.Lock()


def reset_service() -> None:
    """Invalidate the cached client. Call this right after the admin panel
    saves a new calendar ID or service-account key, so the very next
    request picks up the new credentials instead of the previous ones
    (or the previous "unconfigured" result) that were cached in memory."""
    global _service, _service_load_attempted, _calendar_id_cache
    with _service_lock:
        _service = None
        _service_load_attempted = False
        _calendar_id_cache = None


def _load_credentials_and_calendar_id():
    """Returns (service_account_info_dict, calendar_id), preferring the
    admin-panel config over the legacy .env fallback. Either element is
    None if that source isn't fully configured."""
    from app import storage  # local import: avoids a hard import-order dependency

    config = storage.load_config()
    calendar_id = ((config.get("calendar") or {}).get("calendarId") or "").strip()
    sa_json = storage.get_decrypted_calendar_service_account(config)

    if sa_json and calendar_id:
        try:
            return json.loads(sa_json), calendar_id
        except json.JSONDecodeError:
            log.warning("Stored calendar service-account JSON is corrupt; falling back to .env if set.")

    if settings.GOOGLE_SERVICE_ACCOUNT_FILE and settings.GOOGLE_CALENDAR_ID:
        try:
            with open(settings.GOOGLE_SERVICE_ACCOUNT_FILE, "r", encoding="utf-8") as f:
                return json.load(f), settings.GOOGLE_CALENDAR_ID
        except (OSError, json.JSONDecodeError) as e:
            log.warning("Could not read GOOGLE_SERVICE_ACCOUNT_FILE: %s", e)

    return None, None


def _build_service(service_account_info: dict):
    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    creds = service_account.Credentials.from_service_account_info(
        service_account_info, scopes=["https://www.googleapis.com/auth/calendar"],
    )
    return build("calendar", "v3", credentials=creds, cache_discovery=False)


def _get_service():
    global _service, _service_load_attempted, _calendar_id_cache
    if _service is not None:
        return _service
    if _service_load_attempted:
        return None

    with _service_lock:
        if _service is not None:
            return _service
        if _service_load_attempted:
            return None
        _service_load_attempted = True

        info, calendar_id = _load_credentials_and_calendar_id()
        if not info or not calendar_id:
            return None
        try:
            _service = _build_service(info)
            _calendar_id_cache = calendar_id
            return _service
        except Exception as e:
            log.warning("Google Calendar not available: %s", e)
            return None


def is_configured() -> bool:
    return _get_service() is not None


def fetch_busy_intervals(day_start: datetime.datetime, day_end: datetime.datetime) -> list[tuple[str, str]]:
    """Returns [(start_iso, end_iso), ...] busy blocks on the shared calendar for that window."""
    service = _get_service()
    calendar_id = _calendar_id_cache
    if not service or not calendar_id:
        return []
    try:
        body = {
            "timeMin": day_start.isoformat(),
            "timeMax": day_end.isoformat(),
            "items": [{"id": calendar_id}],
        }
        result = service.freebusy().query(body=body).execute()
        busy = result.get("calendars", {}).get(calendar_id, {}).get("busy", [])
        return [(b["start"], b["end"]) for b in busy]
    except Exception as e:
        log.warning("freebusy query failed: %s", e)
        return []


def create_event(
    *,
    summary: str,
    description: str,
    start: datetime.datetime,
    end: datetime.datetime,
    attendee_email: Optional[str] = None,
) -> Optional[str]:
    """Creates a calendar event, returns its event id, or None if unconfigured/failed."""
    service = _get_service()
    calendar_id = _calendar_id_cache
    if not service or not calendar_id:
        return None
    event = {
        "summary": summary,
        "description": description,
        "start": {"dateTime": start.isoformat(), "timeZone": settings.APPT_TIMEZONE},
        "end": {"dateTime": end.isoformat(), "timeZone": settings.APPT_TIMEZONE},
    }
    if attendee_email:
        event["attendees"] = [{"email": attendee_email}]
    try:
        created = service.events().insert(
            calendarId=calendar_id, body=event, sendUpdates="all" if attendee_email else "none"
        ).execute()
        return created.get("id")
    except Exception as e:
        log.warning("Calendar event creation failed: %s", e)
        return None


def delete_event(event_id: str) -> bool:
    service = _get_service()
    calendar_id = _calendar_id_cache
    if not service or not calendar_id or not event_id:
        return False
    try:
        service.events().delete(calendarId=calendar_id, eventId=event_id).execute()
        return True
    except Exception as e:
        log.warning("Calendar event deletion failed: %s", e)
        return False


def test_access(calendar_id: str, service_account_json: str) -> dict:
    """Independently verifies both read and write access for the given
    (possibly not-yet-saved) credentials, without touching the cached
    module-level client used by the rest of this file. Used by the admin
    panel's "Test Connection" button.

    Read is checked with a freebusy query; write is checked by inserting a
    small event one year in the future (so it can never collide with a real
    appointment) and deleting it immediately afterward.
    """
    calendar_id = (calendar_id or "").strip()
    if not calendar_id:
        return {"ok": False, "readOk": False, "writeOk": False, "message": "Calendar ID is required."}

    try:
        info = json.loads(service_account_json)
    except (json.JSONDecodeError, TypeError):
        return {"ok": False, "readOk": False, "writeOk": False, "message": "That isn't valid JSON."}

    if info.get("type") != "service_account" or "client_email" not in info or "private_key" not in info:
        return {
            "ok": False, "readOk": False, "writeOk": False,
            "message": "That doesn't look like a Google service-account key file "
                       "(expected a JSON object with type, client_email, private_key).",
        }

    try:
        service = _build_service(info)
    except Exception as e:
        return {"ok": False, "readOk": False, "writeOk": False, "message": f"Could not build credentials: {e}"}

    read_ok = False
    write_ok = False
    problems = []
    now = datetime.datetime.now(datetime.timezone.utc)

    try:
        service.freebusy().query(body={
            "timeMin": now.isoformat(),
            "timeMax": (now + datetime.timedelta(hours=1)).isoformat(),
            "items": [{"id": calendar_id}],
        }).execute()
        read_ok = True
    except Exception as e:
        problems.append(f"read check failed ({e})")

    if read_ok:
        try:
            start = now + datetime.timedelta(days=365)
            end = start + datetime.timedelta(minutes=15)
            event = {
                "summary": "Perennia connection test (safe to ignore / auto-deleted)",
                "description": "Created automatically by the Perennia admin panel to verify write "
                                "access. It is deleted immediately after this check.",
                "start": {"dateTime": start.isoformat()},
                "end": {"dateTime": end.isoformat()},
            }
            created = service.events().insert(calendarId=calendar_id, body=event).execute()
            service.events().delete(calendarId=calendar_id, eventId=created["id"]).execute()
            write_ok = True
        except Exception as e:
            problems.append(f"write check failed ({e})")

    ok = read_ok and write_ok
    if ok:
        message = f"Connected as {info.get('client_email', '')}. Read and write access confirmed."
    else:
        message = "; ".join(problems) or "Could not verify access."
        if not read_ok:
            message += (
                " Make sure the calendar has been shared with the service account's "
                f"email ({info.get('client_email', 'see JSON key')}) with \"Make changes to events\" permission."
            )
    return {"ok": ok, "readOk": read_ok, "writeOk": write_ok, "message": message}
