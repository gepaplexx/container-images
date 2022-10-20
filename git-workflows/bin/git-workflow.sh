#!/bin/bash

PRG=`basename $0`

DIR=$(dirname $0)
BASEDIR=${DIR-.}/..
HOME=/root

######################### variables   #################
DO_CLONE=false
DO_CHECKOUT=false
UPDATE_ARGO=false
UPDATE_ARGO_MULTIDIR=false
DELETE_ARGO=false
DELETE_ARGO_MULTIDIR=false
CREATE_ARGO=false
CREATE_ARGO_MULTIDIR=false
BRANCH="main"
ENVIRONMENT="main"
NAMESPACE=""
CLONE_URL=""
REPO_NAME="sources"
WORKSPACE="/mnt/out"
COMMIT_HASH=""
CI_REPOSITORY_SUFFIX="ci"
IMAGE_TAG_LOCATION=""
DEFAULT_IMAGE_TAG_LOCATION=true
DEPLOY_FROM_BRANCH=""
DEPLOY_TO_BRANCH=""
DEPLOY_MULTIDIR=false
######################### print usage #################

print_usage(){
cat <<EOF 1>&2
usage: $PRG [-hE]

Options:
    c | clone:                  Clone a git repository
    u | url:                    Clone url of the git repository
    b | branch:                 Switches to specific branch. Default: main
    p | path:                   directory of workspace
    n | name:                   name of the git repository
    t | tag:                    allows override of image tag for argo update. Default: commit-hash
    - | image-tag-location:     allows to override the path to the image tag in application.yaml. Default: .image.tag
    - | namespace:              namespace for argocd application update
    - | extract:                saves the commit hash as output to be used as image tag
    - | argo-update:            update existing argocd application (multibranch)
    - | argo-update-multidir:   update existing argocd application (multidirectory)
    - | argo-create:            create a new argocd application in $namespace (multibranch)
    - | argo-create-multidir:   create a new argocd application in $namespace (multidir)
    - | argo-delete:            deletes the corresponding $branch in infrastructure repository (multibranch)
    - | argo-delete-multidir:   deletes the corresponding $branch in infrastructure repository (multidir)
    - | from-branch:          source branch for deploying from one branch to another
    - | to-branch:            target branch for deploying from one branch to another
    - | deploy-multidir:   boolean flag to differentiate multibranch and multidir deployment

    h | help: This help

Function:
    performs various operations on a git repository

EOF
}

####################### helper ###################
formatOutput() {
  while IFS= read -r line; do
    log "$line"
  done
}

log() {
  printf "%s [git-workflows] %s\n" "$(date '+%Y-%m-%d %T')" "$1"
}

changedirOrExit() {
  set +e
  TARGET=$1
  log "switch to dir '$TARGET'"
  cd "$TARGET"
  ERR=$?
  if [ $ERR -ne 0 ]; then
    log "cannot switch into dir '$TARGET'"
    exit 1
  fi
  set -e
}

checkoutOrExit() {
  set +e
  MSG=$(git checkout "$1" 2>&1)
  ERR=$?
  log "$MSG"
  [ $ERR -ne 0 ] && exit 1
  set -e
}

####################### checkout ##################

# TODO: handle private repositories (https://stackoverflow.com/questions/2505096/clone-a-private-repository-github)

git_clone() {
  log "--- GIT CLONE ---"
  if [ -z "${CLONE_URL}" ]; then
      log "missing parameters: url"
      print_usage
      exit 1
  fi
  log "cloning '$CLONE_URL' into '${WORKSPACE}/${REPO_NAME}"
  git clone --depth 1 --recurse-submodules --shallow-submodules "${CLONE_URL}" "${WORKSPACE}"/"${REPO_NAME}" 2>&1 | formatOutput

}

git_checkout() {
  set +e
  log "--- GIT CHECKOUT ---"
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  git remote set-branches origin '*' | formatOutput
  git fetch | formatOutput
  log "checkout branch '${BRANCH}'"
  MSG=$(git checkout ${BRANCH} 2>&1)
  ERR=$?
  log "$MSG"
  if [ $ERR -ne 0 ]; then
      log "create new branch '${BRANCH}'"
      git checkout -b ${BRANCH} 2>&1 | formatOutput
  fi
  cd || exit 1
  set -e
}

extract_git_commit() {
  log "--- EXTRACT TAG ---"
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  COMMIT_HASH=$(git rev-parse --short HEAD)
  log "commit hash='${COMMIT_HASH}'"
  cd || exit 1
  log "write commit hash to '${WORKSPACE}/commit_hash'"
  echo "${COMMIT_HASH}" > "${WORKSPACE}/commit_hash"
}

update_vars() {
  log "--- UPDATE VARS ---"

  if [[ ${DEFAULT_IMAGE_TAG_LOCATION} ]]; then
    IMAGE_TAG_LOCATION=".${REPO_NAME}.image.tag"
  fi

  CLONE_URL="${CLONE_URL%.git}-${CI_REPOSITORY_SUFFIX}.git"
  REPO_NAME="${REPO_NAME}-${CI_REPOSITORY_SUFFIX}"
  log "IMAGE_TAG_LOCATION='${IMAGE_TAG_LOCATION}'; CLONE_URL='${CLONE_URL}'; REPO_NAME='${REPO_NAME}'"
}

update_version_multibranch() {
  log "--- UPDATE VERSION (multibranch) ---"
  export COMMIT_HASH
  export IMAGE_TAG_LOCATION
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  log "update image tag: ${IMAGE_TAG_LOCATION} = ${COMMIT_HASH}"
  yq -i "${IMAGE_TAG_LOCATION} = env(COMMIT_HASH)" values.yaml
  yq -i "${IMAGE_TAG_LOCATION} style=\"double\"" values.yaml
  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git add .
  git commit -m "updated image version to tag ${COMMIT_HASH}" 2>&1 | formatOutput
  git push 2>&1 | formatOutput
}

update_version_multidir() {
  log "--- UPDATE VERSION (multidir) ---"
  export COMMIT_HASH
  export IMAGE_TAG_LOCATION
  changedirOrExit "${WORKSPACE}/${REPO_NAME}/apps/env"

  log "update image tag: ${IMAGE_TAG_LOCATION} = ${COMMIT_HASH}"
  if [ $ENVIRONMENT == "main" ]
  then
    log "merge to main => update all envs except feature branches"
    for env in $(find . -mindepth 1 -maxdepth 1 -type d -not -name "*feature*")
    do
      log "updating values.yaml in directory '${env}'"
      yq -i "${IMAGE_TAG_LOCATION} = env(COMMIT_HASH)" "$env/values.yaml"
      yq -i "${IMAGE_TAG_LOCATION} style=\"double\"" "$env/values.yaml"
    done
  else
    # Update feature branches, etc.
    log "feature branch update => update values.yaml in directory ${ENVIRONMENT}"
    changedirOrExit "${ENVIRONMENT}"
    yq -i "${IMAGE_TAG_LOCATION} = env(COMMIT_HASH)" values.yaml
    yq -i "${IMAGE_TAG_LOCATION} style=\"double\"" values.yaml
  fi

  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git add .
  git commit -m "updated image version to tag ${COMMIT_HASH}" 2>&1 | formatOutput
  git push 2>&1 | formatOutput
}

yq_update_application() {
  log "--- YQ UPDATE APPLICATION ---"
  export REPO_NAME
  export NAMESPACE
  export BRANCH
  export NAME=${REPO_NAME%-${CI_REPOSITORY_SUFFIX}}-${NAMESPACE}

  log "updating .metadata.name to ${NAME} in $(pwd)/application.yaml}"
  log "updating .spec.destination.namespace to ${NAME} in $(pwd)/application.yaml}"
  log "updating .spec.source.targetRevision to ${BRANCH} in $(pwd)/application.yaml}"
  yq -i '.metadata.name = env(NAME) | .spec.destination.namespace = env(NAME) | .spec.source.targetRevision = env(BRANCH)' application.yaml
}

yq_update_application_multidir() {
  log "--- YQ UPDATE APPLICATION (multidir) ---"
  export NAMESPACE

  ELEMENT="{\"cluster\": \"${NAMESPACE}\", \"url\": \"https://kubernetes.default.svc\", \"branch\": \"main\"}"
  log "appending ${ELEMENT} to .spec.generators[0].list.elements in $(pwd)/argocd/applicationset.yaml}"
  yq -i ".spec.generators[0].list.elements += $ELEMENT" argocd/applicationset.yaml

  export SOURCE_VERSION=$(yq '.spec.generators[0].list.elements | map(select(.branch == "main")) | .[0].cluster' argocd/applicationset.yaml)
  log "creating directory for new branch: apps/env/${NAMESPACE}, source: apps/env/${SOURCE_VERSION}"
  cp -r "apps/env/${SOURCE_VERSION}" "apps/env/${NAMESPACE}"
}

update_namespace() {
  log "--- UPDATE NAMESPACE ---"
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  yq_update_application
  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git add .
  git commit -m "created branch ${BRANCH} and updated application.yaml" 2>&1 | formatOutput
  git push --set-upstream origin "${BRANCH}" 2>&1 | formatOutput
  log "WORKSPACE: ${WORKSPACE}; REPONAME: ${REPO_NAME}"
  log "copy '${WORKSPACE}/${REPO_NAME}/application.yaml' to '${WORKSPACE}/application.yaml'"
  cp "${WORKSPACE}/${REPO_NAME}/application.yaml" "${WORKSPACE}/application.yaml"
}

update_namespace_multidir() {
  log "--- UPDATE NAMESPACE (multidir) ---"
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  yq_update_application_multidir
  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git add .
  git commit -m "new folder '${NAMESPACE}' in apps/env, updated argocd/applicationset.yaml" 2>&1 | formatOutput
  git push 2>&1 | formatOutput
  log "WORKSPACE: ${WORKSPACE}; REPONAME: ${REPO_NAME}"
  log "copy '${WORKSPACE}/${REPO_NAME}/argocd/applicationset.yaml' to '${WORKSPACE}/argocd/application.yaml'"
  cp "${WORKSPACE}/${REPO_NAME}/argocd/applicationset.yaml" "${WORKSPACE}/application.yaml"
}

delete_branch() {
  log "--- DELETE BRANCH ---"
  if [ "${BRANCH}" == "main" ] || [ "${BRANCH}" == "master" ]; then
    log "Not allowed to delete main/master branch"
    exit 1
  fi
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  log "copy '${WORKSPACE}/${REPO_NAME}/application.yaml' to '${WORKSPACE}/application.yaml'"
  cp "${WORKSPACE}/${REPO_NAME}/application.yaml" "${WORKSPACE}/application.yaml"
  git checkout main 2>&1 | formatOutput
  git branch -D ${BRANCH} 2>&1 | formatOutput
  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git push origin :${BRANCH} 2>&1 | formatOutput
}

delete_branch_multidir() {
  log "--- DELETE BRANCH (multidir)---"
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  git checkout main 2>&1 | formatOutput

  log "removing ${NAMESPACE} from argocd/applicationset.yaml"
  yq -i "del(.spec.generators[0].list.elements[] | select(.cluster == \"${NAMESPACE}\"))" argocd/applicationset.yaml
  log "copy '${WORKSPACE}/${REPO_NAME}/argocd/applicationset.yaml' to '${WORKSPACE}/application.yaml'"
  cp "${WORKSPACE}/${REPO_NAME}/argocd/applicationset.yaml" "${WORKSPACE}/application.yaml"
  log "deleting directory ${NAMESPACE} from apps/env"
  rm -rf "apps/env/${NAMESPACE}"

  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git add .
  git commit -m "removed folder '${NAMESPACE}' from apps/env, updated argocd/applicationset.yaml" 2>&1 | formatOutput
  git push 2>&1 | formatOutput
}

update_deploy_branches() {
  REPO_NAME=$(echo "$REPO_NAME" | tr -d '"[]')
  DEPLOY_FROM_BRANCH=$(echo "$DEPLOY_FROM_BRANCH" | tr -d '"[]')
  DEPLOY_TO_BRANCH=$(echo "$DEPLOY_TO_BRANCH" | tr -d '"[]')
  log "new source branch: $DEPLOY_FROM_BRANCH"
  log "new target branch: $DEPLOY_TO_BRANCH"
}

deploy_from_to() {
  log "--- DEPLOY VERSION FROM $DEPLOY_FROM_BRANCH to $DEPLOY_TO_BRANCH ---"
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  git remote set-branches origin '*'
  git fetch
  checkoutOrExit "${DEPLOY_FROM_BRANCH}" # source ausgecheckt
  export IMAGE_TAG_LOCATION
  export VERSION=$(yq "${IMAGE_TAG_LOCATION}" values.yaml)
  checkoutOrExit "${DEPLOY_TO_BRANCH}"
  log "replace ${IMAGE_TAG_LOCATION} = $VERSION in $(pwd)/values.yaml"
  yq -i "${IMAGE_TAG_LOCATION} = env(VERSION)" values.yaml
  yq -i "${IMAGE_TAG_LOCATION} style=\"double\"" values.yaml
  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git add .
  git commit -m "updated image version to tag ${COMMIT_HASH}" 2>&1 | formatOutput
  git push 2>&1 | formatOutput

}

deploy_from_to_multibranch(){
  log "--- DEPLOY VERSION FROM $DEPLOY_FROM_BRANCH to $DEPLOY_TO_BRANCH multibranch-style---"
  #TODO handle feature-branches
  changedirOrExit "${WORKSPACE}/${REPO_NAME}"
  git remote set-branches origin '*'
  git fetch --unshallow
  checkoutOrExit "${DEPLOY_TO_BRANCH}"
  git config --global user.name "argo-ci"
  git config --global user.email "argo-ci@gepardec.com"
  git merge "${DEPLOY_FROM_BRANCH}"
  git push 2>&1 | formatOutput
}

######################   handle options ###################

handle_options() {
local opts=$(getopt -o cu:b:p:n:t: -l argo-update,argo-update-multidir,clone,url:,branch:,path:,name:,extract,tag:,argo-create,argo-create-multidir,namespace:,argo-delete,argo-delete-multidir,image-tag-location:,from-branch:,to-branch:,deploy-multidir -- "$@")
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
    --argo-update-multidir)
      UPDATE_ARGO_MULTIDIR=true
      shift 1
      ;;
    --argo-create)
      CREATE_ARGO=true
      shift 1
      ;;
    --argo-create-multidir)
      CREATE_ARGO_MULTIDIR=true
      shift 1
      ;;
    --argo-delete)
      DELETE_ARGO=true
      shift 1
      ;;
    --argo-delete-multidir)
      DELETE_ARGO_MULTIDIR=true
      shift 1
      ;;
    --tag | -t)
      COMMIT_HASH="${2}"
      shift 2
      ;;
    --image-tag-location)
      IMAGE_TAG_LOCATION="${2}"
      DEFAULT_IMAGE_TAG_LOCATION=false
      shift 2
      ;;
    --from-branch)
      DEPLOY_FROM_BRANCH="${2}"
      shift 2
      ;;
    --to-branch)
      DEPLOY_TO_BRANCH="${2}"
      shift 2
      ;;
    --deploy-multidir)
      DEPLOY_MULTIDIR=true
      shift 1
      ;;
    *)
      break
      ;;
  esac
done

}

######################   MAIN ####################

main() {
  log "$*"
  handle_options "$@"

  if [ "${DEPLOY_MULTIDIR}" == true ] && [ -n "${DEPLOY_FROM_BRANCH}" ] && [ -n "${DEPLOY_TO_BRANCH}" ]; then
    update_deploy_branches
    update_vars
    git_clone
    deploy_from_to_multibranch
    exit 0
  fi

  if [ -n "${DEPLOY_FROM_BRANCH}" ] && [ -n "${DEPLOY_TO_BRANCH}" ]; then
    update_deploy_branches
    update_vars
    git_clone
    deploy_from_to
    exit 0
  fi
  if [ "${CREATE_ARGO}" == true ]; then
    update_vars
    git_clone
    git_checkout
    update_namespace
    exit 0
  fi
  if [ "${CREATE_ARGO_MULTIDIR}" == true ]; then
    update_vars
    git_clone
    update_namespace_multidir
    exit 0
  fi
  if [ "${DELETE_ARGO}" == true ]; then
    update_vars
    git_clone
    git_checkout
    delete_branch
    exit 0
  fi
  if [ "${DELETE_ARGO_MULTIDIR}" == true ]; then
    update_vars
    git_clone
    delete_branch_multidir
    exit 0
  fi
  if [ "${UPDATE_ARGO}" == true ]; then
    update_vars
    git_clone
    git_checkout
    update_version_multibranch
    exit 0
  fi
  if [ "${UPDATE_ARGO_MULTIDIR}" == true ]; then
    ENVIRONMENT=${BRANCH}
    BRANCH="main"
    update_vars
    git_clone
    git_checkout
    update_version_multidir
    exit 0
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

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "${last_command} command exited with exit code $?."' EXIT

main "$@"



