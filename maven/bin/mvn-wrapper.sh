#!/bin/sh

SETTINGS_LOCATION=/root/.m2/maven-settings.xml
SETTINGS_STRING=""


main(){

  if [ -f "${SETTINGS_LOCATION}" ]; then
    SETTINGS_STRING="-s ${SETTINGS_LOCATION}"
  else
    SETTINGS_STRING="-s /usr/share/maven/conf/settings.xml"
  fi
  echo "mvn $* $SETTINGS_STRING"
  bash -c "mvn $* ${SETTINGS_STRING} -fae"
}

main "$*"