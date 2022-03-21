#!/bin/bash

source /etc/slack-config

export SLACK_ICON="https://github.com/fhochleitner/logos/raw/main/argo.png"
export SLACK_USERNAME="argo-workflows"
export SLACK_MARKDOWN=true
export SLACK_WEBHOOK
SLACK_COLOR="#228b22"

#if [[ "$*" != "null" ]]; then
#  SLACK_COLOR="#ff0033"
#  #TODO: trim leading and trailing '"' | replace '\"' with '"'
#  FAILURES=$(echo "${FAILURES}" | jq -r '.[] | "Failed Step: \(.displayName) Message: \(.message)"')
#  SLACK_MESSAGE="${SLACK_MESSAGE}${FAILURES}"
#fi

export SLACK_COLOR

/bin/slack-notify
