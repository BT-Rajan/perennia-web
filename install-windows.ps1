<#
.SYNOPSIS
    Perennia Production - Windows PowerShell Installer
.DESCRIPTION
    Sets up Perennia Production on Windows with Python virtual environment
.VERSION
    1.0
#>

# Color functions
function Write-Header {
    param([string]$Text)
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " $Text" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
}

function Write-Step {
    param([int]$Number, [string]$Text)
    Write-Host "[$Number/6] $Text" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "✓ $Text" -ForegroundColor Green
}

function Write-Error {
    param([string]$Text)
    Write-Host "✗ ERROR: $Text" -ForegroundColor Red
}

# Start
Clear-Host
Write-Header "PERENNIA PRODUCTION - WINDOWS INSTALLER"

Write-Host ""
Write-Host "This installer will:"
Write-Host "  1. Check Python installation"
Write-Host "  2. Create virtual environment"
Write-Host "  3. Install Python dependencies"
Write-Host "  4. Create data directories"
Write-Host "  5. Generate configuration file"
Write-Host "  6. Verify installation"
Write-Host ""
Read-Host "Press Enter to continue"

# Step 1: Check Python
Write-Step 1 "Checking Python installation..."
try {
    $pythonVersion = python --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Python found: $pythonVersion"
    } else {
        Write-Error "Python not found or not in PATH"
        Write-Host ""
        Write-Host "Download Python from: https://www.python.org/downloads/" -ForegroundColor Yellow
        Write-Host "IMPORTANT: Check 'Add Python to PATH' during installation!" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
} catch {
    Write-Error "Failed to check Python: $_"
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 2: Check pip
Write-Step 2 "Checking pip..."
try {
    pip --version | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "pip is available"
    } else {
        Write-Error "pip not found"
        Read-Host "Press Enter to exit"
        exit 1
    }
} catch {
    Write-Error "Failed to check pip: $_"
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 3: Create Virtual Environment
Write-Step 3 "Creating virtual environment..."
if (Test-Path ".\venv") {
    Write-Host "Virtual environment already exists, skipping..." -ForegroundColor Yellow
} else {
    try {
        python -m venv venv
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Virtual environment created"
        } else {
            Write-Error "Failed to create virtual environment"
            Read-Host "Press Enter to exit"
            exit 1
        }
    } catch {
        Write-Error "Failed to create virtual environment: $_"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Step 4: Install Dependencies
Write-Step 4 "Installing dependencies..."
try {
    # Activate venv
    & ".\venv\Scripts\Activate.ps1"
    
    # Upgrade pip
    python -m pip install --upgrade pip 2>&1 | Out-Null
    
    # Install requirements
    pip install -r requirements.txt
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Dependencies installed successfully"
    } else {
        Write-Error "Failed to install dependencies"
        Write-Host "Try running manually:" -ForegroundColor Yellow
        Write-Host "  .\venv\Scripts\Activate.ps1" -ForegroundColor Yellow
        Write-Host "  pip install -r requirements.txt" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
} catch {
    Write-Error "Failed to install dependencies: $_"
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 5: Create Directories and Config
Write-Step 5 "Setting up directories and configuration..."
try {
    # Create directories
    if (-not (Test-Path "data")) { New-Item -ItemType Directory -Path "data" | Out-Null }
    if (-not (Test-Path "data\uploads")) { New-Item -ItemType Directory -Path "data\uploads" | Out-Null }
    if (-not (Test-Path "public\static\images")) { New-Item -ItemType Directory -Path "public\static\images" | Out-Null }
    
    # Create config if it doesn't exist
    if (-not (Test-Path "data\config.json")) {
        $configContent = @{
            provider = "anthropic"
            model = "claude-sonnet-4-6"
            baseUrl = ""
            apiKeyEncrypted = ""
            tone = ""
            knowledge = @{}
            contact = @{
                "ct-email" = "info@perennia.com"
                "ct-phone" = "+965 0000 0000"
                "ct-addr-en" = "Kuwait"
                "ct-addr-ar" = "الكويت"
            }
            landing = @{
                "welcomeText-en" = "Welcome to Perennia"
                "welcomeText-ar" = "مرحبا بك في بيرينيا"
                "tagline-en" = "Visit our V-Lounge for more"
                "tagline-ar" = "زر V-Lounge الخاص بنا لمزيد من المعلومات"
                "ourWorkUrl" = ""
                "contactUrl" = ""
            }
            booking = @{
                enabled = $true
                promptsEn = @(
                    "Would you like me to schedule a call with our Growth Strategist?",
                    "Shall I book an appointment with our Growth Strategist for you?",
                    "Interested in speaking with our Growth Strategist? I can set that up.",
                    "Want to chat with our Growth Strategist? I can book a time.",
                    "Would a call with our Growth Strategist be helpful?"
                )
                promptsAr = @(
                    "هل تود لي أن أحجز لك موعداً مع خبيرنا في النمو؟",
                    "هل تود لي أن أحجز لك مكالمة مع خبيرنا في النمو؟",
                    "هل تود التحدث مع خبيرنا في النمو؟ يمكنني ترتيب ذلك.",
                    "هل مكالمة مع خبيرنا في النمو مفيدة لك؟",
                    "هل ترغب في جدولة موعد مع خبيرنا في النمو؟"
                )
            }
        }
        $configContent | ConvertTo-Json -Depth 10 | Out-File "data\config.json" -Encoding UTF8
        Write-Success "Configuration created: data/config.json"
    } else {
        Write-Success "Configuration already exists"
    }
    
    Write-Success "Directories ready"
} catch {
    Write-Error "Failed to create directories: $_"
    Read-Host "Press Enter to exit"
    exit 1
}

# Step 6: Verification
Write-Step 6 "Verifying installation..."
try {
    $pythonFiles = Get-ChildItem -Path "app" -Filter "*.py" -ErrorAction Stop | Measure-Object
    $htmlFiles = Get-ChildItem -Path "public" -Filter "*.html" -ErrorAction Stop | Measure-Object
    
    if ($pythonFiles.Count -gt 0 -and $htmlFiles.Count -gt 0) {
        Write-Success "Installation verification passed"
    } else {
        Write-Error "Missing required files"
    }
} catch {
    Write-Error "Verification failed: $_"
}

# Complete
Write-Host ""
Write-Header "INSTALLATION COMPLETE!"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. CONFIGURE API KEY (Required):"
Write-Host "   - Edit: data/config.json" -ForegroundColor Yellow
Write-Host "   - Add your Anthropic API key" -ForegroundColor Yellow
Write-Host "   - Save the file" -ForegroundColor Yellow
Write-Host ""
Write-Host "2. START THE APPLICATION:"
Write-Host "   - Option A: Double-click start-server.bat" -ForegroundColor Yellow
Write-Host "   - Option B: Run in PowerShell:" -ForegroundColor Yellow
Write-Host "     .\venv\Scripts\Activate.ps1" -ForegroundColor Yellow
Write-Host "     uvicorn app.main:app --reload --host 0.0.0.0 --port 8000" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. OPEN IN BROWSER:"
Write-Host "   - Visit: http://localhost:8000" -ForegroundColor Yellow
Write-Host "   - Admin: http://localhost:8000/admin" -ForegroundColor Yellow
Write-Host ""
Write-Host "For support: Check README.md or contact support@perennia.com" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"
