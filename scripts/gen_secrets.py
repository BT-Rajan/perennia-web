#!/usr/bin/env python3
"""
Generates the secret values you need to fill in .env:
  - SECRET_KEY        (session/CSRF signing)
  - ENCRYPTION_KEY     (Fernet key for encrypting the LLM API key at rest)
  - ADMIN_PASSWORD_HASH (bcrypt hash of a password you choose)

Also writes admin_credentials.secret in the project root with the plaintext
username/password chosen just now, since this is the only point in the
whole system where the plaintext password is ever known — everywhere else
(including .env and config.json) only the one-way bcrypt hash is stored.
That file is gitignored; read it once to save the password somewhere safe
(a password manager), then delete it.

Usage:
    python3 scripts/gen_secrets.py
    python3 scripts/gen_secrets.py --password "your-new-admin-password" --username admin
"""
import argparse
import datetime
import getpass
import secrets
from pathlib import Path

import bcrypt
from cryptography.fernet import Fernet

BASE_DIR = Path(__file__).resolve().parent.parent
CREDENTIALS_FILE = BASE_DIR / "admin_credentials.secret"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--password", help="Admin password (omit to be prompted, hidden input)")
    parser.add_argument("--username", default="admin", help="Admin username (default: admin)")
    args = parser.parse_args()

    username = args.username
    password = args.password or getpass.getpass("Choose an admin password: ")
    if len(password) < 12:
        print("Warning: use a password of at least 12 characters for a production deployment.")

    secret_key = secrets.token_urlsafe(48)
    encryption_key = Fernet.generate_key().decode()
    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=12)).decode()

    print("\nAdd these to your .env file:\n")
    print(f"ADMIN_USERNAME={username}")
    print(f"SECRET_KEY={secret_key}")
    print(f"ENCRYPTION_KEY={encryption_key}")
    print(f"ADMIN_PASSWORD_HASH={password_hash}")
    print("\nKeep .env out of version control and out of any web-served directory.")

    CREDENTIALS_FILE.write_text(
        "Perennia — Admin Credentials\n"
        f"Generated: {datetime.datetime.now(datetime.timezone.utc).isoformat()}\n\n"
        f"Username: {username}\n"
        f"Password: {password}\n\n"
        "This is the only place the plaintext password is ever written — the\n"
        "app itself only ever stores the one-way bcrypt hash above, so it can't\n"
        "be recovered later if you lose it (use the admin panel's 'Forgot\n"
        "password?' link instead, or re-run this script).\n\n"
        "Copy this into a password manager, then delete this file. It's listed\n"
        "in .gitignore so it won't be committed, but it still exists in plaintext\n"
        "on disk until you remove it.\n",
        encoding="utf-8",
    )
    print(f"\nAlso wrote {CREDENTIALS_FILE.name} with the plaintext username/password — "
          f"save it somewhere safe and delete the file.")


if __name__ == "__main__":
    main()
