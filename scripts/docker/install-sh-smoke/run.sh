#!/usr/bin/env bash
set -euo pipefail

LOCAL_INSTALL_PATH="/opt/clawdbot-install.sh"
if [[ -n "${CLAWDBOT_INSTALL_URL:-}" ]]; then
  INSTALL_URL="$CLAWDBOT_INSTALL_URL"
elif [[ -f "$LOCAL_INSTALL_PATH" ]]; then
  INSTALL_URL="file://${LOCAL_INSTALL_PATH}"
else
  INSTALL_URL="https://clawd.bot/install.sh"
fi

echo "==> Resolve npm versions"
LATEST_VERSION="$(npm view clawdbot version)"
PREVIOUS_VERSION="$(node - <<'NODE'
const { execSync } = require("node:child_process");

const versions = JSON.parse(execSync("npm view clawdbot versions --json", { encoding: "utf8" }));
if (!Array.isArray(versions) || versions.length === 0) {
  process.exit(1);
}
const previous = versions.length >= 2 ? versions[versions.length - 2] : versions[0];
process.stdout.write(previous);
NODE
)"

echo "latest=$LATEST_VERSION previous=$PREVIOUS_VERSION"

echo "==> Installer: --help"
curl -fsSL "$INSTALL_URL" | bash -s -- --help >/tmp/install-help.txt
grep -q -- "--install-method" /tmp/install-help.txt

echo "==> Preinstall previous (forces installer upgrade path)"
npm install -g "clawdbot@${PREVIOUS_VERSION}"

echo "==> Run official installer one-liner"
curl -fsSL "$INSTALL_URL" | bash -s -- --no-onboard

echo "==> Verify installed version"
INSTALLED_VERSION="$(clawdbot --version 2>/dev/null | head -n 1 | tr -d '\r')"
echo "installed=$INSTALLED_VERSION expected=$LATEST_VERSION"

if [[ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]]; then
  echo "ERROR: expected clawdbot@$LATEST_VERSION, got clawdbot@$INSTALLED_VERSION" >&2
  exit 1
fi

echo "==> Sanity: CLI runs"
clawdbot --help >/dev/null

echo "==> Installer: detect source checkout (dry-run)"
TMP_REPO="/tmp/clawdbot-repo-detect"
rm -rf "$TMP_REPO"
mkdir -p "$TMP_REPO"
cat > "$TMP_REPO/package.json" <<'EOF'
{"name":"clawdbot"}
EOF
touch "$TMP_REPO/pnpm-workspace.yaml"

(
  cd "$TMP_REPO"
  set +e
  curl -fsSL "$INSTALL_URL" | bash -s -- --dry-run --no-onboard --no-prompt >/tmp/repo-detect.out 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    echo "ERROR: expected repo-detect dry-run to fail without --install-method" >&2
    cat /tmp/repo-detect.out >&2
    exit 1
  fi
)

echo "==> Installer: dry-run (explicit methods)"
curl -fsSL "$INSTALL_URL" | bash -s -- --dry-run --no-onboard --install-method npm --no-prompt >/dev/null
curl -fsSL "$INSTALL_URL" | bash -s -- --dry-run --no-onboard --install-method git --git-dir /tmp/clawdbot-src --no-prompt >/dev/null

echo "OK"
