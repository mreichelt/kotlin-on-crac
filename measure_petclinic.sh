#!/usr/bin/env bash

set -euo pipefail

# script is hard-coded for spring-petclinic project, adjust to your needs
BACKEND_URL=http://localhost:8080/owners\?lastName=

if [ $# -eq 0 ]; then
  echo "Error: no arguments provided."
  echo "Usage: $0 <java-args>"
  echo "Example:          $0 -jar app.jar"
  echo "Example AOTCache: $0 -XX:AOTMode=on -XX:AOTCache=app.aot -jar app.jar"
  echo "Example CRaC:     $0 -XX:CRaCRestoreFrom=crac-files"
  exit 1
fi

JAVA_ARGS="$@"

# Record start in nanoseconds
start=$(date +%s%N)

# Start backend in background
java $JAVA_ARGS &
backend_pid=$!

# Poll until HTTP 200
until [ "$(curl -s -o /dev/null -w "%{http_code}" $BACKEND_URL)" = "200" ]; do
  sleep 0.001
done

# End time
end=$(date +%s%N)

# Compute elapsed time in microseconds
elapsed_ns=$(( end - start ))
elapsed_ms=$(( elapsed_ns / 1000000 ))

echo
echo
echo "Backend ready in ${elapsed_ms} ms"
echo
echo

kill $backend_pid
