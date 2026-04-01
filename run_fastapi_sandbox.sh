#!/usr/bin/env bash
# run_fastapi_sandbox.sh
# Starts a FastAPI hello world app inside a Linux namespace + cgroup sandbox
# Requires: python3, pip, unshare (util-linux), cgcreate/cgexec (cgroup-tools)
# Run as root or with sufficient privileges (CAP_SYS_ADMIN)

set -euo pipefail

APP_DIR="$(mktemp -d)"
CGROUP_NAME="fastapi_sandbox"
PORT=8000

# ── Cleanup on exit ────────────────────────────────────────────────────────────
cleanup() {
  echo "[*] Cleaning up..."
  # Kill any process using our port
  fuser -k ${PORT}/tcp 2>/dev/null || true
  # Remove cgroup
  cgdelete -r cpu,memory:${CGROUP_NAME} 2>/dev/null || true
  # Remove temp app dir
  rm -rf "${APP_DIR}"
  echo "[*] Done."
}
trap cleanup EXIT

# ── 1. Install FastAPI + uvicorn if not present ────────────────────────────────
echo "[*] Installing FastAPI and uvicorn..."
# --break-system-packages is required on distributions that mark the system
# Python environment as externally-managed (PEP 668, e.g. Debian 12+).
# Use a virtual environment if you prefer to avoid touching system packages.
pip install fastapi uvicorn --quiet --break-system-packages

# ── 2. Write the FastAPI app ───────────────────────────────────────────────────
echo "[*] Writing FastAPI app to ${APP_DIR}..."
cat > "${APP_DIR}/main.py" <<'EOF'
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "Hello, World!"}

@app.get("/health")
def health():
    return {"status": "ok"}
EOF

# ── 3. Create cgroup (cpu + memory limits) ─────────────────────────────────────
echo "[*] Creating cgroup: ${CGROUP_NAME}..."

# Detect cgroup version
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  echo "[!] WARNING: cgroup v2 detected. This script uses the cgroup v1 interface"
  echo "    (cgcreate/cgexec/memory.limit_in_bytes). Ensure cgroup v1 controllers"
  echo "    are enabled (e.g. systemd.unified_cgroup_hierarchy=0 on the kernel"
  echo "    command line) or migrate to cgroup v2 tooling."
fi

cgcreate -g cpu,memory:${CGROUP_NAME}

# Limit to 50% of one CPU and 256MB RAM
cgset -r cpu.cfs_period_us=100000  ${CGROUP_NAME}
cgset -r cpu.cfs_quota_us=50000   ${CGROUP_NAME}
cgset -r memory.limit_in_bytes=268435456 ${CGROUP_NAME}  # 256MB

echo "[*] cgroup limits set: 50% CPU, 256MB RAM"

# ── 4. Launch uvicorn inside a new namespace + cgroup ─────────────────────────
echo "[*] Starting FastAPI inside namespace + cgroup..."
echo "[*] App will be available at http://localhost:${PORT}"
echo "[*] Press Ctrl+C to stop."
echo ""

# Note: --net is intentionally omitted so the process shares the host network
# namespace and the app remains reachable at http://localhost:${PORT}.
# The remaining namespaces (pid, mount, uts, ipc) still provide meaningful
# isolation without breaking host connectivity.
cgexec -g cpu,memory:${CGROUP_NAME} \
  unshare --pid --mount --uts --ipc --fork \
  bash -c "
    # Mount a new /proc for the PID namespace so tools like ps work correctly.
    if ! mount -t proc proc /proc; then
      echo '[!] WARNING: failed to mount /proc in new namespace' >&2
    fi

    # Set hostname inside UTS namespace
    hostname fastapi-sandbox

    cd ${APP_DIR}
    exec python3 -m uvicorn main:app --host 0.0.0.0 --port ${PORT}
  "
