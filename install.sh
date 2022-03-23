#!/usr/bin/env bash

set -Eeuo pipefail

installDaemon=
agentPath=
appName=
appRoot=
phpPath=${AGENT_INSTALLER_PHP:-"$(command -v php)"}
swatAgentDirName="swat-agent"
updaterDomain=${AGENT_INSTALLER_UPDATER:-"updater.swat.magento.com"}
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
  local defaultValue="$2"
  local path=
  read -e -r -p "$1 (default: $2): " path
  path=${path:-$defaultValue}
  path="$path/$swatAgentDirName"
  path="$(echo "$path" | sed 's/\/\//\//g')"
  [ -d "$path" ] && error_exit "The directory $path already exists."
  mkdir -p "$path"
  echo "$(cd "$path"; pwd)"
}

askRequiredField() {
  local result=
  while [ -z "$result" ]
  do
    read -r -p "$1: " result
    [ -z "$result" ] && echo "This is a required field. Please try again."
  done
  echo "$result"
}

printSuccess() {
  local msg=( "$@" )
  green="$(tput setaf 2)"
  reset="$(tput sgr0)"
  echo "${green}${msg[@]}${reset}"
}

verifySignature() {
  echo -n "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUE0M2FBTk1WRXR3eEZBdTd4TE91dQpacG5FTk9pV3Y2aXpLS29HendGRitMTzZXNEpOR3lRS1Jha0MxTXRsU283VnFPWnhUbHZSSFhQZWt6TG5vSHVHCmdmNEZKa3RPUEE2S3d6cjF4WFZ3RVg4MEFYU1JNYTFadzdyOThhenh0ZHdURVh3bU9GUXdDcjYramFOM3ErbUoKbkRlUWYzMThsclk0NVJxWHV1R294QzBhbWVoakRnTGxJUSs1d1kxR1NtRGRiaDFJOWZqMENVNkNzaFpsOXFtdgorelhjWGh4dlhmTUU4MUZsVUN1elRydHJFb1Bsc3dtVHN3ODNVY1lGNTFUak8zWWVlRno3RFRhRUhMUVVhUlBKClJtVzdxWE9kTGdRdGxIV0t3V2ppMFlrM0d0Ylc3NVBMQ2pGdEQzNytkVDFpTEtzYjFyR0VUYm42V3I0Nno4Z24KY1Q4cVFhS3pYRThoWjJPSDhSWjN1aFVpRHhZQUszdmdsYXJSdUFacmVYMVE2ZHdwYW9ZcERKa29XOXNjNXlkWApBTkJsYnBjVXhiYkpaWThLS0lRSURnTFdOckw3SVNxK2FnYlRXektFZEl0Ni9EZm1YUnJlUmlMbDlQMldvOFRyCnFxaHNHRlZoRHZlMFN6MjYyOU55amgwelloSmRUWXRpdldxbGl6VTdWbXBob1NrVnNqTGtwQXBiUUNtVm9vNkgKakJmdU1sY1JPeWI4TXJCMXZTNDJRU1MrNktkMytwR3JyVnh0akNWaWwyekhSSTRMRGwrVzUwR1B6LzFkeEw2TgprZktZWjVhNUdCZm00aUNlaWVNa3lBT2lKTkxNa1cvcTdwM200ejdUQjJnbWtldm1aU3Z5MnVMNGJLYlRoYXRlCm9sdlpFd253WWRxaktkcVkrOVM1UlNVQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQ==" | base64 -d > "$agentPath/release.pub"

  cd "$agentPath"
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

askIsProductionEnvironment() {
  echo "Do you install the agent on a production environment?"
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
  local cronContent
  local agentCommand
  cronContent="$(crontab -l)"
  agentCommand="* * * * * flock -n /tmp/swat-agent.lockfile -c '$agentPath/scheduler' >> $agentPath/errors.log 2>&1"
  if [[ ! ("$cronContent" =~ "swat-agent") ]]; then
     printSuccess "Please configure cron to run the agent using the following command:"
     printSuccess "(crontab -l; echo \"$agentCommand\") | crontab -"
  fi
}

installAndConfigureDaemon() {
  printSuccess "Next steps: Configure the agent as a daemon service. Follow the installation guide https://devdocs.magento.com/tools/site-wide-analysis.html#run-the-agent"
}

checkDependencies "php" "wget" "awk" "nice" "grep" "openssl"
# /usr/local/swat-agent see: https://refspecs.linuxfoundation.org/FHS_2.3/fhs-2.3.html
canBeInstalledAsService && installDaemon=1
sandboxEnv=false
askIsProductionEnvironment || sandboxEnv=true
[ "$installDaemon" ] && echo "Installing as a service." || echo "Installing agent as a cron."
agentPath=$(askWriteableDirectory "Where to download the Site Wide Analysis Agent? " "/usr/local/")
echo "Site Wide Analysis Agent will be installed into $agentPath"
appName=$(askRequiredField "Enter the company or the site name: ")

# Get Adobe Commerce Application Root
while [[ -z "$appRoot" ]] || [[ -z "$(ls -A "$appRoot")" ]] || [[ -z "$(ls -A "$appRoot/app/etc")" ]] || [[ ! -f "$appRoot/app/etc/env.php" ]]
do
  read -e -r -p "Enter the Adobe Commerce Application Root directory (default:/var/www/html): " appRoot
  appRoot=${appRoot:-/var/www/html}
  if [[ ! -f "$appRoot/app/etc/env.php" ]]; then
    echo "Directory $appRoot is not an Adobe Commerce Application Root."
    continue
  fi
  appRoot="$(cd "$appRoot"; pwd)"
done

appConfigVarDBName=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['dbname']);")
appConfigVarDBUser=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['username']);")
appConfigVarDBPass=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['connection']['default']['password']);")
appConfigVarDBHost=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; \$host = \$config['db']['connection']['default']['host']; echo(strpos(\$host,':')!==false?reset(explode(':', \$host)):\$host);")
appConfigVarDBPort=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; \$host = \$config['db']['connection']['default']['host']; echo(strpos(\$host,':')!==false?end(explode(':', \$host)):'3306');")
appConfigDBPrefix=$($phpPath -r "\$config = require '$appRoot/app/etc/env.php'; echo(\$config['db']['table_prefix']);")

[ -d "$agentPath" ] && [ -n "$(ls -A "$agentPath")" ] && error_exit "The Site Wide Analysis Tool Agent Directory $agentPath is not empty. Please review and remove it <rm -r $agentPath>"

set -x
wget -qP "$agentPath" "https://$updaterDomain/launcher/launcher.linux-amd64.tar.gz"
tar -xf "$agentPath/launcher.linux-amd64.tar.gz" -C "$agentPath"
set +x
[ "$checkSignature" == "1" ] && verifySignature

cat << EOF > "$agentPath/config.yaml"
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

printSuccess "The Site Wide Analysis Tool Agent has been successfully installed at $agentPath"
if [ "$installDaemon" ]
then
  installAndConfigureDaemon
else
  installAndConfigureCron
fi
