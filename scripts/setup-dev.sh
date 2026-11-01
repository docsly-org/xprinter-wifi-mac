#!/bin/bash
# Run once after cloning: commits in this repository are signed as docsly-org,
# so a personal global git name/email never reaches the public history.
set -euo pipefail
cd "$(dirname "$0")/.."
git config user.name "docsly-org"
git config user.email "231897172+docsly-org@users.noreply.github.com"
echo "This repository now commits as: $(git config user.name) <$(git config user.email)>"
