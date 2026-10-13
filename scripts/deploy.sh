#!/usr/bin/env bash
# Replace the running application container with the image the pipeline just built.
# Only the APPLICATION is started here. The database is separate infrastructure (docker-compose.yml) that must
# already be running, like in a real project where a pipeline only ships the app.
#
# usage:  IMAGE_NAME=sonarcube DB_URL=... DB_USER=... DB_PASSWORD=... [APP_PORT=8081] [DOCKER_NETWORK=sonarcube-net] \
#         scripts/deploy.sh <image-tag>
# On a failed start the previous version (if there was one) is started again and the script still exits 1.
set -euo pipefail

tag=${1:?usage: deploy.sh <image-tag>}
image_name=${IMAGE_NAME:-sonarcube}
: "${DB_URL:?DB_URL is not set}" "${DB_USER:?DB_USER is not set}" "${DB_PASSWORD:?DB_PASSWORD is not set}"
export DB_URL DB_USER DB_PASSWORD   # passed to the container by name, so the password is never on a command line
port=${APP_PORT:-8081}
name=$image_name
network=${DOCKER_NETWORK:-}

start() { # $1 = image reference
  local net=()
  if [ -n "$network" ]; then net=(--network "$network"); fi
  docker run -d --name "$name" --restart unless-stopped ${net[@]+"${net[@]}"} \
    -p "127.0.0.1:$port:8080" -e DB_URL -e DB_USER -e DB_PASSWORD \
    --health-cmd 'wget -qO- http://127.0.0.1:8080/api/students >/dev/null || exit 1' \
    --health-interval 5s --health-timeout 3s --health-retries 12 --health-start-period 10s \
    "$1" >/dev/null
}

wait_healthy() { # up to ~2 minutes
  local state
  for _ in $(seq 1 40); do
    state=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo missing)
    case "$state" in
      healthy) return 0 ;;
      unhealthy|missing) return 1 ;;
    esac
    sleep 3
  done
  return 1
}

# read the previous container's settings first: a rollback must reuse them, not the ones of this deploy
env_of() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null | sed -n "s/^$1=//p"; }
previous=$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null || true)
prev_url="" prev_user="" prev_password=""
if [ -n "$previous" ]; then
  prev_url=$(env_of DB_URL) prev_user=$(env_of DB_USER) prev_password=$(env_of DB_PASSWORD)
  echo "application is running as $previous: stopping it"
  docker rm -f "$name" >/dev/null
else
  echo "application is not running"
fi

echo "starting $image_name:$tag on 127.0.0.1:$port"
start "$image_name:$tag"
if wait_healthy; then
  echo "application is healthy: $image_name:$tag"
  exit 0
fi

log=$(docker logs --tail 80 "$name" 2>&1 || true)
cause=$(printf '%s\n' "$log" | grep -m1 -E 'password authentication failed|Connection refused|UnknownHost|Could not resolve placeholder|Failed to determine a suitable|Caused by' || true)
echo "[ERROR] $image_name:$tag did not become healthy${cause:+: $cause}"
echo "--- last container log lines:"
printf '%s\n' "$log" | tail -15
docker rm -f "$name" >/dev/null 2>&1 || true
if [ -n "$previous" ] && [ "$previous" != "$image_name:$tag" ]; then
  echo "rolling back to $previous with its own settings"
  (export DB_URL="$prev_url" DB_USER="$prev_user" DB_PASSWORD="$prev_password"; start "$previous")
  if wait_healthy; then echo "rolled back: $previous is running again"; else echo "[ERROR] rollback to $previous failed too"; fi
fi
exit 1
