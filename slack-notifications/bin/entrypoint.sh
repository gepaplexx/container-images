#!/bin/bash
source /etc/slack-config
SLACK_COLOR="#228b22"
export SLACK_ICON="https://github.com/fhochleitner/logos/raw/main/argo.png"
export SLACK_WEBHOOK
export SLACK_USERNAME="argo-workflows"
export SLACK_MARKDOWN=true

if [[ "$*" != "null" ]]; then
  SLACK_COLOR="#ff0033"
  FAILURES=$(echo "$*" | jq -r '.[] | "Failed Step: \(.displayName) Message: \(.message)"')
  SLACK_MESSAGE="${SLACK_MESSAGE}${FAILURES}"
fi
export SLACK_COLOR

/bin/slack-notify
