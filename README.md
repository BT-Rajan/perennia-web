# Perennia Web

AI-powered chat application with appointment booking.

## Clone

```bash
git clone https://github.com/BT-Rajan/perennia-web.git
cd perennia-web
```

## One-Command Install (Ubuntu + CloudPanel, production)

`install.sh` does everything end-to-end: installs system deps (python3/venv,
Node.js, pm2), creates the venv, installs `requirements.txt`, generates
`.env` with real secrets, starts the app under **pm2 as a process named
`web`**, and — if you pass `--domain` — wires it up to **HTTPS on the
standard port 443** by asking CloudPanel's own Nginx to reverse-proxy your
domain to the app and issuing a free Let's Encrypt certificate.

The app itself only ever binds to `127.0.0.1:8001` (never `0.0.0.0`, never
`443`), so it can never clash with CloudPanel's Nginx (which already owns
80/443 for every site on the box) or with the **CloudPanel admin panel on
port 8443** — that port is never touched.

```bash
git clone https://github.com/BT-Rajan/perennia-web.git
cd perennia-web
chmod +x install.sh
sudo ./install.sh --domain app.yourdomain.com --email you@yourdomain.com
```

No domain yet? Install the app only (reachable at `127.0.0.1:8001` on the
server) and wire up HTTPS later once DNS is pointed at the server:

```bash
sudo ./install.sh
# later:
sudo ./install.sh --domain app.yourdomain.com --email you@yourdomain.com
```

Re-running `install.sh` is safe — it preserves your existing secrets and
admin password unless you pass `--force`. An explicit `--port` always takes
effect, even on a re-install (it overwrites whatever `PORT` is currently in
`.env`), so moving the app to a different internal port later is just:

```bash
sudo ./install.sh --port 8001 --domain app.yourdomain.com --email you@yourdomain.com
```

If you change the port and the app is already live behind a CloudPanel
reverse-proxy site, also re-point that site's `proxy_pass` to the new port
(CloudPanel has no `site:update:reverse-proxy` CLI command as of this
writing, so it's a one-line manual edit + reload):

```bash
sudo grep -rl "127.0.0.1:<OLD_PORT>" /etc/nginx/sites-enabled/
sudo sed -i 's/127\.0\.0\.1:<OLD_PORT>/127.0.0.1:<NEW_PORT>/g' /etc/nginx/sites-enabled/<your-vhost>.conf
sudo nginx -t && sudo systemctl reload nginx
```

See `./install.sh --help` for all options (custom port, admin credentials,
CloudPanel site user, etc).

## Install Dependencies (manual / other OS)

```bash
pip install -r requirements.txt
```

## Environment Setup

```bash
cp .env.example .env
# Edit .env with your API keys
nano .env
```

## Generate Secrets

```bash
python scripts/gen_secrets.py
```

## Run Locally

```bash
python -m uvicorn app.main:app --host 127.0.0.1 --port 8001
```

Server runs on `http://localhost:8001`. (The app's own default, if
`HOST`/`PORT` aren't set in `.env`, is `0.0.0.0:443` — meant for the
CloudPanel/reverse-proxy production setup above — so pass `--host`/
`--port` explicitly, or set them in `.env`, for a plain local run.)

## Docker

```bash
docker build -t perennia-web .
docker run -p 8001:8001 perennia-web
```

## Directory Structure

```
perennia-web/
├── app/
│   ├── main.py           # FastAPI app
│   ├── config.py         # Configuration
│   ├── llm.py            # LLM integration
│   ├── extract.py        # Document extraction
│   ├── storage.py        # Data storage
│   ├── security.py       # Auth & security
│   ├── gcal.py           # Google Calendar
│   ├── scheduling.py     # Appointment scheduling
│   └── prompt.py         # LLM prompts
├── public/
│   ├── index.html        # Frontend (single page)
│   ├── admin.html        # Admin panel
│   └── static/           # Images & assets
├── scripts/
│   └── gen_secrets.py    # Secret key generator
├── data/                 # Persistent storage
├── requirements.txt      # Python dependencies
└── Dockerfile           # Container config
```

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/chat` | POST | Send chat message |
| `/api/appointments/availability` | GET | Get available slots |
| `/api/appointments/book` | POST | Book appointment |
| `/api/landing-config` | GET | Get UI config |

## Browser

Visit `http://localhost:8001` after starting server.

## Windows

Easiest: double-click `installer.bat` (see `WINDOWS-INSTALL.txt` for the
full walkthrough). It creates the virtual environment, installs
dependencies, generates a working `.env`, and writes `start-server.bat`
for you — no manual steps required.

Manual setup, if you'd rather do it yourself:

```cmd
git clone https://github.com/BT-Rajan/perennia-web.git
cd perennia-web
python -m venv venv
venv\Scripts\activate.bat
pip install -r requirements.txt
python scripts\gen_secrets.py
copy .env.example .env
notepad .env
```

Paste the `SECRET_KEY` / `ENCRYPTION_KEY` / `ADMIN_PASSWORD_HASH` values
`gen_secrets.py` printed into `.env`, set `HOST=127.0.0.1`, `PORT=8001`,
and `COOKIE_SECURE=false` (there's no TLS on a local install — a `true`
value here silently breaks admin login), then run:

```cmd
venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8001
```

Server runs on `http://localhost:8001`.

## Linux Production

```bash
pip install gunicorn
gunicorn -k uvicorn.workers.UvicornWorker -w 4 -b 0.0.0.0:8001 app.main:app
```

(Or use `install.sh` above, which sets this up under pm2 with HTTPS
automatically instead.)

## License

Proprietary - Perennia
