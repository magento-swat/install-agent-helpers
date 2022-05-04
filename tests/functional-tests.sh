#!/usr/bin/env bash
set -Eeuo pipefail

docker build -f tests/Dockerfile -t installer-functional-test .
docker run -e TERM=xterm -e AGENT_DEV_MODE=1 -v "$(pwd)":/app --rm -i installer-functional-test expect -f /app/tests/test-as-root-production
docker run -e TERM=xterm -e AGENT_DEV_MODE=1 -v "$(pwd)":/app --rm -i installer-functional-test expect -f /app/tests/test-as-root-sandbox
docker run -e TERM=xterm -v "$(pwd)":/app --rm -i installer-functional-test bash /app/tests/test-skip-first-run-error-catch
