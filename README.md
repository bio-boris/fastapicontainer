# fastapicontainer

Run a FastAPI hello-world app inside a Linux namespace + cgroup sandbox — **no Docker required**.

## Prerequisites

- Linux (kernel ≥ 3.8)
- `python3` and `pip`
- `unshare` (part of **util-linux**)
- `cgcreate` / `cgexec` / `cgset` / `cgdelete` (part of **cgroup-tools**)
- Root or a user with `CAP_SYS_ADMIN`

Install the tools on Debian/Ubuntu:

```bash
sudo apt-get install util-linux cgroup-tools
```

## Usage

```bash
sudo bash run_fastapi_sandbox.sh
```

The script will:

1. Install `fastapi` and `uvicorn` via `pip` (if not already present).
2. Write the FastAPI application to a temporary directory.
3. Create a **cgroup** named `fastapi_sandbox` with:
   - CPU quota: 50 % of one core (`cpu.cfs_quota_us=50000`)
   - Memory limit: 256 MB (`memory.limit_in_bytes=268435456`)
4. Start `uvicorn` inside a new **Linux namespace** (`--pid`, `--mount`, `--uts`, `--ipc`) constrained by that cgroup. The network namespace is intentionally *not* isolated so the app remains reachable on the host network.

Once running, the app is reachable at <http://localhost:8000>.

| Endpoint  | Description            |
|-----------|------------------------|
| `GET /`   | Returns `{"message": "Hello, World!"}` |
| `GET /health` | Returns `{"status": "ok"}` |

Press **Ctrl+C** to stop the server. The cleanup handler removes the cgroup and temporary files automatically.

## Files

| File | Description |
|------|-------------|
| `run_fastapi_sandbox.sh` | Main launcher script |
| `main.py` | FastAPI application (also embedded in the script) |