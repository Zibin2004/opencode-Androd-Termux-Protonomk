#!/data/data/com.termux/files/usr/bin/bash
#
# publish.sh - upload the Protonomk installer files to GitHub via the REST API.
#
#   GITHUB_TOKEN=github_pat_... ./publish.sh
#   GITHUB_TOKEN=github_pat_... ./publish.sh install.sh README.md
#   ./publish.sh ghp_xxx install.sh README.md
#
# The token needs: Repository permissions -> Contents: Read and write,
# and this repository must be selected in "Repository access".
# A classic PAT with the `repo` (or `public_repo`) scope works too.
#
# Environment:
#   GITHUB_TOKEN / GH_TOKEN   fine-grained PAT (or classic PAT with `repo`)
#   GITHUB_REPO               default: Zibin2004/opencode-Androd-Termux-Protonomk
#   GITHUB_BRANCH             default: main

set -euo pipefail

REPO="${GITHUB_REPO:-Zibin2004/opencode-Androd-Termux-Protonomk}"
BRANCH="${GITHUB_BRANCH:-main}"

# Token from the environment, or as the first positional argument.
if [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ]; then
    TOKEN="${GITHUB_TOKEN:-${GH_TOKEN}}"
    FILES="${*:-install.sh README.md LICENSE publish.sh}"
else
    TOKEN="${1:-}"
    [ $# -gt 0 ] && shift
    FILES="${*:-install.sh README.md LICENSE publish.sh}"
fi

DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
API="https://api.github.com/repos/$REPO/contents"

if [ -z "$TOKEN" ]; then
    echo "publish.sh: no token" >&2
    echo "usage: GITHUB_TOKEN=github_pat_... $0 [files...]" >&2
    exit 2
fi

# Fail early with a clear message instead of a confusing 403 later.
login="$(curl -sS -H "Authorization: Bearer $TOKEN" \
             -H "Accept: application/vnd.github+json" \
             https://api.github.com/user | jq -r '.login // empty')"
if [ -z "$login" ]; then
    echo "publish.sh: the token was rejected by GitHub" >&2
    exit 1
fi
echo "authenticated as: $login"

AUTH=(-H "Authorization: Bearer $TOKEN"
      -H "Accept: application/vnd.github+json"
      -H "X-GitHub-Api-Version: 2022-11-28")

body="$(mktemp)"
resp="$(mktemp)"
trap 'rm -f "$body" "$resp"' EXIT

rc=0
for f in $FILES; do
    src="$DIR/$f"
    if [ ! -f "$src" ]; then
        echo "skip $f (not found in $DIR)"
        continue
    fi

    # Existing file -> need its blob sha to update it.
    sha=""
    code="$(curl -sS -o "$resp" -w '%{http_code}' "${AUTH[@]}" "$API/$f?ref=$BRANCH")"
    if [ "$code" = "200" ]; then
        sha="$(jq -r '.sha // empty' "$resp")"
    fi

    content="$(base64 -w0 "$src")"
    if [ -n "$sha" ]; then
        jq -n --arg msg "Update $f" --arg content "$content" --arg sha "$sha" --arg branch "$BRANCH" \
           '{message:$msg, content:$content, sha:$sha, branch:$branch}' > "$body"
    else
        jq -n --arg msg "Add $f" --arg content "$content" --arg branch "$BRANCH" \
           '{message:$msg, content:$content, branch:$branch}' > "$body"
    fi

    code="$(curl -sS -o "$resp" -w '%{http_code}' -X PUT "${AUTH[@]}" "$API/$f" --data-binary @"$body")"
    if [ "$code" = "200" ] || [ "$code" = "201" ]; then
        echo "OK   $f  ($(jq -r '.content.sha // "-" ' "$resp"))"
    else
        echo "FAIL $f  HTTP $code: $(jq -r '.message // tostring' "$resp")" >&2
        rc=1
    fi
done

if [ "$rc" = 0 ]; then
    echo
    echo "raw URLs:"
    for f in $FILES; do
        [ -f "$DIR/$f" ] || continue
        echo "  https://raw.githubusercontent.com/$REPO/$BRANCH/$f"
    done
fi
exit "$rc"
