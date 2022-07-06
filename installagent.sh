#!/bin/bash
## BRCM_COPYRIGHT_BEGIN,2021
## ================================================================================
## Copyright (c) 2021 Broadcom. All rights reserved. The term
## “Broadcom” refers to Broadcom Inc. and/or its subsidiaries.
## ================================================================================
##
## This software and all information contained therein is confidential and
## proprietary and shall not be duplicated, used, disclosed or disseminated in any
## way except as authorized by the applicable license agreement, without the
## express written permission of Broadcom. All authorized reproductions must be
## marked with this language.
##
## EXCEPT AS SET FORTH IN THE APPLICABLE LICENSE AGREEMENT, TO THE EXTENT
## PERMITTED BY APPLICABLE LAW OR AS AGREED BY BROADCOM IN ITS APPLICABLE LICENSE
## AGREEMENT, BROADCOM PROVIDES THIS DOCUMENTATION “AS IS” WITHOUT WARRANTY OF ANY
## KIND, INCLUDING WITHOUT LIMITATION, ANY IMPLIED WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE, OR NONINFRINGEMENT. IN NO EVENT WILL BROADCOM
## BE LIABLE TO THE END USER OR ANY THIRD PARTY FOR ANY LOSS OR DAMAGE, DIRECT OR
## INDIRECT, FROM THE USE OF THIS DOCUMENTATION, INCLUDING WITHOUT LIMITATION,
## LOST PROFITS, LOST INVESTMENT, BUSINESS INTERRUPTION, GOODWILL, OR LOST DATA,
## EVEN IF BROADCOM IS EXPRESSLY ADVISED IN ADVANCE OF THE POSSIBILITY OF SUCH
## LOSS OR DAMAGE.
## ================================================================================
## BRCM_COPYRIGHT_END,2021
MYNAME=${0}
MYDIR="$PWD"
_LOGFILE=sdcss_install.log
_LOGFILE_UPGRADE_STATUS=/var/log/sdcsslog/upgradestatus.log
MY_VERSION=2.2.6.38

# GENERAL FLAGS
DOWNLOAD=false
UNINSTALL=false
INSTALL=true
REBOOT=false
IMAGE=false
ENROLL=false
SIMPLE_INSTALL=false
CONFIGURE=false
UPDATE=false
UPDATE_KMOD=false
UPDATE_SCRIPTS=true
FORCE=false
RESET_STATE=false
UPDATE_REPO=false
ARG_ENABLE_PINNING=false
ARG_DISABLE_PINNING=false
REQUIRE_REBOOT_AFTER_INSTALL=false
DISABLE_REPO=false
REPO_ENABLE=${REPO_ENABLE:-0}
CAF_COMM_TEST=false
SAL_REPONAME=${SAL_REPONAME:-'SAL/1.0'}
CAF_PACKAGE=sdcss-caf
devRepo=false
verifyRepo=false
debugMode=false
localRepo=false
printPlatformInfo=false
SELINUX_STATUS=none
reRun=false
listAllRepo=false
validateProxy=false
NOAGENTSTART="/etc/noAgentStart"
RESPONSE_FILE="/etc/sisips/sdcss-agent.response"
INSTALLREG_FILE="/etc/sisips/install.reg"
SIS_CONF="/etc/symantec/sis/sis.conf"
SIS_DEFAULT_LOGDIR="/var/log/sdcsslog"
SIS_DEFAULT_INSTALLDIR="/opt/Symantec"
AGENTINI_FILE="/etc/sisips/agent.ini"
productStrDcsLinux="DcsLinuxSettings"
productStrSepLinux="SepLinuxSettings"
SAL_STR="Symantec Agent for Linux\n"
SDCSS_NAME="Symantec Data Center Security Server Agent (DCS)"
INSTALL_PARMS="$*"
POLICY_FILE_PATH="/etc/caf/policy/amd"

# CAF injectable parameters - CWP ONLY
##########ATTENTION###########
####Please replace the following CONFIGURATION PARAMETERS with appropriate vaules
#### i.e. Replace %SECRET_KEY%  with a proper key value etc...
#### NEW_SECRET_KEY="rrk23f9kfdf9ikfk"
#### NEW_CUST_ID="1k2k29dkkd90"
#### NEW_DOMAIN_ID="iowere1lk20kfks"
#### NEW_SERVER_ADDR="127.0.0.1"
#### NEW_PROTOCOL="http"
#### NEW_PROTOCOL="https"
#### NEW_SERVICE_PORTAL_NAME="dcs-service"
#### NEW_PROXYMODE="Manual"
#### NEW_PROXY_ADDR="127.0.0.1"
#### NEW_PROXY_PORT="3128"
#### NEW_PROXY_PROTOCOL="http"
#### NEW_PROXYUSERNAME="some_user"
#### NEW_PROXYPASSWORD="some_password"

NEW_SECRET_KEY="%SECRET_KEY%"
NEW_CUST_ID="%CUSTOMER_ID%"
NEW_DOMAIN_ID="%DOMAIN_ID%"
NEW_SERVER_ADDR="%SERVER_ADDR%"
NEW_PORT="%PORT%"
NEW_PROTOCOL="%PROTOCOL%"
NEW_SERVICE_PORTAL_NAME="%SERVICE_PORTAL_NAME%"
NEW_PROXYMODE="%PROXY_MODE%"
NEW_PROXY_ADDR="%PROXY_ADDR%"
NEW_PROXY_PORT="%PROXY_PORT%"
NEW_PROXY_PROTOCOL="http"
NEW_PROXYUSERNAME="%PROXY_USERNAME%"
NEW_PROXYPASSWORD="%PROXY_PASSWORD%"
NEW_TAGS="%NEW_TAGS%"

CVE_CONFIG_DIR=/etc/symantec/sep
BACKUP_DIR=/tmp/
PXY_PREFIX=6XXX96XXX9

start_debug()
{
   exec 2<&-       # Close STDERR FD
   exec 2>$_LOGFILE # Open STDOUT as LOG_FILE file for read and write.
   set -x          # Turn on shell debugging
   export SIS_DEBUG_MODE=true
   export debugMode=true
}

setAgentType()
{
  if [ -f "$INSTALLREG_FILE" ]; then
    _AGENT_TYPE=`grep AgentType "$INSTALLREG_FILE" | cut -d"=" -f2`
    if [ ! -z "$_AGENT_TYPE" ]; then
      log_msg "_AGENT_TYPE : $_AGENT_TYPE"
      AGENT_TYPE=$_AGENT_TYPE
      if [ "$UNINSTALL" = false ]; then
        [ "$_AGENT_TYPE" = "1" ] && AGENT_TYPE=5 && DCS_DUAL=true
        [ "$_AGENT_TYPE" = "3" ] && AGENT_TYPE=4
        [ "$AGENT_TYPE" = "1" ]  && DCS_DCS=true        
        [ "$AGENT_TYPE" = "4" ]  && SEPL_SEPL=true
        [ "$_AGENT_TYPE" = "5" ] && DUAL_DUAL=true
      fi
      export _AGENT_TYPE AGENT_TYPE
    else
      error 1 "Unable to detect AgentType in $INSTALLREG_FILE"
    fi
  else
    export AGENT_TYPE=4
  fi

  return 0
}

setProductFeature()
{
  # Query SEP product version from CAFConfig.ini if installed
  [ "$PRODUCT_VERSION" = "" ]  && [ -f $CAFCONFIGFILE ] && \
     PRODUCT_VERSION=`getValue sep_version $CAFCONFIGFILE 2>/dev/null`
  # Validate product_version form - should look like 14.3RU3
  case x$PRODUCT_VERSION in x[1-9][0-9]\.[1-9]RU[1-9]*) ;; *) PRODUCT_VERSION="";; esac

  SEP_VER=14.3
  REPO_NAME=${SAL_REPONAME}
  PRODUCT_VERSION=${PRODUCT_VERSION:-14.3RU4}
  SEP_RU_VERSION=`echo $PRODUCT_VERSION |sed 's/[1-9][1-9].[1-9]RU\(.\)/\1/'`
  case $SEP_RU_VERSION in ''|*[!0-9]*) SEP_RU_VERSION=3 ;; esac
  if [ "$SEP_RU_VERSION" ] && [ $SEP_RU_VERSION -lt 3 ]; then
    case $SEP_RU_VERSION in 1) SEP_MP_VERSION=1;; 2) SEP_MP_VERSION=0;; esac
    AGENT_PACKAGE=sdcss-sepagent
    OLD_AGENT_PKGS=(SYMCsdcss symcsdcss sdcss-agent sdcss)
  else
    SEP_MP_VERSION=0
    AGENT_PACKAGE=sdcss
    OLD_AGENT_PKGS=(SYMCsdcss symcsdcss sdcss-agent)
  fi

  
  if ( [ "$AGENT_TYPE" = "3" ] || [ "$AGENT_TYPE" = "4" ] ); then
     DAEMONS=(cafagent sisamdagent sisidsagent sisipsagent)
     export IPS_DISABLE=true
     export FIM_DISABLE=true
     export OS_FEATURES=DA
     MODULES=(sisevt sisap)     
  fi
  
  if [ "$AGENT_TYPE" = "5" ]; then
    OLD_AGENT_PKGS=(sdcss-agent)
    DAEMONS=(cafagent sisamdagent sisidsagent sisipsagent sisipsutil)
    MODULES=(sisevt sisap sisfim sisips)
    export OS_FEATURES=DPA
  fi
  
  ( [ "$_AGENT_TYPE" = "1" ] && [ "$AGENT_TYPE" = "5" ] ) && CONFIGURE=true

  return 0
}

validateDCSUpgrade()
{
  [ "$_AGENT_TYPE" != "1" ] && return 0
  
  pkgs_installed sdcss && error 1 "Unable detect sdcss package version"
  
  sdcss_pkg_ver=${PKGS_INSTALLED_VERSIONS[0]}
   
  if ( ! version_ge $sdcss_pkg_ver "6.9.2" ); then
    error 1 "Upgrade not supported from DCS version $sdcss_pkg_ver"
  fi
  
  local ret=0
  local log_str
  local sdcss_basedir=`grep SisInstallDir $SIS_CONF |awk -F= '{print $2}' | xargs`
  local sdcss_logdir=`grep SisLogDir $SIS_CONF |awk -F= '{print $2}' | xargs`
  [ -z "$sdcss_basedir" ] &&  { log_str="\"SisInstallDir\""; ret=1; }
  [ -z "$sdcss_logdir" ] &&  { log_str="$log_str${log_str:+" and "}\"SisLogDir\""; ret=1; }
  
  [ "$ret" = 1 ] && error 1 "$PRODUCT_NAME: $log_str not present in \"$SIS_CONF\"."

  [ "$sdcss_basedir" != "$SIS_DEFAULT_INSTALLDIR" ] && { log_str="Installation on custom path"; ret=1; }
  [ "$sdcss_logdir" != "$SIS_DEFAULT_LOGDIR" ] && { log_str="$log_str${log_str:+" and "}custom Log files path"; ret=1; }
  
  [ ! -z "$log_str" ] && log_str="$log_str is not supported."
  [ "$ret" = 1 ] && error 1 "$PRODUCT_NAME: $log_str"
  
  return 0
}

getProductConfig()
{
  # GENERIC SETTINGS
  DCSLOGFILE=/var/log/sdcsslog/`basename $_LOGFILE`
  REPO_URL=${REPO_URL:-linux-repo.us.securitycloud.symantec.com}
  REPO_URL_DEV=linux-repo.dev.gcp.sepadvanced.cloud
  REPO_URL_VERIFY=linux-repo.verify.gcp.sepadvanced.cloud
  REPO_URL_TRANSPORT=${REPO_URL_TRANSPORT:-https}
  REPO_GPG_CHECK=${REPO_GPG_CHECK:-1}
  TMOUT_SEC=60
  UPGRADE_FROM=""   # set to CWP,SEPFL,SAVFL,DCS or SEP (update from prior build)
  REQUEST_LICENSE="true"   # set default value to true
  CAF_SUPPORTED=1
  CAFCONFIGFILE=/etc/caf/CAFConfig.ini
  CAF_STORAGE_INI_FILE_PATH="/opt/Symantec/cafagent/bin/CAFStorage.ini"
  CAF_COMMUNICATION_LOG=/var/log/sdcss-caflog/connection.out
  AMDCONFIGFILE=/opt/Symantec/sdcssagent/AMD/system/AntiMalware.ini
  INSTALLER_SCRIPT=/usr/lib/symantec/installagent.sh
  # Create these files in Windows Azure Agent directory instead of redhat-centos/version directory
  # as this is common to all VM ext versions.
  VM_EXT_UPDATE_IN_PROGRESS_DIR="/var/lib/waagent"
  VM_EXT_UPDATE_IN_PROGRESS_FILE="$VM_EXT_UPDATE_IN_PROGRESS_DIR/.ScwpVmExtUpdateInProgress"
  VM_EXT_REBOOT_AFTER_INSTALL_FILE="$VM_EXT_UPDATE_IN_PROGRESS_DIR/.ScwpVmExtRebootAfterInstall"
  
  [ -f $CAFCONFIGFILE ] && PREV_PRODUCT_ID=`grep product_id= $CAFCONFIGFILE |cut -d= -f2`

  # Determine which product (CWP or SEP Linux)
  if [ -f ./manifest ] && ( [ $INSTALL = true ] || [ $UNINSTALL = true ] || [ $DOWNLOAD = true ] || [ "$versionOnly" = true ] || [ $CONFIGURE = true ] ); then
     sed -i 's/\r//' manifest
     . ./manifest
     ( [ "$product_id" = "CWP" ] || [ "$secret_key" ] || ( [ "$NEW_SECRET_KEY" ] && [ "$NEW_SECRET_KEY" != "%SECRET_KEY%" ] ) ) && PRODUCT_ID=CWP || \
        { [ "$product_id" ] && PRODUCT_ID=$product_id || PRODUCT_ID=SAEP; }
  elif [ "$PREV_PRODUCT_ID" ]; then PRODUCT_ID=$PREV_PRODUCT_ID
  elif [ ! -z "$NEW_SECRET_KEY" ] && [ "$NEW_SECRET_KEY" != "%SECRET_KEY%" ]; then
     PRODUCT_ID=CWP
   elif [ ! -z "$_AGENT_TYPE" ] && [ "$_AGENT_TYPE" = "1" ]; then
     PRODUCT_ID=DCS
     log_msg "continue for $PRODUCT_ID..."
   elif [ $INSTALL = true ] && [ $SIMPLE_INSTALL = false ] && [ "$NEW_SECRET_KEY" = "%SECRET_KEY%" ]; then
     printf "Please replace configuration parameters in $MYNAME" && exit 1
  fi
  [ -z "$PRODUCT_ID" ] && PRODUCT_ID=CWP  #Default to CWP

  case $PRODUCT_ID in
    DCS)
      PRODUCT_NAME="${SAL_STR}${SDCSS_NAME}"
      PRODUCT_VERSION=6.9.2
      REPO_NAME=${SAL_REPONAME}
      AGENT_PACKAGE=sdcss
      DAEMONS=(sisamdagent sisidsagent sisipsagent sisipsutil)
      MODULES=(sisips sisfim sisevt sisap)
      if [ ! -z "$SDCSSLOG_DIR" ]; then
        _LOGFILE_UPGRADE_STATUS="$SDCSSLOG_DIR/upgradestatus.log";
        DCSLOGFILE="$SDCSSLOG_DIR/`basename $_LOGFILE`"
        log_msg "_LOGFILE_UPGRADE_STATUS : $_LOGFILE_UPGRADE_STATUS"; 
        log_msg "DCSLOGFILE : $DCSLOGFILE"
      fi
      export OS_FEATURES=DPA
      export AGENT_TYPE=1 
    ;;

    CWP)
     PRODUCT_NAME="${SAL_STR}Cloud Workload Protection Agent (CWP)"
     PRODUCT_VERSION=${PRODUCT_VERSION:-1.6.1}
     REPO_NAME=cloud_agent_v${PRODUCT_VERSION}
     AGENT_PACKAGE=sdcss-agent
     OLD_AGENT_PKGS=(SYMCsdcss symcsdcss sdcss-sepagent sdcss)
     DAEMONS=(cafagent sisamdagent sisidsagent sisipsagent sisipsutil)
     MODULES=(sisips sisfim sisevt sisap)
     export OS_FEATURES=DPA
     export AGENT_TYPE=2

     # CAF SETTINGS
     #settings picked up from manifest
     NEW_SECRET_KEY=${secret_key:-$NEW_SECRET_KEY}
     NEW_CUST_ID=${customer_id:-$NEW_CUST_ID}
     NEW_DOMAIN_ID=${domain_id:-$NEW_DOMAIN_ID}
     NEW_SERVER_ADDR=${server_addr:-$NEW_SERVER_ADDR}
     NEW_PORT=${port:-$NEW_PORT}
     NEW_PROTOCOL=${protocol:-$NEW_PROTOCOL}
     NEW_SERVICE_PORTAL_NAME=${service_portal_name:-$NEW_SERVICE_PORTAL_NAME}
     ;;

    SAEP)
     PRODUCT_NAME="${SAL_STR}Symantec Endpoint Protection (Cloud)"
     
     setAgentType
     setProductFeature
     validateDCSUpgrade

     # CAF SETTINGS
     #settings picked up from manifest
     NEW_SECRET_KEY=${connect_token:-%SECRET_KEY%}
     NEW_CUST_ID=${customer_id:-%CUSTOMER_ID%}
     NEW_DOMAIN_ID=${domain_id:-%DOMAIN_ID%}
     NEW_BOOTSTRAPURI=${enrollment_url:-%BOOTSTRAPURI%}
     NEW_PROXY_HTTP_PORT=${NEW_PROXY_HTTP_PORT:-"%PROXY_PORT%"} # set in getProxyInput
     NEW_PROXY_HTTPS_PORT=${NEW_PROXY_HTTPS_PORT:-"%PROXY_PORT%"} # set in getProxyInput

     CAF_COMM_TEST=true
     
     # Run configure if switching from SEPM to CDM
     [ "$PREV_PRODUCT_ID" = "SEPM" ] && CONFIGURE=true
     ;;

    SEPM)
     PRODUCT_NAME="${SAL_STR}Symantec Endpoint Protection (SEPM)"
     [ "$product_version" ] && [ "$PRODUCT_VERSION" = "" ] && PRODUCT_VERSION=${product_version}

     setAgentType
     setProductFeature
     validateDCSUpgrade

     [ "$repo_url" ] && { LOCAL_REPO_URL=${repo_url}; [ "$LOCAL_REPO_URL" ] && localRepo=true; }
     NEW_PROXY_HTTP_PORT=${NEW_PROXY_HTTP_PORT:-"%PROXY_PORT%"} # set in getProxyInput
     NEW_PROXY_HTTPS_PORT=${NEW_PROXY_HTTPS_PORT:-"%PROXY_PORT%"} # set in getProxyInput

     # Run configure if switching from SEPM to CDM
     [ "$PREV_PRODUCT_ID" = "SAEP" ] && CONFIGURE=true
     ;;
    *) echo "Unknown product install" && exit 1 ;;
  esac
  KMOD_PACKAGE=sdcss-kmod
  SCRIPTS_PACKAGE=sdcss-scripts
  [ "$PRODUCT_ID" = "DCS" ] && PACKAGES=($AGENT_PACKAGE $KMOD_PACKAGE) || PACKAGES=($CAF_PACKAGE $AGENT_PACKAGE $KMOD_PACKAGE)
}

usage()
{
   echo $MYNAME |grep -q installagent && INSTALL_SCRIPT_HELP=true 
   echo $MYNAME |grep -q uninstall && UNINSTALL_SCRIPT_HELP=true
   [ "$subhelp" = "true" ] && printf "Extended Optional Arguments:\n" || \
     printf "Usage: $MYNAME [<args>]\nOptional Arguments:"

   printf "\n\t-V|--version          List the versions associated with this install"
 if [ "$PRODUCT_ID" != "DCS" ]; then
   printf "\n\t-i|--image            Used for creating images (skips enrollment with the server)"
   printf "\n\t                      To be used post install only."
   printf "\n\t-e|--enroll           Enroll with the server."
   printf "\n\t                      To be used alone, post install only."
   printf "\n\t-s|--simple-install   Install only (skips configuration and enrollment). Added for Azure VM extension."
   printf "\n\t                      To be used for a new install only."
   printf "\n\t-c|--configure        Configure agent with command line parameters. Added for Azure VM extension."
   printf "\n\t                      To be used alone, post install only."
   printf "\n\t  -k|--customer-secret-key   Customer secret key"
   printf "\n\t  -t|--customer-id           Customer ID"
   printf "\n\t  -d|--domain-id             Domain ID"
   printf "\n\t  -a|--server-address        server address"
   printf "\n\t  -o|--port                  server port"
   printf "\n\t  -l|--protocol              server protocol"
   printf "\n\t  -v|--service-portal-name   service portal name"
   printf "\n\t  -m|--proxy-mode            Proxy mode e.g. Manual"
   printf "\n\t  -x|--proxy-address         Proxy address"
   printf "\n\t  -y|--proxy-port            Proxy HTTP port"
   printf "\n\t  -q|--proxy-protocol        Proxy protocol"
   printf "\n\t  -w|--proxy-user-name       Proxy user name"
   printf "\n\t  -z|--proxy-password        Proxy password"
   printf "\n\t  -N|--pinning               Enable certificate pinning in config."
   printf "\n\t  -n|--no-pinning            Disable certificate pinning."
   printf "\n\t  --proxy-https-port         Proxy HTTPS port (Symantec Agent for Linux only)"
 fi
 if [ "$PRODUCT_ID" = "DCS" ] && [ "$INSTALL_SCRIPT_HELP" = "true" ]; then 
   printf "\n\t  --update-kmod              Check for and update only the kmod package from the repository" 
 fi  
 if [ "$PRODUCT_ID" = "DCS" ] && ([ "$INSTALL_SCRIPT_HELP" = "true" ] || [ "$UNINSTALL_SCRIPT_HELP" = "true" ]); then
   printf "\n\t  -u|--uninstall             Uninstall agent. May be used alone if a single product is installed, or as follows"
   printf "\n\t                             to uninstall one or all products if the agent is configured in Dual mode:"
   printf "\n\t                             --uninstall "
   printf "\n\t                             --uninstall ALL"
   printf "\n\t                             --uninstall SEPL"
   printf "\n\t                             --uninstall DCS"  
 fi   
 if [ "$PRODUCT_ID" != "DCS" ]; then
   if [ "$subhelp" = "false" ]; then
     printf "\n\t                        e.g. $MYNAME --configure --customer-id <CUST_ID> --domain-id <DOMAIN_ID> "
     printf "\n\t                        --customer-secret-key <CUST_SECRET_KEY> --server-address scwp.securitycloud.symantec.com "
     printf "\n\t                        --port 443 --protocol https --service-portal-name dcs-service --proxy-mode %%PROXY_MODE%% "
     printf "\n\t                        --proxy-address %%PROXY_ADDR%% --proxy-http-port %%PROXY_PORT%% --proxy-https-port %%PROXY_PORT%% "
     printf "\n\t                        --proxy-user-name %%PROXY_USERNAME%% --proxy-password %%PROXY_PASSWORD%% --reboot --pinning"
     printf "\n\t-u|--uninstall        Uninstall agent. May be used alone if a single product is installed, or as follows"
     printf "\n\t                      to uninstall one or all products if the agent is configured in Dual mode:"
     printf "\n\t                        --uninstall "
     printf "\n\t                        --uninstall ALL"
     printf "\n\t                        --uninstall SEP"
     printf "\n\t                        --uninstall DCS"
     printf "\n\t-r|--reboot           Reboot after the install/upgrade, if required"
     printf "\n\t                      To be used for new install or upgrade.\n"
   fi
   printf "\n\t--update-kmod         Check for and update only the kmod package from the repository" 
   printf "\n\t-p|--update           Flag update. Added for Azure VM extension."
   printf "\n\t-b|--reset-state      Erase enrollment info and perform re-enroll. Added for Azure VM Extension."
   printf "\n\t                      To be used alone, post install only."
   printf "\n\t-g|--disable-repo     Temporarily disable the repository for install/update."
   printf "\n\t                      NOTE: All necessary packages must be available in current working directory."
   printf "\n\t-h|--local-repo       Specify local repository URL, in case if you dont want to use Symantec Agent for Linux package repository."
   printf "\n\t                      The remote agent update feature will query available packages from this repo location."
   printf "\n\t                      Example: --local-repo 'http://<repo_ip_or_hostname:<port_optional>/cwp1.6'  (note OS and architecture are added to URL)"
   printf "\n\t--product-version     <Product_version> Useful to specify install from a specific release version (SEPM only at this time)"
   printf "\n\t                      i.e. --product-version 14.3RU2"
   printf "\n\t--disable-feature     <Feature-List> Diables the features on install."
   printf "\n\t                      i.e. --disable-feature \"AM IPS RTFIM AP\" ( keep the feature item list in quotes )."
   printf "\n\t                      AM - Disable Antimalware feature ( On-demand and Real time auto protection )."
   printf "\n\t                      IPS - Disable Intrusion Protection feature."
   printf "\n\t                      RTFIM - Disable Real time file monitoring feature."
   printf "\n\t                      AP  - Disable Real time auto protection."
   printf "\n\t                      To be used for a new install only."
   printf "\n\t                      Can be combined with --simple-install, --image(new install only) options."
   printf "\n\t--tags                Instance specific tags to be use by cloud server to organize."
   printf "\n\t                      Multiple tags could be supplied separated by comma with no spaces in tag names or in between."
   printf "\n\t                      Tag names could be alpha-numeric with no special characters."
   printf "\n\t                      Tag names must be in double quotes."
   printf "\n\t                      Example  --tags \"US-EAST,Oracle,Production\"\n"
 else
   printf "\n"
 fi
}

log_msg()
{
  _tod=`date +"%D %T"`
  printf "$_tod: $1\n" >> $_LOGFILE 2>/dev/null
  [ "$2" ] && [ "$2" -eq "1" ] && printf "$1\n"
  [ "$2" ] && [ "$2" -eq "2" ] && log_msg_upgrade_status "$1"
  [ "$2" ] && [ "$2" -eq "3" ] && printf "$1\n" && log_msg_upgrade_status "$1"
  return 0
}

log_msg_upgrade_status()
{
  if [ "$ISUPGRADE" = true ] && [ -d `dirname $_LOGFILE_UPGRADE_STATUS` ]; then
      _tod=`date +"%D %T"`
      printf "$_tod: $1\n" >> $_LOGFILE_UPGRADE_STATUS
  fi
  return 0
}

clean_exit()
{
   selinux_on
   _ret=$1
   # In case of VM extension toggles, return success if error code >1 (not so serious .. i.e. status)
   [ $_ret -gt 1 ] && ( [ $SIMPLE_INSTALL = true ] || [ $RESET_STATE = true ] || [ $CONFIGURE = true ] || [ $UPDATE = true ] ) && \
      { log_msg "Ignoring return code $_ret"; _ret=0; }
   disableSDCSSRepo
   copyInstallLogs
   exit $_ret
}

error()
{
   log_msg "Error $1: $2" 3
   printf "Please refer to install logfile $_LOGFILE for more information\n"
   clean_exit $1
}

trap_caught()
{
   error 1 "Script exit on signal $1" 1  
}

trap_with_arg() 
{
   func="$1" ; shift
   for sig in "$@"; do
      trap "$func $sig" "$sig"
   done
}

selinux_off()
{
   if [ -f '/etc/selinux/config' ]; then
     SELINUX_STATUS=$(getenforce 2>/dev/null)
     if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        setenforce 0 >> $_LOGFILE 2>&1 && log_msg "Temporarily disabling SELinux enforcement during installation..."
     fi
   fi
}

selinux_on()
{
   if [ "$SELINUX_STATUS" = "Enforcing" ]; then 
      setenforce 1 >> $_LOGFILE 2>&1 && log_msg "SELinux enforcement re-enabled."
   fi
}

pkg_installed()
{
  case $PLAT_PKG in
    deb) if [ $INSTALL = true ]; then dpkg-query -W -f='${Status}\n' $1 2>/dev/null | grep -v "not-installed" |grep -q "^install ok installed";
	 else dpkg-query -W -f='${Status}\n' $1 2>/dev/null | grep -v "not-installed" |grep -qw "^install ok";
         fi;;
    rpm) rpm --quiet -q $1 >/dev/null 2>&1;;
  esac;
  return $?;
}

pkg_version()
{
  local _ret=0
  if [ -f "$1" ]; then
    case $PLAT_PKG in
      deb) dpkg -f $1 Version 2>/dev/null; _ret=$?;;
      rpm) v=`rpm -qp --qf "%{VERSION}-%{RELEASE}" $1 2>/dev/null`; _ret=$?
              [ $_ret = 0 ] && echo "$v" |sed 's/\([0-9.]*\)-\([0-9]*\)\..*/\1-\2/';;
    esac;
  else
    case $PLAT_PKG in
      deb) dpkg-query -W -f='${Version}\n' $1 2>/dev/null; _ret=$?;;
      rpm) v=`rpm -q $1 >/dev/null 2>&1 && rpm -q --qf "%{VERSION}-%{RELEASE}" $1 2>/dev/null`; _ret=$?
              [ $_ret = 0 ] && echo "$v" |sed 's/\([0-9.]*\)-\([0-9]*\)\..*/\1-\2/';;
    esac;
  fi
  return $_ret
}
check_pkg_names()
{
  for _p in $*; do
     v=`check_package_ver $_p`
     [ "$v" ] && case $PKG_MGR in zypp|apt) printf "%s " $_p=$v;; *) printf "%s " $_p-$v*;; esac || echo $_p
  done
}
    
# $1 - list of packages to check for specific versions (i.e. --packages parameter)
check_package_ver()
{
  _pkg=$1
  if [ "$SPECIFIC_PACKAGES" ]; then
    local sp=`echo "$SPECIFIC_PACKAGES" |sed 's/\s\+/\n/g' |grep -w $_pkg=.*`
    [ -z "$sp" ] && return 0
    local _v
    case $sp in
      $_pkg=[0-9]*.[0-9]*.[0-9]*[.-][0-9]*) _v=`avail_pkg_version $_pkg true |grep -w ${sp#*=}`;;
      $_pkg=[0-9]*) _pkgidx=`echo "$sp" |cut -d= -f2 |awk '{printf "%d",$0}'`;
             _v=`avail_pkg_version $_pkg true |awk -v idx=$(expr $_pkgidx + 1) 'NR==idx {print $0}'`;;
      *) printf "Invalid package specification for $_pkg. use $_pkg=x.x.x-bld or $_pkg=idx as seen from --list-all";;
    esac
    [ "$_v" ] && echo $_v
  fi

   unset sp _pkg
}

avail_pkg_version()
{
   [ $REPO_COMM_STATUS -ne 0 ] && return 1
   [ $DISABLE_REPO = true ] && return 1
   [ -f $1 ] && return 0
   searchall=${2:-false}

   if [ "$SPECIFIC_PACKAGES" ] && [ "$searchall" = "false" ]; then
      v=`check_package_ver $1`
      log_msg "Specific package $1 $v selected and is available in repo"
      [ "$v" ] && echo $v && return 0
   fi

   case $PKG_MGR in
      yum) [ $searchall = true ] && PARM="--showduplicates"
           v="`yum -q --disablerepo="*" --enablerepo="SDCSS*" $PARM list available $1 2>>$_LOGFILE |grep ^${1%%-[0-9]*} |awk '{print $2}'`";
           [ -z "$v" ] && \
             v="`yum -q --disablerepo="*" --enablerepo="SDCSS*" $PARM list installed $1 2>>$_LOGFILE |grep ^${1%%-[0-9]*} |awk '{print $2}'`";;
      zypp) [ $searchall = true ] && v="`zypper -n search -s -r SDCSS $1 2>>$_LOGFILE |awk '/package \|/ {print $7}'`" || \
           v="`zypper -vn info -r SDCSS $1 2>>$_LOGFILE | grep ^Version |cut -d: -f2 |cut -d. -f1-3 |awk '{printf $1}'`";;
      apt) [ $searchall = true ] && v="`apt-cache madison $1 2>>$_LOGFILE |awk '{printf "%s\n",$3}'`" || \
           v=`apt-cache madison $1 2>>$_LOGFILE |head -1 |awk '{printf "%s",$3}'`;;
   esac
   [ "$v" ] && { [ $searchall = true ] && \
     { echo "$v" |sort -r -u -V -t- -k 3 -k1,2 && return 0; } || \
     { echo "$v" |sed 's/\([0-9.]*\)-\([0-9]*\)\..*/\1-\2/' && return 0; } }
   unset searchall
   return 1
}

# pkgs_installed()
# $1 - list of packages to query
# Returns: $pkgcnt - number of pkgs installed
# Sets: PKGS_INSTALLED[$pkgcnt]
#       PKGS_INSTALLED_VERSIONS[$pkg]
pkgs_installed()
{
   unset PKGS_INSTALLED PKGS_INSTALLED_VERSIONS; pkgcnt=0
   for pkg in $*; do 
      if pkg_installed $pkg; then
        PKGS_INSTALLED[$pkgcnt]=$pkg
        PKGS_INSTALLED_VERSIONS[$pkgcnt]=`pkg_version $pkg`
        ((pkgcnt++))
      fi
   done
   return $pkgcnt
}


preserve_sepfl_pem()
{
  if [ $PRODUCT_ID = SEPM ] && [ "$CVE_CONFIG_DIR" ] && [ -d $CVE_CONFIG_DIR ] ; then
	if [ -e $CVE_CONFIG_DIR/sepfl.pem ]; then
		log_msg "Need to take a backup of sepfl.pem file"
		cp -f $CVE_CONFIG_DIR/sepfl.pem $BACKUP_DIR/sepfl.pem
	fi
  fi
}

uninstallSavfl()
{
    # CSPT-5655 check sepfl.pem file existance. 
    preserve_sepfl_pem

   [ -f /etc/Symantec.conf ] && basedir=$(cat /etc/Symantec.conf | grep BaseDir | awk -F'=' '{print $2}')

   #set UPGRADE_FROM flag for CAF
   [[ ${PKGS_INSTALLED[0]} = sav* ]] && UPGRADE_FROM=SAVFL || UPGRADE_FROM=SEPFL

   log_msg "Uninstalling the legacy Symantec Antivirus product (${PKGS_INSTALLED[0]}-${PKGS_INSTALLED_VERSIONS[0]})" 1
   if [ -x $basedir/symantec_antivirus/uninstall.sh ]; then
      log_msg "Running $basedir/symantec_antivirus/uninstall.sh -u.." 1
      $basedir/symantec_antivirus/uninstall.sh -u >>$_LOGFILE 2>&1 || \
         error 1 "Running $basedir/symantec_antivirus/uninstall.sh -u"
   else
      log_msg "Uninstalling packages: ${PKGS_INSTALLED[*]}" 1
      pkg_uninstall "${PKGS_INSTALLED[*]}" || error 1 "Uninstalling packages ${PKGS_INSTALLED[*]}"
      [ -d "${basedir}/virusdefs" ] && rm -rf "${basedir}/virusdefs"
      [ -d "${basedir}/sep" ] && rm -fr "${basedir}/sep"
      [ -d "${basedir}/tmp" ] && rm -fr "${basedir}/tmp"
   fi
   return 0
}

uninstallPrevAgent()
{
   pkgs_installed ${OLD_AGENT_PKGS[*]} $CAF_PACKAGE sdcss-kmod

   #set UPGRADE_FROM flag for CAF
   [ "${PKGS_INSTALLED[0]}" = "sdcss-agent" ] && UPGRADE_FROM=CWP || \
      { [ "${PKGS_INSTALLED[0]}" = "sdcss-sepagent" ] && UPGRADE_FROM=SEP || UPGRADE_FROM=DCS; }

   [ "$UPGRADE_FROM" ] && ( [ "$UPGRADE_FROM" = "CWP" ] || [ "$UPGRADE_FROM" = "DCS" ] ) && [ $FORCE = false ] && \
      error 1 "Please uninstall previous Symantec $UPGRADE_FROM product prior to installation of $PRODUCT_NAME"

   isPreventionEnabled && error 1 "Agent install failed as prevention policy is applied. Revoke the prevention policy from $UPGRADE_FROM before installing."

   log_msg "Uninstalling previous Symantec $UPGRADE_FROM product (${PKGS_INSTALLED[0]}-${PKGS_INSTALLED_VERSIONS[0]})" 1
   log_msg "Uninstalling packages: ${PKGS_INSTALLED[*]} ..." 1
   pkg_uninstall "${PKGS_INSTALLED[*]}" || error 1 "Uninstalling packages ${PKGS_INSTALLED[*]}"
   return 0
}

preInstallChecks()
{
  [ $INSTALL != true ] && return 0
  [ $PRODUCT_ID = CWP ] && getAMProxy
  if ( [ $ISUPGRADE = false ] || ([ $ISUPGRADE = true ] && [ "$_AGENT_TYPE" = 1 ] && [ "$AGENT_TYPE" = 5 ]) ) ; then
    # Check for unsupported Paravirtual type
    # On AWS, if Xen, look for HVM domU type, Paravirtual systems can't get SMBIOS
    [ -x /usr/sbin/virt-what ] && virt_type=`/usr/sbin/virt-what 2>&1`
    if [ "$virt_type" ] &&  echo "$virt_type" |grep -q xen; then
      virt_prod=`dmidecode -s system-product-name 2>/dev/null`
      echo "$virt_prod" |grep -iq hvm || { \
        printf "\nERROR: Paravirtual (xen) Virtualization type detected.\n"
        printf "This is not a supported platform type for the Symantec Agent.\n\n"
        exit 1;
      }
    fi

    # check feature settings
    check_feature_list

    # Check for legacy sepfl or savfl and uninstall if found
    pkgs_installed sav savap savap-x64 savui savjlu sep sepap sepap-x64 sepui sepjlu || uninstallSavfl
  
    # Check for DCS Agents (Onprem or CWP) and uninstall if found
    pkgs_installed ${OLD_AGENT_PKGS[*]} || uninstallPrevAgent
  
    # check for any resident kernel modules that may require reboot after installation
    [ "$_AGENT_TYPE" != 1 ] && kmod_check && REQUIRE_REBOOT_AFTER_INSTALL=true

    # make sure /opt has 751 minimum 
    [ ! -d /opt ] && ( mkdir /opt && chmod 751 /opt; ) ||  chmod o+x /opt
  fi

  return 0
}

getPlatform()
{
  POSTFIX=repo; PLAT_PKG=rpm;
  if [ "`uname`" = "Linux" ]; then
     if grep -qi "Santiago\|CentOS release 6" /etc/redhat-release 2>/dev/null; then OS=rhel6; PKG_MGR=yum; PKG_MASK='\.\(rh\)?el6\.';
     elif grep -qi "Maipo\|CentOS Linux release 7" /etc/redhat-release 2>/dev/null; then OS=rhel7; PKG_MGR=yum; PKG_MASK='\.\(rh\)?el7\.';
     elif grep -qi "Ootpa\|CentOS Linux release 8" /etc/redhat-release 2>/dev/null; then OS=rhel8; PKG_MGR=yum; PKG_MASK='\.\(rh\)?el8\.';
     elif grep -qi "Amazon Linux AMI release" /etc/system-release 2>/dev/null; then OS=amazonlinux; PKG_MGR=yum; PKG_MASK='\.amzn1\.';
        REPO_GPG_CHECK=0;  # temporarily disable as packages are not signed yet (GB-TODO)
     elif grep -qi "Amazon Linux release 2" /etc/system-release 2>/dev/null; then OS=amazonlinux2; PKG_MGR=yum; PKG_MASK='\.amzn2\.';
     elif grep -qi "Ubuntu 14.04" /etc/lsb-release 2>/dev/null; then OS=ubuntu14; PKG_MGR=apt; POSTFIX=list; PKG_MASK='\.ub\(untu\)?14\.';
     elif grep -qi "Ubuntu 16.04" /etc/lsb-release 2>/dev/null; then OS=ubuntu16; PKG_MGR=apt; POSTFIX=list; PKG_MASK='\.ub\(untu\)?16\.';
     elif grep -qi "Ubuntu 18.04" /etc/lsb-release 2>/dev/null; then OS=ubuntu18; PKG_MGR=apt; POSTFIX=list; PKG_MASK='\.ub\(untu\)?18\.';
     elif grep -qi "Ubuntu 20.04" /etc/lsb-release 2>/dev/null; then OS=ubuntu20; PKG_MGR=apt; POSTFIX=list; PKG_MASK='\.ub\(untu\)?20\.';
     elif grep -qi "suse.*server 12" /etc/SuSE-release 2>/dev/null; then OS=sles12; PKG_MGR=zypp; PKG_MASK='\.suse12\.';
     elif grep -qi "suse.*server 15" /etc/SuSE-release 2>/dev/null; then OS=sles15; PKG_MGR=zypp; PKG_MASK='\.suse15\.';
     elif grep -qi "suse.*server 15" /etc/os-release 2>/dev/null; then OS=sles15; PKG_MGR=zypp; PKG_MASK='\.suse15\.';
     elif grep -qi "debian.*linux 9" /etc/os-release 2>/dev/null; then OS=debian9; PKG_MGR=apt; POSTFIX=list; PKG_MASK='\.deb\(ian\)?9\.';
     elif grep -qi "debian.*linux 10" /etc/os-release 2>/dev/null; then OS=debian10; PKG_MGR=apt; POSTFIX=list; PKG_MASK='\.deb\(ian\)?10\.';
     fi
     if [ -z "$OS" ] || [ -z "$PKG_MGR" ]; then error 1 "Linux Distribution not supported"; fi
  fi
  [ $printPlatformInfo = true ] && printf "os=$OS\npkg=$PLAT_PKG\n" && exit 0
  [ $PKG_MGR = apt ] && PLAT_PKG=deb
  case $PKG_MGR in
   yum) REPOFILE=/etc/yum.repos.d/sdcss.repo;
        REPO_GPG_PATH=/etc/pki/rpm-gpg/RPM-GPG-KEY-SDCSS;;
   zypp) REPOFILE=/etc/zypp/repos.d/sdcss.repo;
         REPO_GPG_PATH=/etc/pki/trust/anchors/RPM-GPG-KEY-SDCSS;;
   apt) REPOFILE=/etc/apt/sources.list.d/sdcss.list;;
  esac
  case $OS in rhel6|amazonlinux) INIT_SUBSYSTEM=sysinit;; ubuntu14) INIT_SUBSYSTEM=upstart;; *) INIT_SUBSYSTEM=systemd;; esac
}

installGPGKeys () 
{
  ( [ ! -z "$SIS_CERT_PATH" ] && [ -f "$SIS_CERT_PATH" ] ) && pkg_cert="$SIS_CERT_PATH" || pkg_cert=Release.gpg
  
  [ ! -f $pkg_cert ] && log_msg "Warning: $pkg_cert missing" && return 0
  log_msg "Running key import for Symantec Repo. pkg_cert=$pkg_cert"
  case $PKG_MGR in
    yum)
      rpm --import $pkg_cert >>$_LOGFILE 2>&1  && \
        cp -f $pkg_cert $REPO_GPG_PATH || \
        log_msg "Missing RPM Cert file $pkg_cert" 1
        ;;
    zypp)
      rpm --import $pkg_cert >>$_LOGFILE 2>&1 && \
        cp -f $pkg_cert $REPO_GPG_PATH || \
        log_msg "Missing RPM Cert file $pkg_cert" 1
        ;;
    apt)
      apt-key add $pkg_cert >>$_LOGFILE 2>&1 || \
         log_msg "Error adding GPG to APT keyring" 1
      ;;
  esac
}

fold_msg()
{
  local ncols=$((`tput cols 2>/dev/null` - 5));
  [ -z "$ncols" ] && ncols=40;
  ncols=$(( $ncols > 120 ? 120 : $ncols ))
  which fold >/dev/null 2>&1 && echo "$1" |fold -w $ncols -s || echo "$1";
}

box_msg()
{
   fold_msg "$1" | awk 'length($0) > length(longest) { longest = $0 } { lines[NR] = $0 } END { gsub(/./, "=", longest); print "/=" longest "=\\"; n = length(longest); for(i = 1; i <= NR; ++i) { printf("| %s %*s\n", lines[i], n - length(lines[i]) + 1, "|"); } print "\\=" longest "=/" } ' |tee -a $_LOGFILE;
}

refreshSDCSSRepo()
{
  [ $DISABLE_REPO = false ] && enableSDCSSRepo || { log_msg "Repo is disabled or $REPOFILE missing.. not refreshing."; REPO_COMM_STATUS=0; return 1; }
  REPO_COMM_STATUS=0

  # clean any old yum sdcss cache and get new cache
  log_msg "Refreshing repo cache and testing connection..\n"
  local ret;
  case $PKG_MGR in
     yum) [ $OS = rhel8 ] && cache_dir=/var/cache/dnf/SDCSS* || cache_dir=/var/cache/yum/`uname -m`/*/SDCSS*
          rm -rf $cache_dir
          ret=`yum --disablerepo="*" --enablerepo="SDCSS" makecache 2>&1`; log_msg "$ret"
          echo "$ret" |grep -iq 'Error\|Errno' && { log_msg "YUM Repo communication error:\n" 1; box_msg "$ret"; REPO_COMM_STATUS=1; } ;;
     zypp) ret=`zypper -n refresh -f SDCSS 2>&1`
           [ $? = 0 ] && log_msg "$ret" || \
            { log_msg "Zypper Repo communication error:\n" 1; box_msg "$ret"; REPO_COMM_STATUS=1; } ;;
     apt) ret=`apt-get update -o Dir::Etc::sourcelist="sources.list.d/sdcss.list" \
           -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>&1;`; log_msg "$ret"
          ( echo "$ret" |grep -q "^E: Failed\|^Err:" ) || [ `echo "$ret" |wc -l` -le 1 ] && \
             { log_msg "APT Repo communication error:\n" 1; box_msg "$ret"; REPO_COMM_STATUS=1; } ;;
  esac

  [ $REPO_COMM_STATUS = 1 ] && [ $ISUPGRADE = true ] && log_msg "NOTICE: Unable to communicate with repository. Check repo file $REPOFILE\n" 1
  log_msg "Repo communication status = $REPO_COMM_STATUS"
  return $REPO_COMM_STATUS;
}

useVerifyRepo()
{
  local ret=1
  case $PRODUCT_ID in
     SAEP) echo "$NEW_BOOTSTRAPURI" | grep -qi "\/\/r3\.stage" && ret=0;;
  esac
  return $ret
}

useDevRepo()
{
  local ret=1
  case $PRODUCT_ID in
     CWP) echo "$NEW_SERVER_ADDR" |grep -qi "dcs-devint" && ret=0;;
     SAEP) echo "$NEW_BOOTSTRAPURI" | grep -qi "\/\/r3\.dev" && ret=0;;
  esac
  return $ret
}

isDevRepo()
{
  [ -f $REPOFILE ] && grep -q "//${REPO_URL_DEV}/" $REPOFILE 2>/dev/null && return 0 || \
     return 1
}

devRepoNotice()
{
   repeat() { v=$(printf "%-${2}s%s" "$3" "$4"); echo "${v// /$1}"; }
   repeat "*" 60
   repeat " " 59 "* NOTICE: USE OF THE DEVELOPMENT REPOSITORY" "*"
   repeat " " 59 "* ($REPO_URL_TRANSPORT://$REPO_URL_DEV)" "*"
   repeat " " 59 "* IS NOT RECOMMENDED FOR PRODUCTION ENVIRONMENTS" "*"
   repeat "*" 60
   echo ""
}

isLocalRepo()
{
  if ( ! grep -q "//${REPO_URL}/" $REPOFILE 2>/dev/null && \
       ! grep -q "//${REPO_URL_DEV}/" $REPOFILE 2>/dev/null && \
       ! grep -q "//${REPO_URL_VERIFY}/" $REPOFILE 2>/dev/null ); then 
    return 0
  fi
  return 1
}

enableSDCSSRepo()
{
  ( [ ! -f $REPOFILE ] || [ $DISABLE_REPO = true ] ) && return 1
  case $PKG_MGR in 
     yum|zypp) sed -i 's/^enabled=0/enabled=1/g' $REPOFILE 2>/dev/null;;
     apt) sed -i -r "s|^#.*deb (.*)$|deb \1|g" $REPOFILE 2>/dev/null;;
  esac
  return 0
}

disableSDCSSRepo()
{
  ( [ ! -f $REPOFILE ] || [ $DISABLE_REPO = true ] || [ $debugMode = true ] ) && return 0
  case $PKG_MGR in 
     yum|zypp) sed -i 's/^enabled=1/enabled=0/g' $REPOFILE 2>/dev/null;;
     apt) sed -i -r "s|^deb (.*)$|# deb \1|g" $REPOFILE 2>/dev/null;;
  esac
  return 0
}

configureSDCSSRepo()
{
  # On Debian9, out-of-the-box, missing https support for APT to communicate with our repo
  if [ $OS = debian9 ] && [ "$REPO_URL_TRANSPORT" = "https" ] && [ $DISABLE_REPO = false ] && ! pkg_installed apt-transport-https; then
     log_msg "Installing apt-transport-https for Repo communication.." 1;
     apt-get -y update >>$_LOGFILE 2>&1 && apt-get install -y apt-transport-https >>$_LOGFILE 2>&1 || \
       error 1 "Unable to install apt-transport-https for Repo communication on $OS";
  fi

  # check existing Repo file
  if [ -f $REPOFILE ]; then
    grep -q "#.*DisableRepo=true" $REPOFILE && { DISABLE_REPO=true; REPO_ENABLE=0; }
    if [ $UPDATE_REPO  = false ]; then
      if ! isLocalRepo && ! grep -q "$REPO_NAME" $REPOFILE; then
        UPDATE_REPO=true
        log_msg "Appears to be upgrade, so updating repo file"
      elif ( [ $ISUPGRADE = false ] && [ "$DCS_DUAL" != true ] ); then
        UPDATE_REPO=true
        log_msg "Appears to be clean install, so updating old repo file"
      else log_msg "Not updating repo file.."
	grep -q "//${REPO_URL_DEV}/" $REPOFILE 2>/dev/null && devRepo=true && devRepoNotice
	grep -q "//${REPO_URL_VERIFY}/" $REPOFILE 2>/dev/null && verifyRepo=true
      fi
    fi
  else
    UPDATE_REPO=true;
  fi

  # Update the Repo now
  if [ $UPDATE_REPO = true ]; then
    if [ -f $REPOFILE ] && [ -d /etc/symantec ]; then
       repo_bak=/etc/symantec/`basename $REPOFILE`.prev
       log_msg "backing up previous repo file to $repo_bak" && mv -f $REPOFILE $repo_bak
    fi
    [ -f ${REPOFILE}.prev ] && rm -f ${REPOFILE}.prev

    if [ $localRepo = true ] && [ "$LOCAL_REPO_URL" ]; then
     echo $LOCAL_REPO_URL |grep -q "//${REPO_URL_DEV}/" 2>/dev/null && devRepo=true && devRepoNotice
     log_msg "\nConfiguring Local Repo ($LOCAL_REPO_URL) for \n$PRODUCT_NAME .." 1
      
      case $PKG_MGR in
       yum|zypp) 
         cat > $REPOFILE 2>>$_LOGFILE <<EOF
[SDCSS]
name=Local Symantec Agent for Linux repository
baseurl=${LOCAL_REPO_URL}/${OS}/\$basearch
enabled=$REPO_ENABLE
gpgcheck=0
skip_if_unavailable=1
EOF
         ;;
       apt)
         [ $REPO_ENABLE = 0 ] && HASH="# " || HASH=""
         ARCHTAG="[ arch=amd64 ]"
         cat > $REPOFILE 2>>$_LOGFILE <<EOF
${HASH}deb ${ARCHTAG} ${LOCAL_REPO_URL}/${OS} ${REPO_NAME} main
EOF
         ;;
      esac

    else #Normal install
      installGPGKeys
      [ $devRepo = false ] && useDevRepo && devRepo=true
      [ $verifyRepo = false ] && useVerifyRepo && verifyRepo=true
      if [ $devRepo = true ] && [ -z "$prodRepo" ]; then 
         REPO_URL=$REPO_URL_DEV
         devRepoNotice
         log_msg "Configuring Dev Repo ($REPO_URL) in $REPOFILE .." 1 
      elif [ $verifyRepo = true ] && [ -z "$prodRepo" ]; then 
         REPO_URL=$REPO_URL_VERIFY
         log_msg "\nConfiguring Verify Repo ($REPO_URL) in $REPOFILE .." 1 
      else
         log_msg "\nConfiguring Repo ($REPO_URL) .." 1
      fi
      case $PKG_MGR in
       yum|zypp) 
	 [ ! -f $REPO_GPG_PATH ] && log_msg "Warning: GPG check disabled. Missing $REPO_GPG_PATH" && REPO_GPG_CHECK=0
         cat > $REPOFILE 2>>$_LOGFILE <<EOF
# Symantec Agent for Linux repository
# DisableRepo=$DISABLE_REPO
[SDCSS]
name=Symantec Agent for Linux repository
baseurl=${REPO_URL_TRANSPORT}://${REPO_URL}/${REPO_NAME}/${OS}/\$basearch
enabled=$REPO_ENABLE
gpgcheck=$REPO_GPG_CHECK
gpgkey=file://$REPO_GPG_PATH
skip_if_unavailable=1
EOF
         ;;
       apt) 
         [ $REPO_ENABLE = 0 ] && HASH="# " || HASH=""
         ARCHTAG="[ arch=amd64 ]"
         cat > $REPOFILE 2>>$_LOGFILE <<EOF
# Symantec Agent for Linux repository
# DisableRepo=$DISABLE_REPO
${HASH}deb ${ARCHTAG} ${REPO_URL_TRANSPORT}://${REPO_URL}/${REPO_NAME}/${OS} ${REPO_NAME} main
EOF
         ;;
      esac
    fi
  fi
  [ -f $REPOFILE ] && case $PKG_MGR in
     yum|zypp) BASE_REPO_URL=`grep ^baseurl= $REPOFILE |head -1 |sed "s|baseurl=\(.*\)/\$basearch.*|\1|"`;;
     apt) BASE_REPO_URL=`grep 'deb.*http' $REPOFILE |head -1 |awk '{for(i=1;i<=NF;i++) {if ($i ~ /http/) print $i}}'`;;
  esac
  [ "$PKG_MGR" = "zypp" ] && cat >/etc/zypp/vendors.d/symantec 2>>$_LOGFILE <<EOF
[main]
vendors = Symantec,Broadcom
EOF
  refreshSDCSSRepo
  return $?
}

isPreventionEnabled()
{
  ( [ -d /etc/sisips ] && [ "`ls -1 /etc/sisips |grep testforprevention`" ] && [ ! -r /etc/sisips/testforprevention ] ) && rc=0 || rc=1
  return $rc;
}

removePreventionPolicy()
{
  su -s /bin/bash - sisips -c "./sisipsconfig.sh -r" || \
    error 1 "Policy removal failed please remove and retry"
  return 0
}

applyPreventionPolicy()
{
  su -s /bin/bash - sisips -c "./sisipsconfig.sh -s" && ret=$?
  [ ! $ret ] && echo "Policy apply failed please apply again\n" && clean_exit 1
  return 0
}

removeRTFIMPolicy()
{
  if [ -f "$RESPONSE_FILE" ]; then
    log_msg "Sourcing the response file: $RESPONSE_FILE"
    . $RESPONSE_FILE
    SIS_RDIR=$BASEDIR/${INSTPOSTDIR}
    rm -rf $SIS_RDIR/IDS/system/logwatch.ini >> $_LOGFILE 2>&1
    rm -rf $SIS_RDIR/IDS/system/AgentPolicyInfo.ini >> $_LOGFILE 2>&1
    rm -rf $SIS_RDIR/IDS/system/filewatch.ini >> $_LOGFILE 2>&1
    rm -rf $SIS_RDIR/IDS/system/*.pol >> $_LOGFILE 2>&1
 else
    log_msg "Response file missing at $RESPONSE_FILE"
 fi

}

enrollCAF() 
{
  ( ! pkg_installed $AGENT_PACKAGE || ! pkg_installed $CAF_PACKAGE ) && error 1 "$PRODUCT_NAME is not installed";
  log_msg "Enrolling with the server..." 1
  service cafagent stop >>$_LOGFILE 2>&1
  POLICY_APPLIED=false
  isPreventionEnabled && POLICY_APPLIED=true && removePreventionPolicy
  updateCustomerSecretKey
  cp -f /var/log/sdcss-caflog/cafagent.log "/var/log/sdcss-caflog/cafagent`date +%s`.log";
  rm -f $CAF_STORAGE_INI_FILE_PATH
   [ "$POLICY_APPLIED" = "true" ] && applyPreventionPolicy
  service cafagent start >>$_LOGFILE 2>&1 || log_msg "cafagent start failed\n"
  dcsAgentStatus
}

isvarset()
{
   DFLTVAR=${2:-%*%}
   ( [ -z "$1" ] || [[ "$1" =~ ($DFLTVAR|FSD_SEPEG_LINUX*) ]] ) && return 1 || return 0
}

#-------------------------------------------------------
#  getValue() Function
#  Parameters: $1=string name of key
#              $2=string filename
#              $3=optional delimiter
#  Purpose: Return value of the key in the file
#-------------------------------------------------------
getValue()
{
  local searchkey="$1"
  local filename="$2"
  local delimiter="${3:-=}"
  ( [ -z "$searchkey" ] || [ -z "$filename" ] || [ ! -f "$filename" ] ) && return 1
  grep "^${searchkey}${delimiter}" "$filename" |cut -d${delimiter} -f2 | awk '{$1=$1};1'
  return $?
}

#-------------------------------------------------------
#  updateValue() Function
#  Parameters: $1=string name of key
#              $2=string new value for the key
#              $3=string filename
#              $4=optional delimiter
#  Purpose: Update new value of the key in the file
#-------------------------------------------------------
updateValue()
{
  log_msg "updateValue: $1, $2, $3"
  
  local filename="$3"
  ( [ -z "$1" ] || [ -z "$2" ] || [ ! -f "$filename" ] ) && return 1
  
  local searchkeystr=`echo "$1" | xargs`
  local newvalstr=`echo "$2" | xargs`
  ( [ -z "$searchkeystr" ] || [ -z "$newvalstr" ] ) && return 1
  
  local delimiter="/"
  [ ! -z "$4" ] && delimiter=`echo "$4" | xargs`
  log_msg "updateValue: Delimiter $delimiter, key $searchkeystr, value $newvalstr"
  
  local replacestr="$searchkeystr=$newvalstr"
  log_msg "updateValue: Delimiter $delimiter, New keyvalue $replacestr"
  
  sed -i -r "s${delimiter}^$searchkeystr=(.*)${delimiter}$replacestr${delimiter}g" "$filename" 2>/dev/null

  return 0;
}

getProxyInput()
{
  [ $PRODUCT_ID = CWP ] && return 0;

  # get proxy mode - only support proxy_type=CUSTOM for now from manifest
  # If proxy-mode provided via command-line, return 0
  [ "$NEW_PROXYMODE" = "%PROXY_MODE%" ] && isvarset $proxy_type && [ "$proxy_type" = "CUSTOM" ] && NEW_PROXYMODE=Manual || return 0;

  # get proxy addr, port and protocol from proxy_host
  if [ "$NEW_PROXY_ADDR" = "%PROXY_ADDR%" ] && isvarset $proxy_host && isvarset $proxy_port; then
      NEW_PROXY_ADDR=$proxy_host
      isvarset $proxy_port && NEW_PROXY_HTTP_PORT=$proxy_port
      isvarset $proxy_httpsport && NEW_PROXY_HTTPS_PORT=$proxy_httpsport
  else
     return 1;     
  fi

  # get proxy username and password
  [ "$NEW_PROXYUSERNAME" = "%PROXY_USERNAME%" ] && isvarset $proxy_user && NEW_PROXYUSERNAME=$proxy_user && \
    [ "$NEW_PROXYPASSWORD" = "%PROXY_PASSWORD%" ] && isvarset $proxy_password && NEW_PROXYPASSWORD=$proxy_password

  return 0;
}

validateInput() 
{
  ( [ $INSTALL = false ] || [ $SIMPLE_INSTALL = true ] ) && return 0;
  ( [ $IMAGE = false ] && [ $ISUPGRADE = true ] && ( [ "$_AGENT_TYPE" != "1" ] || ([ "$_AGENT_TYPE" = "1" ] && [ "$AGENT_TYPE" != "5" ]) ) ) && return 0;
  
  if [ "$PRODUCT_ID" = "SAEP" ]; then
     ### Check no configuration parameter is empty or not set
     if [ -z "$NEW_SECRET_KEY" ]  || [ $NEW_SECRET_KEY = "%SECRET_KEY%" ] || \
        [ -z "$NEW_CUST_ID" ]     || [ $NEW_CUST_ID = "%CUSTOMER_ID%" ] || \
        [ -z "$NEW_DOMAIN_ID" ]   || [ $NEW_DOMAIN_ID = "%DOMAIN_ID%" ] || \
        [ -z "$NEW_BOOTSTRAPURI" ] || [ $NEW_BOOTSTRAPURI = "%BOOTSTRAPURI%" ]; then
         error 1 "Please provide configuration parameters in $MYNAME.\nThe manifest file may be missing from the installer."
     fi
     getProxyInput || error 1 "Missing proxy mandatory parameters";

  elif [ "$PRODUCT_ID" = "SEPM" ]; then
     ( [ ! -f sylink.xml ] || [ ! -f sep.slf ] || [ ! -f serdef.dat ] ) && error 1 "Missing communication files for SEP  installation: sylink.xml, sep.slf or serdef.dat"
     getProxyInput || error 1 "Missing proxy mandatory parameters";

  else #product_id is CAF
     ### Check no configuration parameter is empty or not set
     if [ -z "$NEW_SECRET_KEY" ]  || [ $NEW_SECRET_KEY = "%SECRET_KEY%" ] || \
        [ -z "$NEW_CUST_ID" ]     || [ $NEW_CUST_ID = "%CUSTOMER_ID%" ] || \
        [ -z "$NEW_DOMAIN_ID" ]   || [ $NEW_DOMAIN_ID = "%DOMAIN_ID%" ] || \
        [ -z "$NEW_SERVER_ADDR" ] || [ $NEW_SERVER_ADDR = "%SERVER_ADDR%" ] || \
        [ -z "$NEW_PROTOCOL" ]    || [ $NEW_PROTOCOL = "%PROTOCOL%" ] || \
        [ -z "$NEW_SERVICE_PORTAL_NAME" ] || [ $NEW_SERVICE_PORTAL_NAME = "%SERVICE_PORTAL_NAME%" ]; then
         error 1 "Please provide configuration parameters in $MYNAME for CWP.\nThe manifest file may be missing from the installer."
     fi
  fi

  # Verify minimum proxy information is provided
  if [ "$validateProxy" = "true" ]; then
    if isvarset $NEW_PROXY_ADDR && isvarset $NEW_PROXY_HTTP_PORT; then
      ! isvarset $NEW_PROXYMODE && NEW_PROXYMODE=Manual
      log_msg "Validated minimum proxy parameters"
    else
      error 1 "At minimum proxy address and port must be provided (--proxy-address and --proxy-port)."
    fi
  fi
  return 0;
}

printInput() 
{
  if [ $CONFIGURE = true ]; then
    isvarset $PRODUCT_VERSION && echo "PRODUCT_VERSION: $PRODUCT_VERSION"
    isvarset $NEW_CUST_ID && echo "NEW_CUST_ID: $NEW_CUST_ID"
    isvarset $NEW_DOMAIN_ID && echo "NEW_DOMAIN_ID: $NEW_DOMAIN_ID"
    isvarset $NEW_SECRET_KEY && echo "NEW_SECRET_KEY: ******"
    if [ "$PRODUCT_ID" = "SAEP" ]; then
      isvarset $NEW_BOOTSTRAPURI && echo "NEW_BOOTSTRAPURI: $NEW_BOOTSTRAPURI"
    elif [ "$PRODUCT_ID" = "CWP" ]; then
      isvarset $NEW_SERVER_ADDR && echo "NEW_SERVER_ADDR: $NEW_SERVER_ADDR"
      isvarset $NEW_PROTOCOL && echo "NEW_PROTOCOL: $NEW_PROTOCOL"
      isvarset $NEW_SERVICE_PORTAL_NAME && echo "NEW_SERVICE_PORTAL_NAME: $NEW_SERVICE_PORTAL_NAME"
      isvarset $NEW_PROXY_PORT && echo "NEW_PROXY_PORT: $NEW_PROXY_PORT"
    fi
    isvarset $NEW_PROXYMODE && echo "NEW_PROXYMODE: $NEW_PROXYMODE"
    isvarset $NEW_PROXY_ADDR && echo "NEW_PROXY_ADDR: $NEW_PROXY_ADDR"
    isvarset $NEW_PROXY_PROTOCOL http && echo "NEW_PROXY_PROTOCOL: $NEW_PROXY_PROTOCOL"
    isvarset $NEW_PROXYUSERNAME && {
      echo "NEW_PROXYUSERNAME: $NEW_PROXYUSERNAME" && \
      echo "NEW_PROXYPASSWORD: ******"
    }
    isvarset $ARG_ENABLE_PINNING false && echo "PINNING ENABLED:  $ARG_ENABLE_PINNING"
    isvarset $REBOOT false && echo "REBOOT: $REBOOT"
  fi
}

configCustomerSecretKey() 
{
  [ "$PRODUCT_ID" = "SEPM" ] && return 0;
  #replace secret key
  [ "$PRODUCT_ID" = "SAEP" ] && SECRETKEY_SEARCHSTR="connect_token=" || \
     SECRETKEY_SEARCHSTR="x-dcs-customer-secret-key="
  isvarset $NEW_SECRET_KEY && {
    REPLACE_TEXT=$SECRETKEY_SEARCHSTR$NEW_SECRET_KEY
    sed -i -r "s|$SECRETKEY_SEARCHSTR(.*)|$REPLACE_TEXT|" "$CAFCONFIGFILE"
  }
}

removeEncryprtedFlag() 
{
  sed -i -r -e '/caf-params/d' -e '/config_encrypted/d' -e '/encryption_migrated/d' -e '/encryption_done/d' $CAFCONFIGFILE
}

configProxyPassword() 
{
  #replace PROXY PASSWORD
  isvarset $NEW_PROXYPASSWORD && {
    PROXYPASSWORD_SEARCHSTR="proxy-password="
    REPLACE_TEXT=$PROXYPASSWORD_SEARCHSTR$NEW_PROXYPASSWORD
    sed -i -r "s|$PROXYPASSWORD_SEARCHSTR(.*)|$REPLACE_TEXT|" "$CAFCONFIGFILE"
  }
}

getAMProxy()
{
   # on upgrade, grap the http_proxy= setting from service file for AMD
   if [ $ISUPGRADE = "true" ]; then
     if [ -f /etc/init/sisamddaemon.conf ]; then _svc_file=/etc/init/sisamddaemon.conf;
     elif [ -f /etc/systemd/system/sisamddaemon.service ]; then _svc_file=/etc/systemd/system/sisamddaemon.service;
     fi
     [ "$_svc_file" ] && [ -f "$_svc_file" ] && grep -q http_proxy= "$_svc_file" 2>/dev/null && \
        PREV_PROXY=`sed -n -e 's/.*http_proxy=\(.*\)/\1/p' $_svc_file`
     unset _svc_file
   fi
}

configureAMProxy ()
{
   if [ "$PREV_PROXY" ]; then  PROXY=$PREV_PROXY
   elif ( [ $ISUPGRADE = "true" ] && [ $CONFIGURE = false ] ) || \
        ( [ "${NEW_PROXYMODE,,}" != "disabled" ] && \
         ( [ -z "$NEW_PROXY_ADDR" ] || [ "$NEW_PROXY_ADDR" = "%PROXY_ADDR%" ] || \
           [ -z "$NEW_PROXY_PORT" ] || [ "$NEW_PROXY_ADDR" = "%PROXY_PORT%" ] ) ); then
      return 0
   else
      [ -n "$NEW_PROXYUSERNAME" ] && [ "$NEW_PROXYUSERNAME" != "%PROXY_USERNAME%" ] && \
          USER_CREDENTIALS=$NEW_PROXYUSERNAME
      [ -n "$USER_CREDENTIALS" ] && [ -n "$NEW_PROXYPASSWORD" ] && [ "$NEW_PROXYPASSWORD" != "%PROXY_PASSWORD%" ] && \
          USER_CREDENTIALS=${USER_CREDENTIALS}:$NEW_PROXYPASSWORD

      [ -n "$USER_CREDENTIALS" ] && USER_CREDENTIALS=${USER_CREDENTIALS}@

      PROTOCOL=${NEW_PROXY_PROTOCOL:-http}
      PROXY=$PROTOCOL://$USER_CREDENTIALS$NEW_PROXY_ADDR:$NEW_PROXY_PORT
   fi
   proto=http_proxy

   # Set proxy in AMD service script
   if [ -f /etc/init/sisamddaemon.conf ]; then # RHEL6, AMZN1, and Ubuntu 14
       service sisamdagent stop
       if [ "${NEW_PROXYMODE,,}" = "disabled" ]; then   #Note, this is case insensitive test
         log_msg "Removing proxy environment variable  $proto=$PROXY in /etc/init/sisamddaemon.conf ..." 
         grep -q "^env $proto=" /etc/init/sisamddaemon.conf && \
            sed -i "/^env $proto=.*/d" /etc/init/sisamddaemon.conf
       else
         log_msg "Setting proxy environment variable  $proto=$PROXY in /etc/init/sisamddaemon.conf ..." 
         grep -q "^env $proto=" /etc/init/sisamddaemon.conf && \
            sed -i "s|^env $proto=.*|env $proto=$PROXY|" /etc/init/sisamddaemon.conf || \
            sed -i "/^exec .*/i env $proto=$PROXY" /etc/init/sisamddaemon.conf
       fi
   elif [ -f /etc/systemd/system/sisamddaemon.service ]; then # Amzn2, RHEL7, Ubuntu 16 & 18
       systemctl stop sisamddaemon
       if [ "${NEW_PROXYMODE,,}" = "disabled" ]; then   #Note, this is case insensitive test
         log_msg "Removing proxy environment variable  $proto=$PROXY in /etc/systemd/system/sisamddaemon.service ..." 
         grep -q "^Environment=$proto=" /etc/systemd/system/sisamddaemon.service && \
            sed -i "/^Environment=$proto=.*/d" /etc/systemd/system/sisamddaemon.service
       else
         log_msg "Setting proxy environment variable  $proto=$PROXY in /etc/systemd/system/sisamddaemon.service ..." 
         grep -q "^Environment=$proto=" /etc/systemd/system/sisamddaemon.service && \
            sed -i "s|^Environment=$proto=.*|Environment=$proto=$PROXY|" /etc/systemd/system/sisamddaemon.service || \
            sed -i "/^ExecStart=.*/i Environment=$proto=$PROXY" /etc/systemd/system/sisamddaemon.service
       fi
       systemctl daemon-reload
   else
       log_msg "Cannot find Anti-malware service file. Perhaps agent not installed?"
   fi
}

configureAMD()
{
   [ $PRODUCT_ID = CWP ] && configureAMProxy

   # Don't re-run configure on normal update/upgrade 
   [ $ISUPGRADE = true ] && [ $CONFIGURE = false ] && return 0
   
   if [ -f $AMDCONFIGFILE ] && ( [ $PRODUCT_ID = SAEP ] || [ $PRODUCT_ID = SEPM ] ); then
       log_msg "Configuring AMD for $PRODUCT_NAME .. id=$PRODUCT_ID version=$PRODUCT_VERSION"

       #replace proxy username
       if [  ! -z "$NEW_PROXYUSERNAME" ] && [ "$NEW_PROXYUSERNAME" != "%PROXY_USERNAME%" ]; then
         PROXYUSERNAME_SEARCHSTR="proxy.username="
         REPLACE_TEXT=$PROXYUSERNAME_SEARCHSTR$PXY_PREFIX$NEW_PROXYUSERNAME
         sed -i -r "s/$PROXYUSERNAME_SEARCHSTR(.*)/$REPLACE_TEXT/" "$AMDCONFIGFILE"
       fi

       #replace proxy password
       if [  ! -z "$NEW_PROXYPASSWORD" ] && [ "$NEW_PROXYPASSWORD" != "%PROXY_PASSWORD%" ]; then
         PROXYPASSWORD_SEARCHSTR="proxy.password="
         REPLACE_TEXT=$PROXYPASSWORD_SEARCHSTR$PXY_PREFIX$NEW_PROXYPASSWORD
         sed -i -r "s|$PROXYPASSWORD_SEARCHSTR(.*)|$REPLACE_TEXT|" "$AMDCONFIGFILE"
       fi

       if [  ! -z "$NEW_PROXY_HTTP_PORT" ] && [ "$NEW_PROXY_HTTP_PORT" != "%PROXY_PORT%" ]; then
         PROXYPORT_SEARCHSTR="proxy.http.port="
         REPLACE_TEXT=$PROXYPORT_SEARCHSTR$NEW_PROXY_HTTP_PORT
         sed -i -r "s/$PROXYPORT_SEARCHSTR(.*)/$REPLACE_TEXT/" "$AMDCONFIGFILE"
       fi

       if [  ! -z "$NEW_PROXY_HTTPS_PORT" ] && [ "$NEW_PROXY_HTTPS_PORT" != "%PROXY_PORT%" ]; then
         PROXYPORT_SEARCHSTR="proxy.https.port="
         REPLACE_TEXT=$PROXYPORT_SEARCHSTR$NEW_PROXY_HTTPS_PORT
         sed -i -r "s/$PROXYPORT_SEARCHSTR(.*)/$REPLACE_TEXT/" "$AMDCONFIGFILE"
       fi

       if [  ! -z "$NEW_PROXY_ADDR" ] && [ "$NEW_PROXY_ADDR" != "%PROXY_ADDR%" ]; then
         PROXYADDR_SEARCHSTR="proxy.address="
         REPLACE_TEXT=$PROXYADDR_SEARCHSTR$NEW_PROXY_ADDR
         sed -i -r "s/$PROXYADDR_SEARCHSTR(.*)/$REPLACE_TEXT/" "$AMDCONFIGFILE"
       fi
   fi
}

#-------------------------------------------------------
#  postInstallConfigure() Function
#  Parameters: none
#  Purpose: Perform post install tasks while upgrading 
#           from DCS agent if the agent UM package 
#           installed is at the latest version.
#-------------------------------------------------------
postInstallConfigure()
{
  pkgs_installed sdcss $CAF_PACKAGE; pkgs_cnt=$?
  
  if [ "$pkgs_cnt" != 2 ]; then
    log_msg "postInstallConfigure: Required package(s) (sdcss and or sdcss-caf) not installed."
    return 0
  fi
   
  if ( [ "$_AGENT_TYPE" = "1" ] && [ "$AGENT_TYPE" = "5" ] ); then
    updateValue "AgentType" "5" "$INSTALLREG_FILE"
    updateValue "AGENT_TYPE" "5" "$RESPONSE_FILE"
  fi
  setupCAFIPScomm
}

#-------------------------------------------------------
#  setupCAFIPScomm() Function
#  Parameters: none
#  Purpose: Setup dcscaf/sisips user/group and rpc pipes
#           for comm between caf and ips daemons, if sdcss 
#           agent package is already at latest version
#-------------------------------------------------------
setupCAFIPScomm()
{
  if [ -f "$RESPONSE_FILE" ]; then
    log_msg "setupCAFIPScomm: Sourcing the response file $RESPONSE_FILE"
    . $RESPONSE_FILE
 else
    log_msg "setupCAFIPScomm: response file missing at $RESPONSE_FILE."
    return 1
 fi
 INFUNLIB=$BASEDIR/sdcssagent/lib/instfunlib
 INSTATE=POST
 if [ ! -f $INFUNLIB ]; then
    log_msg "setupCAFIPScomm: file $INFUNLIB missing. Unable to configure user/ipc."
    return 1
 else . $INFUNLIB; fi

 updateUserGroup
 setupRPCPipe
}

disable_pinning()
{
  [ ! -f $CAFCONFIGFILE ] && return 1

  CAF_WAS_RUNNING=false
  pgrep cafservicemain > /dev/null && CAF_WAS_RUNNING=true && service cafagent stop >>$_LOGFILE 2>&1
  sed -i -r -e '/Https_CertFilePath/d' -e '/ssl-config/d' $CAFCONFIGFILE
  if [ -f $CAF_STORAGE_INI_FILE_PATH ]; then
    sed -i -r -e '/Https_CertFilePath/d'  $CAF_STORAGE_INI_FILE_PATH
  fi
  log_msg "Certificate pinning disabled on agent config." 1

  [ $CAF_WAS_RUNNING = true ] && service cafagent start >>$_LOGFILE 2>&1
}

pinning_enabled()
{
   if grep -q "Https_CertFilePath" $CAFCONFIGFILE 2>/dev/null ; then
      log_msg "Certficate pinning found to be enabled" 1
      return 0
   fi
   log_msg "Certificate pinning found to be disabled" 1
   return 1
}

enable_pinning()
{
  [ ! -f $CAFCONFIGFILE ] && return 1

  CAF_WAS_RUNNING=false
  pgrep cafservicemain > /dev/null  && CAF_WAS_RUNNING=true && service cafagent stop >>$_LOGFILE 2>&1
  if ! pinning_enabled; then
        sed -i '$ a  [ssl-config]\nHttps_CertFilePath=certs\n' $CAFCONFIGFILE
        log_msg "Certificate pinning enabled on agent config." 1
  else log_msg "Certficate pinning already enabled on agent config" 1
  fi

  [ $CAF_WAS_RUNNING = true ] && service cafagent start >>$_LOGFILE 2>&1
}

configureCAF()
{
  #replace version whether it is install or upgrade
  if [ $PRODUCT_ID = SEPM ] || [ $PRODUCT_ID = SAEP ]; then
    getSAEPAgentVersion
    if [ -f $CAFCONFIGFILE ]; then
      isvarset $SEPFL_VERSION && {
        SEPFLVERSION="version=$SEPFL_VERSION"
        SEPFLVERSION_SEARCHSTR="^version="
        sed -i -r "s/$SEPFLVERSION_SEARCHSTR(.*)/$SEPFLVERSION/" "$CAFCONFIGFILE"
      }
    fi

    # make sure product_version is replaced
    if [ "$PRODUCT_VERSION" ]; then
      grep -q "^sep_version=" $CAFCONFIGFILE && \
        sed -i -r "s|^sep_version=.*|sep_version=$PRODUCT_VERSION|g" "$CAFCONFIGFILE" || \
        sed -i "/^product_id=.*/a sep_version=$PRODUCT_VERSION" "$CAFCONFIGFILE"
    fi
  fi

  # Run configure if current and previous customer ids are different (CDM Acoount switch) 
  # stop CAF and make sure Storage and encrypted flags are removed
  if [ -f $CAFCONFIGFILE ] && [ $PRODUCT_ID = SAEP ]; then
    CURRENT_CUST_ID=`grep x-epmp-customer-id $CAFCONFIGFILE |cut -d= -f2-`
    [ "$PREV_PRODUCT_ID" = "SAEP" ]  && [ "$NEW_CUST_ID" != "%CUSTOMER_ID%" ] && [ ! -z "$CURRENT_CUST_ID" ] &&  \
      [ "$CURRENT_CUST_ID" != "$NEW_CUST_ID" ] &&  \
      log_msg "Switching CDM account" && \
      service cafagent stop >>$_LOGFILE 2>&1 && \
      CONFIGURE=true && removeCAFStorage && removeEncryprtedFlag
  fi    
  
  if [ $ISUPGRADE = true ]; then
     # Add request_license for caf enrollment
    if [ "$REQUEST_LICENSE" ]; then
      REQUESTLICENSE="request_license=$REQUEST_LICENSE"
      REQUESTLICENSE_SEARCHSTR="request_license="
      grep -q $REQUESTLICENSE_SEARCHSTR $CAFCONFIGFILE && \
        sed -i -r "s/$REQUESTLICENSE_SEARCHSTR(.*)/$REQUESTLICENSE/" $CAFCONFIGFILE
    fi
    
    #We changed the policy name from RU4 onwards
    #incase of upgrade if we need to rename the old policy before starting the agents
    if [ $PRODUCT_VERSION = "14.3RU4" ] && [ -f $POLICY_FILE_PATH/am_policy ]; then 
         [ $PRODUCT_ID = "SAEP" ] && mv -fv $POLICY_FILE_PATH/am_policy $POLICY_FILE_PATH/policy_cdm >>$_LOGFILE 2>&1
         [ $PRODUCT_ID = "SEPM" ] && mv -fv $POLICY_FILE_PATH/am_policy $POLICY_FILE_PATH/policy_sepm >> $_LOGFILE 2>&1
    fi 
  fi
  
  # Don't re-run configure on normal update/upgrade 
  [ $ISUPGRADE = true ] && [ $CONFIGURE = false ] && return 0

  if [ -f $CAFCONFIGFILE ]; then

    log_msg "Configuring CAF for $PRODUCT_NAME .. id=$PRODUCT_ID version=$PRODUCT_VERSION"

    [ $CONFIGURE = true ] && isvarset $NEW_SECRET_KEY && removeEncryprtedFlag $CAFCONFIGFILE && removeCAFStorage

    configCustomerSecretKey

    #replace customer id
    isvarset $NEW_CUST_ID && {
      CUSTID_SEARCHSTR="x-epmp-customer-id="
      REPLACE_TEXT=$CUSTID_SEARCHSTR$NEW_CUST_ID
      sed -i -r "s|$CUSTID_SEARCHSTR(.*)|$REPLACE_TEXT|" "$CAFCONFIGFILE"
    }

    #replace domain id
    isvarset $NEW_DOMAIN_ID && {
      DOMIANID_SEARCHSTR="x-epmp-domain-id="
      REPLACE_TEXT=$DOMIANID_SEARCHSTR$NEW_DOMAIN_ID
      sed -i -r "s|$DOMIANID_SEARCHSTR(.*)|$REPLACE_TEXT|" "$CAFCONFIGFILE"
    }

    #replace proxy mode
    isvarset $NEW_PROXYMODE && {
      PROXYMODE_SEARCHSTR="proxy-mode="
      REPLACE_TEXT=$PROXYMODE_SEARCHSTR$NEW_PROXYMODE
      sed -i -r "s/$PROXYMODE_SEARCHSTR(.*)/$REPLACE_TEXT/" "$CAFCONFIGFILE"
    }

    #replace proxy username
    isvarset $NEW_PROXYUSERNAME && {
      PROXYUSERNAME_SEARCHSTR="proxy-username="
      REPLACE_TEXT=$PROXYUSERNAME_SEARCHSTR$NEW_PROXYUSERNAME
      sed -i -r "s/$PROXYUSERNAME_SEARCHSTR(.*)/$REPLACE_TEXT/" "$CAFCONFIGFILE"
    }

    #replace proxy password
    isvarset $NEW_PROXYPASSWORD && {
      PROXYPASSWORD_SEARCHSTR="proxy-password="
      REPLACE_TEXT=$PROXYPASSWORD_SEARCHSTR$NEW_PROXYPASSWORD
      sed -i -r "s|$PROXYPASSWORD_SEARCHSTR(.*)|$REPLACE_TEXT|" "$CAFCONFIGFILE"
    }

    #replace protocol (dnsUri and baseUri)
    if isvarset $NEW_PROTOCOL; then
       sed -i -r "s|^baseUri=.*:\/\/(.*)|baseUri=$NEW_PROTOCOL:\/\/\1|" "$CAFCONFIGFILE"
       sed -i -r "s|^dnsUri=.*:\/\/(.*)|dnsUri=$NEW_PROTOCOL:\/\/\1|" "$CAFCONFIGFILE"
    fi

    #replace port (dnsUri and baseUri)
    if isvarset $NEW_PORT; then
        sed -i -r "s|^baseUri=(.*):\/\/(.*)\/(.*)|baseUri=\1:\/\/\2:$NEW_PORT\/\3|" "$CAFCONFIGFILE"
        sed -i -r "s|^dnsUri=(.*):\/\/(.*)|dnsUri=\1:\/\/\2:$NEW_PORT|" "$CAFCONFIGFILE"
    fi

    #replace server address (dnsUri and baseUri)
    if isvarset $NEW_SERVER_ADDR; then
      isvarset $NEW_PORT && SRVADDR=$NEW_SERVER_ADDR:$NEW_PORT || SRVADDR=$NEW_SERVER_ADDR;
      sed -i -r "s|^baseUri=(.*):\/\/.*\/(.*)|baseUri=\1:\/\/$SRVADDR\/\2|" "$CAFCONFIGFILE"
      sed -i -r "s|^dnsUri=(.*):\/\/.*|dnsUri=\1:\/\/$SRVADDR|" "$CAFCONFIGFILE"
    fi

    #replace service portal
    if isvarset $NEW_SERVICE_PORTAL_NAME; then
      sed -i -r "s|^baseUri=(.*):\/\/(.*)\/.*|baseUri=\1:\/\/\2\/$NEW_SERVICE_PORTAL_NAME|" "$CAFCONFIGFILE"
      sed -i -r "s|^enrollmentUri=\/[^/]*\/(.*)|enrollmentUri=\/$NEW_SERVICE_PORTAL_NAME\/\1|" "$CAFCONFIGFILE"
    fi

    if [ $PRODUCT_ID = SAEP ]; then

      # make sure product_id=SEPM when upgrading to CDM condtrol
      [ "$PREV_PRODUCT_ID" = "SEPM" ] && \
         sed -i -r "s|^product_id=.*|product_id=SAEP|" "$CAFCONFIGFILE"

      #replace bootstrapUri
      isvarset $NEW_BOOTSTRAPURI && { 
        SEARCHSTR="bootstrapUri="
        REPLACE_TEXT=$SEARCHSTR$NEW_BOOTSTRAPURI
        sed -i -r "s|$SEARCHSTR(.*)|$REPLACE_TEXT|" "$CAFCONFIGFILE"
      }

      #replace proxy address
      isvarset $NEW_PROXY_ADDR && {
        PROXYADDR="proxy-host=$NEW_PROXY_ADDR"
        PROXYADDR_SEARCHSTR="proxy-host="
        sed -i -r "s/$PROXYADDR_SEARCHSTR(.*)/$PROXYADDR/" "$CAFCONFIGFILE"
      }

      #replace proxy port
      isvarset $NEW_PROXY_HTTP_PORT && {
        PROXYHTTPPORT="proxy-port=$NEW_PROXY_HTTP_PORT"
        PROXYHTTPPORT_SEARCHSTR="proxy-port="
        sed -i -r "s/$PROXYHTTPPORT_SEARCHSTR(.*)/$PROXYHTTPPORT/" "$CAFCONFIGFILE"
      }

      #replace proxy port
      isvarset $NEW_PROXY_HTTPS_PORT && {
        PROXYHTTPSPORT="proxy-https-port=$NEW_PROXY_HTTPS_PORT"
        PROXYHTTPSPORT_SEARCHSTR="proxy-https-port="
        sed -i -r "s/$PROXYHTTPSPORT_SEARCHSTR(.*)/$PROXYHTTPSPORT/" "$CAFCONFIGFILE"
      }

    elif [ $PRODUCT_ID = CWP ]; then  # PRODUCT_ID = CWP
      #replace proxy port (proxy-uri)
      if isvarset $NEW_PROXY_PORT; then
         sed -i -r "s|^proxy-uri=(.*):\/\/(.*)\/|proxy-uri=\1:\/\/\2:$NEW_PROXY_PORT\/|" "$CAFCONFIGFILE"
      fi

      #replace proxy address (proxy-uri)
      if isvarset $NEW_PROXY_ADDR; then
        isvarset $NEW_PROXY_PORT && PROXYADDR=$NEW_PROXY_ADDR:$NEW_PROXY_PORT || PROXYADDR=$NEW_PROXY_ADDR;
        sed -i -r "s|^proxy-uri=(.*):\/\/.*\/|proxy-uri=\1:\/\/$PROXYADDR\/|" "$CAFCONFIGFILE"
      fi

      #replace proxy protocol (proxy-uri)
      isvarset "$NEW_PROXY_PROTOCOL" http && {
        PROXYPROTOCOL="proxy-uri=$NEW_PROXY_PROTOCOL:"
        PROXYPROTOCOL_SEARCHSTR="proxy-uri=http:"
        sed -i -r "s/$PROXYPROTOCOL_SEARCHSTR/$PROXYPROTOCOL/" "$CAFCONFIGFILE"
      }
    elif [ $PRODUCT_ID = SEPM ]; then
       # make sure product_id=SEPM
       sed -i -r "s|^product_id=.*|product_id=SEPM|" "$CAFCONFIGFILE"

      #replace proxy address
      isvarset $NEW_PROXY_ADDR && {
        PROXYADDR="proxy-host=$NEW_PROXY_ADDR"
        PROXYADDR_SEARCHSTR="proxy-host="
        sed -i -r "s/$PROXYADDR_SEARCHSTR(.*)/$PROXYADDR/" "$CAFCONFIGFILE"
      }

      #replace proxy port
      isvarset $NEW_PROXY_HTTP_PORT && {
        PROXYHTTPPORT="proxy-port=$NEW_PROXY_HTTP_PORT"
        PROXYHTTPPORT_SEARCHSTR="proxy-port="
        sed -i -r "s/$PROXYHTTPPORT_SEARCHSTR(.*)/$PROXYHTTPPORT/" "$CAFCONFIGFILE"
      }

      #replace proxy port
      isvarset $NEW_PROXY_HTTPS_PORT && {
        PROXYHTTPSPORT="proxy-https-port=$NEW_PROXY_HTTPS_PORT"
        PROXYHTTPSPORT_SEARCHSTR="proxy-https-port="
        sed -i -r "s/$PROXYHTTPSPORT_SEARCHSTR(.*)/$PROXYHTTPSPORT/" "$CAFCONFIGFILE"
      }

       # copy files for /etc/symantec/sep
       [ ! -d /etc/symantec/sep ] && mkdir -p /etc/symantec/sep
       chmod 0775 /etc/symantec; chmod 02775 /etc/symantec/sep;  #Make sure directories have correct permissions
       if [ -f sep.slf ]; then
          [ -f /etc/symantec/sep/sep.slf ] && cp /etc/symantec/sep/sep.slf /etc/symantec/sep/sep.slf.prev
          cp -f sep.slf /etc/symantec/sep && chown dcscaf.dcscaf /etc/symantec/sep/sep.slf
       fi
       if [ -f sylink.xml ]; then
          [ -f /etc/symantec/sep/sylink.xml ] && cp /etc/symantec/sep/sylink.xml /etc/symantec/sep/sylink.xml.prev
          cp -f sylink.xml /etc/symantec/sep && chown dcscaf.dcscaf /etc/symantec/sep/sylink.xml
       fi

       # copy files for /var/symantec/sep
       [ ! -d /var/symantec/sep ] && mkdir -p /var/symantec/sep
       chmod 0775 /var/symantec; chmod 02775 /var/symantec/sep;  #Make sure directories have correct permissions
       if [ -f serdef.dat ]; then
          [ -f /var/symantec/sep/serdef.dat ] && cp /var/symantec/sep/serdef.dat /var/symantec/sep/serdef.dat.prev
          cp -f serdef.dat /var/symantec/sep && chown dcscaf.dcscaf /var/symantec/sep/serdef.dat
       fi
    fi

    ####replace Adapter ini file
    SEARCHSTR="configfiles="; REPLACE_TEXT=
    [ $PRODUCT_ID = SAEP ] && [ -f /etc/caf/SAEPAdapterConfig.ini ] && REPLACE_TEXT="$SEARCHSTR/etc/caf/SAEPAdapterConfig.ini"
    [ $PRODUCT_ID = CWP ] && [ -f /etc/caf/CAFAdapterConfig.ini  ] && REPLACE_TEXT="$SEARCHSTR/etc/caf/CSPAdapterConfig.ini"
    [ $PRODUCT_ID = SEPM ] && [ -f /etc/caf/SEPMAdapterConfig.ini ] && REPLACE_TEXT="$SEARCHSTR/etc/caf/SEPMAdapterConfig.ini"
    [ "$REPLACE_TEXT" ] && sed -i -r "s|$SEARCHSTR(.*)|$REPLACE_TEXT|g" "$CAFCONFIGFILE"

    #replace tags
    isvarset $NEW_TAGS && {
      sed -i -r "s|^tags=.*|tags=\"$NEW_TAGS\"|" "$CAFCONFIGFILE"
    }

    # Add upgrade_from for caf enrollment
    if [ "$UPGRADE_FROM" ]; then
      UPGRADEFROM="upgrade_from=$UPGRADE_FROM"
      UPGRADEFROM_SEARCHSTR="upgrade_from="
      grep -q $UPGRADEFROM_SEARCHSTR $CAFCONFIGFILE && \
        sed -i -r "s/$UPGRADEFROM_SEARCHSTR(.*)/$UPGRADEFROM/" $CAFCONFIGFILE || \
        sed -i -r "/connect_token=(.*)/a $UPGRADEFROM" $CAFCONFIGFILE
    fi
                              
    #handle pinning config
    [ $ARG_ENABLE_PINNING = true ] && enable_pinning
    [ $ARG_DISABLE_PINNING = true ] && disable_pinning

  else
    error 1 "$CAFCONFIGFILE not present"
  fi
}

check_feature_list()
{
  for feature_item in $CWP_FEATURE_SET
  do
  case $feature_item in
    AM) export AMD_DISABLE=true;;
    IPS) export IPS_DISABLE=true;;
    RTFIM) export FIM_DISABLE=true;;
    AP) export AP_DISABLE=true;;
     *);;
  esac
  done
}

create_image()
{
  #Creating an AMI and doing an upgrade
  #delete the cafsotage.ini file
  [ -f $CAF_STORAGE_INI_FILE_PATH ] && rm -f $CAF_STORAGE_INI_FILE_PATH

  [ -d /var/log/sdcss-caflog ] && rm -f /var/log/sdcss-caflog/*.log

  # clean up AMD logs and files
  _logdir=`dirname $DCSLOGFILE`
  [ -d $_logdir/amdlog ] && rm -rf $_logdir/amdlog/*

  if [ -f $AMDCONFIGFILE ]; then
     quarantine_dir=`grep ^amdmanagement.quarantine.path= $AMDCONFIGFILE |cut -d= -f2`
     ( [ -z "$quarantine_dir" ] || [ "$quarantine_dir" = "/" ] ) &&  quarantine_dir="/var/log/sdcsslog/quarantine/"
	 [ -d $quarantine_dir ] && rm -rf $quarantine_dir/*
  fi
  
  # Remove CVE registration file in order to force registration again.
  if [ -d /var/symantec/sep ]; then
     rm -f /var/symantec/sep/registration.xml
     rm -f /var/symantec/sep/registrationInfo.xml
     rm -f /var/symantec/sep/Logs/*.log
  fi

}

updateCustomerSecretKey ()
{
  if [ -f $CAFCONFIGFILE ]; then
    log_msg "Updating $CAFCONFIGFILE with Customer Secret Key..."
    configCustomerSecretKey
    configProxyPassword
    removeEncryprtedFlag $CAFCONFIGFILE
  else
    error 1 "File $CAFCONFIGFILE not present."
  fi
  return 0
}

downloadPackages()
{
  local rc=1
  [ $REPO_COMM_STATUS -ne 0 ] && return 1
  local _pkgs=`check_pkg_names "$*"`
  log_msg "Downloading packages: $_pkgs ..." 1
  case $PKG_MGR in
   yum) [ $ISUPGRADE = true ] && yumcmd=reinstall || yumcmd=install
         yum $yumcmd -y --downloadonly --downloaddir="$PWD" --disablerepo=* --enablerepo=SDCSS* $_pkgs >>$_LOGFILE 2>&1; rc=$?;;
    zypp) [ $ISUPGRADE = true ] && _cmd=update || _cmd=install
         [ $DOWNLOAD = true ] && { _cmd=install; _force=--force; }
         zypper --pkg-cache-dir $PWD -n $_cmd -r SDCSS --download-only $_force $_pkgs >>$_LOGFILE 2>&1; rc=$?;
         [ $rc = 0 ] && mv -f SDCSS*/*.$PLAT_PKG $PWD && rmdir SDCSS*;;
    apt) apt-get -qq download $_pkgs >>$_LOGFILE 2>&1; rc=$?
         # special case for ubuntu, have to rename package
         os_pkg=`echo $OS |sed 's/ubuntu/ub/' |sed 's/debian/deb/'`
         for f in `ls -1 *_amd64.deb 2>/dev/null`; do mv -f $f ${f%_amd64.deb}.${os_pkg}.amd64.deb; done;;
  esac
  if [ $DOWNLOAD = true ]; then
    [ $ISUPGRADE = false ] && [ $debugMode = false ] && rm -f $REPOFILE
    [ $rc = 0 ] && log_msg "Succsessfully downloaded packages:\n`ls -1 *.$PLAT_PKG`\n" 1 || error 1 "Error downloading packages."
  else
   log_msg "Error downloading packages $_pkgs"
   return $rc
  fi
}

installMessage()
{
  if [ -f /var/tmp/agent_install.msg ]; then
     log_msg "Messages from installation of agent:"
     cat /var/tmp/agent_install.msg |tee -a $_LOGFILE
     rm -f /var/tmp/agent_install.msg
  fi
}

installDependency()
{
  log_msg "installDependency: Check/Install dependencies..."
  
  case $PKG_MGR in
   yum)
     package_depends="at audit elfutils-libelf zip"
     [ $OS = amazonlinux ] && package_depends="$package_depends checkpolicy policycoreutils"
     ( [ $OS = rhel6 ] || [ $OS = rhel8 ] ) && package_depends="$package_depends checkpolicy policycoreutils"
     ( [ $OS = rhel7 ] || [ $OS = amazonlinux2 ] ) && package_depends="$package_depends checkpolicy policycoreutils-python"
     ;;
   zypp)
     package_depends="at audit libelf1 checkpolicy policycoreutils zip"   
     ;;
   apt)
     package_depends="at auditd"   
     [ $OS = debian9 ] &&  package_depends="$package_depends libelf1 policycoreutils-python-utils"
     [ $OS = debian10 ] &&  package_depends="$package_depends libelf1 checkpolicy semodule-utils"
     ( [ $OS = ubuntu14 ] || [ $OS = ubuntu16 ] || [ $OS = ubuntu18 ] ) && package_depends="$package_depends libelf-dev zip"
     [ $OS = ubuntu20 ] &&  package_depends="$package_depends libelf-dev"
     ;;
   *)
     log_msg "installDependency: Invalid package manager ($PKG_MGR)."
     return 1
     ;;
  esac

  for pkg in $package_depends; do
    ! pkg_installed $pkg && \
           { log_msg "installDependency: Missing dependent $pkg on $OS"; package_depends_install="$package_depends_install $pkg"; }
  done
  
  package_depends_install=`echo "$package_depends_install" | xargs`
  
  if [ "$PKG_MGR" = "apt" ]; then
    aptget_ret=`apt-get update 2>&1`; aptget_retval=$?; log_msg "installDependency: apt update output $aptget_ret ($aptget_retval)"
    [ "$aptget_retval" != 0 ] && return 1
  fi
  
  if [ ! -z "$package_depends_install" ]; then
  [ $DISABLE_REPO = true ] && error 1 "Missing dependent packages: $package_depends_install.  Please install and retry"
    log_msg "installDependency: install ($package_depends_install)"
    pkg_install "$package_depends_install"
    for pkg in $package_depends; do
      ! pkg_installed $pkg && \
             { log_msg "installDependency: Dependent package $pkg not installed on $OS"; return 1; }
      log_msg "installDependency: Dependent package $pkg installed on $OS";
    done
  else
    log_msg "installDependency: Dependent packages already available ($package_depends) on $OS"
  fi
  return 0
}

checkDependencyRHEL()
{
  yum_rc=0
  [ $DISABLE_REPO = true ] && return $yum_rc
  yum -y clean all >/dev/null 2>&1
  yum_rc=1
  
  yum deplist sdcss-caf sdcss  --enablerepo="SDCSS*" 2>/dev/null | grep "dependency:" | grep -v '/bin' | cut -d: -f2 | cut -d' ' -f2 | xargs rpm -q  >/dev/null 2>&1
  yum_rc=$?
  [ "$yum_rc" != 0 ] && { log_msg "Package dependency check failed ($yum_rc)."; return $yum_rc; }
  log_msg "checkDependencyRHEL: Package dependency check passed ($yum_rc)."
  return $yum_rc
}

checkDependencySLES()
{
  zypp_rc=0
  [ $DISABLE_REPO = true ] && return $zypp_rc
  zypper clean >/dev/null 2>&1
  zypp_rc=$?
  
  zypper in -y -D sdcss-caf sdcss >/dev/null 2>&1
  zypp_rc=$?
  [ "$zypp_rc" != 0 ] && { log_msg "checkDependencySLES: Package dependency check failed ($zypp_rc)."; return $zypp_rc; }
  log_msg "checkDependencySLES: Package dependency check passed ($zypp_rc)."
  return $zypp_rc;
}

checkDependencyAPT()
{
  apt_rc=0  
  [ $DISABLE_REPO = true ] && return $apt_rc
  apt-get clean >/dev/null 2>&1
  apt_rc=$?
  
  for pkg in sdcss sdcss-caf; do
    log_msg "checkDependencyAPT: Checking package dependency ($pkg)."
    apt-cache depends $pkg | grep -v '$pkg' >/dev/null 2>&1
    apt_rc=$?
    [ "$apt_rc" != 0 ] && { log_msg "checkDependencyAPT: Package dependency check failed. (1 apt-cache depends $pkg $apt_rc)."; return $apt_rc; }

    apt-cache depends $pkg | grep "Depends:" | cut -d: -f2 | cut -d' ' -f2 | xargs -i dpkg -l {} >/dev/null 2>&1
    apt_rc=$?
    [ "$apt_rc" != 0 ] && { log_msg "checkDependencyAPT: Package dependency check failed. (2 apt-cache depends $pkg $apt_rc)."; return $apt_rc; }
    
    log_msg "checkDependencyAPT: Package dependency check passed for $pkg ($apt_rc)."
  done
  
  return $apt_rc
}

checkDependency()
{
  case $PKG_MGR in
   yum)  checkDependencyRHEL ; dep_rc=$?;;
   zypp) checkDependencySLES ; dep_rc=$?;;
   apt)  checkDependencyAPT ; dep_rc=$?;;
   *)    log_msg "checkDependency: Failed to identify package manager."; dep_rc=1;;
  esac
  return $dep_rc
}

updateDEBScripts()
{
  local prermfile="/var/lib/dpkg/info/sdcss-sepagent.prerm"
  local postrmfile="/var/lib/dpkg/info/sdcss-sepagent.postrm"
  listfilesrcpath="/var/lib/dpkg/info/sdcss-sepagent.list"
  listfiledestpath="/etc/symantec/sdcss-sepagent.list"
  md5sumsfilesrcpath="/var/lib/dpkg/info/sdcss-sepagent.md5sums"
  md5sumsfiledestpath="/etc/symantec/sdcss-sepagent.md5sums"
 
  if ( [ -f "$prermfile" ] && [ -f "$postrmfile" ] ); then
    sed -i '/sdcss-agent.response/i  if [ "$_AGENT_TYPE" = "3" ] && ( [ "$AGENT_TYPE" = "4" ] || [ "$AGENT_TYPE" = "5" ] ); then  UPGRADE_OBSOLETE=true; fi' "$prermfile" 2>/dev/null 
    sed -i '/^#.*indiscriminate cleanup/ a if [ "$1" = "remove" ] && [ "$2" = "in-favour" ] && [ "$3" = "sdcss" ]; then exit 0; fi' "$prermfile" 2>/dev/null
    sed -i '/^#.*indiscriminate cleanup/ a if [ "$UPGRADE_OBSOLETE" = "true" ]; then exit 0; fi' "$prermfile" 2>/dev/null
    
    sed -i '/^#.*indiscriminate cleanup/ a if [ "$_AGENT_TYPE" = "3" ] && ( [ "$AGENT_TYPE" = "4" ] || [ "$AGENT_TYPE" = "5" ] ); then  exit 0; fi' "$postrmfile" 2>/dev/null 
    sed -i '/^#.*indiscriminate cleanup/ a if ( [ "$1" = "remove" ] && [ -f /var/lib/dpkg/info/sdcss.postrm ] ); then exit 0; fi' "$postrmfile" 2>/dev/null
    mv "$listfilesrcpath" "$listfiledestpath"
    mv "$md5sumsfilesrcpath" "$md5sumsfiledestpath"
    return 0;
  fi
  return 1
}

deb_install()
{
  local rc=0
  log_msg "Using dpkg to install packages $*"
  for p in $*; do
    if [ $ISUPGRADE = "false" ]; then
       dpkg -i $p >> $_LOGFILE 2>&1; rc=$?
       if [ $rc != 0 ]; then
          echo "Attempting to fix dependencies .." |tee -a $_LOGFILE
          apt-get install -fyq  >>$_LOGFILE 2>&1; rc=$?
       fi
    else
       dpkg -i $p >>$_LOGFILE 2>&1; rc=$?
    fi
    [ $rc != 0 ] && log_msg "error occurred trying to install $p" && break;
  done
  return $rc
}
 
restore_sepfl_pem()
{
  if [ $PRODUCT_ID = SEPM ] && [ -e $BACKUP_DIR/sepfl.pem ]; then
  	log_msg "Copying sepfl.pem file to /etc/symantec/sep"
	 mv -f $BACKUP_DIR/sepfl.pem $CVE_CONFIG_DIR/sepfl.pem
         chmod 0644 $CVE_CONFIG_DIR/sepfl.pem  #Set correct permissions to sepfl.pem
  fi
}

installScripts()
{
  pkg=$SCRIPTS_PACKAGE
  localfile="`ls -1tr "$PWD"/$pkg*.$PLAT_PKG 2>/dev/null |sort -V |tail -1`"
  [ $REPO_COMM_STATUS -eq 0 ] && repo_pkg_ver=`avail_pkg_version $pkg`
  installed_pkg_ver=`pkg_version $pkg`
  [ "$localfile" ] && local_pkg_ver=`pkg_version $localfile`

  local_cnt=0
  # Select local or repo script package for consideration
  if [ "$localfile" ] && ( [ -z "$repo_pkg_ver" ] || \
     ( [ "$repo_pkg_ver" ] && version_ge $local_pkg_ver $repo_pkg_ver ) ); then
    pkg=$localfile; pkg_ver=$local_pkg_ver; pkgsrc="file"; ((local_cnt++))
  elif  [ -z "$repo_pkg_ver" ]; then log_msg "No available package version found for $pkg"
  else pkg_ver=$repo_pkg_ver; pkgsrc="repo"; pkg=`check_pkg_names $pkg`
    log_msg "selecting package from repo for install $pkg ($pkg_ver)"
  fi

  if [ "$installed_pkg_ver" ] && [ "$pkg_ver" ] && version_ge $installed_pkg_ver $pkg_ver && \
    pkg_installed $SCRIPTS_PACKAGE && [ $FORCE = false ]; then
    log_msg "\nNo update needed for $pkg ($installed_pkg_ver)" 1
  elif [ "$pkg_ver" ]; then INSTALL_PKG="${pkg}";
    if [ "$installed_pkg_ver" ]; then INSTALL_PKG_VER="${pkg}-${pkg_ver}"
      pkgs_msg="`printf ' %-40s %-15s -> %-15s (%s)' $(basename $pkg) $installed_pkg_ver $pkg_ver $pkgsrc`"
      [ "$installed_pkg_ver" = "$pkg_ver" ] && log_msg "Reinstalling $pkg ($installed_pkg_ver)" 1 && _reinstall=true
    else pkgs_msg="`printf ' %-40s %-15s (%s)' $(basename $pkg) $pkg_ver $pkgsrc`"
    fi
  fi

  if [ -z "$INSTALL_PKG" ] && [ $FORCE = false ]; then
     log_msg "\nNo script package found that needs update";
  else
    if [ -z "$installed_pkg_ver" ]; then
       # print install message
       log_msg "\nInstalling scripts package:" 1
       log_msg "`printf ' %-40s %-15s %s\n' Package Version Source`" 1
       log_msg " ---------------------------------------- --------------- ------" 1
       log_msg "`printf "%s\n\n" "$pkgs_msg"`" 1
    else  #Upgrading
       # print upgrade message
       log_msg "\nUpdating scripts package:\n" 1
       log_msg "`printf ' %-40s %-15s    %-15s %s\n' Package Installed Update Source`" 1
       log_msg " ---------------------------------------- ---------------    --------------- ------" 1
       log_msg "`printf "%s\n\n" "$pkgs_msg"`" 1
    fi

    [ "$installed_pkg_ver" ] && upg=true || upg=false
    installPackages $upg "$INSTALL_PKG"; ret=$?
    if [ $ret != 0 ]; then
      disableSDCSSRepo   # Always leave Repo disabled
      [ $upg = true ] && error 1 "Agent upgrade of scripts package failed: $pkg-$pkg_ver" || \
        error 1 "Scripts package install failed please check error log $_LOGFILE";
    else
      [ $upg = true ] && log_msg "Agent upgrade of scripts package successful: $pkg-$pkg_ver" 3 || \
        log_msg "\nScripts installed successfully"
    fi
  fi

  checkScriptVersion

  unset INSTALL_PKG INSTALL_PKG_VER pkgs_msg pkg_ver installed_pkg_ver pkgsrc upg

}

setInstallPackages()
{
  [ -z "$1" ] && return 0
  
  for p in ${INSTALL_PKGS[@]}; do
    if [ "$p" = "sdcss" ] || echo ${p} | grep -qi "sdcss-[6-9]"; then
      installed_agentpkg=true
    fi
    if [ "$p" = "sdcss-caf" ] || echo ${p} | grep -qi "sdcss-caf"; then
      installed_cafpkg=true
    fi
  done
}

installPackages()
{
  local _ret=0
  local _upgrade=$1; shift;
  local _pkgs="$*"
  local num_pkgs=`echo $_pkgs |wc -w`
  [ "$debugMode" = "true" ] && echo "Press ENTER to continue installation of $_pkgs" && read REPLY
  case $PKG_MGR in
    yum)  if [ $DISABLE_REPO = true ]; then
	    [ $_upgrade = true ] && rpm -Uv ${INSTALL_PKG_PARMS} $_pkgs >> $_LOGFILE 2>&1 || \
            rpm -vi ${INSTALL_PKG_PARMS} $_pkgs >> $_LOGFILE 2>&1; _ret=$?
          else 
            ret=`yum repolist SDCSS 2>&1`; echo "$ret" | grep -q "Repository SDCSS is listed more than once"; _ret=$?
            [ "$_ret" = 0 ] && return 1
            _ret=0
            [ $_upgrade = true ] && yum -y upgrade ${INSTALL_PKG_PARMS} --disablerepo=* --enablerepo=SDCSS $_pkgs >> $_LOGFILE 2>&1 || \
            yum -y install ${INSTALL_PKG_PARMS} --disablerepo=* --enablerepo=SDCSS $_pkgs >> $_LOGFILE 2>&1; _ret=$?;
          fi;;
    zypp) [ $_upgrade = true ] && zypper -vn update ${INSTALL_PKG_PARMS} -r SDCSS $_pkgs >> $_LOGFILE 2>&1 || \
	  [ $DISABLE_REPO = true ] && zypper -vn install ${INSTALL_PKG_PARMS} $_pkgs >> $_LOGFILE 2>&1 || \
          zypper -vn install ${INSTALL_PKG_PARMS} -r SDCSS $_pkgs >> $_LOGFILE 2>&1; _ret=$?;
          case $_ret in 10[0-4,6]) _ret=0;; esac;;
    apt)  ( [ "$_reinstall" = "true" ] || [ $FORCE = true ] ) && INSTALL_PKG_PARMS="--reinstall $INSTALL_PKG_PARMS"
          [ $OS = ubuntu14 ] && [ $local_cnt -eq $num_pkgs ] && deb_install $* || \
           apt-get install -y ${INSTALL_PKG_PARMS}  $_pkgs >>$_LOGFILE 2>&1; _ret=$?;;
  esac
  return $_ret
}

# ------------------------------------------------------
#  addUpgradeArgs() Function
# ------------------------------------------------------ 
addUpgradeArgs()
{
  if [ ! -z "$PREV_SIS_VERSION" ]; then
    if ( ([ "$DCS_DCS" = 1 ] || [ "$DCS_DUAL" = true ]) && [ "$settingsString" = "$productStrDcsLinux" ] ); then
      previous_package="$PREV_SIS_VERSION,en-US,$ProductCode,$UpgradeCode"
      TELEMETRY_CMD="$TELEMETRY_CMD --previous_package \"$previous_package\"" 
      teleaction="2"
    elif ( [ "$DCS_DUAL" = true ] && [ "$settingsString" = "$productStrSepLinux" ] ); then
      previous_package="$PREV_SIS_VERSION,en-US,$ProductCode,$UpgradeCode"
      TELEMETRY_CMD="$TELEMETRY_CMD --previous_package \"$previous_package\"" 
      teleaction="1"
    elif ( [ "$SEPL_SEPL" = true ] && [ "$settingsString" = "$productStrSepLinux" ] ); then
      previous_package="$PREV_SIS_VERSION,en-US,$ProductCode,$UpgradeCode"
      TELEMETRY_CMD="$TELEMETRY_CMD --previous_package \"$previous_package\"" 
      teleaction="2"
    elif [ "$DUAL_DUAL" = true ]; then
      previous_package="$PREV_SIS_VERSION,en-US,$ProductCode,$UpgradeCode"
      TELEMETRY_CMD="$TELEMETRY_CMD --previous_package \"$previous_package\"" 
      teleaction="2"
    fi
  fi
  return 0
}

# ------------------------------------
#  reportTelemetry() function
# ------------------------------------
reportTelemetry()
{
  ( [ "$UPDATE_KMOD" = true ] || [ "$DO_NOT_SEND_TELEMETRY" = true ] ) && return 0;
   
  TELEMETRY_DIR="/opt/Symantec/sdcssagent/IPS/installtelemetry"
  
  [ ! -d "$TELEMETRY_DIR" ] && TELEMETRY_DIR="$MYDIR"

  teleaction=1
  result=`echo "$1" | xargs`
  
  local actionstr="install"
  [ "$3" = "UNINSTALL" ] && teleaction="4" && actionstr="uninstall"
  
  [ ! -d "$TELEMETRY_DIR" ] && log_msg "$TELEMETRY_DIR not found. Not sending $actionstr telemetry." && return 0;
 
  TELEMETRY_FILES=( "$TELEMETRY_DIR/seticli" "$TELEMETRY_DIR/stic.so" "$TELEMETRY_DIR/scd.dat" "$TELEMETRY_DIR/certs.dat" )
  for file in "${TELEMETRY_FILES[@]}"; do
    [ ! -f "$file" ] && log_msg "$file not found. Not sending install telemetry." && return 0;
  done

  settingsString=`echo "$2" | xargs`
  [ -z "$settingsString" ] && log_msg "Product settings not provided. Not sending $actionstr telemetry.\n" && return 0;
  
  DcsLinuxProductCode="{989ED612-30AF-481C-A30B-53A940A8F11B}"
  DcsLinuxUpgradeCode="{FA6A1D55-F38C-46E0-85BB-291D3CBE777C}"

  SepLinuxProductCode="{8DAFF040-9B99-48D6-8CA0-93AEBBEEAF02}"
  SepLinuxUpgradeCode="{C66627C2-6398-4ABC-B4EB-3B050162D424}"

  if [ "$settingsString" = "$productStrDcsLinux" ]; then
    ProductCode="$DcsLinuxProductCode"
    UpgradeCode="$DcsLinuxUpgradeCode"
  fi

  if [ "$settingsString" = "$productStrSepLinux" ]; then
    ProductCode="$SepLinuxProductCode"
    UpgradeCode="$SepLinuxUpgradeCode"
  fi
  
  new_package="$NEW_SIS_VERSION,en-US,$ProductCode,$UpgradeCode"
  TELEMETRY_CMD="\"$TELEMETRY_DIR/seticli\" --settings "$settingsString" --new_package \"$new_package\""
   
  local SDCSS_TMP_LOGDIR="`mktemp -d "$MYDIR/sdcssTempLogDirXXXX"`"
  local rc_mktemp=$?
    
  if ( [ "$rc_mktemp" = 0 ] && [ ! -z "$SDCSS_TMP_LOGDIR" ] && ([ "$result" = 1 ] || [ "$result" = 2 ]) ); then
    if ( [ ! -z "$SDCSSLOG_DIR" ] || [ -f "$MYDIR/$_LOGFILE" ] ); then
      INSTALL_LOGFILE="$SDCSSLOG_DIR/agent_install.log"
      if [ -d "$SDCSS_TMP_LOGDIR" ]; then
        [ -f "$INSTALL_LOGFILE" ] && cp "$INSTALL_LOGFILE" "$SDCSS_TMP_LOGDIR"
        [ -f "$MYDIR/$_LOGFILE" ] && cp "$MYDIR/$_LOGFILE" "$SDCSS_TMP_LOGDIR"
        if [ -f "$SDCSS_TMP_LOGDIR/agent_install.log" ] || [ -f "$SDCSS_TMP_LOGDIR/$_LOGFILE" ]; then 
          TELEMETRY_CMD="$TELEMETRY_CMD --collect_logs --logpath \"$SDCSS_TMP_LOGDIR\""
        fi
      fi
    fi
  fi

  addUpgradeArgs
  
  TELEMETRY_CMD="$TELEMETRY_CMD --result $result --action $teleaction"
  log_msg "Executing seticli command with parameters, action: $teleaction and installresult: $result"

  [ "$MYDIR" = "$TELEMETRY_DIR" ] && LD_LIBRARY_PATH="$MYDIR"${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} || \
     LD_LIBRARY_PATH=/opt/Symantec/sdcssagent/IPS/bin:/opt/Symantec/sdcssagent/IPS/installtelemetry${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

  eval LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\" "$TELEMETRY_CMD" ; rc_tm=$?;
  if [ $rc_tm = 0 ]; then
    log_msg "Successfully executed seticli command."
  else
    log_msg "Error while executing seticli command. return code: $rc_tm"
  fi    
  
  local seticli_logdir="$SDCSSLOG_DIR/seticlilog"
  
  if [ -d "$SDCSSLOG_DIR" ] && [ ! -d "$seticli_logdir" ]; then
    mkdir -p "$seticli_logdir" 2>/dev/null
  fi

  if ( [ "$result" = 0 ] || [ "$teleaction" = 2 ] ) && [ -d "$seticli_logdir" ]; then
	cp -f /tmp/seticli_*.log "$seticli_logdir" 2>/dev/null
	rm -f /tmp/seticli_*.log 2>/dev/null
  fi  
   
  if [ "$rc_mktemp" = 0 ]; then
    case "$SDCSS_TMP_LOGDIR" in
      */sdcssTempLogDir????)
        [ -d "$SDCSS_TMP_LOGDIR" ] && rm -rf "$SDCSS_TMP_LOGDIR"
      ;;
    esac
  fi
  unset SDCSS_TMP_LOGDIR INSTALL_LOGFILE TELEMETRY_CMD
  return 0;
}

installAgent()
{
  [ $INSTALL = false ] && return 0;
  _reinstall=false

  isPreventionEnabled && error 1 "Agent install failed as prevention policy is applied. Revoke the prevention policy before installing the agent."

  # special case on ub14 - either install all from repo or all local packages due to apt inability to do both
  [ $OS = ubuntu14 ] && [ `ls -1 "$PWD"/*.$PLAT_PKG 2>/dev/null |wc -l` -gt 0 ] && \
   [ `ls -1 "$PWD"/*.$PLAT_PKG 2>/dev/null |wc -l` -lt ${#PACKAGES[@]} ] && \
     downloadPackages "${PACKAGES[@]} $SCRIPTS_PACKAGE"

  getSAEPAgentVersion
  [ "$SEPFL_VERSION" ] && _VERSION=$SEPFL_VERSION || _VERSION=$PRODUCT_VERSION
  log_msg "`printf \"\n%-22s %s\n\" "$PRODUCT_NAME" $_VERSION`" 1

  # Update/install installer scripts
  installScripts

  # look for any local packages first, only pick sdcss-kmod if newer package on repo
  pkgs_installed ${PACKAGES[*]}; pkgs_installed=$?
  declare -a INSTALL_PKGS=() pkgs_msg=()
  local_cnt=0; i=0; j=0
  for pkg in ${PACKAGES[@]}; do 
    pkg_name=$pkg
    log_msg "installAgent() pkg: $pkg"
    localfile="`find $PWD -type f -regex "$PWD/$pkg[-_][0-9].*$PKG_MASK.*\.$PLAT_PKG" 2>/dev/null |sort -V |tail -1`"
    [ $REPO_COMM_STATUS -eq 0 ] && repo_pkg_ver=`avail_pkg_version $pkg`
    
    if ( [ ! -z "$_AGENT_TYPE" ] && [ "$_AGENT_TYPE" = "3" ] && [ "$pkg" = "sdcss" ] ); then
      installed_pkg_ver=`pkg_version sdcss-sepagent`
    else
    installed_pkg_ver=`pkg_version $pkg`
    fi
    
    if [ "$localfile" ]; then
      log_msg "installAgent() localfile: $localfile"
      local_pkg_ver=`pkg_version $localfile`
    fi
    
    # Select local or repo package for consideration
    if [ "$localfile" ] && ( [ -z "$repo_pkg_ver" ] || \
       ( [ "$repo_pkg_ver" ] && version_ge $local_pkg_ver $repo_pkg_ver ) ); then
      log_msg "installAgent() local package selected"
      pkg=$localfile; pkg_ver=$local_pkg_ver; pkgsrc="file"; ((local_cnt++))
    elif  [ -z "$repo_pkg_ver" ]; then log_msg "No available package version found for $pkg"
    else 
      if [ "$localfile" ] && [ $pkg != $KMOD_PACKAGE ] && [ $ISUPGRADE = false ]; then
         log_msg "selecting local file package for $pkg install $pkg ($local_pkg_ver, repo version $repo_pkg_ver)"
        pkg=$localfile; pkg_ver=$local_pkg_ver; pkgsrc="file"; ((local_cnt++))
      else
        pkg_ver=$repo_pkg_ver; pkgsrc="repo"; pkg=`check_pkg_names $pkg`
        log_msg "selecting package from repo for install $pkg ($pkg_ver)"
      fi
    fi

    if [ "$installed_pkg_ver" ] && [ "$pkg_ver" ] && version_ge $installed_pkg_ver $pkg_ver && \
       pkg_installed $pkg_name && [ $FORCE = false ]; then
         log_msg "\nNo update needed for ${PACKAGES[$i]} ($installed_pkg_ver)" 1
    elif [ "$pkg_ver" ]; then INSTALL_PKGS[$j]="${pkg}";
      if [ "$installed_pkg_ver" ]; then INSTALL_PKGS_VER[$j]="${pkg}-${pkg_ver}"
         pkgs_msg[$j]="`printf ' %-40s %-15s -> %-15s (%s)' $(basename $pkg) $installed_pkg_ver $pkg_ver $pkgsrc`"
         [ "$installed_pkg_ver" = "$pkg_ver" ] && log_msg "Reinstalling ${PACKAGES[$i]} ($installed_pkg_ver)" 1 && _reinstall=true
      else pkgs_msg[$j]="`printf ' %-40s %-15s (%s)' $(basename $pkg) $pkg_ver $pkgsrc`"
      fi
      ((j++));
    fi
    if [ "$pkg_name" = $AGENT_PACKAGE ]; then  
      PREV_SIS_VERSION="$installed_pkg_ver"
      NEW_SIS_VERSION="$pkg_ver"
      PREV_SIS_VERSION="${PREV_SIS_VERSION//-/.}"
      NEW_SIS_VERSION="${NEW_SIS_VERSION//-/.}"
      export DO_NOT_SEND_TELEMETRY
    fi
    ((i++));
    unset repo_pkg_ver installed_pkg_ver local_pkg_ver pkg pkg_ver pkgsrc
  done

  if [ ${#INSTALL_PKGS[@]} -eq 0 ] && [ $FORCE = false ]; then
     if [ $CONFIGURE = true ]; then
       log_msg "\nNo packages found that need update. Continuing with CAF configuration"
       disableSDCSSRepo
       return 0
     else log_msg "\nNo packages found that need update" 1; clean_exit 0
     fi
  fi
  selinux_off
  if [ $ISUPGRADE = false ]; then
     # print install message
     log_msg "\nInstalling packages:" 1
     log_msg "`printf ' %-40s %-15s %s\n' Package Version Source`" 1
     log_msg " ---------------------------------------- --------------- ------" 1
     log_msg "`for ((i=0; i< ${#pkgs_msg[@]}; i++)); do printf "%s\n" "${pkgs_msg[$i]}"; done`\n" 1 
  else  #Upgrading
     # print upgrade message
     log_msg "\nUpdating packages:\n" 1
     log_msg "`printf ' %-40s %-15s    %-15s %s\n' Package Installed Update Source`" 1
     log_msg " ---------------------------------------- ---------------    --------------- ------" 1
     log_msg "`for ((i=0; i< ${#pkgs_msg[@]}; i++)); do printf "%s\n" "${pkgs_msg[$i]}"; done`\n" 1 

     dcsAgentStop
     if [ "$PRODUCT_ID" != "DCS" ]; then
       log_msg "updating SPOC URL"
       [ -f $CAF_STORAGE_INI_FILE_PATH ] && sed -i 's#spoc-url=.*norton.*#spoc-url=us.spoc.securitycloud.symantec.com#' $CAF_STORAGE_INI_FILE_PATH
     fi
  fi
  
  # clean up any prior messages from install/upgrade
  [ -f /var/tmp/agent_install.msg ] && rm -f /var/tmp/agent_install.msg

  setInstallPackages "${INSTALL_PKGS[@]}"
  if ( [ "$AGENT_TYPE" = "4" ] || [ "$AGENT_TYPE" = "5" ] ) && \
     ( [ "$installed_agentpkg" = "true" ] || [ "$installed_cafpkg" = "true" ] ); then
    installDependency ; ret=$?
    if [ $ret != 0 ]; then
      log_msg "installAgent: Dependency check or dependency install failed on $OS."
      ( [ "$AGENT_TYPE" = "1" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 1 "$productStrDcsLinux"
      ( [ "$AGENT_TYPE" = "4" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 1 "$productStrSepLinux"
      [ $ISUPGRADE = true ] && error 1 "Agent upgrade of packages failed: ${INSTALL_PKGS_VER[*]}" || \
        error 1 "Agent install failed.";      
    fi
  fi
  ret=0
  if ( [ ! -z "$_AGENT_TYPE" ] && [ "$_AGENT_TYPE" = "3" ] && [ $ISUPGRADE = true ] ); then
    if ( [ "$installed_agentpkg" = "true" ] || [ "$installed_cafpkg" = "true" ] ); then
      checkDependency ; ret=$?
      [ "$ret" != 0 ] && log_msg "installAgent: Package dependency check failed"
    fi
    if [ "$ret" = 0 ]; then
      for p in ${INSTALL_PKGS[@]}; do
        if [ "$p" = "sdcss" ] || echo ${p} | grep -qi "sdcss-[6-9]"; then
          if [ "$PKG_MGR" = "apt" ]; then
            updateDEBScripts ; ret=$?
            PURGE_SDCSSSEPAGENT=true
          else
            log_msg "Erasing sdcss-sepagent..."
            rpm -e --justdb --nodeps --noscripts sdcss-sepagent
            installPackages false ${p}; ret=$?
          fi
        fi
      done
    fi
    if [ "$ret" != 0 ]; then
      installMessage
      disableSDCSSRepo   # Always leave Repo disabled
      ( [ "$AGENT_TYPE" = "1" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 1 "$productStrDcsLinux"
      ( [ "$AGENT_TYPE" = "4" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 1 "$productStrSepLinux"
      error 1 "Agent upgrade failed please check error log $_LOGFILE";
    fi
  fi
  
  [ "$DCS_DUAL" = true ] && dcsAgentStop
  
  if [ ${#INSTALL_PKGS[@]} -eq 1 ]; then
    for p in ${INSTALL_PKGS[@]}; do
      if [ "$p" = "sdcss-kmod" ]; then
        DO_NOT_SEND_TELEMETRY=true
      fi
    done
  fi
  
  # Install or update the agent packages
  installPackages $ISUPGRADE "${INSTALL_PKGS[@]}"; ret=$?
  installMessage
  if [ $ret != 0 ]; then
     disableSDCSSRepo   # Always leave Repo disabled
     if [ "$PURGE_SDCSSSEPAGENT" = "true" ]; then
       [ -f "$listfiledestpath" ] && mv "$listfiledestpath" "$listfilesrcpath"
       [ -f "$md5sumsfiledestpath" ] && mv "$md5sumsfiledestpath" "$md5sumsfilesrcpath"
     fi
     ( [ "$AGENT_TYPE" = "1" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 2 "$productStrDcsLinux"
     ( [ "$AGENT_TYPE" = "4" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 2 "$productStrSepLinux"
     [ $ISUPGRADE = true ] && { dcsAgentStart; error 1 "Agent upgrade of packages failed: ${INSTALL_PKGS_VER[*]}"; } || \
       error 1 "\nAgent install failed please check error log $_LOGFILE";
  else
     if [ "$PURGE_SDCSSSEPAGENT" = "true" ]; then
       dpkg --purge sdcss-sepagent 
       rm -f "$md5sumsfiledestpath"
       rm -f "$listfiledestpath"
     fi
     ( [ "$AGENT_TYPE" = "1" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 0 "$productStrDcsLinux"
     ( [ "$AGENT_TYPE" = "4" ] || [ "$AGENT_TYPE" = "5" ] ) && reportTelemetry 0 "$productStrSepLinux"
     [ $ISUPGRADE = true ] && log_msg "Agent upgrade of packages successful: ${INSTALL_PKGS_VER[*]}" 3 || \
       log_msg "\nAgent installed successfully" 1
  fi

  [ -f /etc/sisips/rebootRequired ] && [ -d $VM_EXT_UPDATE_IN_PROGRESS_DIR ] && \
     touch $VM_EXT_REBOOT_AFTER_INSTALL_FILE

  [ $REQUIRE_REBOOT_AFTER_INSTALL = true ] && touch /etc/sisips/rebootRequired

  # double check repo, upgrade from 1.5 may remove or leave empty repo file (1.5 postrm)
  if [ ! -f $REPOFILE ] || ! grep -q "$REPO_NAME" $REPOFILE; then configureSDCSSRepo >/dev/null; fi

  # restore the sepfl.pem file if exist
  restore_sepfl_pem

  # Always leave Repo disabled
  disableSDCSSRepo

  # Special case after upgrade from older agent, installagent.sh can be removed, replace with new ones
   [ ! -f $INSTALLER_SCRIPT ] && cp -fsv /usr/lib/symantec/scripts/*.sh /usr/lib/symantec >>$_LOGFILE 2>&1

  selinux_on

  return 0;
}

imageNotice()
{
  printf "\nNotice: Installation was ran  with –image switch to create\na templated image such as Amazon AMI.\n"
  printf "Instance is ready for Image creation. Please DO NOT Reboot.\n"
  printf "Shutdown the machine at convenience.\n\n"
  return 0
}


dcsAgentStart()
{
  [ $IMAGE = true ] && imageNotice && return 0
  [ -f $NOAGENTSTART ] && \
    log_msg "NOTICE: $NOAGENTSTART exists. Skipping agent start.\nRemove this file and run /usr/lib/symantec/start.sh to start the agent services." 1 && return 0

  [ $ISUPGRADE = false ] && { log_msg "Starting Agent.." 1; _action=start; } || \
     { log_msg "Restarting Agent.." 1; _action=restart; }
  for agent in ${DAEMONS[@]}; do
    case $INIT_SUBSYSTEM in
      systemd) systemctl $_action ${agent}.service >>$_LOGFILE 2>&1;;
      *) service $agent $_action >>$_LOGFILE 2>&1;;
    esac
  done
  unset _action
}

dcsAgentStop()
{
  log_msg "Stopping Agent.." 1
  for agent in ${DAEMONS[@]}; do
    case $INIT_SUBSYSTEM in
      systemd) systemctl stop ${agent}.service >>$_LOGFILE 2>&1;;
      *) service ${agent} stop >>$_LOGFILE 2>&1;;
    esac
  done
}

disableService()
{
  [ -z "$1" ] && return 1
  log_msg "Disabling service $1.."
  for dname in $1; do
    log_msg "Disabling service $dname.." 1
    if [ "$INIT_SUBSYSTEM" = "systemd" ]; then
      systemctl disable -f ${dname}.service >>$_LOGFILE 2>&1      
      systemctl daemon-reload >>$_LOGFILE 2>&1
    else
      case $OS in
        rhel6|amazonlinux)
          chkconfig --del $dname >>$_LOGFILE 2>&1
          ;;
        ubuntu14)
          update-rc.d -f $dname remove >>$_LOGFILE 2>&1
        ;;   
      esac
    fi
  done
  
  unset dname
}

checkDaemonStatus()
{
  [ -z "$1" ] && return 1
  local daemon=$1 retcode=0;

  [ -f $NOAGENTSTART ] && status+=" ($NOAGENTSTART exists)" && return 0;
  
  case $daemon in
    sisamdagent)
      if [ "`getValue amdmanagement.amdstate $AMDCONFIGFILE`" = "disable" ]; then status+=" (AMD feature disabled)" ;
      else retcode=1
      fi
  esac
  return $retcode
}

checkPackageStatus()
{
  [ "$UNINSTALL" = true ] && return 0
  pkgs_installed ${PACKAGES[*]} $SCRIPTS_PACKAGE
  if [ $? -lt `expr ${#PACKAGES[@]} + 1` ]; then
    log_msg "Agent is not fully installed, not all packages are installed" 1
    return 1
  fi
  return 0
}

checkDriverStatus()
{
  [ -z "$1" ] && return 1
  local module=$1 modinit=$module retcode=0;

  # Check if kernel is supported 
  [ "$module" = sisfim ] && modinit=sisids
  if [ -f /etc/init.d/${modinit}.init ]; then
    /etc/init.d/${modinit}.init which >>$_LOGFILE 2>&1
    if [ $? != 0 ]; then
      log_msg "${module} not supported for kernel `uname -r`"
      status+=" (kernel not supported)"
      return 1
    fi
  else 
     log_msg "Missing driver startup script /etc/init.d/${modinit}.init" 1
     return 1
  fi

  # Check various reasons why modules may be disabled
  case $module in
    sisap|sisevt) 
      if [ "`getValue Enable /etc/sisips/sisap.reg`" = "0" ]; then status+=" (AP feature disabled)" ;
      elif [ "`getValue apdriver.enable $AMDCONFIGFILE`" = "disable" ]; then status+=" (AP feature disabled)" ;
      elif grep -q SISAPNULL /proc/cmdline; then status+=" (AP feature disabled by boot cmdline)"
      elif [ "$module" = "sisap" ] && [ "${RUNNING[sisamdagent]}" = "" ]; then status+=" (AMD service not running)"
      else retcode=1
      fi ;;
    sisfim) 
      if [ "`getValue Enable /etc/sisips/sisids.reg`" = "0" ]; then status+=" (RT-FIM feature disabled)";
      elif [ "${RUNNING[sisidsagent]}" = "" ]; then status+=" (IDS service not running)"
      else retcode=1
      fi ;;
    sisips) 
      if [ "`getValue Enable /etc/sisips/sisips.reg`" = "0" ]; then status+=" (IPS feature disabled)";
      elif grep -q SISIPSNULL /proc/cmdline; then status+=" (IPS feature disabled by boot cmdline)";
      elif [ -f /etc/sisips/rebootRequired ]; then status="reboot required";
      else retcode=1
      fi ;;
  esac

  return $retcode
}

dcsAgentStatus()
{
  [ $IMAGE = true ]  && return 0
  checkPackageStatus || return 1

  [ $INSTALL = false ] && isDevRepo && devRepoNotice

  local ret=0 runcnt=0 modcnt=0;
  local daemon_status=0 module_status=0;

  if [ "$AGENT_TYPE" != 1 ]; then
    getSAEPAgentVersion
    [ "$SEPFL_VERSION" ] && _VERSION=$SEPFL_VERSION || _VERSION=$PRODUCT_VERSION
    log_msg "`printf \"\n%-22s %s\n\" "$PRODUCT_NAME" $_VERSION`" 1
  fi

  if ( [ "$AGENT_TYPE" = 1 ] || [ "$AGENT_TYPE" = 5 ] ); then
    getSDCSSAgentVersion
    [ "$AGENT_TYPE" = 1 ] && SDCSS_NAME="${SAL_STR}${SDCSS_NAME}"
    log_msg "`printf \"%-22s %s\n\" "$SDCSS_NAME" $SDCSS_VERSION`" 1
  fi
  # Check agent status
  log_msg "\nDaemon status:" 1
  declare -A RUNNING 
  for agent in ${DAEMONS[@]}; do 
    local status="not enabled"
    case $INIT_SUBSYSTEM in
      systemd) #rhel7,amzn2,ub16,ub18,etc
        systemctl is-enabled -q $agent 2>&1 && msg=`systemctl status $agent 2>&1`; st=$?
        [ $st = 0 ] && status="running" || status="not running";;
      *) #rhel6,amzn1,ub12,ub14
        if [ -x /etc/init.d/$agent ]; then
          msg=`service $agent status 2>&1`; st=$?
          echo "$msg" |grep -q "is running (PID " && status="running" || status="not running"
        fi;;
    esac
    if [ "$status" = "running" ]; then
      RUNNING[$agent]="$status"; 
      ((runcnt++)); 
    else
      checkDaemonStatus $agent; 
      ((daemon_status|=$?)); 
    fi
    printf "  %-20s %s\n" $agent "$status"
    log_msg "------ $agent status $status (rc=$st)\n$msg"
    unset status
  done

  # Check modules loaded
  sleep 2; # sleep some time to allow modules (primarily sisfim) to load
  log_msg "\nModule status:" 1
  for module in ${MODULES[@]}; do 
    msg=`grep -w ^$module /proc/modules`
    if [ "$msg" ]; then 
      status="loaded"; 
      ((modcnt++)); 
    else 
      status="not loaded"; 
      checkDriverStatus $module; 
      ((module_status|=$?));
    fi

    printf "  %-20s %s\n" $module "$status"
    log_msg "------ $module status $status\n$msg"
    unset status
  done
  
  [ "$PRODUCT_ID" = "DCS" ] && CAF_COMM_TEST=false
  
  if [ "$CAF_COMM_TEST" = "true" ]; then  # TBD- to remove after implemented for CWP

  # Check CAF connection status
  log_msg "\nCommunication status:" 1
  local comm_result comm_proxy
  # The first two are CAF and AMD agents are needed for communication test to succeed
  if [ "${RUNNING[cafagent]}" = "running" ] && [ "${RUNNING[sisamdagent]}" = "running" ]; then
    comm_result="unknown"
    for ((i=0; i<$TMOUT_SEC; i++)); do
      if [ -f $CAF_COMMUNICATION_LOG ]; then
        IFS='|' read -a array < $CAF_COMMUNICATION_LOG
        comm_result=${array[1],,}   #get comm status and convert to lowercase
        break
      fi
      printf "."
      sleep 1
    done
    unset IFS
    comm_proxy=${array[3],,}  # will return proxy or noproxy
    [ $i -gt 0 ] && printf "\n"
    printf "  %-20s %s\n" "server connection" "$comm_result"
    [ $i = $TMOUT_SEC ] && log_msg "timed out waiting for CAF connection log" 1 || \
      log_msg "------ connection result after $i seconds: $comm_result\n`cat $CAF_COMMUNICATION_LOG 2>/dev/null`"
    
    # Check if proxy is configured but was not used
    isvarset "$NEW_PROXY_ADDR" && [ -n "$comm_proxy" ] && [ "$comm_proxy" != "proxy" ] && \
      log_msg "\nWARNING: Proxy information provided but not used. Please check proxy details\nin $CAFCONFIGFILE and check for errors in /var/log/sdcss-caflog/cafagent.log" 1
  else
    #Otherwise display meaningful message
    log_msg "CAF and/or AMD daemon did not start successfully. Bypassing communication check" 1
    [ $daemon_status -eq 0 ] && [ $module_status -eq 0 ] && comm_result="success"
  fi

  fi
  printf "\n";

  # unique return codes indicating issue starting agent or communicating
  if [ $daemon_status -ne 0 ]; then ret=2
    [ $INSTALL = true ] && log_msg "Error 2: Some services failed to start" 1
  elif [ $module_status -ne 0 ]; then ret=3
    [ $INSTALL = true ] && log_msg "Error 3: Some modules failed to load" 1
  elif [ "$comm_result" != "success" ] && [ "$CAF_COMM_TEST" = "true" ]; then ret=4
    [ $INSTALL = true ] && log_msg "Error 4: Communication error" 1
  fi
  return $ret
}

getSDCSSAgentVersion()
{
  SIS_VER_FILE="/etc/sisips/sis-version.properties"
  
  if [ -f "$SIS_VER_FILE" ]; then 
    SDCSS_VERSION=`grep ^version $SIS_VER_FILE |cut -d= -f2`
    SDCSS_BUILDNO=`grep ^build\.number $SIS_VER_FILE |cut -d= -f2`
    ( [ ! -z "$SDCSS_VERSION" ] && [ ! -z "$SDCSS_BUILDNO" ] ) && SDCSS_VERSION="$SDCSS_VERSION.$SDCSS_BUILDNO"
  fi
  
  [ -z "$SDCSS_VERSION" ] && SDCSS_VERSION=`pkg_version $AGENT_PACKAGE`
  SDCSS_VERSION="${SDCSS_VERSION//-/.}"
  if [ "$SDCSS_VERSION" ]; then  
    export SDCSS_VERSION
    log_msg "getSDCSSAgentVersion: SDCSS_VERSION=$SDCSS_VERSION"
  fi
}

getSAEPAgentVersion()
{
   if [ $PRODUCT_ID = SEPM ] || [ $PRODUCT_ID = SAEP ]; then
     sep_pkg_ver=`pkg_version $AGENT_PACKAGE`
     caf_pkg_ver=`pkg_version $CAF_PACKAGE`
     [ -z "$sep_pkg_ver" ] && sep_pkg_ver=`avail_pkg_version $AGENT_PACKAGE`
     [ -z "$caf_pkg_ver" ] && caf_pkg_ver=`avail_pkg_version $CAF_PACKAGE`

     # Refresh SEP RU/Product version in case of upgrade
     if [ "$caf_pkg_ver" ]; then
       sep_ru_ver=`echo $caf_pkg_ver |sed 's/[0-9].*\.[0-9].*\.\([0-9].*\)[\.-]\([0-9].*\)/\1/'` 
       [ "$sep_ru_ver" ]  && SEP_RU_VERSION=$sep_ru_ver && PRODUCT_VERSION=${SEP_VER}RU${SEP_RU_VERSION}
       unset sep_ru_ver
     fi

     if [ "$sep_pkg_ver" ]; then
       export build_no="`echo $sep_pkg_ver |sed 's/\([0-9].*\.[0-9].*\.[0-9].*\)[\.-]\([0-9].*\)/\1/'`"
       export release_no="`echo $sep_pkg_ver |sed 's/\([0-9].*\.[0-9].*\.[0-9].*\)[\.-]\([0-9].*\)/\2/'`"
       SEPFL_VERSION="$SEP_VER.${release_no}.${SEP_RU_VERSION}${SEP_MP_VERSION}00"
       export SEPFL_VERSION
       log_msg "build_no=$build_no release_no=$release_no SEPFL_VERSION=$SEPFL_VERSION"
     fi
   fi
}

dcsAgentVersion()
{
   repeat() { v=$(printf "%-${2}s" "$3"); echo "${v// /$1}"; }

   # print installed and available repo package versions
   [ ! -f $REPOFILE ] && [ $ISUPGRADE = false ] && cleanrepo=true || cleanrepo=false
   configureSDCSSRepo

  if [ "$AGENT_TYPE" != 1 ]; then
    getSAEPAgentVersion
    [ "$SEPFL_VERSION" ] && _VERSION=$SEPFL_VERSION || _VERSION=$PRODUCT_VERSION
    log_msg "`printf \"\n%-22s %s\n\" "$PRODUCT_NAME" $_VERSION`" 1
  fi
  if ( [ "$AGENT_TYPE" = 1 ] || [ "$AGENT_TYPE" = 5 ] ); then
    getSDCSSAgentVersion
    [ "$AGENT_TYPE" = 1 ] && SDCSS_NAME="${SAL_STR}${SDCSS_NAME}"
    log_msg "`printf \"%-22s %s\n\" "$SDCSS_NAME" $SDCSS_VERSION`" 1
  fi

   # print my version
   log_msg "`printf \"%-22s %s\n\" $(basename $MYNAME) $MY_VERSION`"

  local _pkgs=(${PACKAGES[@]} $SCRIPTS_PACKAGE)
  if [ "$listAllRepo" = "true" ]; then
    if [ $REPO_COMM_STATUS -eq 0 ]; then 
      log_msg "\nPackage Info:" 1
      printf "\n  %-7s %-20s %-20s\n" Index PkgName Available
      printf   "  %-7s %-20s %-20s\n" `repeat - 7` `repeat - 20` `repeat - 20`
      for ((i=0; i<${#_pkgs[@]}; i++)); do
        pkg=${_pkgs[$i]}
        pkgsavail="$(avail_pkg_version $pkg true)"
	[ -z "$pkgsavail" ] && pkgsavail="not_available"
	echo "$pkgsavail" |awk -vp=$pkg '{printf "  %-7d %-20s %-20s\n",i++,p,$1}'
	printf "\n"
      done
    else log_msg "Repo is not configured or unavailable." 1
    fi
  else
    log_msg "\nPackage Info:" 1
    printf "\n  %-20s %-20s %-20s\n" PkgName Installed Available
    printf   "  %-20s %-20s %-20s\n" `repeat - 20` `repeat - 20` `repeat - 20`
    for ((i=0; i<${#_pkgs[@]}; i++)); do
      pkg=${_pkgs[$i]}
      if pkg_installed $pkg; then
        pkgver=$(pkg_version $pkg)
      else pkgver="not installed"
      fi
      if [ $REPO_COMM_STATUS -eq 0 ]; then
        pkgavail=$(avail_pkg_version $pkg)
        [ -z "$pkgavail" ] && [ "$pkgver" ] && pkgavail=$pkgver  # this happens on YUM.. avail not shown if the same
        [ "$pkgavail" = "not installed" ] && pkgavail="not_available"
      else pkgavail="not_available"
      fi
      log_msg "`printf \"  %-20s %-20s %-20s\n\" $pkg \"$pkgver\" \"$pkgavail\"`" 1
    done
  fi

  [ $REPO_COMM_STATUS = 0 ] && log_msg "\nBase Repo URL: $BASE_REPO_URL" 1
  [ $cleanrepo = true ] && [ $debugMode = false ] && rm -f $REPOFILE
  disableSDCSSRepo
  return 0
}

kmod_check()
{
  grep -q -E "^sisips|^sisfim|^sisevt" /proc/modules 2>/dev/null;
  return $?
}

pkg_install()
{
  rc=1
  log_msg "pkg_install: Installing packages $*"
  case $PKG_MGR in
   yum) yum -y install $* >>$_LOGFILE 2>&1; rc=$?;;
   apt) apt-get -y install $* >>$_LOGFILE 2>&1; rc=$?;;
   zypp) zypper -vn install $* >>$_LOGFILE 2>&1; rc=$?;;
  esac
  return $rc
}

pkg_uninstall()
{
  rc=0
  log_msg "Removing packages $*" 1
  case $PKG_MGR in
   yum) yum remove -y $* >>$_LOGFILE 2>&1; rc=$?;;
   apt) apt-get purge -y $* >>$_LOGFILE 2>&1; rc=$?;;
   zypp) zypper -vn rm $* >>$_LOGFILE 2>&1; rc=$?;;
  esac
  return $rc
}

copyInstallLogs ()
{
  if [ -f "$MYDIR/$_LOGFILE" ]; then
    if ( [ ! -z "$DCSLOGFILE" ] && [ -d `dirname $DCSLOGFILE` ] ); then 
      cat "$MYDIR/$_LOGFILE" 2>/dev/null >> $DCSLOGFILE; rm -f "$MYDIR/$_LOGFILE"
      _LOGFILE=$DCSLOGFILE
    elif [ $_LOGFILE != /var/log/`basename $_LOGFILE` ]; then
       cp -f "$MYDIR/$_LOGFILE" /var/log/`basename $_LOGFILE` 2>/dev/null
    fi
  fi
}

preUninstallCheck()
{
  pkgs_installed ${PACKAGES[*]} $SCRIPTS_PACKAGE; ret=$?
  if [ $ret -gt 0 ]; then
    if [ $ret -gt 0 ]; then
       isPreventionEnabled && error 9 "Uninstall of $UNINST_PROD agent failed as policies are not revoked. Revoke all policies before uninstalling the $UNINST_PROD agent."
    fi
  else
    echo "Agent is not installed"
    exit 0
  fi
  return 0
}

#-------------------------------------------------------
#  cleanFIMpolicydata() Function
#  Parameters: none
#  Purpose: cleanup the FIM policy data
#-------------------------------------------------------
cleanFIMpolicydata()
{
  local filewatchini="/opt/Symantec/sdcssagent/IDS/system/filewatch.ini"
  local filewatchdat="/opt/Symantec/sdcssagent/IDS/bin/FileWatch.dat"
   
  [ -f "$filewatchini" ] && rm -rf "$filewatchini"
  [ -f "$filewatchdat" ] && rm -rf "$filewatchdat"

  local idssystempath="/opt/Symantec/sdcssagent/IDS/system"
  [ ! -d "$idssystempath" ] && return 1
  
  local sepedrconfigpol="/opt/Symantec/sdcssagent/IDS/system/sep_edr_config.pol"
  for polfilename in `ls -1d ${idssystempath}/*.pol`; do
    if echo ${polfilename} | grep -qi "sep_edr_config.pol"; then
      log_msg "Skipping ${polfilename} file"
      continue;
    fi
    [ -f ${polfilename} ] && rm -f ${polfilename}
  done
  
  return 0
}

uninstallDCS()
{
  _LOGFILE=/var/log/sdcsslog/sdcss_uninstall.log
  preUninstallCheck
  rc_preuninst=$?
  
  [ "$rc_preuninst" != 0 ] && error 9 "Uninstallation of ${SDCSS_NAME} aborted."
  
  log_msg "Uninstalling ${SDCSS_NAME} ..." 1

  SIS_DEFAULT_IP=127.0.0.1
  CONFIG_ARGS="-r -h $SIS_DEFAULT_IP -ipsstate off -rtfim off"  

  if [ -f "/opt/Symantec/sdcssagent/IPS/sisipsconfig.sh" ]; then
    su -s /bin/bash - sisips -c "./sisipsconfig.sh $CONFIG_ARGS"
  fi

  dcsAgentStop
  
  cleanFIMpolicydata
  
  updateValue "agent.http.url" "https://127.0.0.1:443/sis-agent/" "$AGENTINI_FILE" "|"
  updateValue "server.list" "127.0.0.1" "$AGENTINI_FILE" "|"
  updateValue "agentini.checksum" "Not Computed" "$AGENTINI_FILE"
  updateValue "FIM_ENABLE" "0" "$RESPONSE_FILE"
  updateValue "IPS_ENABLE" "0" "$RESPONSE_FILE"
  updateValue "AgentType" "4" "$INSTALLREG_FILE"

  sed -i -r 's/^agent.id=(.*)/agent.id=/g' "$AGENTINI_FILE"
  
  [ -d /opt/Symantec/sdcssagent/IPS/certs ] && rm -rf /opt/Symantec/sdcssagent/IPS/certs
  
  disableService "sisipsutil"
  setAgentType

  if [ "$AGENT_TYPE" = 4 ]; then
    NEW_SIS_VERSION=`pkg_version sdcss`
    NEW_SIS_VERSION="${NEW_SIS_VERSION//-/.}"
    reportTelemetry 0 "$productStrDcsLinux" "UNINSTALL"
    UNINSTALLED_PRODUCT="${SDCSS_NAME}"; DAEMONS=(cafagent sisamdagent sisidsagent sisipsagent);
  fi
}

uninstallSEPL()
{
  _LOGFILE=/var/log/sdcsslog/sdcss_uninstall.log
  log_msg "Uninstalling $PRODUCT_NAME ..." 1
  preUninstallCheck
  rc_preuninst=$?
  
  [ "$rc_preuninst" != 0 ] && error 9 "Uninstallation of $PRODUCT_NAME aborted."

  dcsAgentStop
  pkg_uninstall "$CAF_PACKAGE" || error 1 "$PRODUCT_NAME agent uninstall failed."
  [ "$INIT_SUBSYSTEM" = "systemd" ] && systemctl daemon-reload
  
  updateValue "AgentType" "1" "$INSTALLREG_FILE"
  updateValue "AGENT_TYPE" "1" "$RESPONSE_FILE"
  updateValue "apdriver.enable" "enable" "$AMDCONFIGFILE"
  setAgentType
  
  if [ "$AGENT_TYPE" = 1 ]; then
    NEW_SIS_VERSION=`pkg_version sdcss`
    NEW_SIS_VERSION="${NEW_SIS_VERSION//-/.}"
    reportTelemetry 0 "$productStrSepLinux" "UNINSTALL"
    UNINSTALLED_PRODUCT="$PRODUCT_NAME"; PRODUCT_ID="DCS"; PRODUCT_NAME="${SDCSS_NAME}"; DAEMONS=(sisamdagent sisidsagent sisipsagent sisipsutil);
  fi
}

uninstallAgent()
{
  _LOGFILE=/var/log/sdcss_uninstall.log

  if [ -f "$VM_EXT_UPDATE_IN_PROGRESS_FILE" ]; then
    echo "Ignoring uninstall as Azure VM extension update in progress and SCWP agent doesn't require uninstall during update."
    rm -f "$VM_EXT_UPDATE_IN_PROGRESS_FILE"
    clean_exit 0;
  fi

  pkgs_installed ${PACKAGES[*]} $SCRIPTS_PACKAGE; ret=$?
  if [ $ret -gt 0 ]; then
    isPreventionEnabled && error 9 "Agent uninstall failed as policies are not revoked. Revoke all policies before uninstalling the agent."

    dcsAgentStop

    if [ "$AGENT_TYPE" != 5 ]; then
      log_msg "Uninstalling $PRODUCT_NAME ..." 1
    fi
    if [ "$AGENT_TYPE" = 5 ]; then
      log_msg "Uninstalling $PRODUCT_NAME and ${SDCSS_NAME} ..." 1
      UNINSTALLED_PRODUCT="$PRODUCT_NAME and ${SDCSS_NAME}"
    fi

    pkg_uninstall "${PKGS_INSTALLED[*]}" || error 1 "Agent uninstall failed."

    _UNINSTALLED=true
    
    # clean-up repo file
    [ -f $REPOFILE ] && rm -f $REPOFILE
    [ "$PKG_MGR" = "zypp" ] && rm -f /etc/zypp/vendors.d/symantec
  else
    echo "Agent is not installed"
    exit 0
  fi
}

setupImage()
{
   validateInput
   dcsAgentStop
   removePreventionPolicy && removeRTFIMPolicy
   updateCustomerSecretKey && create_image

   printf "Notice: Installation was ran  with –image switch to create a templated image such as Amazon AMI."
   printf "Instance is ready for Image creation. Please DO NOT Reboot.\n"
   printf "Shutdown the machine at convenience.\n\n\n"
}

configAgent()
{
  pkgs_installed ${PACKAGES[*]}; ret=$?
  [ $ret -ne ${#PACKAGES[@]} ] && error 1 "Agent is not fully installed, not all packages are installed"
  
  log_msg "Running configure of agent.."
  validateInput
  printInput |tee -a $_LOGFILE
  service cafagent stop >>$_LOGFILE 2>&1
  service sisamdagent stop >>$_LOGFILE 2>&1
  configureCAF
  configureAMD
  dcsAgentStart
  dcsAgentStatus
  copyInstallLogs
  if [ -f $VM_EXT_REBOOT_AFTER_INSTALL_FILE ]; then
    rm -f $VM_EXT_REBOOT_AFTER_INSTALL_FILE
    checkForReboot
  fi

  exit 0
}

checkForReboot()
{
   ( [ $SIMPLE_INSTALL = true ] || [ $IMAGE = true ] ) && return 0;
  if [ -f /etc/sisips/rebootRequired ] || ( [ "$_UNINSTALLED" = "true" ] && kmod_check ) ; then
    if [ $REBOOT = true ]; then
      log_msg "Rebooting..." 1
      reboot
    else
      [ $UNINSTALL = true ] && [ ! -z "$UNINSTALLED_PRODUCT" ] && PRODUCT_NAME="$UNINSTALLED_PRODUCT"
      [ $UNINSTALL = true ] && action="uninstall" || action="install"
      printf "\n$PRODUCT_NAME ${action}ed successfully.\n"
      printf "A reboot is required to complete ${action}ation.\n"
      printf "Please reboot your machine at the earliest convenience.\n"
    fi
  elif [ $REBOOT = true ]; then
    [ $UNINSTALL = true ] && action="uninstall" || action="install"
    printf "\n$PRODUCT_NAME ${action}ed successfully.\n"
    printf "A reboot was requested but is not required.\n"
  fi
}

checkScriptVersion()
{
  if [ -f $INSTALLER_SCRIPT ]; then
     script_ver=`grep ^MY_VERSION= $INSTALLER_SCRIPT |cut -d= -f2`
     if version_ge $MY_VERSION $script_ver; then
       log_msg "Installer script at same level or newer level.. carry on"
     else
       log_msg "Re-running installer script (ver $script_ver)" 1
       $INSTALLER_SCRIPT -2 $INSTALL_PARMS
       exit $?
     fi
  fi
}
version_ge() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" -o "$1" = "$2"; }
getval() { [ "$1" ] && [[ "$1" != --* ]] && [[ "$1" != -? ]] && echo -n "$1" && return 0 || return 1; }

#-------------------------------------------------------
#  validateProduct() Function
#  Parameters: $1=string product ID
#  Purpose: Valdiate if the product id provided is valid 
#           for the current agent installation
#           ALL is a valid option in all cases
#-------------------------------------------------------
validateProduct()
{
  #echo "validateProduct: AGENT_TYPE $_AGENT_TYPE, Product name $1"
  [ -z "$1" ] && [ "$_AGENT_TYPE" != "5" ] && return 0
  [ ! -z "$1" ] && [ "$1" = "ALL" ] && return 0
  [ ! -z "$1" ] && [ "$1" = "CWP" ] && [ "$_AGENT_TYPE" = "2" ] && return 0  
  [ ! -z "$1" ] && [ "$1" = "DCS" ] && ( [ "$_AGENT_TYPE" = "1" ] || [ "$_AGENT_TYPE" = "5" ] ) && return 0
  [ ! -z "$1" ] && [ "$1" = "SEPL" ] && \
    ( [ "$_AGENT_TYPE" = "4" ] || [ "$_AGENT_TYPE" = "5" ] ) && return 0
  
  return 1;
}

#-------------------------------------------------------
#  removeCAFStorage() Function
#  Parameters: None
#  Purpose: delete the CAFStorage.ini
#  Prerequisite: CAF_STORAGE_INI_FILE_PATH should be set to the location of CAFStorage.ini
#-------------------------------------------------------

removeCAFStorage()
{
   log_msg "Remove CAFStorage $CAF_STORAGE_INI_FILE_PATH"
   #delete CAFStorage 
   [ -f $CAF_STORAGE_INI_FILE_PATH ] && rm -f $CAF_STORAGE_INI_FILE_PATH
}
#-------------------------------------------------------
#  removeEncryptionDoneFlag() Function
#  Parameters: None
#  Purpose: delete the encryption_done entry from CAFConfig.ini
#  Prerequisite: CAFCONFIGFILE should be set to the location of CAFConfig.ini
#-------------------------------------------------------

removeEncryptionDoneFlag()
{
  log_msg "Remove encryption flag from $CAFCONFIGFILE"
  sed -i -r -e '/encryption_done/d' $CAFCONFIGFILE 2>/dev/null
}

trap_with_arg trap_caught INT QUIT HUP PIPE

if [ -f "$INSTALLREG_FILE" ]; then
    _AGENT_TYPE=`grep AgentType $INSTALLREG_FILE | cut -d"=" -f2`		  
    SDCSSLOG_DIR=`grep LogInstallRoot $INSTALLREG_FILE | cut -d"=" -f2 | xargs`
    [ -z "$_AGENT_TYPE" ] && error 1 "Unable to detect Agent Type"
    if [ ! -z "$_AGENT_TYPE" ] && [ "$_AGENT_TYPE" = "1" ] && [ ! -f ./manifest ]; then
      AGENT_TYPE=1
      DCS_DCS=true
      PRODUCT_ID=DCS
      log_msg "PRODUCT_ID : $PRODUCT_ID"
    fi
else
	SDCSSLOG_DIR="$SIS_DEFAULT_LOGDIR"
fi

while [ $# != 0 ]; do
 if [ "$PRODUCT_ID" != "DCS" ]; then 
  case "$1" in 
    -a|--server-address) NEW_SERVER_ADDR=`getval $2`; [ $? = 0 ] && shift;;
    -b|--reset-state) RESET_STATE=true;;
    -c|--configure) CONFIGURE=true; INSTALL=false;;
    -d|--domain-id) NEW_DOMAIN_ID=`getval $2`; [ $? = 0 ] && shift;;
    -e|--enroll) RESET_STATE=true;; # currently redundant with reset state
    -f|--force) FORCE=true;; # Force uninstall/install/reinstall (TBD)
    -g|--disable-repo) DISABLE_REPO=true;;
    -h|--local-repo) LOCAL_REPO_URL=`getval $2`; [ $? = 0 ] && shift; UPDATE_REPO=true; localRepo=true;;
    -i|--image)  IMAGE=true;;
    -k|--customer-secret-key) NEW_SECRET_KEY=`getval $2`; [ $? = 0 ] && shift;;
    -l|--protocol) NEW_PROTOCOL=`getval $2`; [ $? = 0 ] && shift;;
    -m|--proxy-mode) validateProxy=true; NEW_PROXYMODE=`getval $2`; [ $? = 0 ] && shift;;
    -n|--no-pinning)  ARG_DISABLE_PINNING=true;;
    -N|--pinning)  ARG_ENABLE_PINNING=true;;
    -o|--port) NEW_PORT=`getval $2`; [ $? = 0 ] && shift;;
    -p|--update) UPDATE=true;;
    -q|--proxy-protocol) validateProxy=true; NEW_PROXY_PROTOCOL=`getval $2`; [ $? = 0 ] && shift;;
    -r|--reboot) REBOOT=true;;
    -s|--simple-install) SIMPLE_INSTALL=true; INSTALL=true;;
    -t|--customer-id) NEW_CUST_ID=`getval $2`; [ $? = 0 ] && shift;;
    -u|--uninstall) UNINSTALL=true; INSTALL=false; UNINST_PROD=`getval $2`; [ $? = 0 ] && shift; \
                    validateProduct "$UNINST_PROD"; [ $? != 0 ] && { usage; exit 1; } ;;
    -v|--service-portal-name) NEW_SERVICE_PORTAL_NAME=`getval $2`; [ $? = 0 ] && shift;;
    -w|--proxy-user-name) validateProxy=true; NEW_PROXYUSERNAME=`getval $2`; [ $? = 0 ] && shift;;
    -x|--proxy-address) validateProxy=true; NEW_PROXY_ADDR=`getval $2`; [ $? = 0 ] && shift;;
    -y|--proxy-port) validateProxy=true; NEW_PROXY_HTTP_PORT=`getval $2`; [ $? = 0 ] && shift; 
                     NEW_PROXY_PORT=$NEW_PROXY_HTTP_PORT;;
    -z|--proxy-password) validateProxy=true; NEW_PROXYPASSWORD=`getval $2`; [ $? = 0 ] && shift;;
    --proxy-https-port) validateProxy=true; NEW_PROXY_HTTPS_PORT=`getval $2`; [ $? = 0 ] && shift;;
    --disable-feature) CWP_FEATURE_SET=`getval "$2"`; [ $? = 0 ] && shift;;
    --product-version) PRODUCT_VERSION=`getval $2`; [ $? = 0 ] && shift;;
    --tags) NEW_TAGS=`getval "$2"`; [ $? = 0 ] && shift;;
    --update-kmod) UPDATE_KMOD=true; INSTALL=true;;
    --print-platform) printPlatformInfo=true; INSTALL=false;;
    --devrepo) devRepo=true; UPDATE_REPO=true;;
    --verifyrepo) verifyRepo=true; UPDATE_REPO=true;;
    --prodrepo) prodRepo=true; UPDATE_REPO=true;;
    --configure-repo) CONFIGURE_REPO=true; UNINSTALL=false; INSTALL=false; SIS_CERT_PATH=`getval $2`; [ $? = 0 ] && shift;;    
    --download) DOWNLOAD=true; INSTALL=false;;
    --subhelp) subhelp=true; usage; exit 0;;
    --status) statusOnly=true; INSTALL=false;;
    --start)  startOnly=true; INSTALL=false;;
    --stop)  stopOnly=true; INSTALL=false;;
    --debug) start_debug;;
    -V|--version) versionOnly=true; INSTALL=false;;
    -A|--list-all) listAllRepo=true; versionOnly=true; INSTALL=false;;
    --packages) [ "$2" ] && [ -f "$2" ] && SPECIFIC_PACKAGES="`cat $2 |sed 's/\s\+/\n/g'`" || SPECIFIC_PACKAGES=`getval "$2"`; [ $? = 0 ] && shift;;
    -2) reRun=true;;
    *) subhelp=false; usage; exit 1;;
  esac
 else
  case "$1" in
    --update-kmod)    UPDATE_KMOD=true; INSTALL=true;;
    -u|--uninstall)   UNINSTALL=true; INSTALL=false; UNINST_PROD=`getval $2`; [ $? = 0 ] && shift; \
                      validateProduct "$UNINST_PROD"; [ $? != 0 ] && { usage; exit 1; } ;;
    --configure-repo) CONFIGURE_REPO=true; UNINSTALL=false; INSTALL=false; SIS_CERT_PATH=`getval $2`; [ $? = 0 ] && shift;;
    --subhelp) subhelp=true; usage; exit 0;;
    --status) statusOnly=true; INSTALL=false;;
    --debug) start_debug;;
    -V|--version) versionOnly=true; INSTALL=false;;
    -2) reRun=true;;
    *) subhelp=false; usage; exit 1;;
  esac
 fi
  shift
done

echo $MYNAME |grep -q uninstall && { UNINST_PROD=$2 | xargs; validateProduct "$UNINST_PROD"; [ $? != 0 ] && { usage; exit 1; } || \
                                   { UNINSTALL=true; INSTALL=false; INSTALL_PARMS="--uninstall $INSTALL_PARMS"; } }
echo $MYNAME |grep -q configure && { CONFIGURE=true; INSTALL=false; INSTALL_PARMS="--configure $INSTALL_PARMS"; }
echo $MYNAME |grep -q status && { statusOnly=true; INSTALL=false; INSTALL_PARMS="--status $INSTALL_PARMS"; }
echo $MYNAME |grep -q start && { startOnly=true; INSTALL=false; INSTALL_PARMS="--start $INSTALL_PARMS"; }
echo $MYNAME |grep -q stop && { stopOnly=true; INSTALL=false; INSTALL_PARMS="--stop $INSTALL_PARMS"; }
echo $MYNAME |grep -q version && { versionOnly=true; INSTALL=false; INSTALL_PARMS="--version $INSTALL_PARMS"; }

getPlatform
getProductConfig

if ( [ ! -z "$_AGENT_TYPE" ] && [ "$_AGENT_TYPE" = "3" ] ); then
  pkgs_installed sdcss-sepagent sdcss-kmod $CAF_PACKAGE;
else 
  pkgs_installed ${PACKAGES[@]};
fi

[ $pkgcnt -eq ${#PACKAGES[@]} ] && ISUPGRADE=true || ISUPGRADE=false

log_msg "ISUPGRADE : $ISUPGRADE"

# Make sure only root can run our script
[ "$(id -u)" != "0" ] && error 1 "This script must be run as root"

if [ "$PRODUCT_ID" = "DCS" ]; then
  if [ $ISUPGRADE = false ]; then
    error 1 "No previous DCS agent installation found. This script supports only upgrade for DCS agent."
  fi
fi

# IDS sets LD_LIBRARY_PATH, due to which yum gives curl error while executing this script through IDS collector.
export LD_LIBRARY_PATH=""; log_msg "clearing variable LD_LIBRARY_PATH..."

checkScriptVersion

# Status only check
[ "$statusOnly" = true ] && { dcsAgentStatus; clean_exit $?; }
[ "$startOnly" = true ] && { dcsAgentStart; clean_exit $?; }
[ "$stopOnly" = true ] && { dcsAgentStop; clean_exit $?; }

# Version check
[ "$versionOnly" = true ] && { dcsAgentVersion; clean_exit $?; }

if [ "$CONFIGURE_REPO" = true ]; then
  log_msg "Configuring repo..."
  [ ! -f "$SIS_CERT_PATH" ] && error 1 "option --configure-repo requires cert path" 
  configureSDCSSRepo; clean_exit $?;
fi

exit_rc=0;

log_msg "Running $MYNAME (PWD $MYDIR; version $MY_VERSION)"

if [ $UNINSTALL = true ]; then
  if ( [ "$_AGENT_TYPE" = "5" ] && [ "$UNINST_PROD" != "ALL" ] ); then
    if [ "$UNINST_PROD" = "DCS" ]; then
      uninstallDCS      
    elif [ "$UNINST_PROD" = "SEPL" ]; then
      uninstallSEPL
    fi
    dcsAgentStart
    dcsAgentStatus; exit_rc=$?
  else
    uninstallAgent
  fi
elif [ $IMAGE = true ] && [ $ISUPGRADE = true ]; then
  #[ $ISUPGRADE = false ] && error 1 "option --image requires agent to be installed first"
  setupImage
elif [ $ISUPGRADE = true ] && [ $ARG_ENABLE_PINNING = true ] &&  [ $CONFIGURE = false ]; then
 error 1 "option --pinning needs to be used with --configure."
elif [ $ISUPGRADE = true ] && [ $ARG_DISABLE_PINNING = true ] &&  [ $CONFIGURE = false ]; then
 error 1 "option --no-pinning needs to be used with --configure."
elif [ $CONFIGURE = true ] && [ $INSTALL = false ]; then
  configAgent
elif [ $RESET_STATE = true ]; then
  enrollCAF
elif [ $UPDATE_KMOD = true ]; then
  [ $ISUPGRADE = false ] && error 1 "option --update-kmod requires agent to be installed first"
  DAEMONS=(sisamdagent sisidsagent)
  PACKAGES=($KMOD_PACKAGE)
  configureSDCSSRepo
  installAgent
  dcsAgentStart
else  #INSTALL
  preInstallChecks
  validateInput
  configureSDCSSRepo
  [ $DOWNLOAD = true ] && { downloadPackages ${PACKAGES[*]} $SCRIPTS_PACKAGE; clean_exit $?; }
  installAgent
  if [ $SIMPLE_INSTALL = false ] && [ $UPDATE = false ]; then
    if [ $PRODUCT_ID != DCS ]; then
      configureCAF
      configureAMD
      postInstallConfigure
    fi
    dcsAgentStart
    dcsAgentStatus; exit_rc=$?
  else 
    [ -d $VM_EXT_UPDATE_IN_PROGRESS_DIR ] && touch $VM_EXT_REBOOT_AFTER_INSTALL_FILE
  fi
fi

copyInstallLogs
checkForReboot
exit $exit_rc
