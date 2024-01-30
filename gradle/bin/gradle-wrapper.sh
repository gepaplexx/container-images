#!/bin/sh

main(){

  gradle --version | while IFS= read -r line; do printf '%s [gradle-wrapper] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"; done
  printf "%s [gradle-wrapper] %s" "$(date '+%Y-%m-%d %T')" "gradle $* "
  bash -c "gradle $* -Dorg.slf4j.simpleLogger.showDateTime=true -Dorg.slf4j.simpleLogger.dateTimeFormat='yyyy-MM-dd HH:mm:ss'"
}

main "$*"