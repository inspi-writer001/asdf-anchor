#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────
# Plugin configuration
# ────────────────────────────────────────────────────────────────────────────────
GH_REPO="https://github.com/solana-foundation/anchor"
TOOL_NAME="anchor"
TOOL_TEST="anchor --version"

# ────────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────────
fail() {
  echo "asdf-${TOOL_NAME}: $*" >&2
  exit 1
}

curl_opts=(-fsSL)
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts+=(-H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
  # Convert semver into sortable form and back
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k1,1 -k2,2n -k3,3n -k4,4n |
    awk '{print $2}'
}

# ────────────────────────────────────────────────────────────────────────────────
# 1) List all installable versions
# ────────────────────────────────────────────────────────────────────────────────
list_all_versions() {
  # Use GitHub API for consistency
  curl "${curl_opts[@]}" "https://api.github.com/repos/solana-foundation/anchor/releases" |
    grep -E '"tag_name":' |
    sed -E 's/.*"v?([^"]+)".*/\1/' |
    sort_versions
}

# ────────────────────────────────────────────────────────────────────────────────
# 2) Download a release asset
#    $1 = version (e.g. 0.31.1)
#    $2 = destination file path
# ────────────────────────────────────────────────────────────────────────────────
download_release() {
  local version="$1" dest="$2" filename url

  # Detect platform
  local arch os
  arch="$(uname -m)"
  os="$(uname -s)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) fail "Unsupported architecture: $arch" ;;
  esac
  case "$os" in
    Linux) os="unknown-linux-gnu" ;;
    Darwin) os="apple-darwin" ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) os="pc-windows-msvc.exe" ;;
    *) fail "Unsupported OS: $os" ;;
  esac

  filename="${TOOL_NAME}-${version}-${arch}-${os}"
  url="${GH_REPO}/releases/download/v${version}/${filename}"

  echo "* Downloading ${TOOL_NAME} v${version} → ${dest}"
  curl "${curl_opts[@]}" -o "$dest" "$url" || fail "Could not download $url"
}

# ────────────────────────────────────────────────────────────────────────────────
# 3) Install a version that’s already been downloaded
#    Called by bin/install (via install_version)
#    $1 = install_type (should be “version”)
#    $2 = version
#    $3 = full install path
# ────────────────────────────────────────────────────────────────────────────────
install_version() {
  local install_type="$1" version="$2" install_prefix="$3"

  if [ "$install_type" != "version" ]; then
    fail "Only version-based installs are supported"
  fi

  # Download into a temp dir
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  local archive="$tmpdir/${TOOL_NAME}.bin"
  download_release "$version" "$archive"

  # Create final bin dir
  mkdir -p "$install_prefix/bin"
  mv "$archive" "$install_prefix/bin/$TOOL_NAME"
  chmod +x "$install_prefix/bin/$TOOL_NAME"

  # Verify it runs
  if ! "$install_prefix/bin/$TOOL_NAME" --version &>/dev/null; then
    rm -rf "$install_prefix"
    fail "Installed binary did not run correctly"
  fi

  echo "✅ ${TOOL_NAME} v${version} installed to ${install_prefix}/bin/$TOOL_NAME"
}
