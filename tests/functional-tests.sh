#!/usr/bin/env bash
set -Eeuo pipefail

docker build -f tests/Dockerfile -t installer-functional-test .
docker run -e TERM=xterm -e AGENT_SKIP_FIRST_RUN=1 -v "$(pwd)":/app --rm -i installer-functional-test expect -f /app/tests/test-as-root-production
docker run -e TERM=xterm -e AGENT_SKIP_FIRST_RUN=1 -v "$(pwd)":/app --rm -i installer-functional-test expect -f /app/tests/test-as-root-sandbox
