#!/bin/bash
set -e

echo "=== Checking prerequisites for k8s-lab ==="

REQUIRED_TOOLS=("kind" "kubectl" "helm" "helmfile")

missing_tools=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        missing_tools+=("$tool")
    else
        version=$($tool version 2>/dev/null | head -n 1 || echo "unknown")
        echo "[OK] $tool: $version"
    fi
done

if [ ${#missing_tools[@]} -ne 0 ]; then
    echo ""
    echo "[ERROR] Missing tools: ${missing_tools[*]}"
    echo ""
    echo "Install missing tools using Homebrew:"
    for tool in "${missing_tools[@]}"; do
        case $tool in
            kind)
                echo "  brew install kind"
                ;;
            kubectl)
                echo "  brew install kubectl"
                ;;
            helm)
                echo "  brew install helm"
                ;;
            helmfile)
                echo "  brew install helmfile"
                ;;
        esac
    done
    exit 1
fi

echo ""
echo "=== All prerequisites are installed ==="
