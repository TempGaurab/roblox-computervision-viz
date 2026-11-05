#!/usr/bin/env bash
# The definition of done (static checks, tests, build). Run from anywhere: scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== stylua"
stylua --check src tests

echo "== selene"
selene src

echo "== lune"
lune run tests/run

echo "== rojo build"
mkdir -p build
rojo build -o build/NeuralGlass.rbxl

echo "== luau-lsp"
rojo sourcemap default.project.json -o sourcemap.json
# Roblox type definitions, pinned to the luau-lsp version in rokit.toml and cached in build/.
lsp_version="$(sed -n 's/^luau-lsp = ".*@\(.*\)"$/\1/p' rokit.toml)"
definitions="build/globalTypes-${lsp_version}.d.luau"
if [ ! -f "$definitions" ]; then
	curl -fsSL -o "$definitions" \
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${lsp_version}/scripts/globalTypes.d.luau"
fi
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions="@roblox=${definitions}" src

echo "All checks passed."
