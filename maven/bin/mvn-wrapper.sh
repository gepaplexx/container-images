#!/bin/sh

SETTINGS_LOCATION=/root/.m2/settings.xml
SETTINGS_STRING=""


main(){

  if [ -f "${SETTINGS_LOCATION}" ]; then
    SETTINGS_STRING="-s ${SETTINGS_LOCATION}"
  else
    SETTINGS_STRING="-s /usr/share/maven/conf/settings.xml"
  fi
  printf "%s [maven-wrapper] %s" "$(date '+%Y-%m-%d %T')" "mvn $* $SETTINGS_STRING"

#  bash -c "mvn $* -D org.slf4j.simpleLogger.showDateTime=true -D org.slf4j.simpleLogger.dateTimeFormat='yyyy-MM-dd HH:mm:ss' ${SETTINGS_STRING} -fae -C"
  bash -c "mvn $* -D org.slf4j.simpleLogger.showDateTime=true -D org.slf4j.simpleLogger.dateTimeFormat='yyyy-MM-dd HH:mm:ss' ${SETTINGS_STRING} -fae"
}

main "$*"