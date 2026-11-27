#!/usr/bin/env bash
# Runs the MySQL-only test suite (EntityStorageMySQLTests) against a throwaway
# MySQL 9 in Docker. Needs only Docker: the tests build inside the same Swift
# image the Dockerfile uses.
#
# Usage: scripts/run-mysql-tests.sh [git-ref]   (default: the current checkout)
set -euo pipefail

readonly mysql_image="mysql:9"
readonly swift_image="swift:6.4-noble"
readonly db_container="ha-mysql-tests-db"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly ref="${1:-}"

cleanup() {
    docker rm -f "$db_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ -n "$ref" ]]; then
    git -C "$repo_root" fetch --quiet origin
    git -C "$repo_root" checkout --quiet "$ref"
fi
echo "Testing $(git -C "$repo_root" rev-parse --short HEAD) ($(git -C "$repo_root" branch --show-current))"

cleanup
docker run -d --name "$db_container" \
    -e MYSQL_ROOT_PASSWORD=root \
    -e MYSQL_DATABASE=t -e MYSQL_USER=u -e MYSQL_PASSWORD=p \
    "$mysql_image" >/dev/null

echo "Waiting for MySQL..."
for _ in $(seq 1 60); do
    if docker exec "$db_container" mysqladmin ping -uu -pp --silent >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
docker exec "$db_container" mysqladmin ping -uu -pp --silent >/dev/null

# The tests connect to 127.0.0.1, so the Swift container shares the database
# container's network namespace.
docker run --rm \
    --network "container:$db_container" \
    -v "$repo_root:/src" -w /src \
    -e HA_TEST_MYSQL_PORT=3306 \
    "$swift_image" \
    bash -c 'apt-get update -qq && apt-get install -y -qq libjemalloc-dev >/dev/null; swift test --scratch-path /tmp/build --filter EntityStorageMySQLTests' \
    2>&1 | tee "$repo_root/mysql-tests.log"

echo "Log written to $repo_root/mysql-tests.log"
