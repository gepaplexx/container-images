#!/bin/bash

source /etc/slack-config

export SLACK_ICON="https://github.com/fhochleitner/logos/raw/main/argo.png"
export SLACK_USERNAME="argo-workflows"
export SLACK_MARKDOWN=true
export SLACK_COLOR="#ff0033"
export SLACK_WEBHOOK

#if [[ "$*" != "null" ]]; then
#  #TODO: trim leading and trailing '"' | replace '\"' with '"'
#  FAILURES=$(echo "${FAILURES}" | jq -r '.[] | "Failed Step: \(.displayName) Message: \(.message)"')
#  SLACK_MESSAGE="${SLACK_MESSAGE}${FAILURES}"
#fi

/bin/slack-notify
