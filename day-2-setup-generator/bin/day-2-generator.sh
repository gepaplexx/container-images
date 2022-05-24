#!/bin/sh
##### VARS ##############
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
normal=$(tput sgr0)

##### HELPERS ###########
function waitToContinue() {
    printf "\npress any key to continue..."
    read  -n 1
}

function replace() {
    export VARS="$1"
    cat generated/values-${ENV}.yaml | envsubst "$VARS" > generated/values-${ENV}.yaml.tmp
    [[ $? = 1 ]] && printFailureAndExit "Replacing environment variables"
    mv generated/values-${ENV}.yaml.tmp generated/values-${ENV}.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Overriding 'generated/values-${ENV}"
}

function printUsageAndExit() {
    printf "\nUsage: ./day-2-generator.sh [CONFIGFILE]\n"
    exit 1
}

function printHeader() {
    printf "${2}################################################################################\n"
    printf "# Name: Day-2-Operations Generator\n"
    printf "# Description: TODO\n"
    printf "# Author: gattma,fhochleitner\n"
    printf "# Version: v1.0\n"
    printf "# Documentation: https://gepardec.atlassian.net/wiki/spaces/G/pages/2393276417/Day-2-Operations\n"
    printf "# Configuration: ${1}\n"
    printf "################################################################################${normal}\n\n"
}

function printActionHeader() {
    printf "\n${2}################################################################################\n"
    printf "%*s\n" $(((${#1}+80)/2)) "${2}${1}"
    printf "################################################################################${normal}\n"
}

function printSuccess() {
    printf '\033[79`%s\n' "${green}OK${normal}"
}

function printFailure() {
    printf '\033[75`%s\n' "${red}FAILED${normal}"
}

function printFailureAndExit() {
    printf "${1} ${red}FAILED${normal}"
    exit 1
}

##### SURVEY ############
function generateCertificate() {
    printActionHeader "GENERATE SEALED SECRETS CERTIFICATE" $yellow
    if [[ -f "generated/${ENV}.key" ]] && [[ -f "generated/${ENV}.crt" ]]; then
        printf "Existing Certififactes found for Cluster: ${ENV}...\n"
        printf "Skipping generation and use existing files..."
        printSuccess
    else
      printf "Generating certificate and private key..."
      openssl req -x509 -nodes -newkey rsa:4096 -keyout "generated/${ENV}.key" -out "generated/${ENV}.crt" -subj "/CN=sealed-secret/O=sealed-secret" >> /dev/null
      [[ $? = 0 ]] && printSuccess || printFailureAndExit "Generating"
    fi
}

function encryptSealedSecretCertificateForAnsibleVault() {
    printActionHeader "ENCRYPT SEALED SECRET CERTIFICATE FOR VAULT" $yellow
    printf "Enter Ansible-Vault-Password: "
    read -s password
    echo ${password} >> vault.password
    printf "\nEncrypting certificate for sealed secret..."
    ansible-vault encrypt_string --vault-password-file vault.password --name 'sealedSecretCertificate' -- "$(cat generated/${ENV}.crt | base64 -w0)" > generated/${ENV}-crt-vault.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Encrypting"

    printf "\nCopy the following part (red) into inventory-spoke-gepaplexx-${ENV}/group-vars/all/vault.yaml\n"
    printf "${red}$(cat generated/${ENV}-crt-vault.yaml)${normal}"
    
    waitToContinue

    printActionHeader "ENCRYPT SEALED SECRET KEY FOR VAULT" $yellow
    printf "Encrypting key for sealed secret..."
    ansible-vault encrypt_string --vault-password-file vault.password --name 'sealedSecretPrivateKey' -- "$(cat generated/${ENV}.key | base64 -w0)" > generated/${ENV}-key-vault.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Encrypting"

    printf "\nCopy the following part (red) into inventory-spoke-gepaplexx-${ENV}/group-vars/all/vault.yaml\n"
    printf "${red}$(cat generated/${ENV}-key-vault.yaml)${normal}"
    waitToContinue
    rm vault.password
    
}

function removeIdentityProvGoogle() {
    printf "Disable Identity Provider 'GOOGLE'..."
    sed -i .bak \
        '/name: "google.clientSecret"/,+1d;/name: "google.clientId"/,+1d;/name: "google.restrDomain"/,+1d' \
        generated/values-${ENV}.yaml

    rm generated/*.bak
    export GOOGLE_ENABLE=false
    replace '$GOOGLE_ENABLE'
}

function removeIdentityProvGit() {
    printf "Disable Identity Provider 'GIT'..."
    sed -i .bak \
        '/name: "git.clientSecret"/,+1d;/name: "git.clientId"/,+1d;/name: "git.restrOrgs"/,+1d' \
        generated/values-${ENV}.yaml

    rm generated/*.bak
    export GIT_ENABLE=false
    replace '$GIT_ENABLE'
}

function configureIdentityProvGoogle() {    
    printf "generating sealed secret values for google oauth identity provider..."
    export GOOGLE_CLIENTSECRET=$(printf "$GOOGLE_CLIENTSECRET" | base64 -w0)
    export GOOGLE_CLIENTID=$(printf "$GOOGLE_CLIENTID" | base64 -w0)
    export GOOGLE_RESTRICTED_DOMAIN=$(printf "$GOOGLE_RESTRICTED_DOMAIN" | base64 -w0)

    cat templates/secret-ip-google.yaml.TEMPLATE \
        | envsubst '$GOOGLE_CLIENTSECRET:$GOOGLE_CLIENTID:$GOOGLE_RESTRICTED_DOMAIN' \
        | kubeseal --cert generated/${ENV}.crt -o yaml > generated/google-oauth-secret.yaml

    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Generating"
    printf "Replacing parameters in values-${ENV}.yaml..."
    
    export GOOGLE_CLIENTSECRET=$(cat generated/google-oauth-secret.yaml | grep clientSecret | cut -d ':' -f 2 | xargs)
    export GOOGLE_CLIENTID=$(cat generated/google-oauth-secret.yaml | grep clientId | cut -d ':' -f 2 | xargs)
    export GOOGLE_RESTRDOMAIN=$(cat generated/google-oauth-secret.yaml | grep restrDomain | cut -d ':' -f 2 | xargs)
    export GOOGLE_ENABLE=true

    replace '$GOOGLE_CLIENTSECRET:$GOOGLE_CLIENTID:$GOOGLE_RESTRDOMAIN:$GOOGLE_ENABLE'
    
    printf "Cleanup..."
    rm generated/google-oauth-secret.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Cleanup"
}

function configureIdentityProvGit() {
    printf "Generating sealed secret values for git oauth identity provider..."
    export GIT_CLIENTSECRET=$(printf "$GIT_CLIENTSECRET" | base64 -w0)
    export GIT_CLIENTID=$(printf "$GIT_CLIENTID" | base64 -w0)
    export GIT_RESTRICTED_ORGS=$(printf "$GIT_RESTRICTED_ORGS" | base64 -w0)

    cat templates/secret-ip-git.yaml.TEMPLATE \
        | envsubst '$GIT_CLIENTSECRET:$GIT_CLIENTID:$GIT_RESTRICTED_ORGS' \
        | kubeseal --cert generated/${ENV}.crt -o yaml > generated/github-oauth-secret.yaml

    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Generating"

    printf "Replacing parameters in values-${ENV}.yaml..."
    export GIT_CLIENTSECRET=$(cat generated/github-oauth-secret.yaml | grep clientSecret | cut -d ':' -f 2 | xargs)
    export GIT_CLIENTID=$(cat generated/github-oauth-secret.yaml | grep clientId | cut -d ':' -f 2 | xargs)
    export GIT_RESTRORGS=$(cat generated/github-oauth-secret.yaml | grep restrOrgs | cut -d ':' -f 2 | xargs)
    export GIT_ENABLE=true

    replace '$GIT_CLIENTSECRET:$GIT_CLIENTID:$GIT_RESTRORGS:$GIT_ENABLE'

    printf "Cleanup..."
    rm generated/github-oauth-secret.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Cleanup"
}

function configureClusterUpdater() {
    printf "Generating values for cluster updater..."
    export ENV=${ENV}
    export CONSOLE_URL=$CONSOLE_URL
    export SLACK_B64=$(printf "$SLACK_CHANNEL_CU" | base64 -w0)
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Generating"

    printf "Replacing parameters in values-${ENV}.yaml..."
    replace '$SLACK_B64:$CONSOLE_URL:${ENV}'
}

function configureClusterConfig() {
    printf "Generating sealed secret value for alertmanager..."

    if [ -z $ALERTMANAGER_CONFIG ]
    then
        export ENV=${ENV}
        export SLACK_CHANNEL_AM=$SLACK_CHANNEL_AM
        cat templates/default-alertmanager.yaml.TEMPLATE \
            | envsubst '${ENV}:$SLACK_CHANNEL_AM' > generated/alertmanager.yaml
        AM_YAML=generated/alertmanager.yaml
    else
        AM_YAML=$ALERTMANAGER_CONFIG
    fi
    
    export ALERTMANAGER_CONFIG=$(cat $AM_YAML | base64 -w0)
    cat templates/secret-alertmanager.yaml.TEMPLATE \
        | envsubst '$ALERTMANAGER_CONFIG' \
        | kubeseal --cert generated/${ENV}.crt -o yaml > generated/alertmanager-secret.yaml

    export GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_USERNAME=$( printf "$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_USERNAME" | base64 -w0)
    export GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_SSHPRIVATEKEY=$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_SSHPRIVATEKEY
    export GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_ENABLED=$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_ENABLED
    cat templates/secret-cicd-repository-git.yaml.TEMPLATE \
        | envsubst '$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_USERNAME:$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_SSHPRIVATEKEY:$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_ENABLED' \
        | kubeseal --cert generated/${ENV}.crt -o yaml > generated/cicd-repository-git-secret.yaml

    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Generating"

    printf "Replacing parameters in values-${ENV}.yaml..."
    export ENCRYPTED_YAML=$(cat generated/alertmanager-secret.yaml | grep alertmanager.yaml | cut -d ':' -f 2 | xargs)
    export GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_USERNAME=$(cat generated/cicd-repository-git-secret.yaml | grep username | cut -d ':' -f 2 | xargs)
    export GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_SSHPRIVATEKEY=$(cat generated/cicd-repository-git-secret.yaml | grep sshPrivateKey | cut -d ':' -f 2 | xargs)
    replace '$ENCRYPTED_YAML:$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_USERNAME:$GITHUB_CICD_TOOLS_WORKFLOWREPOSITORY_SSHPRIVATEKEY'

    printf "Cleanup..."
    rm generated/alertmanager-secret.yaml
    rm generated/alertmanager.yaml
    rm generated/cicd-repository-git-secret.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Cleanup"
}

function configureRookCeph() {
    [[ ${ENABLE_ROOK_CEPH} = true ]] && printf "Enable Rook/Ceph deployment..." || printf "Disable Rook/Ceph deployment...";
    export ENABLE_ROOK_CEPH=$ENABLE_ROOK_CEPH
    replace '$ENABLE_ROOK_CEPH'
}

function configureClusterLogging() {
    [[ ${ENABLE_CLUSTER_LOGGING} = true ]] && printf "Enable ClusterLogging deployment..." || printf "Disable ClusterLogging deployment...";
    export ENABLE_CLUSTER_LOGGING=$ENABLE_CLUSTER_LOGGING
    replace '$ENABLE_CLUSTER_LOGGING'
}

function configureClusterCertificates() {
    printf "Replace custom url for certificate patches..."
    export APISERVER_CUSTOMURL=$APISERVER_CUSTOMURL
    replace '$APISERVER_CUSTOMURL'

    printf "Configure cluster issuer solvers..."
    export SOLVERS_DNS_ZONE=$SOLVERS_DNS_ZONE
    export SOLVERS_ACCESSKEYID=$SOLVERS_ACCESSKEYID
    export SOLVERS_SECRETNAME=$SOLVERS_SECRETNAME
    export SOLVERS_SECRETACCESSKEY=$(printf "$SOLVERS_SECRETACCESSKEY" | base64 -w0)
    cat templates/secret-route53-credentials-secret.yaml.TEMPLATE \
            | envsubst '$SOLVERS_SECRETACCESSKEY:$ENV' \
            | kubeseal --cert generated/${ENV}.crt -o yaml > generated/route-53-credentials-secret.yaml
    export SOLVERS_SECRETACCESSKEY=$(cat generated/route-53-credentials-secret.yaml | grep secret-access-key | cut -d ':' -f 2 | xargs)
    replace '$SOLVERS_DNS_ZONE:$SOLVERS_ACCESSKEYID:$SOLVERS_SECRETNAME:$SOLVERS_SECRETACCESSKEY'

    printf "Configure cluster issuer certificates..."
    export CERTIFICATES_DEFAULTINGRESS=$CERTIFICATES_DEFAULTINGRESS
    export CERTIFICATES_CONSOLE=$CERTIFICATES_CONSOLE
    export CERTIFICATES_API=$CERTIFICATES_API
    replace '$CERTIFICATES_DEFAULTINGRESS:$CERTIFICATES_CONSOLE:$CERTIFICATES_API'

    printf "Cleanup..."
    rm generated/route-53-credentials-secret.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Cleanup"
}

function configureConsolePatches() {
    printf "Replace hostname..."
    export ROUTE_HOSTNAME=$ROUTE_HOSTNAME
    replace '$ROUTE_HOSTNAME'
}

function configureGepaplexxCicdTools() {
    printf "Configure Gepaplexx CICD tools hostnames..."
    export GEPAPLEXX_CICD_TOOLS_ARGOCD_ROUTE_HOSTNAME=${GEPAPLEXX_CICD_TOOLS_ARGOCD_ROUTE_HOSTNAME}
    export GEPAPLEXX_CICD_TOOLS_ROLLOUTS_ROUTE_HOSTNAME=${GEPAPLEXX_CICD_TOOLS_ROLLOUTS_ROUTE_HOSTNAME}
    export GEPAPLEXX_CICD_TOOLS_WORKFLOWS_ROUTE_HOSTNAME=${GEPAPLEXX_CICD_TOOLS_WORKFLOWS_ROUTE_HOSTNAME}
    replace '$GEPAPLEXX_CICD_TOOLS_ARGOCD_ROUTE_HOSTNAME:$GEPAPLEXX_CICD_TOOLS_ROLLOUTS_ROUTE_HOSTNAME:$GEPAPLEXX_CICD_TOOLS_WORKFLOWS_ROUTE_HOSTNAME'


    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Generating"
    printf "Replacing parameters in values-${ENV}.yaml..."
    export GEPAPLEXX_CICD_TOOLS_PSQL_PASSWORD=$(printf "$GEPAPLEXX_CICD_TOOLS_PSQL_PASSWORD" | base64 -w0)
    export GEPAPLEXX_CICD_TOOLS_PSQL_POSTGRES_PASSWORD=$(printf "$GEPAPLEXX_CICD_TOOLS_PSQL_POSTGRES_PASSWORD" | base64 -w0)

    printf "generating sealed secret for cicd-tools postgres db..."
    cat templates/secret-postgresql-creds.yaml.TEMPLATE \
        | envsubst '$GEPAPLEXX_CICD_TOOLS_PSQL_PASSWORD:$GEPAPLEXX_CICD_TOOLS_PSQL_POSTGRES_PASSWORD' \
        | kubeseal --cert generated/${ENV}.crt -o yaml > generated/postgreql-creds-secret.yaml

    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Generating"
    printf "Replacing parameters in values-${ENV}.yaml..."

    export GEPAPLEXX_CICD_TOOLS_PSQL_PASSWORD=$(cat generated/postgreql-creds-secret.yaml | grep -E "(^| )password" | cut -d ':' -f 2 | xargs)
    export GEPAPLEXX_CICD_TOOLS_PSQL_POSTGRES_PASSWORD=$(cat generated/postgreql-creds-secret.yaml | grep postgres-password | cut -d ':' -f 2 | xargs)

    replace '$GEPAPLEXX_CICD_TOOLS_PSQL_PASSWORD:$GEPAPLEXX_CICD_TOOLS_PSQL_POSTGRES_PASSWORD'

    printf "Cleanup..."
    rm generated/postgreql-creds-secret.yaml
    [[ $? = 0 ]] && printSuccess || printFailureAndExit "Cleanup"
}

function checkPrerequisites() {
    ok=true
    printf "envsubst is installed..."
    which envsubst >> /dev/null
    [[ $? = 0 ]] && printSuccess || { ok=false; printFailure; }
    
    printf "ansible is installed..."
    which ansible >> /dev/null
    [[ $? = 0 ]] && printSuccess || { ok=false; printFailure; }

    printf "ansible-vault is installed..."
    which ansible-vault >> /dev/null
    [[ $? = 0 ]] && printSuccess || { ok=false; printFailure; }

    printf "kubeseal is installed..."
    which kubeseal >> /dev/null
    [[ $? = 0 ]] && printSuccess || { ok=false; printFailure; }

    printf "openssl is installed..."
    which openssl >> /dev/null
    [[ $? = 0 ]] && printSuccess || { ok=false; printFailure; }

    [[ $ok = false ]] && { printf "\n${red}Check failed! Please install the necessary tools.${normal}"; exit 1; }
}

function main() {
    [[ -z ${1} ]] && { printUsageAndExit; }
    [[ ! -f ${1} ]] && { echo "File not found: '${1}'"; exit 1; }

    printHeader "${1}" $blue
    . ${1}

    printActionHeader "CHECK PREREQUISITES" $yellow
    checkPrerequisites

    mkdir -p generated
    cp templates/day-2-ops-values.yaml.TEMPLATE generated/values-${ENV}.yaml
    [[ $? = 1 ]] && printFailureAndExit "Copying day-2-ops-values-TEMPLATE"
    
    waitToContinue

    generateCertificate
    encryptSealedSecretCertificateForAnsibleVault

    printActionHeader "CONFIGURE IDENTITY PROVIDER" $yellow
    [[ ${ENABLE_GOOGLE_IP} = true ]] && configureIdentityProvGoogle || removeIdentityProvGoogle;
    [[ ${ENABLE_GIT_IP} = true ]] && configureIdentityProvGit || removeIdentityProvGit;

    printActionHeader "CONFIGURE CLUSTER UPDATER" $yellow
    configureClusterUpdater

    printActionHeader "CONFIGURE CLUSTER CONFIG" $yellow
    configureClusterConfig

    printActionHeader "CONFIGURE ROOK/CEPH INSTANCE" $yellow
    configureRookCeph

    printActionHeader "CONFIGURE CLUSTER LOGGING" $yellow
    configureClusterLogging

    printActionHeader "CONFIGURE CLUSTER CERTIFICATES" $yellow
    configureClusterCertificates

    printActionHeader "CONFIGURE CONSOLE PATCHES" $yellow
    configureConsolePatches

    printActionHeader "CONFIGURE GEPAPLEXX CICD TOOLS" $yellow
    configureGepaplexxCicdTools

    printActionHeader "SUMMARY" $green
    printf "Successfully generated values for environment '${ENV}': generated/values-${ENV}.yaml\n"
    printf "Copy these file to https://github.com/gepaplexx/gp-helm-chart-development/tree/main/day-2-operations/gp-cluster-setup/values \n"
}

# 1 .. Config file
main "${1}"