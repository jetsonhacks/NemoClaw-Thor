#!/usr/bin/env bash
# install.sh — Install NemoClaw on Jetson AGX Thor
#
# This script:
#   1. Verifies all prerequisites are in place
#   2. Applies the cgroupns fix to /etc/docker/daemon.json if needed
#   3. Clones NemoClaw to ~/NemoClaw
#   4. Runs NemoClaw's interactive onboarding wizard
#   5. Creates the vllm-local inference provider
#   6. Switches the inference route to vllm-local
#
# Prerequisites:
#   - OpenShell installed with all five openshell-thor fixes applied
#   - Docker running with NVIDIA container runtime
#   - nvm and Node.js 22 installed (run ./install-node.sh first)
#   - HF_TOKEN set (required if using local vLLM inference)
#   - Run ./check-prerequisites.sh to verify all of the above
#
# Usage:
#   ./install.sh
#
# The NemoClaw onboarding wizard is interactive. You will be prompted for:
#   - A sandbox name (or one will be generated)
#   - An NVIDIA API key (from https://build.nvidia.com/settings/api-keys)
#   - Policy preset selection (suggested: accept defaults)
#
# After installation, switch to local vLLM inference:
#   1. Start the inference server:  ./nemotron3-thor.sh
#   2. This script will configure the vllm-local provider automatically.
#      To switch manually at any time:
#        openshell inference set --provider vllm-local \
#          --model nvidia/nemotron-3-nano-30b-a3b --no-verify

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/checks.sh"

NEMOCLAW_DIR="${HOME}/NemoClaw"
NEMOCLAW_REPO="https://github.com/NVIDIA/NemoClaw.git"

# ── Header ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}NemoClaw-Thor Installer${NC}"
echo -e "JetsonHacks — https://github.com/JetsonHacks/NemoClaw-Thor"
echo ""
echo "This script installs NemoClaw on Jetson AGX Thor."
echo "The NemoClaw onboarding wizard is interactive — you will be"
echo "prompted for a sandbox name, an NVIDIA API key, and policy presets."
echo ""
echo "Estimated time: 10-20 minutes depending on network speed."
echo ""

# ── Step 1: Prerequisite checks ────────────────────────────────────────────────

header "Step 1: Prerequisite checks"
echo ""

CHECKS_FAILED=0

run_check() {
    local ret
    "$@" && ret=0 || ret=$?
    if [[ "${ret}" -ne 0 && "${ret}" -ne 2 ]]; then
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
    return 0
}

run_check check_openshell_installed
run_check check_fix_iptable_raw
run_check check_fix_iptables_legacy
run_check check_fix_br_netfilter
run_check check_fix_docker_ipv6
run_check check_fix_cgroupns
run_check check_docker_installed
run_check check_docker_running
run_check check_docker_nvidia_runtime
run_check check_nvm_installed
run_check check_node_version
run_check check_build_tools
run_check check_connectivity_github

if [[ "${CHECKS_FAILED}" -gt 0 ]]; then
    echo ""
    echo -e "${RED}${BOLD}  ${CHECKS_FAILED} prerequisite check(s) failed.${NC}"
    echo ""
    echo "  Run ./check-prerequisites.sh for details and fix instructions."
    echo "  Address all failures before running install.sh again."
    echo ""
    exit 1
fi

echo ""
echo -e "${GREEN}${BOLD}  All prerequisite checks passed.${NC}"

# ── Step 2: cgroupns fix ───────────────────────────────────────────────────────

header "Step 2: Docker cgroupns configuration"
echo ""

DAEMON_JSON="/etc/docker/daemon.json"

if python3 -c "
import json, sys
with open('${DAEMON_JSON}') as f:
    d = json.load(f)
sys.exit(0 if d.get('default-cgroupns-mode') == 'host' else 1)
" 2>/dev/null; then
    pass "Docker cgroupns already configured — skipping"
else
    info "Applying cgroupns fix to ${DAEMON_JSON}..."
    info "This requires sudo."
    echo ""
    sudo python3 - << 'PYEOF'
import json

path = "/etc/docker/daemon.json"
with open(path) as f:
    d = json.load(f)

d["default-cgroupns-mode"] = "host"

with open(path, "w") as f:
    json.dump(d, f, indent=4)
    f.write("\n")
PYEOF

    info "Restarting Docker..."
    sudo systemctl restart docker

    # Verify Docker came back up
    local retries=5
    local i=0
    while [[ $i -lt $retries ]]; do
        if docker info &>/dev/null; then
            break
        fi
        sleep 2
        i=$((i + 1))
    done

    if ! docker info &>/dev/null; then
        fail "Docker did not restart cleanly after cgroupns fix"
        fix "Check: sudo systemctl status docker"
        fix "Check: sudo journalctl -u docker --no-pager | tail -20"
        exit 1
    fi

    pass "cgroupns fix applied and Docker restarted successfully"
fi

# ── Step 3: Check ~/NemoClaw doesn't already exist ─────────────────────────────

header "Step 3: Checking for existing NemoClaw installation"
echo ""

if [[ -d "${NEMOCLAW_DIR}" ]]; then
    fail "${NEMOCLAW_DIR} already exists"
    echo ""
    info "NemoClaw may already be installed, or a previous install attempt"
    info "left an incomplete directory behind."
    echo ""
    info "To reinstall from scratch:"
    info "  1. Run ./uninstall.sh to remove the existing installation"
    info "  2. Run ./install.sh again"
    echo ""
    info "To use your existing installation:"
    info "  nemoclaw --help"
    echo ""
    exit 1
fi

pass "${NEMOCLAW_DIR} does not exist — ready to install"

# ── Step 4: Ensure nvm and Node 22 are active ──────────────────────────────────

header "Step 4: Activating Node.js 22"
echo ""

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
    nvm use 22 &>/dev/null
    pass "Node.js $(node --version) active via nvm"
else
    fail "nvm not found at ${NVM_DIR}"
    fix "Run ./install-node.sh then open a new terminal before retrying"
    exit 1
fi

# ── Step 5: Clone NemoClaw ─────────────────────────────────────────────────────

header "Step 5: Cloning NemoClaw"
echo ""
info "Cloning ${NEMOCLAW_REPO} to ${NEMOCLAW_DIR}..."
echo ""

git clone "${NEMOCLAW_REPO}" "${NEMOCLAW_DIR}"

pass "NemoClaw cloned to ${NEMOCLAW_DIR}"

# ── Step 6: Run NemoClaw installer ────────────────────────────────────────────

header "Step 6: Running NemoClaw installer"
echo ""
echo "  The NemoClaw onboarding wizard will now run."
echo "  You will be prompted for:"
echo "    • Sandbox name (a name will be generated if you press Enter)"
echo "    • NVIDIA API key (from https://build.nvidia.com/settings/api-keys)"
echo "    • Policy presets (recommended: accept the suggested defaults)"
echo ""
echo "  Note: The wizard configures cloud inference by default. After"
echo "  installation this script will configure local vLLM inference."
echo ""
echo "  Press Enter to continue..."
read -r

cd "${NEMOCLAW_DIR}"
./install.sh

# Get the sandbox name now that onboarding has completed
SANDBOX_NAME=$(openshell sandbox list 2>/dev/null     | sed 's/\[[0-9;]*m//g'     | awk 'NR>1 && $1 != "" {print $1; exit}' || echo "")

# The NemoClaw installer starts a port forward as a background child process
# which keeps this shell alive. Stop it and restart it explicitly in the
# background so it survives the installer exiting cleanly.
if [[ -n "${SANDBOX_NAME}" ]]; then
    openshell forward stop 18789 "${SANDBOX_NAME}" 2>/dev/null || true
    openshell forward start 18789 "${SANDBOX_NAME}" --background
fi

# Disown any remaining background children from the NemoClaw installer
# (e.g. SSH tunnel processes) so the script exits cleanly.
disown -a 2>/dev/null || true

# ── Step 7: Verify nemoclaw is on PATH ─────────────────────────────────────────

header "Step 7: Verifying nemoclaw installation"
echo ""

# Re-source nvm in case the NemoClaw installer modified PATH
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
    nvm use 22 &>/dev/null
fi

if ! command -v nemoclaw &>/dev/null; then
    fail "nemoclaw command not found after installation"
    info "This may be the known Node version collision bug."
    info "Try opening a new terminal and running:"
    info "  source ~/.bashrc"
    info "  nemoclaw --help"
    info "If nemoclaw is still not found, check:"
    info "  ls ~/.nvm/versions/node/v22.*/bin/nemoclaw"
    exit 1
fi

pass "nemoclaw found at $(command -v nemoclaw)"

# ── Step 8: Create vllm-local inference provider ──────────────────────────────

header "Step 8: Creating vllm-local inference provider"
echo ""
info "Creating OpenShell provider for local vLLM inference..."
info "(endpoint: http://host.openshell.internal:8000/v1)"
echo ""

if openshell provider get vllm-local &>/dev/null; then
    pass "vllm-local provider already exists — skipping"
else
    openshell provider create \
        --name vllm-local \
        --type openai \
        --credential OPENAI_API_KEY=dummy \
        --config OPENAI_BASE_URL=http://host.openshell.internal:8000/v1

    pass "vllm-local provider created"
fi

# ── Step 9: Switch inference to vllm-local ────────────────────────────────────

header "Step 9: Switching inference to vllm-local"
echo ""
info "Configuring gateway to route inference to local vLLM..."
echo ""

openshell inference set \
    --provider vllm-local \
    --model nvidia/nemotron-3-nano-30b-a3b \
    --no-verify

pass "Inference route set to vllm-local / nvidia/nemotron-3-nano-30b-a3b"

# ── Done ───────────────────────────────────────────────────────────────────────
# Use sandbox name discovered after onboarding; fall back if empty
SANDBOX_NAME="${SANDBOX_NAME:-<sandbox-name>}"


echo ""
echo "══════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}${BOLD}  NemoClaw installation complete.${NC}"
echo ""
echo "  Sandbox:  ${SANDBOX_NAME}"
echo "  Inference: vllm-local → nvidia/nemotron-3-nano-30b-a3b"
echo ""
echo -e "${BOLD}  Next steps:${NC}"
echo ""
echo "  1. Open a new terminal and start one of the inference servers:"
echo ""
echo "       ./nemotron3-thor-no-thinking.sh   # Fast — recommended for most use"
echo "       ./nemotron3-thor.sh               # Thinking — better accuracy, slower"
echo ""
echo "     Wait for: \"Application startup complete.\""
echo "     First startup may take several minutes while the model loads."
echo ""
echo "  2. Check system status:"
echo "       ./status.sh"
echo ""
echo "  See README for full usage instructions:"
echo "  https://github.com/JetsonHacks/NemoClaw-Thor"
echo ""

exit 0