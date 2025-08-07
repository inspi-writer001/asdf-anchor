# lib/utils.bash - Updated with hybrid installation approach

#!/usr/bin/env bash
set -euo pipefail

# Plugin configuration - CORRECTED REPOSITORY
GH_REPO="https://github.com/coral-xyz/anchor"
TOOL_NAME="anchor"
TOOL_TEST="anchor --version"

# Helpers
fail() {
  echo "asdf-${TOOL_NAME}: $*" >&2
  exit 1
}

curl_opts=(-fsSL)
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts+=(-H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k1,1 -k2,2n -k3,3n -k4,4n |
    awk '{print $2}'
}

get_arch() {
  local arch="$(uname -m)"
  case "$arch" in
    x86_64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) fail "Unsupported architecture: $arch" ;;
  esac
}

get_platform() {
  local os="$(uname -s)"
  case "$os" in
    Linux) echo "unknown-linux-gnu" ;;
    Darwin) echo "apple-darwin" ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) echo "pc-windows-msvc.exe" ;;
    *) fail "Unsupported OS: $os" ;;
  esac
}

# Check if binary download is available (0.31.0+)
has_binary_download() {
  local version="$1"
  
  # Binary downloads were introduced in 0.31.0
  # Use simple version comparison
  if printf '%s\n%s\n' "0.31.0" "$version" | sort -V | head -n1 | grep -q "^0.31.0$"; then
    return 0  # version >= 0.31.0
  else
    return 1  # version < 0.31.0
  fi
}

# Download pre-built binary (for 0.31.0+)
download_binary() {
  local version="$1" dest="$2"
  local arch platform filename url
  
  arch="$(get_arch)"
  platform="$(get_platform)"
  filename="${TOOL_NAME}-${version}-${arch}-${platform}"
  url="${GH_REPO}/releases/download/v${version}/${filename}"

  echo "* Downloading pre-built binary: ${TOOL_NAME} v${version}"
  curl "${curl_opts[@]}" -o "$dest" "$url"
  
  if [ ! -s "$dest" ] || head -c 10 "$dest" | grep -q "Not Found"; then
    fail "Binary download failed - file not found or corrupted"
  fi
  
  chmod +x "$dest"
  echo "* Binary downloaded successfully"
}

# Compile from source (for versions < 0.31.0 or when binary download fails)
compile_from_source() {
  local version="$1" dest="$2"
  
  echo "* Compiling Anchor from source (this may take several minutes)..."
  
  # Check if Rust is available
  if ! command -v cargo >/dev/null 2>&1; then
    fail "Rust/Cargo is required to compile Anchor from source. Install Rust first: https://rustup.rs/"
  fi
  
  # Use a temporary directory
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  
  # Compile using cargo
  echo "* Running: cargo install --git ${GH_REPO} --tag v${version} anchor-cli --root $tmpdir --locked"
  if ! cargo install --git "${GH_REPO}" --tag "v${version}" anchor-cli --root "$tmpdir" --locked; then
    fail "Failed to compile Anchor from source. This might be due to Rust version compatibility issues."
  fi
  
  # Move the compiled binary
  if [ -f "$tmpdir/bin/anchor" ]; then
    mv "$tmpdir/bin/anchor" "$dest"
    chmod +x "$dest"
    echo "* Compilation successful"
  else
    fail "Compilation succeeded but binary not found at expected location"
  fi
}

# List all versions
list_all_versions() {
  curl "${curl_opts[@]}" "https://api.github.com/repos/coral-xyz/anchor/releases" |
    grep -E '"tag_name":' |
    sed -E 's/.*"v?([^"]+)".*/\1/' |
    sort_versions
}

# Main download function with fallback logic
download_release() {
  local version="$1" dest="$2"
  
  if has_binary_download "$version"; then
    echo "* Attempting binary download for v${version}"
    if download_binary "$version" "$dest" 2>/dev/null; then
      return 0
    else
      echo "* Binary download failed, falling back to compilation"
      compile_from_source "$version" "$dest"
    fi
  else
    echo "* Version ${version} predates binary releases, compiling from source"
    compile_from_source "$version" "$dest"
  fi
}

# Install function
install_version() {
  local install_type="$1" version="$2" install_path="$3"
  
  if [ "$install_type" != "version" ]; then
    fail "Only version-based installs are supported"
  fi

  echo "* Installing ${TOOL_NAME} v${version}"
  
  # Create install directory
  mkdir -p "$install_path/bin"
  
  # Download or compile
  download_release "$version" "$install_path/bin/$TOOL_NAME"
  
  # Test the installation
  if ! "$install_path/bin/$TOOL_NAME" --version >/dev/null 2>&1; then
    fail "Installation verification failed - binary does not respond to --version"
  fi
  
  echo "✅ ${TOOL_NAME} v${version} installed successfully"
}