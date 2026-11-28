#!/usr/bin/env bash
# Tests migrate.sh against two throwaway MySQL 9 containers: an old database with a few rows of every kind
# (old-schema.sql), dumped the way backup.sh dumps it, and a new database (new-schema.sql) the new server already
# wrote to. Checks --check, the migration and a second run. Needs only Docker.
#
# Usage: scripts/migrate-old-database/test/test.sh
set -Eeuo pipefail

readonly image="mysql:9" old_container="ha-migrate-test-old" new_container="ha-migrate-test-new"
test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly test_dir
work=$(mktemp -d)
readonly work

cleanup() {
    docker rm -f "$old_container" "$new_container" >/dev/null 2>&1 || true
    rm -rf -- "${work:?}"
}
trap cleanup EXIT

start_db() {
    docker rm -f "$1" >/dev/null 2>&1 || true
    docker run -d --name "$1" -e MYSQL_RANDOM_ROOT_PASSWORD=yes -e MYSQL_DATABASE=vapor_database \
        -e MYSQL_USER=vapor_username -e MYSQL_PASSWORD=vapor_password "$image" >/dev/null
}

# The entrypoint starts a temporary server first, so wait until the app user can run a query.
wait_for_db() {
    for _ in $(seq 1 90); do
        if docker exec "$1" mysql -uvapor_username -pvapor_password -e 'SELECT 1' vapor_database >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    printf 'MySQL in %s did not come up\n' "$1" >&2
    return 1
}

sql() {
    local container="$1"
    shift
    docker exec -i -e MYSQL_PWD=vapor_password "$container" mysql -uvapor_username -N "$@" vapor_database
}

start_db "$old_container"
start_db "$new_container"
wait_for_db "$old_container"
wait_for_db "$new_container"
sql "$old_container" <"$test_dir/old-schema.sql"
sql "$new_container" <"$test_dir/new-schema.sql"

# Same flags as backup.sh in the config repo.
# shellcheck disable=SC2016  # the $MYSQL_* variables expand inside the container
docker exec "$old_container" sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" exec mysqldump -u"$MYSQL_USER" \
    --single-transaction --routines --triggers --events \
    --set-gtid-purged=OFF --no-tablespaces --skip-masking-policies "$MYSQL_DATABASE"' | gzip -9 >"$work/dump.sql.gz"

failures=0
expect() {
    local name="$1" query="$2" expected="$3" actual
    actual=$(sql "$new_container" -e "$query" | tr '\t\n' ' ' | sed 's/ *$//')
    if [[ "$actual" == "$expected" ]]; then
        printf 'ok    %s\n' "$name"
    else
        printf 'FAIL  %s: expected [%s], got [%s]\n' "$name" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

counts="SELECT (SELECT COUNT(*) FROM entities), (SELECT COUNT(*) FROM entityChanges), (SELECT COUNT(*) FROM journal),
                (SELECT COUNT(*) FROM entityHourlyAggregates), (SELECT COUNT(*) FROM weatherHours), (SELECT COUNT(*) FROM deviceToken)"

"$test_dir/../migrate.sh" --check "$work/dump.sql.gz" "$new_container" >"$work/check.log"
expect "--check leaves the new database as it was" "$counts" "1 1 0 0 0 0"

"$test_dir/../migrate.sh" "$work/dump.sql.gz" "$new_container" >"$work/run.log"
cat "$work/run.log"

expect "counts" "$counts" "16 21 5 1 1 1"
expect "no legacy_ table left" \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name LIKE 'legacy\\_%'" "0"
expect "an entity the new server knew keeps its id and gains the old change" \
    "SELECT HEX(e.id), COUNT(*) FROM entities e JOIN entityChanges c ON c.entityId = e.id
     WHERE e.placeId = 'Kueche' AND e.serviceName = 'Lampe' AND e.characteristicType = 'switcher' GROUP BY e.id" \
    "AA000000000000000000000000000001 2"
expect "the newest name wins" \
    "SELECT characteristicsName FROM entities WHERE placeId = 'Flur' AND characteristicType = 'motionSensor'" "Bewegung"
expect "a Bool becomes 1 or 0, microseconds survive" \
    "SELECT c.timestamp, c.number FROM entityChanges c JOIN entities e ON e.id = c.entityId
     WHERE e.characteristicType = 'motionSensor' ORDER BY c.timestamp" \
    "2026-11-20 10:00:00.123456 1 2026-11-21 10:00:00.000000 0"
expect "a color becomes the text red green blue" \
    "SELECT c.text, c.number IS NULL FROM entityChanges c JOIN entities e ON e.id = c.entityId WHERE e.characteristicType = 'color'" \
    "1 0.5 0.25 1"
expect "numbers per type" \
    "SELECT e.characteristicType, c.number FROM entityChanges c JOIN entities e ON e.id = c.entityId
     WHERE e.placeId IN ('Flur', 'Kinderzimmer', 'Bad OG') AND e.characteristicType IN
       ('lightSensor', 'carbonDioxideSensorId', 'heatingMode', 'valvePosition', 'temperatureCalibration', 'targetTemperature', 'temperatureSensor')
     ORDER BY e.characteristicType, e.placeId" \
    "carbonDioxideSensorId 812 heatingMode 1 lightSensor 59.27 targetTemperature 21 temperatureCalibration -1.5 temperatureSensor 21.4 valvePosition 35"
expect "origins" \
    "SELECT c.origin, COUNT(*) FROM entityChanges c GROUP BY c.origin ORDER BY c.origin" "ValveJob 2 app 2 homekit 15 server 2"
expect "the fireplace becomes the server-owned switch" \
    "SELECT c.number FROM entityChanges c JOIN entities e ON e.id = c.entityId
     WHERE e.placeId = 'server' AND e.serviceName = 'fireplace' ORDER BY c.timestamp" "1 0"
expect "one plan target change per room and value" \
    "SELECT c.timestamp, c.number FROM entityChanges c JOIN entities e ON e.id = c.entityId
     WHERE e.placeId = 'server' AND e.serviceName = 'Bad OG' AND e.characteristicType = 'targetTemperature' ORDER BY c.timestamp" \
    "2026-11-21 06:00:00.100000 21 2026-11-21 22:00:00.000000 17.5"
expect "radiator writes become journal commands" \
    "SELECT entityName, title, detail, status, reason, commandValue FROM journal WHERE kind = 'command' ORDER BY timestamp" \
    "Eve Thermo setTargetTemperature setTargetTemperature(celsius: 21.0) executed plan 21 Eve Thermo 2 setTargetTemperature setTargetTemperature(celsius: 21.0) executed plan 21 Eve Thermo setHeating setHeating(active: false) executed window 0"
expect "runs become journal runs, a running one is interrupted" \
    "SELECT title, outcome, HEX(runId) = HEX(id), entityPlaceId FROM journal WHERE kind = 'run' ORDER BY timestamp" \
    "motion-at-night-flur completed 1 Flur room-heating-bad-og interrupted 1 NULL"
expect "names that differ only in case are two entities (binary collation)" \
    "SELECT e.placeId, c.number FROM entities e JOIN entityChanges c ON c.entityId = e.id
     WHERE e.serviceName = 'Lampe' AND e.characteristicType = 'switcher' AND c.timestamp < '2026-11-28'
     ORDER BY BINARY e.placeId" "Kueche 1 kueche 0"
expect "a FLOAT keeps its short decimal" \
    "SELECT c.number FROM entityChanges c JOIN entities e ON e.id = c.entityId
     WHERE e.characteristicType = 'colorTemperature' ORDER BY c.timestamp" "0.5 0.3"
expect "aggregates point to the entity" \
    "SELECT e.placeId, e.characteristicType, a.valueCount FROM entityHourlyAggregates a JOIN entities e ON e.id = a.entityId" \
    "Flur lightSensor 12"
grep -q 'entityItems rows of an unknown type *| *1 ' "$work/run.log" || { printf 'FAIL  report: unknown type\n'; failures=$((failures + 1)); }
grep -q 'entityItems rows without a value of their type *| *1 ' "$work/run.log" || { printf 'FAIL  report: no value\n'; failures=$((failures + 1)); }

"$test_dir/../migrate.sh" "$work/dump.sql.gz" "$new_container" >"$work/rerun.log"
expect "a second run adds nothing" "$counts" "16 21 5 1 1 1"

if [[ "$failures" -gt 0 ]]; then
    printf '%s check(s) failed\n' "$failures"
    exit 1
fi
printf 'All checks passed\n'
