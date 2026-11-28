#!/usr/bin/env bash
# Moves the data of the old database into the new schema (docs/database-schema.md, "Moving data from the old schema").
#
# Usage: scripts/migrate-old-database/migrate.sh [--check] <dump.sql.gz> <db-container>
#   <dump.sql.gz>   a dump of the old database, as backup.sh in the config repo writes it
#   <db-container>  the MySQL container of the new database; the server has created its schema there
#   --check         runs everything, prints the report and rolls back: the new database stays as it was
#
# The old tables are loaded into the new database under the prefix `legacy_` (the old and the new schema both
# have a table `entityHourlyAggregates`), migrate.sql moves their rows in one transaction, and the legacy_
# tables are dropped again. Credentials and database come from the container's own MYSQL_* environment;
# TARGET_DATABASE overrides the database. Running it again adds nothing twice.
set -Eeuo pipefail

fail() { printf 'migrate.sh: %s\n' "$*" >&2; exit 1; }
trap 'printf "migrate.sh: failed at line %s\n" "$LINENO" >&2' ERR

end_statement="COMMIT"
if [[ "${1:-}" == "--check" ]]; then
    end_statement="ROLLBACK"
    shift
fi
[[ $# -eq 2 ]] || fail "usage: migrate.sh [--check] <dump.sql.gz> <db-container>"
readonly dump="$1" container="$2" end_statement
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

for cmd in docker gzip sed; do
    command -v "$cmd" >/dev/null || fail "$cmd not found in PATH"
done
[[ -s "$dump" ]] || fail "dump $dump not found or empty"
[[ "$(gzip -dc "$dump" | tail -n 1)" == "-- Dump completed"* ]] || fail "dump $dump is truncated (no '-- Dump completed' footer)"

# Runs the mysql client in the container; stdin is the SQL. The password stays in the container (MYSQL_PWD).
db() {
    # shellcheck disable=SC2016  # the $MYSQL_* variables expand inside the container
    docker exec -i -e TARGET_DATABASE="${TARGET_DATABASE:-}" "$container" sh -c \
        'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql -u"$MYSQL_USER" --default-character-set=utf8mb4 "$@" "${TARGET_DATABASE:-$MYSQL_DATABASE}"' \
        mysql "$@"
}

drop_legacy_tables() {
    local tables
    tables=$(db -N -e "SELECT GROUP_CONCAT(CONCAT('\`', table_name, '\`')) FROM information_schema.tables
                       WHERE table_schema = DATABASE() AND table_name LIKE 'legacy\\_%'")
    if [[ -n "$tables" && "$tables" != "NULL" ]]; then
        db -e "DROP TABLE $tables"
    fi
}

db -N -e "SELECT 1 FROM entities LIMIT 0" >/dev/null 2>&1 \
    || fail "no table entities in the target database: start the new server against it once, so it creates the schema"

# Read in full (no grep -q): an early exit would break the pipe and fail it under pipefail.
# shellcheck disable=SC2016  # the backticks are literal MySQL identifier quotes
dumped_tables=$(gzip -dc "$dump" | sed -nE 's/^CREATE TABLE `([A-Za-z0-9_]+)`.*/\1/p')
for table in entityItems automationRuns heatingWrites fireplaceSwitches entityHourlyAggregates weatherHours deviceToken; do
    grep -qx "$table" <<<"$dumped_tables" || fail "dump has no table $table: is it a dump of the old database?"
done

drop_legacy_tables
trap 'drop_legacy_tables || true' EXIT

printf 'Loading the old tables as legacy_* into the new database...\n'
# Renames every table of the dump on the statements that name it (the old schema has no foreign keys, views or
# triggers, so no other statement refers to a table name) and gives each table the binary collation of the new
# schema, so the old names compare with the new ones exactly. The old columns carry no collation of their own.
# shellcheck disable=SC2016  # the backticks are literal MySQL identifier quotes
gzip -dc "$dump" \
    | sed -E -e 's/^(DROP TABLE IF EXISTS|CREATE TABLE|INSERT INTO|LOCK TABLES|\/\*!40000 ALTER TABLE) `([A-Za-z0-9_]+)`/\1 `legacy_\2`/' \
             -e '/^\) ENGINE=/s/DEFAULT CHARSET=[a-z0-9]+( COLLATE=[a-z0-9_]+)?/DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin/' \
    | db

printf 'Moving the rows (%s at the end)...\n' "$end_statement"
{ cat "$script_dir/migrate.sql"; printf '%s;\n' "$end_statement"; } | db --table

if [[ "$end_statement" == "ROLLBACK" ]]; then
    printf 'Check only: rolled back, the new database is unchanged.\n'
else
    printf 'Done.\n'
fi
