#!/usr/bin/env bash
# install-node.sh — Install nvm and Node.js 22 for NemoClaw-Thor
#
# Installs nvm and Node.js 22, which are required by the NemoClaw installer.
# Safe to run multiple times — skips steps that are already complete.
#
# Usage:
#   ./install-node.sh
#
# After this script completes, open a new terminal or run:
#   source ~/.bashrc
# to ensure nvm and node are available in your current shell.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/checks.sh"

NVM_VERSION="v0.39.7"
NODE_VERSION="22"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"

# ── Header ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}NemoClaw-Thor — Node.js Installer${NC}"
echo -e "JetsonHacks — https://github.com/JetsonHacks/NemoClaw-Thor"
echo ""

# ── Step 1: Install nvm ────────────────────────────────────────────────────────

header "Step 1: nvm"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ -d "${NVM_DIR}" ]] && [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    pass "nvm is already installed at ${NVM_DIR} — skipping"
else
    echo ""
    info "Installing nvm ${NVM_VERSION}..."
    echo ""
    if curl -fsSL --max-time 30 "${NVM_INSTALL_URL}" | bash; then
        echo ""
        pass "nvm installed successfully"
    else
        echo ""
        fail "nvm installation failed"
        info "Check your network connection and try again."
        info "Manual install: https://github.com/nvm-sh/nvm#installing-and-updating"
        exit 1
    fi
fi

# Source nvm into the current shell so subsequent steps can use it
# without requiring a new terminal
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
else
    fail "nvm.sh not found at ${NVM_DIR}/nvm.sh after installation"
    exit 1
fi

# ── Step 2: Install Node 22 ────────────────────────────────────────────────────

header "Step 2: Node.js ${NODE_VERSION}"
echo ""

if command -v node &>/dev/null; then
    current_major=$(node --version | cut -d. -f1 | tr -d 'v')
    if [[ "${current_major}" -eq "${NODE_VERSION}" ]]; then
        pass "Node.js $(node --version) is already installed — skipping"
    else
        warn "Node.js $(node --version) is installed but NemoClaw requires version ${NODE_VERSION}"
        info "Installing Node.js ${NODE_VERSION} alongside existing version..."
        echo ""
        nvm install "${NODE_VERSION}"
    fi
else
    info "Installing Node.js ${NODE_VERSION}..."
    echo ""
    nvm install "${NODE_VERSION}"
fi

# ── Step 3: Set Node 22 as default ────────────────────────────────────────────

header "Step 3: Set Node.js ${NODE_VERSION} as default"
echo ""

nvm alias default "${NODE_VERSION}"
nvm use "${NODE_VERSION}"

pass "Node.js ${NODE_VERSION} set as nvm default"

# ── Verify ─────────────────────────────────────────────────────────────────────

header "Verification"
echo ""

node_ver=$(node --version)
npm_ver=$(npm --version)
node_path=$(command -v node)
node_major=$(echo "${node_ver}" | cut -d. -f1 | tr -d 'v')

if [[ "${node_major}" -eq "${NODE_VERSION}" ]]; then
    pass "node ${node_ver} at ${node_path}"
    pass "npm ${npm_ver}"
else
    fail "Expected Node.js ${NODE_VERSION}.x but found ${node_ver}"
    info "Run: nvm use ${NODE_VERSION}"
    exit 1
fi

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}${BOLD}  Node.js ${node_ver} and nvm are ready.${NC}"
echo ""
echo "  IMPORTANT: Open a new terminal before running install.sh, or run:"
echo ""
echo "    source ~/.bashrc"
echo ""
echo "  This ensures nvm and node are available in your shell."
echo "  Then run ./check-prerequisites.sh to confirm all checks pass."
echo ""
