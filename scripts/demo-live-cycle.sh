#!/usr/bin/env bash
# demo-live-cycle.sh — grade-C live demo for payments-service-grade-c
#
#   ./scripts/demo-live-cycle.sh start    # bump json-path 2.7.0 → 2.8.0.rhlw-00001 + open PR
#   ./scripts/demo-live-cycle.sh finish   # close PR(s) without merge; restore community json-path
#   ./scripts/demo-live-cycle.sh status
#
# Expected pipeline: headline C → grade-gate pass → cab-decision WAITS for human:
#   oc create configmap upgrade-delta-cab-approved -n upgrade-delta-demo --from-literal=approved=true
#
# Never bump snakeyaml here (would headline F and fail fail-on D).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

POM=pom.xml
COMMUNITY='2.7.0'
LIGHTWELL='2.8.0.rhlw-00001'
PROP='json-path.version'
BRANCH_PREFIX='demo/live-jsonpath'
LABEL='demo-live-pom'
SCORECARD='https://scorecard-gradec-upgrade-delta-demo.apps.asaran.na-launch.com/out/reports/scorecard.html'

die() { echo "FATAL: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "'$1' required"; }

jsonpath_ver() {
  local f="${1:-$POM}"
  sed -n "s/.*<${PROP}>\\([^<]*\\)<\\/${PROP}>.*/\\1/p" "$f" | head -1
}

ensure_baseline() {
  local v
  v=$(jsonpath_ver "$POM")
  [ "$v" = "$COMMUNITY" ] || die \
    "$POM has ${PROP}=$v (want $COMMUNITY on the branch you start from). Run: $0 finish"
}

cmd_status() {
  echo "${PROP} in $POM: $(jsonpath_ver "$POM")  (baseline=$COMMUNITY demo=$LIGHTWELL)"
  echo "branch: $(git rev-parse --abbrev-ref HEAD)  sha: $(git rev-parse --short HEAD)"
  if command -v gh >/dev/null; then
    echo "open demo PRs:"
    gh pr list --label "$LABEL" --state open 2>/dev/null || \
      gh pr list --search "head:$BRANCH_PREFIX" --state open 2>/dev/null || true
  fi
}

cmd_start() {
  need git
  need gh
  [ -f "$POM" ] || die "missing $POM"
  git rev-parse --is-inside-work-tree >/dev/null

  local base="${DEMO_BASE_BRANCH:-main}"
  echo "== sync $base =="
  git fetch origin "$base" 2>/dev/null || true
  git checkout "$base"
  git pull --ff-only origin "$base" 2>/dev/null || git pull --ff-only || true
  ensure_baseline

  if [ ! -f .tekton/pull-request-live.yaml ]; then
    echo "WARN: .tekton/pull-request-live.yaml missing — live pipeline will not fire."
  fi

  local stamp branch
  stamp=$(date +%Y%m%d-%H%M)
  branch="${BRANCH_PREFIX}-${stamp}"
  echo "== create $branch =="
  git checkout -b "$branch"

  if grep -q "<${PROP}>${COMMUNITY}</${PROP}>" "$POM"; then
    sed -i.bak "s|<${PROP}>${COMMUNITY}</${PROP}>|<${PROP}>${LIGHTWELL}</${PROP}>|" "$POM"
    rm -f "${POM}.bak"
  else
    die "expected <${PROP}>${COMMUNITY}</${PROP}> in $POM"
  fi
  [ "$(jsonpath_ver "$POM")" = "$LIGHTWELL" ] || die "bump failed"

  git add "$POM"
  git commit -m "$(cat <<EOF
demo: adopt json-path ${LIGHTWELL} (grade C / human CAB)

Live-pipeline demo trigger. Close without merging when done
(./scripts/demo-live-cycle.sh finish) so ${base} stays on community ${COMMUNITY}.
EOF
)"

  echo "== push + open PR =="
  git push -u origin HEAD

  local body
  body=$(cat <<EOF
## Live pom.xml demo — grade **C** (human CAB)

Bumps \`${PROP}\` \`${COMMUNITY}\` → \`${LIGHTWELL}\` so \`upgrade-delta-live\` grades a
**base-version** Lightwell adoption (expected project grade **C**).

### After the PipelineRun reaches \`cab-decision\`
Approve in the demo namespace:

\`\`\`bash
oc create configmap upgrade-delta-cab-approved -n upgrade-delta-demo \\
  --from-literal=approved=true
\`\`\`

### Reset
**Do not merge.** When done:

\`\`\`bash
./scripts/demo-live-cycle.sh finish
\`\`\`

See upgrade-delta [docs/DEMO-LIVE-POM.md](https://github.com/anurag-saran/upgrade-delta/blob/main/docs/DEMO-LIVE-POM.md).
EOF
)

  local url
  url=$(gh pr create \
    --base "$base" \
    --title "demo: json-path ${COMMUNITY} to ${LIGHTWELL} (grade C / human CAB)" \
    --body "$body" \
    --label "$LABEL" 2>&1) || {
      gh label create "$LABEL" --description "Live pom.xml demo PR — close without merge" --color "0E8A16" 2>/dev/null || true
      url=$(gh pr create \
        --base "$base" \
        --title "demo: json-path ${COMMUNITY} to ${LIGHTWELL} (grade C / human CAB)" \
        --body "$body")
      local n
      n=$(gh pr view --json number -q .number)
      gh pr edit "$n" --add-label "$LABEL" 2>/dev/null || true
    }
  echo "$url"
  echo
  echo "Watch: OpenShift PipelineRun upgrade-delta-live-pr-gradec-..."
  echo "Scorecard: ${SCORECARD}"
  echo "CAB wait: create ConfigMap upgrade-delta-cab-approved when cab-decision pauses"
  echo "When done:  ./scripts/demo-live-cycle.sh finish"
}

cmd_finish() {
  need git
  need gh
  local base="${DEMO_BASE_BRANCH:-main}"

  echo "== close open demo PRs (no merge) =="
  local nums
  nums=$(gh pr list --label "$LABEL" --state open --json number -q '.[].number' 2>/dev/null || true)
  if [ -z "$nums" ]; then
    nums=$(gh pr list --search "head:${BRANCH_PREFIX}" --state open --json number -q '.[].number' 2>/dev/null || true)
  fi
  if [ -z "$nums" ]; then
    echo "(no open demo PRs found)"
  else
    for n in $nums; do
      echo "closing PR #$n"
      gh pr close "$n" --comment \
        "Demo complete — closed without merge so \`${base}\` stays on community ${PROP} (${COMMUNITY}) for the next \`./scripts/demo-live-cycle.sh start\`." \
        || true
    done
  fi

  echo "== ensure $base baseline =="
  git fetch origin "$base" 2>/dev/null || true
  git checkout "$base"
  git pull --ff-only origin "$base" 2>/dev/null || git pull --ff-only || true

  local v
  v=$(jsonpath_ver "$POM")
  if [ "$v" != "$COMMUNITY" ]; then
    echo "WARN: $base has ${PROP}=$v — restoring community ${COMMUNITY}"
    sed -i.bak "s|<${PROP}>${v}</${PROP}>|<${PROP}>${COMMUNITY}</${PROP}>|" "$POM"
    rm -f "${POM}.bak"
    git add "$POM"
    git commit -m "demo: restore community ${PROP} ${COMMUNITY} on ${base} after live demo"
    git push origin "$base"
  else
    echo "OK: $POM already on community ${COMMUNITY}"
  fi

  git branch --list "${BRANCH_PREFIX}-*" | while read -r b; do
    b=$(echo "$b" | tr -d ' *')
    [ -n "$b" ] && git branch -D "$b" 2>/dev/null || true
  done

  cmd_status
  echo "Ready for next: ./scripts/demo-live-cycle.sh start"
}

usage() {
  echo "Usage: $0 {start|finish|status}"
  echo "  start   — bump json-path to Lightwell (grade C) on a new branch + open PR"
  echo "  finish  — close demo PR(s) without merge; restore community json-path on main"
  echo "  status  — show current json-path version and open demo PRs"
}

case "${1:-}" in
  start)  cmd_start ;;
  finish) cmd_finish ;;
  status) cmd_status ;;
  *) usage; exit 2 ;;
esac
