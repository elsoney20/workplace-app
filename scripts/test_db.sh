#!/usr/bin/env bash
# Applies all migrations to a throwaway local PostgreSQL database and runs the
# security tests. Needs psql + a Postgres server (CI provides one).
# Usage: PGHOST=... PGPORT=... PGUSER=postgres scripts/test_db.sh
set -euo pipefail
cd "$(dirname "$0")/../supabase"
DB="${TEST_DB_NAME:-workplace_test}"

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
psql -v ON_ERROR_STOP=1 -q -d "$DB" -c "set client_min_messages = error" -f tests/00_supabase_stub.sql
for f in migrations/*.sql; do
  echo "Applying $f"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$f"
done
psql -v ON_ERROR_STOP=1 -q -d "$DB" -f tests/01_rls_test.sql
