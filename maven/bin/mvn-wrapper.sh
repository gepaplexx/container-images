#!/bin/sh

SETTINGS_LOCATION=/maven/maven-settings.xml
SETTINGS_STRING=""


main(){

  if [ -f "${SETTINGS_LOCATION}" ]; then
    SETTINGS_STRING="-s ${SETTINGS_LOCATION}"
  fi
  mvn "$*" "${SETTINGS_STRING}"
}

main "$*"