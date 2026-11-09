#!/usr/bin/env bash
# AI Deep SAST - Control Panel (Linux / Ubuntu)
#
# Interactive menu that wraps the scanners so nobody has to memorise flags.
# Dry-run switch:  START_DRYRUN=1 ./start.sh   (prints commands, runs nothing)
#
# The Linux virtualenv lives in .venv-linux/ so it never collides with the
# Windows .venv/ (Scripts/) that start.bat uses in the same directory.

set -o pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
cd "$SCRIPT_DIR" || exit 1

REPORT_DIR="security-reports"
CONFIG_FILE="config/scanner_config.yaml"
DEMO_TARGET="samples/sample_vuln.py"
VENV_DIR=".venv-linux"
PY="python3"

if [ -x "$VENV_DIR/bin/python" ]; then
    PY="$VENV_DIR/bin/python"
fi

# Optional local overrides for the remote LLM (gitignored).
if [ -f "config/llm_env.sh" ]; then
    # shellcheck disable=SC1091
    . "config/llm_env.sh"
fi

EMPTY=0

say()  { printf '%s\n' "$*"; }
blank() { printf '\n'; }

hr() { printf '%s\n' "------------------------------------------------------------"; }

pause_if_interactive() {
    [ "${START_DRYRUN:-}" = "1" ] && return 0
    [ -t 0 ] || return 0
    read -r -p "Press Enter to continue..." _ || true
}

fail() {
    blank
    say "[ERROR] $*"
    pause_if_interactive
    return 1
}

done_msg() {
    blank
    say "[OK] $*"
    pause_if_interactive
}

run() {
    if [ "${START_DRYRUN:-}" = "1" ]; then
        say "[DRYRUN] $*"
        return 0
    fi
    "$@"
    return $?
}

show_menu() {
    if [ -t 1 ] && [ "${START_DRYRUN:-}" != "1" ]; then
        clear 2>/dev/null
    fi
    say "============================================================"
    say " AI Deep SAST - Control Panel"
    say "============================================================"
    say " Working dir : $PWD"
    say " Python      : $PY"
    if [ -x "$VENV_DIR/bin/python" ]; then
        say " Venv        : $VENV_DIR detected"
    else
        say " Venv        : not found - option 1 creates it"
    fi
    hr
    say "  [1] Setup environment  - create venv and install requirements"
    say "  [2] Fast scan          - Semgrep only, no LLM"
    say "  [3] AI fast scan       - Semgrep plus local LLM triage"
    say "  [4] Deep scan          - exploratory plus guided AI analysis"
    say "  [5] Demo scan          - scan the bundled sample file"
    say "  [6] View config        - show scanner_config.yaml"
    say "  [7] Model status       - check Python, llama.cpp and model files"
    say "  [8] Run tests          - pytest on the tests directory"
    say "  [0] Exit"
    hr
    [ "${START_DRYRUN:-}" = "1" ] || say " Hint        : Ctrl+C or option 0 to quit"
    blank
}

check_py() {
    [ "${START_DRYRUN:-}" = "1" ] && return 0
    if ! "$PY" --version >/dev/null 2>&1; then
        fail "Python interpreter not working: $PY" || true
        say "Run option 1 to set up the environment."
        return 1
    fi
    return 0
}

check_deps() {
    [ "${START_DRYRUN:-}" = "1" ] && return 0
    if ! "$PY" -c "import semgrep, yaml, openai" >/dev/null 2>&1; then
        fail "Python dependencies are missing." || true
        say "Run option 1 to install requirements."
        return 1
    fi
    return 0
}

check_pytest() {
    [ "${START_DRYRUN:-}" = "1" ] && return 0
    if ! "$PY" -c "import pytest" >/dev/null 2>&1; then
        fail "pytest is not installed." || true
        say "Install it with: $PY -m pip install pytest"
        return 1
    fi
    return 0
}

check_llama() {
    if ! command -v llama-completion >/dev/null 2>&1; then
        blank
        say "[WARN] llama-completion not found on PATH."
        say "Install llama.cpp and add it to PATH so the local model can run."
        [ "${START_DRYRUN:-}" = "1" ] && return 0
        pause_if_interactive
        return 1
    fi
    say "[OK] llama-completion found on PATH."
    return 0
}

find_gguf() {
    local d f
    local dirs=()
    [ -n "${LLAMA_CACHE:-}" ]      && dirs+=("$LLAMA_CACHE")
    [ -n "${HF_HOME:-}" ]          && dirs+=("$HF_HOME/hub")
    [ -n "${HF_HUB_CACHE:-}" ]     && dirs+=("$HF_HUB_CACHE")
    dirs+=("$HOME/.cache/huggingface/hub" "$HOME/.cache/llama.cpp")

    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        f=$(find "$d" -name 'foundation-sec-8b-instruct-q8_0.gguf' -print -quit 2>/dev/null)
        if [ -n "$f" ]; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

ask_target() {
    TARGET=""
    blank
    if ! read -r -p "Target directory [default .]: " TARGET; then
        TARGET="."
    fi
    [ -z "$TARGET" ] && TARGET="."
    while [ ! -e "$TARGET" ]; do
        say "[WARN] Path not found: $TARGET"
        sleep 1
        if ! read -r -p "Target directory [default .]: " TARGET; then
            TARGET="."
            break
        fi
        [ -z "$TARGET" ] && TARGET="."
    done
    return 0
}

show_reports() {
    blank
    if [ ! -d "$REPORT_DIR" ]; then
        say "[i] No report directory yet: $REPORT_DIR"
        return 0
    fi
    say "[i] Recent files in $REPORT_DIR:"
    local n=0 f
    while IFS= read -r f; do
        n=$((n + 1))
        [ "$n" -le 10 ] && say "  $f"
    done <<EOF
$(ls -1t "$REPORT_DIR" 2>/dev/null)
EOF
    [ "$n" -eq 0 ] && say "  none"
    return 0
}

finish_scan() {
    local rc=$1 label=$2
    if [ "$rc" -ge 2 ]; then
        fail "$label error - see messages above." || true
        return 1
    fi
    if [ "$rc" -eq 1 ]; then
        say "[WARN] Findings at or above threshold. Reports below."
    fi
    show_reports
    done_msg "$label complete."
    return 0
}

opt_setup() {
    blank
    say "=== Setup environment ==="
    if ! command -v python3 >/dev/null 2>&1; then
        fail "Python 3 not found on PATH." || true
        return 0
    fi
    if [ ! -x "$VENV_DIR/bin/python" ]; then
        if ! run python3 -m venv "$VENV_DIR"; then
            fail "Failed to create $VENV_DIR." || true
            return 0
        fi
        if [ "${START_DRYRUN:-}" != "1" ] && [ ! -x "$VENV_DIR/bin/python" ]; then
            fail "Failed to create $VENV_DIR." || true
            return 0
        fi
    fi
    PY="$VENV_DIR/bin/python"
    say "[i] Using interpreter: $PY"
    if ! run "$PY" -m pip install --upgrade pip; then
        fail "pip upgrade failed." || true
        return 0
    fi
    if ! run "$PY" -m pip install -r requirements.txt; then
        fail "Dependency installation failed." || true
        return 0
    fi
    done_msg "Environment ready. Run this script again to use $VENV_DIR."
}

opt_fast() {
    blank
    say "=== Fast scan - Semgrep only ==="
    check_py || return 0
    check_deps || return 0
    ask_target
    say "[i] Scanning: $TARGET"
    run "$PY" aideepsast.py --target "$TARGET" --skip-llm --output-dir "$REPORT_DIR"
    finish_scan $? "Fast scan"
}

opt_ai() {
    blank
    say "=== AI fast scan ==="
    check_py || return 0
    check_deps || return 0
    check_llama || return 0
    ask_target
    say "[i] Scanning: $TARGET"
    say "[i] The local model may download on first run."
    run "$PY" aideepsast.py --target "$TARGET" --output-dir "$REPORT_DIR"
    finish_scan $? "AI fast scan"
}

opt_deep() {
    blank
    say "=== Deep scan ==="
    check_py || return 0
    check_deps || return 0
    ask_target
    say "[i] Scanning: $TARGET"
    run "$PY" deepscan.py --target "$TARGET" --output-dir "$REPORT_DIR"
    finish_scan $? "Deep scan"
}

opt_demo() {
    blank
    say "=== Demo scan ==="
    if [ ! -e "$DEMO_TARGET" ]; then
        fail "Demo file not found: $DEMO_TARGET" || true
        return 0
    fi
    check_py || return 0
    check_deps || return 0
    say "[i] Scanning demo file: $DEMO_TARGET"
    run "$PY" aideepsast.py --target "$DEMO_TARGET" --skip-llm --output-dir "$REPORT_DIR"
    finish_scan $? "Demo scan"
}

opt_config() {
    blank
    say "=== Configuration ==="
    if [ ! -f "$CONFIG_FILE" ]; then
        fail "Config file not found: $CONFIG_FILE" || true
        return 0
    fi
    if [ "${START_DRYRUN:-}" = "1" ]; then
        say "[DRYRUN] show $CONFIG_FILE"
        return 0
    fi
    editor_cmd=""
    if [ -t 0 ] && [ -t 1 ]; then
        if [ -n "${EDITOR:-}" ] && command -v "${EDITOR%% *}" >/dev/null 2>&1; then
            editor_cmd="${EDITOR}"
        elif command -v sensible-editor >/dev/null 2>&1; then
            editor_cmd="sensible-editor"
        fi
    fi
    if [ -n "$editor_cmd" ]; then
        $editor_cmd "$CONFIG_FILE"
    else
        say "[i] Showing $CONFIG_FILE"
        hr
        head -n 40 "$CONFIG_FILE"
        hr
        say "[i] Edit it with: nano $CONFIG_FILE"
    fi
    done_msg "Configuration displayed."
}

opt_status() {
    blank
    say "=== Model status ==="
    check_py || return 0
    say "[i] Python:"
    "$PY" --version
    blank
    say "[i] llama.cpp runtime:"
    if command -v llama-completion >/dev/null 2>&1; then
        say "    llama-completion : found"
        command -v llama-completion
    else
        say "    llama-completion : not found on PATH"
        say "    Needed by option 3 only. Install llama.cpp and add it to PATH."
    fi
    blank
    say "[i] GGUF model:"
    FS_MODEL=$(find_gguf || true)
    if [ -n "$FS_MODEL" ]; then
        say "    found"
        say "    $FS_MODEL"
    else
        say "    not found - the first AI scan downloads it, about 8 GB"
    fi
    blank
    say "[i] LLM environment:"
    say "    LLM_BASE_URL = ${LLM_BASE_URL:-not set}"
    say "    LLM_MODEL = ${LLM_MODEL:-not set}"
    if [ -n "${LLM_API_KEY:-}" ]; then
        say "    LLM_API_KEY = set"
    else
        say "    LLM_API_KEY = not set"
    fi
    blank
    say "[i] Next steps:"
    if [ -n "$FS_MODEL" ]; then
        say "    Option 3 is ready - llama.cpp and the GGUF model are present."
    else
        say "    Option 3 needs llama.cpp on PATH plus a GGUF model."
    fi
    if [ -n "${LLM_BASE_URL:-}" ]; then
        say "    Option 4 is ready - remote LLM endpoint is configured."
    else
        say "    Option 4 needs LLM_BASE_URL, LLM_API_KEY and LLM_MODEL."
    fi
    done_msg "Model status displayed."
}

opt_tests() {
    blank
    say "=== Run tests ==="
    check_py || return 0
    check_pytest || return 0
    run "$PY" -m pytest tests -v
    if [ $? -ne 0 ]; then
        fail "Tests failed." || true
        return 0
    fi
    done_msg "Tests passed."
}

while true; do
    show_menu
    CHOICE=""
    if ! read -r -p "Select an option: " CHOICE; then
        EMPTY=$((EMPTY + 1))
        if [ "$EMPTY" -ge 3 ]; then
            blank
            say "[ERROR] No input received - stdin closed. Exiting."
            exit 1
        fi
        blank
        say "[WARN] No input received. Type a number and press Enter."
        sleep 1
        continue
    fi
    EMPTY=0
    case "$CHOICE" in
        1) opt_setup ;;
        2) opt_fast ;;
        3) opt_ai ;;
        4) opt_deep ;;
        5) opt_demo ;;
        6) opt_config ;;
        7) opt_status ;;
        8) opt_tests ;;
        0) break ;;
        *) blank; say "[WARN] Invalid choice: $CHOICE"; sleep 1 ;;
    esac
done

blank
say "Goodbye."
exit 0
