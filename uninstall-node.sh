#!/usr/bin/env bash
# uninstall-node.sh — Remove nvm and Node.js installed by install-node.sh
#
# Removes:
#   - The nvm directory (~/.nvm) and all Node versions installed through it
#   - The nvm initialisation block added to shell config files
#   - The nemoclaw command if installed under nvm's npm prefix
#
# Does NOT remove:
#   - System Node.js installed via apt (/usr/bin/node)
#   - Any other system packages
#
# Usage:
#   ./uninstall-node.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/checks.sh"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# Shell config files that nvm's installer may have modified
SHELL_CONFIGS=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.profile"
    "$HOME/.zshrc"
)

# ── Header ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}NemoClaw-Thor — Node.js Uninstaller${NC}"
echo -e "JetsonHacks — https://github.com/JetsonHacks/NemoClaw-Thor"
echo ""

# ── Check there is anything to remove ─────────────────────────────────────────

nvm_present=false
nemoclaw_present=false
configs_with_nvm=()

if [[ -d "${NVM_DIR}" ]]; then
    nvm_present=true
fi

if command -v nemoclaw &>/dev/null; then
    nemoclaw_path=$(command -v nemoclaw)
    # Only flag it if it lives under the nvm directory
    if [[ "${nemoclaw_path}" == "${NVM_DIR}"* ]]; then
        nemoclaw_present=true
    fi
fi

for config in "${SHELL_CONFIGS[@]}"; do
    if [[ -f "${config}" ]] && grep -q 'NVM_DIR' "${config}"; then
        configs_with_nvm+=("${config}")
    fi
done

if [[ "${nvm_present}" == false ]] && [[ ${#configs_with_nvm[@]} -eq 0 ]]; then
    echo "Nothing to remove — nvm does not appear to be installed."
    echo ""
    exit 0
fi

# ── Show what will be removed ──────────────────────────────────────────────────

echo -e "${BOLD}The following will be removed:${NC}"
echo ""

if [[ "${nvm_present}" == true ]]; then
    echo "  • nvm directory: ${NVM_DIR}"
    echo "    (contains nvm and all Node versions installed through it)"
    # Show installed Node versions if nvm is loadable
    if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        source "${NVM_DIR}/nvm.sh" 2>/dev/null || true
        node_versions=$(nvm list 2>/dev/null | grep -v 'system' | tr -d ' \t' || true)
        if [[ -n "${node_versions}" ]]; then
            echo ""
            echo "    Node versions that will be removed:"
            nvm list 2>/dev/null | grep -v 'system' | sed 's/^/      /' || true
        fi
    fi
    echo ""
fi

if [[ "${nemoclaw_present}" == true ]]; then
    echo "  • nemoclaw command: ${nemoclaw_path}"
    echo ""
fi

if [[ ${#configs_with_nvm[@]} -gt 0 ]]; then
    echo "  • nvm initialisation block from:"
    for config in "${configs_with_nvm[@]}"; do
        echo "      ${config}"
        echo ""
        echo "      Lines that will be removed:"
        grep -n 'NVM_DIR\|nvm\.sh\|bash_completion' "${config}" | sed 's/^/        /' || true
        echo ""
    done
fi

echo "  This does NOT remove system Node.js installed via apt."
echo ""

# ── Confirm ────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}${BOLD}  Proceed with removal? [y/N]${NC} " && read -r response
echo ""

if [[ ! "${response}" =~ ^[Yy]$ ]]; then
    echo "Cancelled — nothing was changed."
    echo ""
    exit 0
fi

# ── Remove nemoclaw ────────────────────────────────────────────────────────────

if [[ "${nemoclaw_present}" == true ]]; then
    header "Removing nemoclaw"
    echo ""
    if npm uninstall -g nemoclaw 2>/dev/null; then
        pass "nemoclaw removed"
    else
        # If npm uninstall fails (e.g. nvm already partially removed),
        # remove the binary directly
        rm -f "${nemoclaw_path}" && pass "nemoclaw binary removed directly" \
            || warn "Could not remove nemoclaw at ${nemoclaw_path} — may need manual removal"
    fi
    echo ""
fi

# ── Remove nvm directory ───────────────────────────────────────────────────────

if [[ "${nvm_present}" == true ]]; then
    header "Removing nvm directory"
    echo ""
    info "Removing ${NVM_DIR}..."
    rm -rf "${NVM_DIR}"
    if [[ ! -d "${NVM_DIR}" ]]; then
        pass "nvm directory removed"
    else
        fail "Could not remove ${NVM_DIR}"
        info "Try: rm -rf ${NVM_DIR}"
        exit 1
    fi
    echo ""
fi

# ── Remove nvm blocks from shell config files ──────────────────────────────────

if [[ ${#configs_with_nvm[@]} -gt 0 ]]; then
    header "Cleaning shell config files"
    echo ""
    for config in "${configs_with_nvm[@]}"; do
        info "Cleaning ${config}..."

        # Back up the file before modifying
        cp "${config}" "${config}.nemoclaw-thor.bak"

        # Remove the nvm block — all lines containing NVM_DIR, nvm.sh,
        # or bash_completion added by nvm's installer, plus any surrounding
        # blank lines that were part of the block.
        #
        # nvm's installer adds a block in one of these forms:
        #
        #   export NVM_DIR="$HOME/.nvm"
        #   [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        #   [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        #
        # We remove any line containing NVM_DIR, nvm.sh, or bash_completion.
        python3 - "${config}" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

nvm_markers = ['NVM_DIR', 'nvm.sh', 'bash_completion']

# Find line indices that belong to the nvm block
nvm_lines = set()
for i, line in enumerate(lines):
    if any(marker in line for marker in nvm_markers):
        nvm_lines.add(i)

# Remove those lines
filtered = [line for i, line in enumerate(lines) if i not in nvm_lines]

# Strip trailing blank lines that may have been left behind
while filtered and filtered[-1].strip() == '':
    filtered.pop()
if filtered:
    filtered.append('\n')  # restore single trailing newline

with open(path, 'w') as f:
    f.writelines(filtered)
PYEOF

        if grep -q 'NVM_DIR' "${config}" 2>/dev/null; then
            warn "Some nvm references may remain in ${config} — please review"
        else
            pass "${config} cleaned"
            info "Backup saved at ${config}.nemoclaw-thor.bak"
        fi
        echo ""
    done
fi

# ── Done ───────────────────────────────────────────────────────────────────────

echo "══════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}${BOLD}  nvm and Node.js have been removed.${NC}"
echo ""
echo "  IMPORTANT: Open a new terminal to complete the removal."
echo "  nvm and node may still appear available in this shell"
echo "  until the session ends."
echo ""
echo "  Shell config backups were saved as <file>.nemoclaw-thor.bak"
echo "  Review them and delete when satisfied:"
for config in "${configs_with_nvm[@]}"; do
    echo "    ${config}.nemoclaw-thor.bak"
done
echo ""
