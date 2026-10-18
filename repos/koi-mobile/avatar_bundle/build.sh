#!/usr/bin/env bash
# Builds Fatima's /avatar-host page into ../assets/avatar_local/ (see README.md).
# Works in Git Bash. npm's cache goes to D: when it exists (C: is nearly full).
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${npm_config_cache:-}" ] && [ -d /d/DevCache ]; then
  export npm_config_cache=/d/DevCache/npm-cache
fi

OUT=../assets/avatar_local
npm ci --no-audit --no-fund
npx --no-install esbuild src/main.tsx \
  --bundle --minify --format=iife --target=es2020 --charset=utf8 \
  --jsx=automatic \
  --define:process.env.NODE_ENV='"production"' \
  --legal-comments=none \
  --outfile="$OUT/avatar.js"
cp src/index.html "$OUT/index.html"
ls -l "$OUT"
