#!/bin/sh

SETTINGS_LOCATION=/maven/maven-settings.xml
SETTINGS_STRING=""


main(){

  if [ -f "${SETTINGS_LOCATION}" ]; then
    SETTINGS_STRING="-s ${SETTINGS_LOCATION}"
  fi
  echo "mvn $* $SETTINGS_STRING"
  bash -c "mvn $* ${SETTINGS_STRING}"
}

main "$*"