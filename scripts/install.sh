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

# SIS_TEST_ARCHIVE is for testing only: a local .tar.gz to install from instead
# of querying GitHub and downloading. Not a supported user-facing option.
if [ -z "${SIS_TEST_ARCHIVE:-}" ]; then
# Stable by default: /releases/latest returns the newest non-draft,
# non-prerelease release as a single object. The releases list includes
# prereleases (newest first), so it is used only when explicitly requested.
if [ "${SIS_INSTALL_PRERELEASE:-}" = "1" ]; then
  echo "Installing newest release including prereleases (SIS_INSTALL_PRERELEASE=1)"
  api_url="https://api.github.com/repos/$REPO/releases?per_page=20"
else
  echo "Installing latest stable release"
  api_url="https://api.github.com/repos/$REPO/releases/latest"
fi
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
  # The GitHub API returns either the releases array (prerelease opt-in) or a
  # single release object (/releases/latest) as one minified line, so we
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
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if [ -n "${SIS_TEST_ARCHIVE:-}" ]; then
  tag="test"
  archive="$SIS_TEST_ARCHIVE"
else
  archive="$tmpdir/sis-$tag-$target.$ext"
  curl -fsSL -H "User-Agent: sis-install" -o "$archive" "$url"
fi

# Verify the archive against the release's SHA256SUMS BEFORE extracting anything. Fail closed:
# a missing manifest, a missing entry, a mismatch, or no hashing tool all abort with nothing
# installed. This catches corruption and tampering with a mirror or download path; it does not
# defend against a compromised release, because SHA256SUMS comes from the same release.
if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  hash_cmd="shasum -a 256"
else
  echo "Error: cannot verify the download: neither sha256sum nor shasum is installed." >&2
  echo "Install one of them (coreutils provides sha256sum; perl provides shasum) and re-run." >&2
  exit 1
fi

if [ -n "${SIS_TEST_ARCHIVE:-}" ]; then
  # Testing only: SIS_TEST_SUMS is a local SHA256SUMS file. Unset means "no manifest".
  archive_name="$(basename "$archive")"
  sums_file="${SIS_TEST_SUMS:-$tmpdir/SHA256SUMS.absent}"
  if [ ! -f "$sums_file" ]; then
    echo "Error: SHA256SUMS not found; refusing to install an unverified archive." >&2
    exit 1
  fi
else
  archive_name="$asset_name"
  sums_file="$tmpdir/SHA256SUMS"
  sums_url="${url%/*}/SHA256SUMS"
  if ! curl -fsSL -H "User-Agent: sis-install" -o "$sums_file" "$sums_url"; then
    echo "Error: could not download SHA256SUMS from $sums_url; refusing to install an unverified archive." >&2
    exit 1
  fi
fi

expected="$(awk -v n="$archive_name" '{ f = $2; sub(/^\*/, "", f); if (f == n) { print $1; exit } }' "$sums_file")"
if [ -z "$expected" ]; then
  echo "Error: SHA256SUMS has no entry for $archive_name; refusing to install an unverified archive." >&2
  exit 1
fi
# shellcheck disable=SC2086 # $hash_cmd is deliberately split ("shasum -a 256")
actual="$($hash_cmd "$archive" | awk '{ print $1 }')"
if [ "$actual" != "$expected" ]; then
  echo "Error: checksum mismatch for $archive_name" >&2
  echo "  expected: $expected" >&2
  echo "  actual:   $actual" >&2
  echo "Nothing was installed." >&2
  exit 1
fi
echo "Verified $archive_name against SHA256SUMS"

tar -C "$tmpdir" -xzf "$archive"

# INSTALL_DIR is already resolved at the top (SIS_INSTALL_DIR or ~/.local/bin).
mkdir -p "$INSTALL_DIR"

install -m 755 "$tmpdir/$bin_name" "$INSTALL_DIR/$bin_name"

# `sis sanitize release` looks for sis-cdr-worker in the same directory as sis,
# so install it there. Archives before the release that first shipped it
# (e.g. v0.7.0-beta.1, v0.6.9) do not contain it.
# Integrity: this script verifies no checksums for sis either; the worker comes from the same
# downloaded archive, so it gets exactly the same treatment as sis.
worker_name="sis-cdr-worker"
if [ -f "$tmpdir/$worker_name" ]; then
  install -m 755 "$tmpdir/$worker_name" "$INSTALL_DIR/$worker_name"
  echo "Installed $worker_name to $INSTALL_DIR/$worker_name"
else
  echo "note: this release has no $worker_name; \`sis sanitize release\` is unavailable"
fi

echo "Installed sis $tag to $INSTALL_DIR/$bin_name"
if ! command -v sis >/dev/null 2>&1; then
  echo "Add $INSTALL_DIR to your PATH to run sis" >&2
fi
