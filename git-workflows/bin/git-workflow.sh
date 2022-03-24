#!/bin/bash

PRG=`basename $0`

DIR=$(dirname $0)
BASEDIR=${DIR-.}/..
HOME=/root

######################### variables   #################
DO_CLONE=false
DO_CHECKOUT=false
UPDATE_ARGO=false
DELETE_ARGO=false
CREATE_ARGO=false
BRANCH="main"
NAMESPACE=""
CLONE_URL=""
REPO_NAME="sources"
WORKSPACE=$(pwd)
#WORKSPACE="/mnt/out"
COMMIT_HASH=""

######################### print usage #################

print_usage(){
cat <<EOF 1>&2
usage: $PRG [-hE]

Options:
    c | clone: Clone a git repository
    u | url: clone url of the git repository
    b | branch: switches to specific branch. Default: main
    p | path: directory of workspace
    n | name: name of the git repository
    h | help: This help

Function:
    performs various operations on a git repository

EOF
}

####################### checkout ##################

# TODO: handle private repositories (https://stackoverflow.com/questions/2505096/clone-a-private-repository-github)

git_clone() {
  if [ -z "${CLONE_URL}" ]; then
      echo "missing parameters: url"
      print_usage
      exit 1
  fi
  git clone --depth 1 --recurse-submodules --shallow-submodules "${CLONE_URL}" "${WORKSPACE}"/"${REPO_NAME}"

}

git_checkout() {
  cd "${WORKSPACE}/${REPO_NAME}" \
  && git checkout ${BRANCH} || git checkout -b ${BRANCH} \
  && cd  || exit 1
}

extract_git_commit() {
  cd "${WORKSPACE}/${REPO_NAME}" \
  && COMMIT_HASH=$(git rev-parse --short HEAD) \
  && cd || exit 1
  echo "${COMMIT_HASH}" > "${WORKSPACE}/commit_hash"
}

update_vars() {
  CLONE_URL="${CLONE_URL%.git}-ci.git"
  REPO_NAME="${REPO_NAME}-ci"
}

update_version() {
  cd "${WORKSPACE}/${REPO_NAME}" \
  && sed -i "s/tag: \w\{7\}/tag: ${COMMIT_HASH}/g" values.yaml \
  && git config --global user.name "argo-ci" \
  && git config --global user.email "argo-ci@gepardec.com" \
  && git add . \
  && git commit -m "updated image version to tag ${COMMIT_HASH}" || true \
  && git push
}

update_namespace() {
  cd "${WORKSPACE}/${REPO_NAME}" \
  && sed -i "s/namespace:*/namespace: ${NAMESPACE}/g" application.yml \
  && git config --global user.name "argo-ci" \
  && git config --global user.email "argo-ci@gepardec.com" \
  && git add . \
  && git commit -m "updated image version to tag ${COMMIT_HASH}" || true \
  && git push -set-upstream origin "${BRANCH}"

  cp application.yml ${WORKSPACE}/application.yml
}

delete_branch() {
  if [ "${BRANCH}" == "main" ] || [ "${BRANCH}" == "master" ]; then
    echo "Not allowed to delete main/master branch"
    exit 1
  fi
  cp "${WORKSPACE}"/"${REPO_NAME}"/application.yml "${WORKSPACE}"/application.yml
  cd "${WORKSPACE}/${REPO_NAME}" \
  && git checkout main \
  && git branch -d ${BRANCH} \
  && git config --global user.name "argo-ci" \
  && git config --global user.email "argo-ci@gepardec.com" \
  && git push origin :${BRANCH}
}

######################   handle options ###################

handle_options() {
local opts=$(getopt -o cu:b:p:n:t: -l argo-update,clone,url:,branch:,path:,name:,extract,tag:,argo-create,namespace: -- "$@")
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
    --clone | -c)
      DO_CLONE=true
      shift 1
      ;;
    --url | -u)
      CLONE_URL="${2}"
      shift 2
      ;;
    --branch | -b)
      BRANCH="${2}"
      DO_CHECKOUT=true
      shift 2
      ;;
    --name | -n)
      REPO_NAME="${2}"
      shift 2
      ;;
    --namespace)
      NAMESPACE="${2}"
      shift 2
      ;;
    --path | -p)
      WORKSPACE="${2}"
      shift 2
      ;;
    --extract)
      EXTRACT_TAG=true
      shift 1
      ;;
    --argo-update)
      UPDATE_ARGO=true
      shift 1
      ;;
    --argo-create)
      CREATE_ARGO=true
      shift 1
      ;;
    --argo-delete)
      DELETE_ARGO=true
      shift 1
      ;;
    --tag | -t)
      COMMIT_HASH="${2}"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

}


######################   MAIN ####################

main() {
  echo "$*"
  handle_options "$@"

  if [ "${CREATE_ARGO}" == true ]; then
    update_vars
    git_clone
    git_checkout
    update_namespace
  fi
  if [ "${DELETE_ARGO}" == true ]; then
    update_vars
    git_clone
    git_checkout
    delete_branch
  fi
  if [ "${UPDATE_ARGO}" == true ]; then
    update_vars
    git_clone
    git_checkout
    update_version
  fi
  if [ "${DO_CLONE}" == true ]; then
    git_clone
  fi
  if [ "${DO_CHECKOUT}" == true ]; then
    git_checkout
  fi
  if [ "${EXTRACT_TAG}" == true ]; then
    extract_git_commit
  fi
}

main "$@"



