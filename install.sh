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
  [ -d "$path" ] && error_exit "The directory $path is already exists."
  mkdir -p "$path"
  echo $(cd $path; pwd)
}

askRequiredField() {
  local promptMessage="$1"
  local result=
  while [ -z "$result" ]
  do
    read -r -p "$1: " result
    [ -z "$result" ] && echo "This is required field. Please try again."
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
  openssl dgst -sha256 -verify release.pub -signature launcher.sha256 launcher.checksum || error_exit "Signature verification is failed"
  cd -
}

canBeInstalledAsService() {
  [[ $(id -u) -eq 0 ]] && return;

  echo "Do you have a root access for the infrastracture environment?"
  select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "Run the install script under your root user."
              echo "The root access is required to install and configure a new service."
          exit;;
        No ) 
          return 2
          break;;
    esac
  done
}

isNonProductionEnvironment() {
  echo "Are you installing agent on the non-production environment?"
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
  local cronContent=$(crontab -l)
  local agentCommand="* * * * * flock -n /tmp/swat-agent.lockfile -c '. $agentPath/swat-agent.env; $agentPath/scheduler' >> $agentPath/errors.log 2>&1"
  if [[ ! ($cronContent =~ "swat-agent") ]]; then
     (crontab -l; echo "$agentCommand") | crontab -
  fi
}

installAndConfigureDaemon() {
  echo "Next step: Configure agent as a daemon service. Follow the installation guide 'Agent as a daemon service'"
}

checkDependencies "php" "wget" "awk" "nice" "grep" "openssl"
# /usr/local/swat-agent see: https://refspecs.linuxfoundation.org/FHS_2.3/fhs-2.3.html
canBeInstalledAsService && installDaemon=1
sandboxEnv=False
isNonProductionEnvironment && sandboxEnv=True
[ "$installDaemon" ] && echo "Installing as a service" || echo "Installing agent as a cron"
agentPath=$(askWriteableDirectory "Where to download Site Wide Analysis Agent" "/usr/local/")
echo "Site Wide Analysis Agent will be installed into $agentPath"
appName=$(askRequiredField "Enter company or site name")

# Get Adobe Commerce Application Root
while [[ -z "$appRoot" ]] || [[ -z "$(ls -A $appRoot)" ]] || [[ -z "$(ls -A $appRoot/app/etc)" ]] || [[ ! -f "$appRoot/app/etc/env.php" ]]
do
  read -e -r -p "Enter Adobe Commerce Application Root (default:/var/www/html): " appRoot
  appRoot=${appRoot:-/var/www/html}
  if [[ ! -f "$appRoot/app/etc/env.php" ]]; then
    echo "The directory $appRoot is not the Adobe Commerce Application Root"
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

[ -d "$agentPath" ] && [ ! -z "$(ls -A "$agentPath")" ] && error_exit "Site Wide Analysis Tool Agent Directory $agentPath is not empty. Review and remove it <rm -r $agentPath>"

set -x
wget -qP "$agentPath" "https://$updaterDomain/launcher/launcher.linux-amd64.tar.gz"
tar -xf "$agentPath/launcher.linux-amd64.tar.gz" -C "$agentPath"
set +x
[ "$checkSignature" == "1" ] && verifySignature
[ "$installDaemon" ] && installAndConfigureDaemon || installAndConfigureCron

exportVariables="export "
[ "$installDaemon" ] && exportVariables=""
echo "${exportVariables}SWAT_AGENT_APP_NAME=\"$appName\"" > "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_PHP_PATH=$phpPath" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_MAGENTO_PATH=$appRoot" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_DB_USER=$appConfigVarDBUser" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_DB_PASSWORD=$appConfigVarDBPass" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_DB_HOST=$appConfigVarDBHost" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_DB_PORT=$appConfigVarDBPort" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_DB_NAME=$appConfigVarDBName" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_DB_TABLE_PREFIX=$appConfigDBPrefix" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_APPLICATION_CHECK_REGISTRY_PATH=$agentPath/tmp" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_BACKEND_HOST=${backendDomain}:443" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_LOGIN_BACKEND_HOST=https://${authDomain}/site-wide-analysis-tool/login" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_RUN_CHECKS_ON_START=1" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_LOG_LEVEL=error" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_ENABLE_AUTO_UPGRADE=true" >> "$agentPath/swat-agent.env"
echo "${exportVariables}SWAT_AGENT_IS_SANDBOX=$sandboxEnv" >> "$agentPath/swat-agent.env"

printSuccess "Site Wide Analysis Tool Agent is successfully installed $agentPath"
[ "$installDaemon" ] && printSuccess "Site Wide Analysis Agent has been installed" || printSuccess "Cronjob is configured. Review the command crontab -l"
