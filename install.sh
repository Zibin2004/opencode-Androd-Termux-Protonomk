#!/data/data/com.termux/files/usr/bin/bash
#
# Protonomk installer for Android/Termux.
#
# Installs the native aarch64 OpenCode v2 build, patches the TUI logo from
# "opencode" to "PROTONOMK", adds the `protonomk` launcher, and configures the
# Protonomk AI provider.
#
# Fork of https://github.com/astreele/opencode-android (MIT).
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Zibin2004/opencode-Androd-Termux-Protonomk/main/install.sh)
#
# What it does:
#   * installs OpenCode v2 for native Termux (opencode2 + `opencode` link),
#     either through the signed APT repository or the release zip;
#   * copies the binary to $PREFIX/libexec/protonomk/protonomk.bin and patches
#     the embedded TUI splash logo to the Protonomk wordmark;
#   * creates the `protonomk` launcher;
#   * writes the Protonomk provider into ~/.config/opencode/opencode.json:
#       base URL  https://api.protonomk.ru/api/v1
#       models    fixed catalog (prices per 1M tokens), see PROTONOMK_MODELS
#       chat      POST https://api.protonomk.ru/api/v1/chat/completions
#     The model catalog is embedded, so installation needs no API key;
#     a key is only needed at runtime (or pass --protonomk-key).
#
# Options (append after the command):
#   --cmd opencode     install ONLY as `opencode` (run from just that command;
#                      no opencode2 name, no symlink; implies --zip because
#                      the deb always ships opencode2 + the opencode link)
#   --cmd opencode2    default: install opencode2 + link opencode -> opencode2
#   --no-link          never touch $PREFIX/bin/opencode (implies --zip)
#   --force            replace an existing opencode this installer doesn't manage
#   --apt              force the package-manager path (default)
#   --zip              legacy direct-download path (zip asset + SHA256SUMS check)
#   --no-verify        (zip only) skip SHA256SUMS verification (emergency only)
#   --protonomk-key K  Protonomk API key (also: PROTONOMK_API_KEY env)
#   --no-protonomk     install OpenCode without configuring the provider
#   --no-logo          keep the upstream TUI logo (skip the binary patch)
#
set -e

REPO="astreele/opencode-android"
APT_ROOT="https://opencode-android-apt.psmsword148.workers.dev"
# The key URL is overridable for tests; the raw.githubusercontent copy is the
# fallback for devices reaching GitHub before Pages serves the branch.
APT_KEY_URL="${APT_KEY_URL:-$APT_ROOT/opencode-android.gpg}"
APT_KEY_FALLBACK="https://raw.githubusercontent.com/${REPO}/master/apt/opencode-android.gpg"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

# ── Protonomk preset ─────────────────────────────────────────────────
PROTONOMK=1
PROTONOMK_CMD="protonomk"
LOGO=1
PROTONOMK_KEY="${PROTONOMK_API_KEY:-}"
PROTONOMK_BASE="${PROTONOMK_BASE_URL:-https://api.protonomk.ru/api/v1}"
PROTONOMK_PACKAGE="@opencode/ai/providers/openai-compatible"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

CMD="${OPENCODE_CMD:-opencode2}"
LINK=1
FORCE="${OPENCODE_FORCE:-0}"
VERIFY=1
METHOD="auto"

usage() {
    cat <<'EOF'
Protonomk installer for Android/Termux

Usage: install.sh [options]

Installs the Protonomk-branded launcher `protonomk` (plus the upstream
opencode2/opencode commands used as its binary source).

Options:
  --cmd NAME    Which command to install: 'opencode2' (default) or 'opencode'.
                '--cmd opencode' installs the program so it runs from just
                the `opencode` command — no opencode2 name, no symlink
                (uses the --zip path; the deb always ships both names).
  --link        Create/refresh the `opencode` -> `opencode2` symlink
                (default for --cmd opencode2).
  --no-link     Install opencode2 but never touch $PREFIX/bin/opencode
                (use when a v1 `opencode` should keep working; uses --zip).
  --force       Replace an existing $PREFIX/bin/opencode that this installer
                does not manage (e.g. a v1 install).
  --apt         Install through the system package manager (default):
                registers the signed APT repository and runs
                `pkg install opencode2`. Later updates arrive via `pkg upgrade`.
  --zip         Legacy path instead: download the release zip, verify it
                against SHA256SUMS, and copy the files by hand.
  --no-verify   (zip only) Skip SHA256SUMS verification (emergency only).
  --protonomk-key KEY
                Protonomk API key. Written to the OpenCode config so the
                provider works immediately. Also read from PROTONOMK_API_KEY.
  --no-protonomk
                Skip the Protonomk provider setup entirely.
  --no-logo     Keep the upstream TUI logo (skip the embedded logo patch).
  -h, --help    Show this help.

Environment:
  OPENCODE_CMD, OPENCODE_FORCE=1, PROTONOMK_API_KEY,
  PROTONOMK_BASE_URL (default https://api.protonomk.ru/api/v1).

Protonomk endpoints:
  GET  https://api.protonomk.ru/api/v1/models   (reference, not used at install)
  POST https://api.protonomk.ru/api/v1/chat/completions

The model catalog (27 chat models with prices) is embedded in this script;
installation does not call the API. A key is needed only at runtime.

Examples:
  install.sh                          # install + configure Protonomk
  install.sh --protonomk-key sk-...   # provide the key non-interactively
  install.sh --no-protonomk           # stock OpenCode only
  install.sh --zip                    # same layout, direct download
  install.sh --no-logo                # keep the upstream splash logo
  install.sh --cmd opencode           # just the `opencode` command (zip path)

After installation run:
  protonomk                           # branded TUI
  protonomk --help                    # branded help
EOF
}

die() {
    echo "FAILED: $*" >&2
    exit 1
}

# Is $1 a binary/link managed by this project (and not a foreign/v1 install)?
is_ours() {
    if [ -L "$1" ]; then
        case "$(readlink "$1")" in
            *opencode2*) return 0 ;;
            *) return 1 ;;
        esac
    fi
    [ -f "$1" ] || return 1
    grep -q "wrapper for OpenCode 2 CLI" "$1" 2>/dev/null
}

# Who owns a path according to the package manager (best effort, for hints)?
owner_of() {
    if command -v dpkg >/dev/null 2>&1; then
        dpkg -S "$1" 2>/dev/null | head -n 1 || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Qo "$1" 2>/dev/null || true
    fi
}

# ── options ────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --cmd)
            [ $# -ge 2 ] || die "--cmd needs a value (opencode|opencode2)"
            CMD="$2"; shift 2 ;;
        --cmd=*) CMD="${1#--cmd=}"; shift ;;
        --link) LINK=1; shift ;;
        --no-link) LINK=0; shift ;;
        --force) FORCE=1; shift ;;
        --apt) METHOD="apt"; shift ;;
        --zip) METHOD="zip"; shift ;;
        --no-verify) VERIFY=0; shift ;;
        --protonomk-key)
            [ $# -ge 2 ] || die "--protonomk-key needs a value"
            PROTONOMK_KEY="$2"; shift 2 ;;
        --protonomk-key=*) PROTONOMK_KEY="${1#--protonomk-key=}"; shift ;;
        --no-protonomk) PROTONOMK=0; shift ;;
        --no-logo) LOGO=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

case "$CMD" in
    opencode|opencode2) ;;
    *) die "--cmd must be 'opencode' or 'opencode2' (got '$CMD')" ;;
esac

# The deb always ships opencode2 + the opencode link, so single-name and
# no-link installs can only come from the zip path.
if [ "$METHOD" = "apt" ]; then
    if [ "$CMD" = "opencode" ]; then
        die "--cmd opencode needs --zip (the deb always ships opencode2 + the opencode link)"
    fi
    if [ "$LINK" = 0 ]; then
        die "--no-link needs --zip (the deb always ships the opencode link)"
    fi
elif [ "$METHOD" = "auto" ]; then
    if [ "$CMD" = "opencode" ] || [ "$LINK" = 0 ]; then
        echo "(note: --cmd $CMD / --no-link uses the direct-download path)"
        METHOD="zip"
    else
        METHOD="apt"
    fi
fi

stop_ours() {
    if [ -x "$PREFIX/bin/$PROTONOMK_CMD" ]; then
        "$PREFIX/bin/$PROTONOMK_CMD" service stop >/dev/null 2>&1 || true
    fi
    for c in opencode opencode2; do
        if [ -x "$PREFIX/bin/$c" ] && is_ours "$PREFIX/bin/$c"; then
            "$PREFIX/bin/$c" service stop >/dev/null 2>&1 || true
        fi
    done
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "libexec/opencode" >/dev/null 2>&1 || true
        pkill -f "libexec/protonomk" >/dev/null 2>&1 || true
    fi
}

# ── Protonomk provider ────────────────────────────────────────────────

need_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    command -v pkg >/dev/null 2>&1 || return 1
    echo "  installing jq (needed to merge the provider config)..."
    pkg install -y jq >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1
}

# Fixed Protonomk catalog: only these models are exposed.
# Prices are USD per 1M tokens in the order cache-read / input / output.
# Cache-write pricing is not published, so it is reported as 0.
PROTONOMK_DEFAULT_MODEL="claude-sonnet-5-5"
PROTONOMK_MODELS='{
  "claude-fable-5": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.525,"write":0},"input":5.25,"output":26.25},"family":"claude","name":"claude-fable-5"},
  "claude-fable-5-1": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.13125,"write":0},"input":5.25,"output":26.25},"family":"claude","name":"claude-fable-5-1"},
  "claude-fable-5-1-amazon": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":2.73,"output":13.23},"family":"claude","name":"claude-fable-5-1-amazon"},
  "claude-fable-5-2": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":4.2,"output":21.0},"family":"claude","name":"claude-fable-5-2"},
  "claude-haiku-5-5": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.00525,"write":0},"input":0.0525,"output":0.2625},"family":"claude","name":"claude-haiku-5-5"},
  "claude-opus-4-6": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.2625,"write":0},"input":2.625,"output":13.125},"family":"claude","name":"claude-opus-4-6"},
  "claude-opus-5-5": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.105,"write":0},"input":2.1,"output":10.5},"family":"claude","name":"claude-opus-5-5"},
  "claude-opus-5-5-amazon": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":1.05,"output":5.25},"family":"claude","name":"claude-opus-5-5-amazon"},
  "claude-sonnet-5-5": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0525,"write":0},"input":1.05,"output":5.25},"family":"claude","name":"claude-sonnet-5-5"},
  "claude-sonnet-5-5-amazon": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":0.525,"output":2.73},"family":"claude","name":"claude-sonnet-5-5-amazon"},
  "deepseek-v4.1-flash-1017": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.00672,"write":0},"input":1.134,"output":10.5},"family":"deepseek","name":"deepseek-v4.1-flash-1017"},
  "deepseek-v4.1-flash-1017-uncensored-special": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":1.449,"output":6.09},"family":"deepseek","name":"deepseek-v4.1-flash-1017-uncensored-special"},
  "deepseek-v4.1-flash-uncensored": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":0.84,"output":3.318},"family":"deepseek","name":"deepseek-v4.1-flash-uncensored"},
  "glm-5.3-flash": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0315,"write":0},"input":0.1575,"output":0.525},"family":"glm","name":"glm-5.3-flash"},
  "glm-5.3-flash-uncensored": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.42,"write":0},"input":1.05,"output":4.2},"family":"glm","name":"glm-5.3-flash-uncensored"},
  "gpt-6-astra": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.42,"write":0},"input":3.15,"output":15.75},"family":"gpt","name":"gpt-6-astra"},
  "gpt-6-luna": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0042,"write":0},"input":0.0315,"output":0.1575},"family":"gpt","name":"gpt-6-luna"},
  "gpt-6-sol": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.084,"write":0},"input":0.63,"output":3.15},"family":"gpt","name":"gpt-6-sol"},
  "gpt-6.1-sol": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.042,"write":0},"input":0.63,"output":3.15},"family":"gpt","name":"gpt-6.1-sol"},
  "gpt-6.1-terra": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":0.315,"output":1.575},"family":"gpt","name":"gpt-6.1-terra"},
  "kimi-k3.1-pro-uncensored": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.252,"write":0},"input":2.52,"output":13.23},"family":"kimi","name":"kimi-k3.1-pro-uncensored"},
  "mimo-v26-flash-abl": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":1.995,"output":6.09},"family":"mimo","name":"mimo-v26-flash-abl"},
  "mimo-v26-flash-unc": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":1.848,"output":6.09},"family":"mimo","name":"mimo-v26-flash-unc"},
  "minimax-m3.1-flash": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":0.1575,"output":0.63},"family":"minimax","name":"minimax-m3.1-flash"},
  "qwen38-uncensored-ultraspeed": {"capabilities":{"input":["text"],"output":["text"],"tools":true},"cost":{"cache":{"read":0.0,"write":0},"input":3.36,"output":10.5},"family":"qwen38","name":"qwen38-uncensored-ultraspeed"}
}'

# Merge providers.protonomk (and optionally the key/default model) into the
# global config. Never clobbers unrelated settings; keeps a .bak copy.
write_protonomk_config() {
    _models="$1"
    _target="$CONFIG_DIR/opencode.json"
    if [ ! -f "$_target" ] && [ -f "$CONFIG_DIR/opencode.jsonc" ]; then
        _target="$CONFIG_DIR/opencode.jsonc"
    fi

    mkdir -p "$CONFIG_DIR" || return 1

    _tmp="$_target.tmp.$$"
    if [ -f "$_target" ]; then
        if ! jq -e . "$_target" >/dev/null 2>&1; then
            echo "    WARNING: $_target is not plain JSON (comments?). Left untouched."
            echo "    Add this under \"providers\" manually:"
            jq -n --argjson m "$_models" --arg base "$PROTONOMK_BASE" \
                '{protonomk: {name: "Protonomk", env: ["PROTONOMK_API_KEY"],
                  package: "@opencode/ai/providers/openai-compatible",
                  settings: {baseURL: $base}, models: $m}}'
            return 0
        fi
        cp -f "$_target" "$_target.bak" || true
        if ! jq --argjson models "$_models" --arg base "$PROTONOMK_BASE" \
                --arg key "$PROTONOMK_KEY" --arg default "$PROTONOMK_DEFAULT_MODEL" '
              .providers = (.providers // {})
              | .providers.protonomk =
                  ((.providers.protonomk // {}) + {
                    name: "Protonomk",
                    env: ((["PROTONOMK_API_KEY"]
                          + ((.providers.protonomk // {}).env // [])) | unique),
                    package: "@opencode/ai/providers/openai-compatible",
                    settings: ((((.providers.protonomk // {}).settings) // {})
                               + { baseURL: $base }
                               + (if $key != "" then { apiKey: $key } else {} end)),
                    models: (((.providers.protonomk // {}).models // {}) + $models)
                  })
              | if (.model == null)
                then .model = ("protonomk/" + $default)
                else . end
            ' "$_target" > "$_tmp" 2>/dev/null; then
            rm -f "$_tmp"
            echo "    WARNING: could not merge config into $_target; left untouched."
            return 0
        fi
    else
        if ! jq -n --argjson models "$_models" --arg base "$PROTONOMK_BASE" \
                --arg key "$PROTONOMK_KEY" --arg default "$PROTONOMK_DEFAULT_MODEL" '
              {
                "$schema": "https://opencode.ai/config.json",
                providers: {
                  protonomk: {
                    name: "Protonomk",
                    env: ["PROTONOMK_API_KEY"],
                    package: "@opencode/ai/providers/openai-compatible",
                    settings: ({ baseURL: $base }
                               + (if $key != "" then { apiKey: $key } else {} end)),
                    models: $models
                  }
                }
              }
              | .model = ("protonomk/" + $default)
            ' > "$_tmp" 2>/dev/null; then
            rm -f "$_tmp"
            echo "    WARNING: could not write $_target."
            return 0
        fi
    fi

    mv -f "$_tmp" "$_target"
    chmod 600 "$_target" 2>/dev/null || true
    echo "    provider written to $_target"
}

setup_protonomk() {
    [ "$PROTONOMK" = 1 ] || {
        echo "  Protonomk provider: skipped (--no-protonomk)"
        return 0
    }

    echo "  Protonomk provider:"

    if ! need_jq; then
        echo "    WARNING: jq is unavailable; skipping provider setup."
        echo "    Install it (pkg install jq) and re-run, or add the provider manually:"
        echo "      baseURL: $PROTONOMK_BASE"
        return 0
    fi

    if [ -z "$PROTONOMK_KEY" ] && [ -t 0 ]; then
        printf '    API key (leave empty to configure later): '
        IFS= read -rs PROTONOMK_KEY || true
        printf '\n'
    fi

    _n=$(printf '%s' "$PROTONOMK_MODELS" | jq 'length')
    echo "    fixed catalog: $_n model(s)"
    if [ -z "$PROTONOMK_KEY" ]; then
        echo "    no key given: provider reads PROTONOMK_API_KEY at runtime"
    fi

    write_protonomk_config "$PROTONOMK_MODELS"

    # Pick up the new config in the background service, if one is running.
    "$PREFIX/bin/opencode2" reload >/dev/null 2>&1 ||
        "$PREFIX/bin/opencode" reload >/dev/null 2>&1 || true

    echo "    key: --protonomk-key KEY or export PROTONOMK_API_KEY"
}

# ── Protonomk launcher + logo ────────────────────────────────────────
_protonomk_iconv() {
    if command -v iconv >/dev/null 2>&1; then
        iconv -f UTF-8 -t UTF-16LE
    elif [ -x /system/bin/iconv ]; then
        /system/bin/iconv -f UTF-8 -t UTF-16LE
    else
        return 1
    fi
}

# Patch the UTF-16LE logo strings embedded in the Bun bytecode.  The source
# copy of the same art uses \uXXXX escapes and is not what the TUI executes.
# Each replacement is exactly 19 UTF-16 code units, so no offsets move.
patch_protonomk_logo() {
    _bin="$1"
    [ -f "$_bin" ] || { echo "    logo: skipped (binary not found)"; return 0; }
    if ! command -v iconv >/dev/null 2>&1 && [ ! -x /system/bin/iconv ]; then
        echo "    logo: skipped (iconv not found)"
        return 0
    fi
    _tmp=$(mktemp -d) || { echo "    logo: skipped (mktemp failed)"; return 0; }
    _patched=0

    _old_left=(
        '█▀▀█ █▀▀█ █▀▀█ █▀▀▄'
        '█__█ █__█ █^^^ █__█'
        '▀▀▀▀ █▀▀▀ ▀▀▀▀ ▀~~▀'
    )
    _new_left=(
        '█▀█ █▀█ █▀█ ▀█▀ █▀█'
        '█▀▀ █▀▄ █ █  █  █ █'
        '▀   ▀ ▀ ▀▀▀  ▀  ▀▀▀'
    )
    _old_right=(
        '             ▄     '
        '█▀▀▀ █▀▀█ █▀▀█ █▀▀█'
        '█___ █__█ █__█ █^^^'
        '▀▀▀▀ ▀▀▀▀ ▀▀▀▀ ▀▀▀▀'
    )
    _new_right=(
        '                   '
        '█ █ █▀█ █ █ █ █    '
        '█▄█ █ █ ███ █▀▄    '
        '▀ ▀ ▀▀▀ ▀ ▀ ▀ ▀    '
    )

    _patch_pair() {
        _old="$1"
        _new="$2"
        printf '%s' "$_old" | _protonomk_iconv > "$_tmp/old.utf16" 2>/dev/null || return 0
        printf '\n' >> "$_tmp/old.utf16"
        _offsets=$(LC_ALL=C grep -abo -F -f "$_tmp/old.utf16" "$_bin" 2>/dev/null | cut -d: -f1 || true)
        [ -n "$_offsets" ] || return 0
        printf '%s' "$_new" | _protonomk_iconv > "$_tmp/new.utf16" 2>/dev/null || return 0
        _newlen=$(wc -c < "$_tmp/new.utf16")
        if [ "$_newlen" -ne 38 ]; then
            echo "    logo: replacement has $_newlen bytes, expected 38; skipped"
            return 0
        fi
        for _off in $_offsets; do
            if dd if="$_tmp/new.utf16" of="$_bin" bs=1 seek="$_off" conv=notrunc 2>/dev/null; then
                _patched=$((_patched + 1))
            fi
        done
    }

    for _i in 0 1 2; do
        _patch_pair "${_old_left[$_i]}" "${_new_left[$_i]}"
    done
    for _i in 0 1 2 3; do
        _patch_pair "${_old_right[$_i]}" "${_new_right[$_i]}"
    done

    rm -rf "$_tmp"
    if [ "$_patched" -gt 0 ]; then
        echo "    logo: patched $_patched embedded logo string(s)"
    else
        echo "    logo: no known logo strings found (upstream binary changed?)"
    fi
}

write_protonomk_wrapper() {
    _wrapper="$PREFIX/bin/$PROTONOMK_CMD"
    cat > "$_wrapper" <<'PROTONOMK_WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
# protonomk - Protonomk branded OpenCode CLI for Android/Termux
set -eu
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
DIR="$(CDPATH= cd -- "$(dirname "$SELF")" && pwd)"
export PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export LD_LIBRARY_PATH="${PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
unset OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER || true
export OPENCODE_DISABLE_FFF=1
BIN=""
for candidate in \
    "$DIR/../libexec/protonomk/protonomk.bin" \
    "$PREFIX/libexec/protonomk/protonomk.bin"
do
    if [ -x "$candidate" ]; then BIN="$candidate"; break; fi
done
if [ -z "$BIN" ]; then
    echo "protonomk: error: could not find protonomk.bin" >&2
    exit 127
fi
if [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then
    "$BIN" "$@" | sed -e 's/OpenCode command line interface/Protonomk command line interface/' \
        -e 's/opencode <subcommand>/protonomk <subcommand>/'
    exit "${PIPESTATUS[0]:-0}"
fi
if [ "${1-}" = "--version" ] || [ "${1-}" = "-v" ]; then
    "$BIN" "$@" | sed -e 's/^opencode vv/Protonomk v/' -e 's/^opencode /Protonomk /'
    exit "${PIPESTATUS[0]:-0}"
fi
exec "$BIN" "$@"
PROTONOMK_WRAPPER
    chmod 755 "$_wrapper"
}

install_protonomk_branded() {
    echo "[*] Installing the Protonomk launcher..."

    _src=""
    for _candidate in \
        "$PREFIX/libexec/$CMD/$CMD.bin" \
        "$PREFIX/libexec/opencode2/opencode2.bin" \
        "$PREFIX/libexec/opencode/opencode.bin"
    do
        if [ -x "$_candidate" ]; then _src="$_candidate"; break; fi
    done
    if [ -z "$_src" ]; then
        echo "  WARNING: upstream binary not found; skipping the protonomk launcher."
        return 0
    fi

    mkdir -p "$PREFIX/libexec/protonomk" "$PREFIX/bin"
    cp -f "$_src" "$PREFIX/libexec/protonomk/protonomk.bin"
    chmod 755 "$PREFIX/libexec/protonomk/protonomk.bin"

    if [ "$LOGO" = 1 ]; then
        patch_protonomk_logo "$PREFIX/libexec/protonomk/protonomk.bin"
    else
        echo "  logo: skipped (--no-logo)"
    fi

    if ! LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
         OPENCODE_DISABLE_FFF=1 \
         "$PREFIX/libexec/protonomk/protonomk.bin" --version >/dev/null 2>&1; then
        echo "  WARNING: patched binary failed its smoke test; restoring the unpatched copy."
        cp -f "$_src" "$PREFIX/libexec/protonomk/protonomk.bin"
        chmod 755 "$PREFIX/libexec/protonomk/protonomk.bin"
    fi

    write_protonomk_wrapper
    echo "  launcher: $PREFIX/bin/$PROTONOMK_CMD"
    echo "  binary:   $PREFIX/libexec/protonomk/protonomk.bin"
}

# ── package-manager path ─────────────────────────────────────────────
install_apt() {
    command -v pkg >/dev/null 2>&1 ||
        die "pkg not found — the package-manager path needs Termux (use --zip elsewhere)"
    command -v curl >/dev/null 2>&1 || pkg install -y curl

    echo "[1] Checking for a foreign 'opencode'..."

    # dpkg-owned v1 is handled by the deb itself (Conflicts/Replaces); only a
    # hand-installed file needs the explicit guard. Runs first so a refusal
    # happens before anything is registered or downloaded.
    L="$PREFIX/bin/opencode"
    if { [ -e "$L" ] || [ -L "$L" ]; } && ! is_ours "$L" && ! owner_of "$L" | grep -q .; then
        if [ "$FORCE" = 1 ]; then
            echo "WARNING: replacing existing $L (--force)"
        else
            die "$L already exists and is not managed by this installer.
Options:
  • install without touching it:         install.sh --zip --no-link
    (v2 then runs as \`opencode2\`)
  • replace it with this build:          install.sh --force
Nothing was installed."
        fi
    fi

    echo "[2] Registering the package repository..."

    SOURCES_DIR="$PREFIX/etc/apt/sources.list.d"
    KEYRING_DIR="$PREFIX/etc/apt/trusted.gpg.d"
    mkdir -p "$SOURCES_DIR" "$KEYRING_DIR"

    printf 'deb %s stable main\n' "$APT_ROOT" > "$SOURCES_DIR/opencode-android.list"
    if curl -fL --retry 3 -o "$KEYRING_DIR/opencode-android.gpg.tmp" "$APT_KEY_URL" 2>/dev/null ||
        curl -fL --retry 3 -o "$KEYRING_DIR/opencode-android.gpg.tmp" "$APT_KEY_FALLBACK"; then
        mv -f "$KEYRING_DIR/opencode-android.gpg.tmp" \
            "$KEYRING_DIR/opencode-android.gpg"
        echo "repository key installed"
    else
        rm -f "$KEYRING_DIR/opencode-android.gpg.tmp"
        die "could not fetch the repository key from
  $APT_KEY_URL
  $APT_KEY_FALLBACK
Nothing was installed."
    fi

    echo "[3] Updating package lists..."

    pkg update -y

    echo "[4] Stopping existing OpenCode..."

    stop_ours
    sleep 1

    echo "[5] Installing opencode2 (re-run any time to update)..."

    pkg install -y opencode2

    echo "[6] Verifying..."

    "$PREFIX/bin/opencode2" --version

    echo "[7] Configuring the Protonomk provider..."

    setup_protonomk

    install_protonomk_branded

    echo
    echo "================================"
    echo " Protonomk installed successfully"
    echo "================================"
    echo
    echo "Installed (package manager + Protonomk launcher):"
    echo "  $PREFIX/bin/$PROTONOMK_CMD"
    echo "  $PREFIX/libexec/protonomk/protonomk.bin"
    echo "  $PREFIX/bin/opencode2 (upstream)"
    echo "  $PREFIX/bin/opencode -> opencode2"
    echo "  repository: $APT_ROOT"
    echo
    echo "Update later:"
    echo "  pkg upgrade"
    echo "  # then re-run this installer to refresh the Protonomk-branded copy"
    echo
    echo "Uninstall:"
    echo "  rm -f  $PREFIX/bin/$PROTONOMK_CMD"
    echo "  rm -rf $PREFIX/libexec/protonomk"
    echo "  pkg uninstall opencode2   # remove the upstream package too"
    echo
    echo "Protonomk:"
    echo "  base URL: $PROTONOMK_BASE"
    echo "  config:   $CONFIG_DIR/opencode.json"
    echo "  models:   $PROTONOMK_DEFAULT_MODEL (default), $(printf '%s' "$PROTONOMK_MODELS" | jq 'length') total"
    echo
    echo "Run:"
    echo "  $PROTONOMK_CMD            # branded TUI"
    echo "  $PROTONOMK_CMD --help     # branded help"
    echo "  $PROTONOMK_CMD models     # list models"
}

# ── direct-download path (legacy) ────────────────────────────────────
install_zip() {
    echo "[1] Resolving latest release..."

    API="https://api.github.com/repos/${REPO}/releases/latest"

    TAG=$(curl -fsSL "$API" |
        awk -F'"' '/"tag_name"/ {print $4; exit}')

    if [ -z "$TAG" ]; then
        die "could not resolve latest release"
    fi

    echo "TAG=$TAG"

    echo "[2] Installing dependencies..."

    pkg update -y
    pkg install -y curl unzip grep ripgrep libc++ coreutils

    echo "[3] Creating temporary directory..."

    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    cd "$TMP"

    echo "[4] Getting release information..."

    RELEASE_API="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"

    RELEASE=$(curl -fsSL "$RELEASE_API")

    echo "[5] Finding Android ARM64 binary..."

    ZIP=$(printf '%s\n' "$RELEASE" |
        grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*android[^"]*aarch64[^"]*\.zip"' |
        head -n 1 |
        cut -d '"' -f 4)

    if [ -z "$ZIP" ]; then
        echo
        die "could not find Android ARM64 ZIP. Available release assets:
$(printf '%s\n' "$RELEASE" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' | cut -d '"' -f 4)"
    fi

    echo "Found: $ZIP"

    DOWNLOAD="https://github.com/${REPO}/releases/download/${TAG}/${ZIP}"

    echo "[6] Downloading..."

    curl -fL --retry 3 -o "$ZIP" "$DOWNLOAD"

    echo "[7] Verifying download (SHA256SUMS)..."

    if [ "$VERIFY" = 1 ]; then
        command -v sha256sum >/dev/null 2>&1 ||
            die "sha256sum missing (coreutils); refusing to install unverified — fix coreutils or pass --no-verify"
        curl -fL --retry 3 -o SHA256SUMS \
            "https://github.com/${REPO}/releases/download/${TAG}/SHA256SUMS" ||
            die "release $TAG has no SHA256SUMS; pass --no-verify only if you accept an unverified download"
        # 2>/dev/null || true: an unreadable SHA256SUMS must fall through to the
        # explicit "no entry" error below, not die silently under set -e.
        EXPECTED=$(awk -v f="$ZIP" '$2 == f {print $1; exit}' SHA256SUMS 2>/dev/null || true)
        [ -n "$EXPECTED" ] || die "SHA256SUMS contains no entry for $ZIP"
        ACTUAL=$(sha256sum "$ZIP" | awk '{print $1}')
        if [ "$EXPECTED" != "$ACTUAL" ]; then
            die "checksum mismatch for $ZIP
  expected: $EXPECTED
  actual:   $ACTUAL
The download is corrupt or was tampered with; nothing was installed."
        fi
        echo "checksum OK: $ZIP"
    else
        echo "skipped (--no-verify)"
    fi

    echo "[8] Extracting..."

    unzip -o "$ZIP"

    if [ ! -f opencode2 ]; then
        die "opencode2 not found in archive"
    fi

    if [ ! -f opencode2.bin ]; then
        die "opencode2.bin not found in archive"
    fi

    # ── guard: never silently clobber a command we don't own (e.g. v1) ─────
    TARGET="$PREFIX/bin/$CMD"
    if { [ -e "$TARGET" ] || [ -L "$TARGET" ]; } && ! is_ours "$TARGET"; then
        OWNER=$(owner_of "$TARGET")
        if [ "$FORCE" = 1 ]; then
            echo "WARNING: replacing existing $TARGET (--force)"
            if [ -n "$OWNER" ]; then echo "  it was provided by: $OWNER"; fi
        else
            if [ "$CMD" = "opencode" ]; then
                die "$TARGET already exists and is not managed by this installer.
${OWNER:+  It is provided by: $OWNER}
Options:
  • replace it with this build:          install.sh --cmd opencode --force
  • keep it and install v2 under
    a different command name:            install.sh --cmd opencode2 --no-link
    (v2 then runs as \`opencode2\`)
Nothing was installed."
            else
                die "$TARGET already exists and is not managed by this installer.
${OWNER:+  It is provided by: $OWNER}
Options:
  • install without touching it:         install.sh --no-link
  • replace it with this build:          install.sh --force
  • install v2 under a single command:   install.sh --cmd opencode
Nothing was installed."
            fi
        fi
    fi

    echo "[9] Stopping existing OpenCode..."

    stop_ours

    sleep 1

    echo "[10] Installing (command: $CMD)..."

    mkdir -p "$PREFIX/bin"
    mkdir -p "$PREFIX/libexec/$CMD"

    # The shipped wrapper is named opencode2; rewrite its internal paths when the
    # user asked for a different command name (--cmd opencode).
    sed -e "s/opencode2\.bin/${CMD}.bin/g" \
        -e "s|libexec/opencode2|libexec/${CMD}|g" \
        -e "s/opencode2: error/${CMD}: error/g" \
        -e "s/# opencode2 - wrapper/# ${CMD} - wrapper/g" \
        opencode2 > "$PREFIX/bin/$CMD"
    chmod 755 "$PREFIX/bin/$CMD"
    cp -f opencode2.bin "$PREFIX/libexec/$CMD/$CMD.bin"
    chmod 755 "$PREFIX/libexec/$CMD/$CMD.bin"

    # Ship the license alongside the binary (present in release zips).
    if [ -f LICENSE ]; then
        mkdir -p "$PREFIX/share/doc/$CMD"
        cp -f LICENSE "$PREFIX/share/doc/$CMD/"
    fi

    echo "[11] Linking 'opencode'..."

    LINK_STATE="not requested"
    if [ "$CMD" = "opencode" ]; then
        LINK_STATE="runs directly as 'opencode' (no symlink)"
    elif [ "$LINK" = 0 ]; then
        LINK_STATE="skipped (--no-link)"
    else
        L="$PREFIX/bin/opencode"
        if { [ -e "$L" ] || [ -L "$L" ]; } && ! is_ours "$L"; then
            if [ "$FORCE" = 1 ]; then
                OWNER=$(owner_of "$L")
                echo "WARNING: replacing existing $L (--force)"
                if [ -n "$OWNER" ]; then echo "  it was provided by: $OWNER"; fi
                ln -sf "$TARGET" "$L"
                LINK_STATE="replaced (--force)"
            else
                LINK_STATE="left untouched (existing '$L' is not ours)"
                echo
                echo "  NOTE: $L exists and was left alone (likely a v1 install)."
                echo "  v2 is installed and runs as:  opencode2"
                echo "  To make \`opencode\` run v2 instead:"
                echo "    • remove the old command first (e.g. pkg uninstall <package>),"
                echo "      or re-run with --force to replace it,"
                echo "    • or re-run with --no-link to keep both as-is."
            fi
        else
            ln -sf "$TARGET" "$L"
            LINK_STATE="created ($L -> opencode2)"
        fi
    fi

    echo "[12] Verifying..."

    "$PREFIX/bin/$CMD" --version

    echo "[13] Configuring the Protonomk provider..."

    setup_protonomk

    install_protonomk_branded

    echo
    echo "================================"
    echo " Protonomk installed successfully"
    echo "================================"
    echo
    echo "Installed:"
    echo "  $PREFIX/bin/$PROTONOMK_CMD"
    echo "  $PREFIX/libexec/protonomk/protonomk.bin"
    echo "  $PREFIX/bin/$CMD (upstream)"
    echo "  $PREFIX/libexec/$CMD/$CMD.bin"
    if [ "$CMD" = "opencode2" ]; then
        echo "  symlink opencode: $LINK_STATE"
    else
        echo "  opencode link: $LINK_STATE"
    fi
    echo
    echo "Uninstall:"
    echo "  rm -f  $PREFIX/bin/$PROTONOMK_CMD"
    echo "  rm -rf $PREFIX/libexec/protonomk"
    echo "  rm -f  $PREFIX/bin/$CMD"
    echo "  rm -rf $PREFIX/libexec/$CMD"
    echo "  rm -f  $PREFIX/share/doc/$CMD/LICENSE"
    if [ "$CMD" = "opencode2" ]; then
        echo "  rm -f  $PREFIX/bin/opencode   # only if it points to opencode2"
    fi
    echo
    echo "Protonomk:"
    echo "  base URL: $PROTONOMK_BASE"
    echo "  config:   $CONFIG_DIR/opencode.json"
    echo "  models:   $PROTONOMK_DEFAULT_MODEL (default), $(printf '%s' "$PROTONOMK_MODELS" | jq 'length') total"
    echo
    echo "Run:"
    echo "  $PROTONOMK_CMD            # branded TUI"
    echo "  $PROTONOMK_CMD --help     # branded help"
    echo "  $PROTONOMK_CMD models     # list models"
}

case "$METHOD" in
    apt) install_apt ;;
    zip) install_zip ;;
esac
