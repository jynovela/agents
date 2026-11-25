#!/usr/bin/env bash
# The only way agents deploy. It refuses any target that isn't on the allowed
# list, and writes every attempt to logs/deploy.log, refused ones included.
# Copy it to dev/deploy.sh and fill in the TAILOR lines. See setup/build.md.
#
# Usage:
#   dev/deploy.sh <target>             Deploy the current build to <target>
#   dev/deploy.sh rollback <target>    Put back the deploy before the last one
#
# There is no production target on purpose. Production deploys happen when a
# person merges to the production branch, never from an agent's shell.
set -uo pipefail
cd "$(dirname "$0")/.."

# <!-- TAILOR: the targets agents may deploy to. Never add production. -->
ALLOWED='local staging'

# <!-- TAILOR: the command that deploys to each target, and the command that
# rolls it back. Write "" for a target without a rollback yet, and fix that
# before you rely on the target. With Vercel previews as staging (see
# setup/build.md), staging deploys when you push a branch, so DEPLOY_staging
# can push the current branch to the staging branch. Never put --prod,
# "vercel promote", or a production project ref here. -->
DEPLOY_local='echo "TAILOR: set DEPLOY_local in dev/deploy.sh"; exit 1'
ROLLBACK_local=''
DEPLOY_staging='echo "TAILOR: set DEPLOY_staging in dev/deploy.sh"; exit 1'
ROLLBACK_staging=''

mkdir -p logs
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> logs/deploy.log; }

action=deploy
if [ "${1:-}" = rollback ]; then
  action=rollback
  shift
fi
target="${1:-}"

if [ -z "$target" ]; then
  echo "Usage: dev/deploy.sh <target> | dev/deploy.sh rollback <target>" >&2
  echo "Allowed targets: $ALLOWED" >&2
  exit 2
fi

case " $ALLOWED " in
  *" $target "*) ;;
  *)
    log "REFUSED $action $target"
    echo "Refused: \"$target\" is not an allowed target ($ALLOWED)." >&2
    echo "Production deploys need a person: merge to the production branch." >&2
    exit 2
    ;;
esac

if [ "$action" = rollback ]; then
  eval "cmd=\${ROLLBACK_$target}"
else
  eval "cmd=\${DEPLOY_$target}"
fi
# shellcheck disable=SC2154
if [ -z "$cmd" ]; then
  log "FAILED $action $target (no command set)"
  echo "No $action command is set for $target in dev/deploy.sh." >&2
  exit 1
fi

log "START $action $target"
if bash -c "$cmd"; then
  log "OK $action $target"
  echo "$action $target: OK"
else
  code=$?
  log "FAILED $action $target (exit $code)"
  echo "$action $target: FAILED (exit $code). See the output above." >&2
  exit "$code"
fi
