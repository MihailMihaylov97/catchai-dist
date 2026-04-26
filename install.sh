#!/usr/bin/env bash
#
# catchai installer — one-line install via curl bash.
#
#     curl -fsSL https://install.catchai.io | bash
#
# Or, for testing against a specific dist repo / wheel:
#
#     CATCHAI_DIST_REPO=MihailMihaylov97/catchai-dist bash install.sh
#     CATCHAI_WHEEL_URL=file:///path/to/local.whl bash install.sh
#
# Idempotent. Safe to re-run for upgrades.
#
# Environment overrides:
#   CATCHAI_DIST_REPO    GitHub <owner>/<repo> hosting wheel releases.
#                        Default: MihailMihaylov97/catchai-dist (the public
#                        wheels repo; see CATCHAI_Repos.md §3).
#   CATCHAI_VERSION      Pin to a specific version (default: latest release).
#   CATCHAI_WHEEL_URL    Direct URL to a wheel — bypasses GitHub release lookup.
#                        Useful for local testing: CATCHAI_WHEEL_URL=file:///...
#   CATCHAI_HOME         Where to put ~/.catchai (default: $HOME/.catchai).
#
set -e

REPO="${CATCHAI_DIST_REPO:-MihailMihaylov97/catchai-dist}"
VERSION_PIN="${CATCHAI_VERSION:-}"
WHEEL_URL_OVERRIDE="${CATCHAI_WHEEL_URL:-}"
CATCHAI_HOME="${CATCHAI_HOME:-$HOME/.catchai}"

COMPLETION_MARKER="# catchai shell completion (managed by catchai installer)"

# ── Helpers ──────────────────────────────────────────────────────────────────

extract_first_major_minor() {
    sed -nE 's/[^0-9]*([0-9]+\.[0-9]+).*/\1/p' | head -1
}

extract_json_string_field() {
    local field="$1"
    sed -nE "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\\1/p" | head -1
}

install_shell_completion() {
    # Currently a stub — catchai's CLI is Click-based, completion machinery
    # ships separately in v0.6+. Keep the function to preserve install.sh
    # idempotency when we add it.
    return 0
}


# ── Detect platform ─────────────────────────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)  PLATFORM="linux" ;;
    Darwin) PLATFORM="macosx" ;;
    *)
        echo "Unsupported OS: $OS"
        echo "  catchai supports macOS and Linux. Windows support is on the roadmap."
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64)        MACHINE="x86_64" ;;
    aarch64|arm64) MACHINE="aarch64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "catchai installer"
echo ""
echo "  Platform: $PLATFORM ($MACHINE)"


# ── Find a usable Python 3.11+ ──────────────────────────────────────────────

PYTHON=""
PYTHON_VERSION=""
for cmd in python3.14 python3.13 python3.12 python3.11 python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
        version=$("$cmd" --version 2>&1 | extract_first_major_minor)
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)
        if [ -n "$major" ] && [ -n "$minor" ] && \
           { [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 11 ]; }; }; then
            PYTHON="$cmd"
            PYTHON_VERSION="$version"
            echo "  Python:   $version ($cmd)"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo ""
    echo "ERROR: Python 3.11+ is required."
    echo ""
    echo "  Install Python:"
    echo "    macOS:         brew install python@3.13"
    echo "    Debian/Ubuntu: sudo apt install python3"
    echo "    Arch:          sudo pacman -S python"
    echo "    Or:            https://www.python.org/downloads/"
    exit 1
fi


# ── Check / install pipx ────────────────────────────────────────────────────

if ! command -v pipx >/dev/null 2>&1; then
    echo ""
    echo "Installing pipx..."
    # Try ensurepip first to bootstrap pip on systems that ship without it.
    if ! "$PYTHON" -m pip --version >/dev/null 2>&1; then
        "$PYTHON" -m ensurepip --user 2>/dev/null || true
    fi
    if ! "$PYTHON" -m pip install --user pipx 2>/dev/null; then
        echo ""
        echo "ERROR: Could not install pipx (pip is not available)."
        echo ""
        echo "  Install pipx for your platform, then re-run:"
        echo "    macOS:         brew install pipx"
        echo "    Debian/Ubuntu: sudo apt install pipx"
        echo "    Arch:          sudo pacman -S python-pipx"
        exit 1
    fi
    "$PYTHON" -m pipx ensurepath 2>/dev/null || true
fi

PIPX_VERSION=$(pipx --version 2>/dev/null || echo "(installed)")
echo "  pipx:     $PIPX_VERSION"


# ── Determine the wheel to install ──────────────────────────────────────────

WORK_DIR=$(mktemp -d)
# Catch SIGINT/SIGTERM too — without these, Ctrl+C during a slow download
# leaves a temp dir behind on every interrupted run.
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

if [ -n "$WHEEL_URL_OVERRIDE" ]; then
    # Direct URL or local file path — used in tests and for air-gapped installs.
    echo ""
    echo "Using wheel URL override: $WHEEL_URL_OVERRIDE"
    if [[ "$WHEEL_URL_OVERRIDE" == file://* ]]; then
        # Strip file:// prefix and copy locally
        local_path="${WHEEL_URL_OVERRIDE#file://}"
        WHEEL="$WORK_DIR/$(basename "$local_path")"
        cp "$local_path" "$WHEEL"
    else
        WHEEL="$WORK_DIR/$(basename "$WHEEL_URL_OVERRIDE")"
        curl -fsSL -o "$WHEEL" "$WHEEL_URL_OVERRIDE"
    fi
else
    # Find latest release from the dist repo
    echo ""
    echo "Finding release..."

    if [ -n "$VERSION_PIN" ]; then
        RELEASE_TAG="v$VERSION_PIN"
    elif command -v gh >/dev/null 2>&1; then
        RELEASE_TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || echo "")
    else
        RELEASE_TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
            | extract_json_string_field "tag_name" || echo "")
    fi

    if [ -z "$RELEASE_TAG" ]; then
        echo ""
        echo "ERROR: No releases found at github.com/$REPO"
        echo ""
        echo "  - If the dist repo is private: install gh CLI and run 'gh auth login'."
        echo "  - If you're testing locally:   CATCHAI_WHEEL_URL=file:///path/to/wheel bash install.sh"
        echo "  - For status:                  https://github.com/$REPO/releases"
        exit 1
    fi

    echo "  Latest:   $RELEASE_TAG"

    # Match wheel filename to platform.
    # cp311-abi3 = abi3 stable ABI, works on any Python 3.11+.
    # macOS uses universal2 (single binary covers Intel + Apple Silicon).
    ABI_TAG="cp311-abi3"
    if [ "$PLATFORM" = "macosx" ]; then
        WHEEL_MACHINE="universal2"
    else
        WHEEL_MACHINE="$MACHINE"
    fi
    WHEEL_PATTERN="catchai-*-${ABI_TAG}-*${WHEEL_MACHINE}*.whl"
    echo "  Looking for: $WHEEL_PATTERN"

    if command -v gh >/dev/null 2>&1; then
        gh release download "$RELEASE_TAG" --repo "$REPO" \
            --pattern "$WHEEL_PATTERN" --dir "$WORK_DIR" 2>/dev/null
    else
        ASSETS_URL="https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG"
        WHEEL_URL=$(curl -fsSL "$ASSETS_URL" 2>/dev/null \
            | grep '"browser_download_url"' \
            | grep "$WHEEL_MACHINE" \
            | grep "$ABI_TAG" \
            | head -1 \
            | extract_json_string_field "browser_download_url")

        if [ -z "$WHEEL_URL" ]; then
            echo ""
            echo "ERROR: No wheel found for Python $PYTHON_VERSION on $PLATFORM/$MACHINE"
            echo "  Available wheels: https://github.com/$REPO/releases/tag/$RELEASE_TAG"
            exit 1
        fi

        curl -fsSL -o "$WORK_DIR/$(basename "$WHEEL_URL")" "$WHEEL_URL"
    fi

    WHEEL=$(find "$WORK_DIR" -name '*.whl' | head -1)
fi

if [ -z "$WHEEL" ] || [ ! -f "$WHEEL" ]; then
    echo ""
    echo "ERROR: Wheel download failed — no .whl found in $WORK_DIR"
    exit 1
fi

echo "  Downloaded: $(basename "$WHEEL")"


# ── Install via pipx ────────────────────────────────────────────────────────

echo ""
echo "Installing catchai..."
# Use pipx's own quiet mode rather than grepping output — grep -v silently
# swallows any real warning the user needs to see (and any non-zero exit
# from pipx would be hidden by the pipe). pipx's --pip-args reaches its
# inner pip; --quiet on pipx itself drops the celebratory ✨/🌟/⚠️ noise.
if ! pipx install --force --quiet "$WHEEL" 2>&1; then
    echo "ERROR: pipx install failed"
    exit 1
fi

# Make sure ~/.local/bin is on PATH for future shells
pipx ensurepath 2>/dev/null || true


# ── Set up ~/.catchai/ tree ─────────────────────────────────────────────────

mkdir -p "$CATCHAI_HOME"/{cache,license,reports,rules}
echo "  catchai data dir: $CATCHAI_HOME"


# ── Verify the binary actually works ────────────────────────────────────────

CATCHAI_BIN="${PIPX_BIN_DIR:-$HOME/.local/bin}/catchai"
if [ ! -x "$CATCHAI_BIN" ]; then
    echo ""
    echo "ERROR: catchai binary not found at $CATCHAI_BIN after install"
    exit 1
fi


# ── Shell completion (stub for now) ─────────────────────────────────────────

install_shell_completion


# ── Done ────────────────────────────────────────────────────────────────────

# `|| echo` after `$()` doesn't trigger on inner-pipeline failure — the
# assignment succeeds with empty output. Capture properly: explicitly run
# the command, fall back if empty.
INSTALLED_VERSION=$("$CATCHAI_BIN" --version 2>/dev/null | head -1 | awk '{print $NF}')
INSTALLED_VERSION="${INSTALLED_VERSION:-(version detection failed)}"

echo ""
echo "Done! Installed catchai $INSTALLED_VERSION."
echo ""

if ! command -v catchai >/dev/null 2>&1; then
    echo "NOTE: catchai is not yet on your PATH. Run:"
    echo ""
    echo "  source ~/.bashrc      (or ~/.zshrc)"
    echo ""
    echo "Or open a new terminal."
    echo ""
fi

echo "Next steps:"
echo ""
echo "  catchai --help"
echo "  catchai scan ./my-repo"
echo ""
echo "  # Layer 7 (semantic LLM analysis) requires either:"
echo "  #   - Anthropic API key:  export ANTHROPIC_API_KEY=sk-ant-..."
echo "  #   - Claude Code installed and signed in (claude login)"
echo ""
