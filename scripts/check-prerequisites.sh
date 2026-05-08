#!/usr/bin/env bash
# Verifies that the host has the tools needed to bring up the k3s-on-Lima cluster.
set -euo pipefail

REQUIRED=(limactl kubectl)

missing=()
echo "=== Checking prerequisites for k8s-lab ==="
for tool in "${REQUIRED[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    version="$("$tool" version 2>/dev/null | head -n 1 || echo "unknown")"
    printf "[OK] %-10s %s\n" "$tool" "$version"
  else
    missing+=("$tool")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo
  echo "[ERROR] Missing tools: ${missing[*]}" >&2
  echo
  echo "Install via Homebrew:" >&2
  for tool in "${missing[@]}"; do
    case "$tool" in
      limactl) echo "  brew install lima" >&2 ;;
      kubectl) echo "  brew install kubectl" >&2 ;;
      *) echo "  brew install $tool" >&2 ;;
    esac
  done
  exit 1
fi

echo
echo "=== All prerequisites are installed ==="
