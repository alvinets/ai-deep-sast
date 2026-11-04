@echo off
setlocal EnableExtensions EnableDelayedExpansion
title AI Deep SAST - Control Panel
cd /d "%~dp0"

set "REPORT_DIR=security-reports"
set "CONFIG_FILE=config\scanner_config.yaml"
set "DEMO_TARGET=samples\sample_vuln.py"
set "PY=python"
if exist ".venv\Scripts\python.exe" set "PY=.venv\Scripts\python.exe"
if exist ".venv\Scripts\python.exe" set "PATH=%CD%\.venv\Scripts;%PATH%"
set "EMPTY=0"
set "DEPS_OK=0"

goto :MENU


:MENU
if not defined START_BAT_DRYRUN cls
echo ============================================================
echo  AI Deep SAST - Control Panel
echo ============================================================
echo  Working dir : %CD%
echo  Python      : %PY%
if exist ".venv\Scripts\python.exe" (
    echo  Venv        : .venv detected
) else (
    echo  Venv        : not found - option 1 creates it
)
echo ------------------------------------------------------------
echo   [1] Setup environment  - create .venv and install requirements
echo   [2] Fast scan          - Semgrep only, no LLM
echo   [3] AI fast scan       - Semgrep plus local LLM triage
echo   [4] Deep scan          - exploratory plus guided AI analysis
echo   [5] Demo scan          - scan the bundled sample file
echo   [6] View config        - open scanner_config.yaml
echo   [7] Model status       - check Python, llama.cpp and model files
echo   [8] Run tests          - pytest on the tests directory
echo   [0] Exit
echo ------------------------------------------------------------
if not defined START_BAT_DRYRUN echo  Hint        : Ctrl+C or option 0 to quit
echo.
set "CHOICE="
set /p "CHOICE=Select an option: "
if not defined CHOICE goto :NO_INPUT
set "EMPTY=0"
if "!CHOICE!"=="1" goto :OPT_SETUP
if "!CHOICE!"=="2" goto :OPT_FAST
if "!CHOICE!"=="3" goto :OPT_AI
if "!CHOICE!"=="4" goto :OPT_DEEP
if "!CHOICE!"=="5" goto :OPT_DEMO
if "!CHOICE!"=="6" goto :OPT_CONFIG
if "!CHOICE!"=="7" goto :OPT_STATUS
if "!CHOICE!"=="8" goto :OPT_TESTS
if "!CHOICE!"=="0" goto :END
echo.
echo [WARN] Invalid choice: !CHOICE!
ping -n 2 127.0.0.1 >nul 2>&1
goto :MENU


:OPT_SETUP
echo.
echo === Setup environment ===
where python >nul 2>&1
if errorlevel 1 (
    call :FAIL "Python not found on PATH. Install Python 3.11 and retry."
    goto :MENU
)
if exist ".venv\Scripts\python.exe" goto :SETUP_HAVE_VENV
call :RUN python -m venv .venv
if defined START_BAT_DRYRUN goto :SETUP_HAVE_VENV
if not exist ".venv\Scripts\python.exe" (
    call :FAIL "Failed to create .venv."
    goto :MENU
)
:SETUP_HAVE_VENV
set "PY=.venv\Scripts\python.exe"
set "PATH=%CD%\.venv\Scripts;%PATH%"
echo [i] Using interpreter: !PY!
call :RUN "%PY%" -m pip install --upgrade pip
if errorlevel 1 (
    call :FAIL "pip upgrade failed."
    goto :MENU
)
call :RUN "%PY%" -m pip install -r requirements.txt
if errorlevel 1 (
    call :FAIL "Dependency installation failed."
    goto :MENU
)
call :DONE "Environment ready. Run this script again to use .venv."
goto :MENU


:OPT_FAST
echo.
echo === Fast scan - Semgrep only ===
call :CHECK_PY
if errorlevel 1 goto :MENU
call :CHECK_DEPS
if errorlevel 1 goto :MENU
call :ASK_TARGET
if errorlevel 1 goto :MENU
echo [i] Scanning: !TARGET!
call :RUN "%PY%" aideepsast.py --target "!TARGET!" --skip-llm --output-dir "%REPORT_DIR%"
if errorlevel 2 (
    call :FAIL "Scan error - see messages above."
    goto :MENU
)
if errorlevel 1 echo [WARN] Findings at or above threshold. Reports below.
call :SHOW_REPORTS
call :DONE "Fast scan complete."
goto :MENU


:OPT_AI
echo.
echo === AI fast scan ===
call :CHECK_PY
if errorlevel 1 goto :MENU
call :CHECK_DEPS
if errorlevel 1 goto :MENU
call :CHECK_LLAMA
if errorlevel 1 goto :MENU
call :ASK_TARGET
if errorlevel 1 goto :MENU
echo [i] Scanning: !TARGET!
echo [i] The local model may download on first run.
call :RUN "%PY%" aideepsast.py --target "!TARGET!" --output-dir "%REPORT_DIR%"
if errorlevel 2 (
    call :FAIL "AI scan error - see messages above."
    goto :MENU
)
if errorlevel 1 echo [WARN] Findings at or above threshold. Reports below.
call :SHOW_REPORTS
call :DONE "AI fast scan complete."
goto :MENU


:OPT_DEEP
echo.
echo === Deep scan ===
call :CHECK_PY
if errorlevel 1 goto :MENU
call :CHECK_DEPS
if errorlevel 1 goto :MENU
call :ASK_TARGET
if errorlevel 1 goto :MENU
echo [i] Scanning: !TARGET!
call :RUN "%PY%" deepscan.py --target "!TARGET!" --output-dir "%REPORT_DIR%"
if errorlevel 2 (
    call :FAIL "Deep scan error - see messages above."
    goto :MENU
)
if errorlevel 1 echo [WARN] Findings at or above threshold. Reports below.
call :SHOW_REPORTS
call :DONE "Deep scan complete."
goto :MENU


:OPT_DEMO
echo.
echo === Demo scan ===
if not exist "%DEMO_TARGET%" (
    call :FAIL "Demo file not found: %DEMO_TARGET%"
    goto :MENU
)
call :CHECK_PY
if errorlevel 1 goto :MENU
call :CHECK_DEPS
if errorlevel 1 goto :MENU
echo [i] Scanning demo file: %DEMO_TARGET%
call :RUN "%PY%" aideepsast.py --target "%DEMO_TARGET%" --skip-llm --output-dir "%REPORT_DIR%"
if errorlevel 2 (
    call :FAIL "Demo scan error - see messages above."
    goto :MENU
)
if errorlevel 1 echo [WARN] Findings at or above threshold. Reports below.
call :SHOW_REPORTS
call :DONE "Demo scan complete."
goto :MENU


:OPT_CONFIG
echo.
echo === Configuration ===
if not exist "%CONFIG_FILE%" (
    call :FAIL "Config file not found: %CONFIG_FILE%"
    goto :MENU
)
echo [i] Config file: %CONFIG_FILE%
if defined START_BAT_DRYRUN (
    echo [DRYRUN] notepad "%CONFIG_FILE%"
    goto :MENU
)
start "" notepad "%CONFIG_FILE%"
goto :MENU


:OPT_STATUS
echo.
echo === Model status ===
call :CHECK_PY
if errorlevel 1 goto :MENU
echo [i] Python:
"%PY%" --version
echo.
echo [i] llama.cpp:
call :CHECK_LLAMA
echo.
echo [i] Model cache:
if exist "%USERPROFILE%\.cache\llama.cpp" (
    dir /b "%USERPROFILE%\.cache\llama.cpp" 2>nul
) else (
    echo     not present yet - the model downloads on first AI scan
)
echo.
echo [i] Local model dir:
if exist "foundation-sec-model" (
    dir /b "foundation-sec-model" 2>nul
) else (
    echo     foundation-sec-model not present
)
echo.
echo [i] LLM environment:
if defined LLM_BASE_URL (echo     LLM_BASE_URL = !LLM_BASE_URL!) else (echo     LLM_BASE_URL = not set)
if defined LLM_MODEL (echo     LLM_MODEL = !LLM_MODEL!) else (echo     LLM_MODEL = not set)
if defined LLM_API_KEY (echo     LLM_API_KEY = set) else (echo     LLM_API_KEY = not set)
call :DONE "Model status displayed."
goto :MENU


:OPT_TESTS
echo.
echo === Run tests ===
call :CHECK_PY
if errorlevel 1 goto :MENU
call :CHECK_PYTEST
if errorlevel 1 goto :MENU
call :RUN "%PY%" -m pytest tests -v
if errorlevel 1 (
    call :FAIL "Tests failed."
    goto :MENU
)
call :DONE "Tests passed."
goto :MENU


:END
echo.
echo Goodbye.
endlocal
exit /b 0


:FAIL
echo.
echo [ERROR] %~1
if not defined START_BAT_DRYRUN pause
exit /b 1


:DONE
echo.
echo [OK] %~1
if not defined START_BAT_DRYRUN pause
exit /b 0


:NO_INPUT
set /a EMPTY+=1
if !EMPTY! GEQ 3 (
    echo.
    echo [ERROR] No input received - stdin closed. Exiting.
    endlocal
    exit /b 1
)
echo.
echo [WARN] No input received. Type a number and press Enter.
ping -n 2 127.0.0.1 >nul 2>&1
goto :MENU


:CHECK_PY
if defined START_BAT_DRYRUN exit /b 0
"%PY%" --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Python interpreter not working: %PY%
    echo Run option 1 to set up the environment.
    pause
    exit /b 1
)
exit /b 0


:CHECK_DEPS
if defined START_BAT_DRYRUN (
    set "DEPS_OK=1"
    exit /b 0
)
"%PY%" -c "import semgrep, yaml, openai" >nul 2>&1
if errorlevel 1 (
    set "DEPS_OK=0"
    echo.
    echo [WARN] Python dependencies are missing.
    echo Run option 1 to install requirements.
    pause
    exit /b 1
)
set "DEPS_OK=1"
exit /b 0


:CHECK_PYTEST
if defined START_BAT_DRYRUN exit /b 0
"%PY%" -c "import pytest" >nul 2>&1
if errorlevel 1 (
    echo.
    echo [WARN] pytest is not installed.
    echo Install it with: pip install pytest
    pause
    exit /b 1
)
exit /b 0


:CHECK_LLAMA
where llama-completion >nul 2>&1
if errorlevel 1 (
    echo.
    echo [WARN] llama-completion not found on PATH.
    echo Install llama.cpp and add it to PATH so the local model can run.
    if defined START_BAT_DRYRUN exit /b 0
    pause
    exit /b 1
)
echo [OK] llama-completion found on PATH.
exit /b 0


:ASK_TARGET
echo.
set "TARGET="
set /p "TARGET=Target directory [default .]: "
if not defined TARGET set "TARGET=."
if not exist "!TARGET!" goto :ASK_TARGET_BAD
exit /b 0


:ASK_TARGET_BAD
echo [WARN] Path not found: !TARGET!
ping -n 2 127.0.0.1 >nul 2>&1
goto :ASK_TARGET


:SHOW_REPORTS
echo.
if not exist "%REPORT_DIR%" (
    echo [i] No report directory yet: %REPORT_DIR%
    exit /b 0
)
echo [i] Recent files in %REPORT_DIR%:
set "N=0"
for /f "delims=" %%F in ('dir /b /o-d "%REPORT_DIR%" 2^>nul') do (
    set /a N+=1
    if !N! LSS 10 echo   %%F
)
if !N! EQU 0 echo   none
exit /b 0


:RUN
if defined START_BAT_DRYRUN goto :RUN_DRYRUN
%*
set "RC=!errorlevel!"
exit /b !RC!


:RUN_DRYRUN
echo [DRYRUN] %*
exit /b 0
