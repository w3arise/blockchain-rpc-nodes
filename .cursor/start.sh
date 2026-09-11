#!/usr/bin/env bash
#
# Cloud Agent start: bring up the Docker daemon each boot.
#
# The Cloud Agent VM has no systemd (PID 1 is tini), so dockerd is launched
# directly and supervised in the background. Idempotent: if the daemon is
# already responding, this exits cleanly without starting a second one.
set -euo pipefail

# Make user-local pip installs (yamllint) available to the agent shell.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

LOG=/tmp/dockerd.log

if sudo docker info >/dev/null 2>&1; then
  echo "==> Docker daemon already running"
else
  echo "==> Starting Docker daemon (log: $LOG)"
  sudo bash -c "nohup dockerd >>'$LOG' 2>&1 &"

  # Wait for the daemon socket to come up (up to ~60s).
  for _ in $(seq 1 60); do
    if sudo docker info >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! sudo docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon did not become ready; see $LOG" >&2
    tail -20 "$LOG" >&2 || true
    exit 1
  fi
  echo "==> Docker daemon is ready"
fi

# Allow the agent user to use docker without sudo in this session.
if [ -S /var/run/docker.sock ]; then
  sudo chmod 666 /var/run/docker.sock || true
fi

docker version --format '==> docker client {{.Client.Version}} / server {{.Server.Version}}' 2>/dev/null || true
