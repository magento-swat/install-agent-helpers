#!/usr/bin/env bash

set -Eeuo pipefail

installDaemon=
agentPath=
appName=
agentConfigPath=
appRoot=
phpPath=${AGENT_INSTALLER_PHP:-"$(command -v php)"}
swatAgentDirName="swat-agent"
updaterDomain=${AGENT_INSTALLER_UPDATER:-"updater.swat.magento.com"}
authDomain=${AGENT_INSTALLER_AUTH:-"commerce.adobe.io"}
backendDomain=${AGENT_INSTALLER_BACKEND:-"check.swat.magento.com"}
checkSignature=${AGENT_INSTALLER_CHECK_SIGNATURE:-"1"}

error_exit() {
  echo "$1" 1>&2
  exit 255
}

checkDependencies() {
  for dep in "$@"
  do
    command -v $dep >/dev/null 2>&1 || error_exit "$dep is required"
  done
}

askWriteableDirectory() {
  local promptMessage="$1"
  local defaultValue="$2"
  local path=
  read -e -r -p "$1 (default: $2): " path
  path=${path:-$defaultValue}
  path="$path/$swatAgentDirName"
  path="$(echo $path | sed 's/\/\//\//g')"
  [ -d "$path" ] && error_exit "The directory $path already exists."
  mkdir -p "$path"
  echo $(cd $path; pwd)
}

askRequiredField() {
  local promptMessage="$1"
  local result=
  while [ -z "$result" ]
  do
    read -r -p "$1: " result
    [ -z "$result" ] && echo "This is a required field. Please try again."
  done
  echo $result
}

printSuccess() {
  local msg="$@"
  red=`tput setaf 1`
  green=`tput setaf 2`
  reset=`tput sgr0`
  echo "${green}${msg}${reset}"
}

verifySignature() {
  echo -n "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUE0M2FBTk1WRXR3eEZBdTd4TE91dQpacG5FTk9pV3Y2aXpLS29HendGRitMTzZXNEpOR3lRS1Jha0MxTXRsU283VnFPWnhUbHZSSFhQZWt6TG5vSHVHCmdmNEZKa3RPUEE2S3d6cjF4WFZ3RVg4MEFYU1JNYTFadzdyOThhenh0ZHdURVh3bU9GUXdDcjYramFOM3ErbUoKbkRlUWYzMThsclk0NVJxWHV1R294QzBhbWVoakRnTGxJUSs1d1kxR1NtRGRiaDFJOWZqMENVNkNzaFpsOXFtdgorelhjWGh4dlhmTUU4MUZsVUN1elRydHJFb1Bsc3dtVHN3ODNVY1lGNTFUak8zWWVlRno3RFRhRUhMUVVhUlBKClJtVzdxWE9kTGdRdGxIV0t3V2ppMFlrM0d0Ylc3NVBMQ2pGdEQzNytkVDFpTEtzYjFyR0VUYm42V3I0Nno4Z24KY1Q4cVFhS3pYRThoWjJPSDhSWjN1aFVpRHhZQUszdmdsYXJSdUFacmVYMVE2ZHdwYW9ZcERKa29XOXNjNXlkWApBTkJsYnBjVXhiYkpaWThLS0lRSURnTFdOckw3SVNxK2FnYlRXektFZEl0Ni9EZm1YUnJlUmlMbDlQMldvOFRyCnFxaHNHRlZoRHZlMFN6MjYyOU55amgwelloSmRUWXRpdldxbGl6VTdWbXBob1NrVnNqTGtwQXBiUUNtVm9vNkgKakJmdU1sY1JPeWI4TXJCMXZTNDJRU1MrNktkMytwR3JyVnh0akNWaWwyekhSSTRMRGwrVzUwR1B6LzFkeEw2TgprZktZWjVhNUdCZm00aUNlaWVNa3lBT2lKTkxNa1cvcTdwM200ejdUQjJnbWtldm1aU3Z5MnVMNGJLYlRoYXRlCm9sdlpFd253WWRxaktkcVkrOVM1UlNVQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQ==" | base64 -d > $agentPath/release.pub

  cd $agentPath;
  openssl dgst -sha256 -verify release.pub -signature launcher.sha256 launcher.checksum || error_exit "Signature verification failed."
  cd -
}

canBeInstalledAsService() {
  [[ $(id -u) -eq 0 ]] && return;

  echo "Do you have root access to the infrastructure environment?"
  select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "Run the install script as the root user."
              echo "Root access is required to install and configure this service."
          exit;;
        No ) 
          return 2
          break;;
    esac
  done
}

isNonProductionEnvironment() {
  echo "Are you installing an agent on a non-production environment?"
  select yn in "Yes" "No"; do
    case $yn in
        Yes )
          return 0
          exit;;
        No ) 
          return 2
          break;;
    esac
  done
}

installAndConfigureCron() {
  local cronContent="$(crontab -l)"
  local agentCommand="* * * * * flock -n /tmp/swat-agent.lockfile -c '$agentPath/scheduler' >> $agentPath/errors.log 2>&1"
  if [[ ! ("$cronContent" =~ "swat-agent") ]]; then
     (crontab -l; echo "$agentCommand") | crontab -
  fi
  printSuccess "The cronjob has been configured. Review your cronjobs with the following command crontab -l"
}

installAndConfigureDaemon() {
  printSuccess "Next steps: Configure the agent as a daemon service. Follow the installation guide https://devdocs.magento.com/tools/site-wide-analysis.html#run-the-agent"
}

checkDependencies "php" "wget" "awk" "nice" "grep" "openssl"
# /usr/local/swat-agent see: https://refspecs.linuxfoundation.org/FHS_2.3/fhs-2.3.html
canBeInstalledAsService && installDaemon=1
sandboxEnv=false
isNonProductionEnvironment && sandboxEnv=true
[ "$installDaemon" ] && echo "Installing as a service." || echo "Installing agent as a cron."
agentPath=$(askWriteableDirectory "Where to download the Site Wide Analysis Agent? " "/usr/local/")
echo "Site Wide Analysis Agent will be installed into $agentPath"
appName=$(askRequiredField "Enter the company or the site name: ")

# Get Adobe Commerce Application Root
while [[ -z "$appRoot" ]] || [[ -z "$(ls -A $appRoot)" ]] || [[ -z "$(ls -A $appRoot/app/etc)" ]] || [[ ! -f "$appRoot/app/etc/env.php" ]]
do
  read -e -r -p "Enter the Adobe Commerce Application Root directory (default:/var/www/html): " appRoot
  appRoot=${appRoot:-/var/www/html}
  if [[ ! -f "$appRoot/app/etc/env.php" ]]; then
    echo "Directory $appRoot is not an Adobe Commerce Application Root."
    continue
  fi
  appRoot="$(cd $appRoot; pwd)"
done

appConfigVarDBName=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['dbname']);")
appConfigVarDBUser=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['username']);")
appConfigVarDBPass=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['password']);")
appConfigVarDBHost=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; \$host = \$config['db']['connection']['default']['host']; echo(strpos(\$host,':')!==false?reset(explode(':', \$host)):\$host);")
appConfigVarDBPort=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; \$host = \$config['db']['connection']['default']['host']; echo(strpos(\$host,':')!==false?end(explode(':', \$host)):'3306');")
appConfigDBPrefix=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['table_prefix']);")

[ -d "$agentPath" ] && [ ! -z "$(ls -A "$agentPath")" ] && error_exit "The Site Wide Analysis Tool Agent Directory $agentPath is not empty. Please review and remove it <rm -r $agentPath>"

set -x
wget -qP "$agentPath" "https://$updaterDomain/launcher/launcher.linux-amd64.tar.gz"
tar -xf "$agentPath/launcher.linux-amd64.tar.gz" -C "$agentPath"
set +x
[ "$checkSignature" == "1" ] && verifySignature

cat << EOF > $agentPath/config.yaml
project:
  appname: "$appName"
application:
  phppath: "$phpPath"
  magentopath: "$appRoot"
  redisserverpath: "localhost:9200"
  database:
    user: "$appConfigVarDBUser"
    password: "$appConfigVarDBPass"
    host: "$appConfigVarDBHost"
    dbname: "$appConfigVarDBName"
    port: "$appConfigVarDBPort"
    tableprefix: "$appConfigDBPrefix"
  checkregistrypath: "$agentPath/tmp"
  issandbox: $sandboxEnv
enableautoupgrade: true
runchecksonstart: true
loglevel: error
EOF

echo "** Install validation "

if [[ ! -f "$appRoot/app/etc/env.php" ]]; then
  error_exit "Magento not found."
else
  echo "Magento Found - OK"
fi

if nc -z $updaterDomain 443 2>/dev/null; then
    echo "Connect to API Server - OK"
else
    error_exit "Can not connect to API Server"
fi

if [ -f "$agentPath/config.yaml" ]; then
    echo "Config File is created - OK"
else
    error_exit "Config File was not created."
fi

phpVersion=$($phpPath -v | awk '{ print $2 }' | head -1)
semver=( ${phpVersion//./ } )
major="${semver[0]}"
minor="${semver[1]}"

echo "**Checking php version."

if [ "$major" -eq 7 ]; then
    if [ "$minor" -gt 2 ]; then
        echo "php version - OK"
    else
        echo "You can specify another phpPath using env AGENT_INSTALLER_PHP."
        error_exit "php engine reachable by $phpPath is $phpVersion and is not supported."
    fi
else
    echo "php version - OK"
fi

mkdir $agentPath/tmp

if [ -w "$agentPath/tmp" ] ; then
  echo "Temporary Folder is writeable - OK"
else
  error_exit "Temporary Folder in agent directory is not writable"
fi
firstRun=$("$agentPath/scheduler")
if [[ "$firstRun" == *"is going to update"* ]]; then
  printSuccess "The Site Wide Analysis Tool Agent has been successfully installed at $agentPath"
  [ "$installDaemon" ] && installAndConfigureDaemon || installAndConfigureCron
else
  error_exit "Failed to update launcher"
fi
