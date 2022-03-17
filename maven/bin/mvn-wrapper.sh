#!/bin/sh

SETTINGS_LOCATION=/maven/settings.xml
SETTINGS_STRING=""

######################   handle options ###################

handle_options() {
#  OPTS=$(getopt -o hcb:u:w: -l help,checkout,branch:,url:,workspace:)
local opts=$(getopt -o s: -l settings -- "$@")
local opts_return=$?

if [[ ${opts_return} != 0 ]]; then
    echo
    (>&2 echo "failed to fetch options via getopt")
    echo
    return ${opts_return}
fi

eval set -- "$opts"
while true ; do
  case "$1" in
    --settings | -s)
      SETTINGS_LOCATION="${2}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

}

main(){
  handle_options "$@"

  if [ -f "${SETTINGS_LOCATION}" ]; then
    SETTINGS_STRING="-s ${SETTINGS_LOCATION}"
  fi

  mvn "${SETTINGS_STRING}" "$@"
}

main "$@"