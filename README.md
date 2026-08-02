# Perennia Web

AI-powered chat application with appointment booking.

## Clone

```bash
git clone https://github.com/BT-Rajan/perennia-web.git
cd perennia-web
```

## Install Dependencies

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
python app/main.py
```

Server runs on `http://localhost:5000`

## Docker

```bash
docker build -t perennia-web .
docker run -p 5000:5000 perennia-web
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

Visit `http://localhost:5000` after starting server.

## Windows CMD

### Clone

```cmd
git clone https://github.com/BT-Rajan/perennia-web.git
cd perennia-web
```

### Install Dependencies

```cmd
pip install -r requirements.txt
```

### Environment Setup

```cmd
copy .env.example .env
notepad .env
```

### Generate Secrets

```cmd
python scripts/gen_secrets.py
```

### Run Locally

```cmd
python app/main.py
```

Server runs on `http://localhost:5000`

### Docker

```cmd
docker build -t perennia-web .
docker run -p 5000:5000 perennia-web
```

### Production

```cmd
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 app.main:app
```

## Linux Production

```bash
gunicorn -w 4 -b 0.0.0.0:5000 app.main:app
```

## License

Proprietary - Perennia
