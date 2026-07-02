#!/usr/bin/env sh
# POSIX sh: -e (exit on error) and -u (error on unset vars) are portable.
# pipefail is NOT POSIX (it breaks under dash), so it is deliberately omitted.
set -eu

REPO="${SIS_GITHUB_REPO:-payloadglass/sis-release}"
INSTALL_DIR="${SIS_INSTALL_DIR:-$HOME/.local/bin}"

echo "sis installer: $REPO"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux)
    case "$arch" in
      x86_64 | amd64) target="x86_64-unknown-linux-gnu" ;;
      aarch64 | arm64) target="aarch64-unknown-linux-gnu" ;;
      *)
        echo "Unsupported architecture: $arch" >&2
        exit 1
        ;;
    esac
    ext="tar.gz"
    bin_name="sis"
    ;;
  Darwin)
    # Release ships a single universal (fat) binary that runs natively on both
    # Apple Silicon (arm64) and Intel (x86_64), so no per-arch check is needed.
    target="universal-apple-darwin"
    ext="tar.gz"
    bin_name="sis"
    ;;
  *)
    echo "Unsupported OS: $os" >&2
    exit 1
    ;;
esac

api_url="https://api.github.com/repos/$REPO/releases?per_page=20"
release_json="$(curl -fsSL -H "User-Agent: sis-install" "$api_url")" || {
  echo "Failed to query GitHub releases for $REPO" >&2
  exit 1
}
if [ -z "$release_json" ]; then
  echo "Empty response from GitHub releases API for $REPO" >&2
  exit 1
fi
if printf "%s" "$release_json" | grep -q "API rate limit exceeded"; then
  echo "Error: GitHub API rate limit exceeded. Try again later or use a GitHub token:" >&2
  echo "  export GITHUB_TOKEN=...   # then re-run the installer" >&2
  exit 1
fi

suffix="-$target.$ext"
# Pre-declare so the script is safe under `set -u` even when the read below
# consumes no lines (no matching asset found).
asset_name=""
url=""
tag=""
{
  read -r asset_name
  read -r url
} <<EOF_META
$(printf "%s" "$release_json" | awk -v suffix="$suffix" '
  # The GitHub API returns the releases array as a single minified line, so we
  # walk every "name":"..." occurrence on the record rather than assuming one
  # asset per line. The first CLI asset (sis-<tag>-<target>.<ext>) wins; the
  # companion sis-app-* artefact is skipped.
  {
    rest = $0
    while (match(rest, "\"name\":\"sis-[^\"]*" suffix "\"")) {
      name = substr(rest, RSTART, RLENGTH)
      sub(/.*"name":"/, "", name)
      sub(/".*/, "", name)
      after = substr(rest, RSTART + RLENGTH)
      if (name !~ /^sis-app-/ && match(after, "\"browser_download_url\":\"[^\"]+\"")) {
        url = substr(after, RSTART, RLENGTH)
        sub(/.*"browser_download_url":"/, "", url)
        sub(/".*/, "", url)
        print name
        print url
        exit
      }
      rest = after
    }
  }
')
EOF_META
if [ -n "${asset_name:-}" ]; then
  tag="${asset_name#sis-}"
  tag="${tag%-$target.$ext}"
fi

URL=$url
echo "Reading from repo $REPO, url $URL"

if [ -z "$url" ]; then
  if printf "%s" "$release_json" | grep -q "\"message\""; then
    echo "Error: GitHub API response error:" >&2
    printf "%s\n" "$release_json" | sed -n '1,5p' >&2
  else
    echo "No release asset found for $target" >&2
  fi
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/sis-$tag-$target.$ext"
curl -fsSL -H "User-Agent: sis-install" -o "$archive" "$url"

tar -C "$tmpdir" -xzf "$archive"

# INSTALL_DIR is already resolved at the top (SIS_INSTALL_DIR or ~/.local/bin).
mkdir -p "$INSTALL_DIR"

install -m 755 "$tmpdir/$bin_name" "$INSTALL_DIR/$bin_name"

echo "Installed sis $tag to $INSTALL_DIR/$bin_name"
if ! command -v sis >/dev/null 2>&1; then
  echo "Add $INSTALL_DIR to your PATH to run sis" >&2
fi
