#!/usr/bin/env bash
# Hit the running application and fail unless GET /api/students returns data from the database.
# Runs the request inside the container (docker exec), so it does not depend on the host port or the
# network layout of the node that runs Jenkins.
set -euo pipefail

name=${IMAGE_NAME:-sonarcube}
url=http://127.0.0.1:8080/api/students

echo "GET $url (inside container $name)"
body=$(docker exec "$name" wget -qO- "$url") || { echo "[ERROR] request to $url failed"; exit 1; }
echo "$body" | cut -c1-300

if ! printf '%s' "$body" | grep -q '"grade"'; then
  echo "[ERROR] response has no students with a grade: the database is empty or the query failed"
  exit 1
fi
echo "smoke test passed"
