#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2030,SC2031,SC2016
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1"
  local want="$2"
  local msg="${3:-}"
  if [[ "$got" != "$want" ]]; then
    fail "${msg} expected=${want} got=${got}"
  fi
}

assert_nonempty() {
  local got="$1"
  local msg="${2:-}"
  if [[ -z "$got" ]]; then
    fail "${msg} expected non-empty"
  fi
}

make_exe() {
  local path="$1"
  shift || true
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$*
EOF
  chmod +x "$path"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAWDBOT_INSTALL_SH_NO_RUN=1
# shellcheck source=../public/install.sh
source "${ROOT_DIR}/public/install.sh"

echo "==> case: direct PATH"
(
  bin="${TMP_DIR}/case-path/bin"
  make_exe "${bin}/clawdbot" 'echo "ok" >/dev/null'
  export PATH="${bin}:/usr/bin:/bin"

  got="$(resolve_clawdbot_bin)"
  assert_eq "$got" "${bin}/clawdbot" "resolve_clawdbot_bin (direct PATH)"
)

echo "==> case: npm prefix -g"
(
  root="${TMP_DIR}/case-npm-prefix-direct"
  prefix="${root}/prefix"
  tool_bin="${root}/tool-bin"

  make_exe "${tool_bin}/npm" "if [[ \"\$1\" == \"prefix\" && \"\$2\" == \"-g\" ]]; then echo \"${prefix}\"; exit 0; fi; exit 1"
  make_exe "${prefix}/bin/clawdbot" 'echo "ok" >/dev/null'

  export PATH="${tool_bin}:/usr/bin:/bin"

  got="$(resolve_clawdbot_bin)"
  assert_eq "$got" "${prefix}/bin/clawdbot" "resolve_clawdbot_bin (npm prefix -g)"
)

echo "==> case: npm prefix -g fallback"
(
  root="${TMP_DIR}/case-npm-prefix"
  prefix="${root}/prefix"
  tool_bin="${root}/tool-bin"

  make_exe "${tool_bin}/npm" "if [[ \"\$1\" == \"bin\" && \"\$2\" == \"-g\" ]]; then exit 1; fi; if [[ \"\$1\" == \"prefix\" && \"\$2\" == \"-g\" ]]; then echo \"${prefix}\"; exit 0; fi; exit 1"
  make_exe "${prefix}/bin/clawdbot" 'echo "ok" >/dev/null'

  export PATH="${tool_bin}:/usr/bin:/bin"

  got="$(resolve_clawdbot_bin)"
  assert_eq "$got" "${prefix}/bin/clawdbot" "resolve_clawdbot_bin (npm prefix -g)"
)

echo "==> case: nodenv rehash shim creation"
(
  root="${TMP_DIR}/case-nodenv"
  shim="${root}/shims"
  tool_bin="${root}/tool-bin"

  mkdir -p "${shim}"
  make_exe "${tool_bin}/npm" "exit 1"
  mkdir -p "${tool_bin}"
  cat >"${tool_bin}/nodenv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "rehash" ]]; then
  cat >"${shim}/clawdbot" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
echo ok >/dev/null
SHIM
  chmod +x "${shim}/clawdbot"
  exit 0
fi
exit 0
EOF
  chmod +x "${tool_bin}/nodenv"

  export PATH="${shim}:${tool_bin}:/usr/bin:/bin"
  command -v clawdbot >/dev/null 2>&1 && fail "precondition: clawdbot unexpectedly present"

  got="$(resolve_clawdbot_bin)"
  assert_eq "$got" "${shim}/clawdbot" "resolve_clawdbot_bin (nodenv rehash)"
)

echo "==> case: warn_clawdbot_not_found (smoke)"
(
  root="${TMP_DIR}/case-warn"
  tool_bin="${root}/tool-bin"
  make_exe "${tool_bin}/npm" 'if [[ "$1" == "prefix" && "$2" == "-g" ]]; then echo "/tmp/prefix"; exit 0; fi; if [[ "$1" == "bin" && "$2" == "-g" ]]; then echo "/tmp/prefix/bin"; exit 0; fi; exit 1'
  export PATH="${tool_bin}:/usr/bin:/bin"

  out="$(warn_clawdbot_not_found 2>&1 || true)"
  assert_nonempty "$out" "warn_clawdbot_not_found output"
)

echo "OK"
