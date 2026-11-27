#!/usr/bin/env bash
# Runs the MySQL-only test suite (EntityStorageMySQLTests) against a throwaway
# MySQL 9 in Docker.
# - macOS host with a Swift toolchain: MySQL runs in Docker with its port on 127.0.0.1
#   and the tests run natively on the host.
# - Other hosts: refused with a message, the package holds app targets that need Apple platforms.
#
# Usage: scripts/run-mysql-tests.sh [git-ref]   (default: the current checkout)
set -euo pipefail

readonly mysql_image="mysql:9"
readonly host_port=33306
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

wait_for_mysql() {
    echo "Waiting for MySQL..."
    for _ in $(seq 1 60); do
        if docker exec "$db_container" mysqladmin ping -uu -pp --silent >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    docker exec "$db_container" mysqladmin ping -uu -pp --silent >/dev/null
}

if [[ "$(uname)" == "Darwin" ]] && command -v swift >/dev/null 2>&1; then
    # Native run: publish MySQL on the loopback interface only.
    docker run -d --name "$db_container" -p "127.0.0.1:$host_port:3306" \
        -e MYSQL_ROOT_PASSWORD=root \
        -e MYSQL_DATABASE=t -e MYSQL_USER=u -e MYSQL_PASSWORD=p \
        "$mysql_image" >/dev/null
    wait_for_mysql
    (cd "$repo_root" && HA_TEST_MYSQL_PORT="$host_port" swift test --filter EntityStorageMySQLTests) \
        2>&1 | tee "$repo_root/mysql-tests.log"
else
    echo "This script needs a Mac with a Swift toolchain: the package also holds app targets (SwiftUI, TCA) that do not build on Linux." >&2
    exit 1
fi

echo "Log written to $repo_root/mysql-tests.log"
