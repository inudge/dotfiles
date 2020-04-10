#!/usr/bin/env bash
unset command printf shift || exit $?

# macOS only (10.11+)
if [[ "${OSTYPE:0:6}" != "darwin" ]]; then
  printf "[OSERR]: Sorry this script is macOS only, it wont run on %s\n" "$OSTYPE"
  exit 3
fi

# global constants
declare -r TMP_TRIGF="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
declare -r XCODE_PATH="/Library/Developer/CommandLineTools"
declare -r HOMEBREW_NO_ANALYTICS="No thanks"
declare -r BREWSHEL="/usr/local/bin/bash"
declare -r CLT_TEXT="Command Line Tools"
declare -r BASE_DOM="com.apple.pkg"
declare -r TESTADDR="1.1.1.1"
declare -r MIN_DISK=7                                 # minimum GBs of free disk required
declare -r MIN_BATT=50                                # percent of battery charge required

# packages that are checked to see if Apple CLTools are installed
declare -a REQ_PKGS=( CLTools_Executables CLTools_SDK_macOSSDK DevSDK )

# macOS 10.13 High Sierra Command Line Tools package list
# com.apple.pkg.DevSDK_macOS1013_Public
# com.apple.pkg.CLTools_Executables
# com.apple.pkg.OSXSDK10.13
# com.apple.pkg.CLTools_SDK_OSX1012
# com.apple.pkg.DevSDK
# com.apple.pkg.CLTools_SDK_macOSSDK
# com.apple.pkg.CLTools_SDK_macOS1013
# com.apple.pkg.XcodeCustomerContent

# global variables
declare -i pkgs_installed=0
declare -i start_seconds=0
declare -i SUDO_SECS=0
declare -i swupdl_runs=0
declare +r SWUPNAME
declare +r COFFEPID
declare +r MINMACOS
declare +r SCUTFLAG="Reachable"

LC_ALL=C

start_seconds=$(/bin/date +%s)

# check running at least macOS 10.11
MINMACOS="$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $2}')"
case $MINMACOS in
  11) ;;
  12) SCUTFLAG="Flags = Reachable" ;; # macOS Sierra's strange change
  13|14) REQ_PKGS+=( CLTools_SDK_OSX1012 CLTools_SDK_macOS1013 DevSDK_macOS1013_Public ) ;;
  15) ;; # TODO
  *)
    printf "\n:[OSXVERSERR]: Sorry, this script is unsupported on OSX 10.%d\n" "$MINMACOS"
    exit 4
    ;;
esac

# trapped exit -:- cleanup & info
bye_yo() {
  local -i know_seconds=0 diff_seconds=0 diff_minutes=0
  [[ -n "$COFFEPID"  ]] && /bin/kill  "$COFFEPID" 
  [[ -e "$TMP_TRIGF" ]] && /bin/rm -f "$TMP_TRIGF"
  /usr/bin/sudo -k
  know_seconds=$(/bin/date +%s)
  diff_minutes=$(( ( know_seconds - start_seconds ) / 60 ))
  diff_seconds=$(( ( know_seconds - start_seconds ) % 60 ))
  printf "[FINISHED]: script took %d minutes %d seconds to run\n" $diff_minutes $diff_seconds
  printf "[BYE]: %s\n\n" "$(/bin/date)"
}

# return 0 if user is not root but has admin rights
# return 1 if user is running as root
# return 2 if user is not root and not a member of admin group
check_privs() {
  if [[ $( /usr/bin/id -u ) -eq 0 ]]; then
    printf "[NOROOT]: do not run this script as root (or with sudo)\n"
    return 1
  elif [[ "$( /usr/bin/dsmemberutil checkmembership -U "$USER" -G "admin" 2>/dev/null \
           | /usr/bin/grep -Fc "user is a member of the group" )" -ne 1 ]]; then
    printf "[NOADMIN]: you must be an admin user to run this script\n"
    return 2
  fi
}

# returns 0 if free space is > $1 or $MIN_DISK
check_memory() {
  local -i free_disk_space min_disk_space
  [[ -n "$1" ]] && min_disk_space="$1" || min_disk_space="$MIN_DISK"
  free_disk_space=$( /usr/sbin/diskutil info "/" | /usr/bin/awk  \
                  '/Available Space/ {sub("\\(","",$6);print $6}' )
  [[ -n $free_disk_space ]] || free_disk_space=$(/usr/sbin/diskutil info "/"  \
              | /usr/bin/awk '/Volume Free Space/ {sub("\\(","",$6);print $6}' )
  free_disk_space=$(( free_disk_space / 1000000000 ))
  if [[  ( $free_disk_space -lt $min_disk_space )  ]]; then
    printf "[LOWDISK]: Low on disk space, minimum %s GB required\n" "$min_disk_space"
    printf "[FIXIT]: Please free up or allocate more disk space\n"
    return 1
  fi
}

# touch file $1
# return 0 if file is created and is readable
# return 1 if file exists already and is readble
# return 2 if file exists but unreadable
# return 3 if $1 param is not passed or unable to create file
touch_new_file() {
  local -r tfile="$1"
  if [[ -z "$tfile" ]]; then
    printf "[PARAMERR]: %s no parameter passed\n" "${FUNCNAME}"
    return 3
  fi
  if [[ -e "$tfile" ]]; then
    if [[ -r "$tfile" ]]; then
      return 1
    else
      printf "[FILEERR]: %s problem reading file\n%s\n" "${FUNCNAME}" "$tfile"
      return 2
    fi
  else
    /usr/bin/touch "$tfile" || { 
      printf "[PERMERR]: %s unable to create file\n%s\n" "${FUNCNAME}" "$tfile"
      return 2
    }
    if [[ -r "$tfile" ]]; then
      return 0
    else
      printf "[FILERR]: %s problem reading file\n%s\n" "${FUNCNAME}" "$tfile"
      return 2
    fi
  fi
}

# return 0 if running on AC Power or more than $MIN_BATT charge remaining
# return 1 if running on battery with less than $MIN_BATT charge remaining
check_energy() {
  local -i charge
  /usr/bin/pmset -g ps | /usr/bin/grep -Fq "AC Power" && return
  printf "[POWER]: You are not running on AC Power\n"
  charge=$(/usr/bin/pmset -g ps                       \
         | /usr/bin/awk '/InternalBattery/ {print $3}' \
         | /usr/bin/tr -dc '[:digit:]'                  )
  if [[ ($charge -lt $MIN_BATT ) ]]; then
    printf "[LOWBATT]: Only %s percent battery remaining !\n" "$charge"
    printf "[MINBATT]: This script requires a minimum of %s percent battery charge\n" "$MIN_BATT"
    printf "[ACPOWER]: Please plug into AC POWER or recharge your battery and try again\n"
    return 1
  fi
  printf "[BATTERY]: you have %s percent battery charge remaining\n" "$charge"
}

# advise user if LittleSnitch is detected
check_snitch() {
  if [[ ( "$(/bin/ls /Library/LaunchAgents/at.obdev.LittleSnitch* 2>/dev/null )" != "" ) ]]; then
    printf "[SNITCH]: If you have LittleSnitch enabled be prepared to respond to alerts\n"
    printf "[LSMODE]: ...or consider using LittleSnitch Silent Mode during this install\n"
    return 1
  fi
}

# prevent the system sleeping until we've finished
dont_sleep() {
  /usr/bin/caffeinate -dis & 
  COFFEPID="$!"
  printf "[NOSLEEP]: Temporarily preventing system from sleeping %d\n" "$COFFEPID"
}

# TRY to keep sudo alive for an improved UX
get_sudo() {
  if [[ -z "$SUDO_SECS" || $SUDO_SECS -eq 0 ]]; then
    printf "[SUDOPASSWD]: sudo is about to ask you to enter your password\n"
    printf "[PASSORQUIT]: You can enter your password or Control-C to quit\n"
  else
    local -i now_secs=$(/bin/date +%s)
    if [[ $((now_secs - SUDO_SECS )) -ge 300 ]]; then
      printf "[LASTSUDO]: More than 5 minutes have now passed since sudo was last used\n"
      printf "[RENTERPW]: sudo will now ask you to re-enter your password to continue\n"
    fi
  fi
  /usr/bin/sudo -v && SUDO_SECS=$(/bin/date +%s)
}

# wait for network connectivity
check_network() {
  local -i patience="${1:-10}"
  local -i n=0
  /bin/date
  until [[ $(/usr/sbin/scutil -r "$TESTADDR") = "$SCUTFLAG" ]] || (( n > patience )); do
    /bin/sleep $n
    case $n in
      0)          printf "[INTERNET]: waiting for internet connectivity..." ;;
      $patience)  printf ".%d :[TIMEOUT]:\n" "$n"
                  printf "[NONETWORK]: the internet is unavailable\n"
                  return 3 ;;
      *)          printf ".%d" "$n" ;;
    esac
    (( n++ ))
  done
}

# gets packaged files for package $1
get_pkg_files() {
  [[ -n "$1" ]] || { printf "[$red]: %s no package name passed\n" "ERROR" "${FUNCNAME}" ; return 3 ; }
  local +r package="$1" prefix="${BASE_DOM:-com.apple.pkg}"
  [[ -n "${package##*.*}" && -n "$prefix" ]] && package="${prefix}.${package}"
  /usr/sbin/pkgutil --files "$package"
}

# lists packages installed on $1 volume or "/"
get_pkg_list() { /usr/sbin/pkgutil --pkgs --volume "${1:-/}" ; }

# returns: 0 if package $1 is installed on $2 or "/", otherwise returns 1
pkg_is_installed() {
  [[ -n "$1" ]] || { printf "[$red]: %s no package name passed\n" "ERROR" "${FUNCNAME}" ; return 3 ; }
  local +r line package="$1"
  while read -r line; do
    [[ "$line" = "$package" ]] && return 0
  done <<< "$(/usr/sbin/pkgutil --pkgs --volume "${2:-/}")"
  return 1
}

# review status of packages in global array $REQ_PKGS
# return number of missing packages
# use $1 as target volume or "/" by default
pkgs_review() {
  local vol_name="${1:-/}"
  local -i pkgs_missing num_req_pkgs="${#REQ_PKGS[@]}"
  pkgs_installed=0
  for pack in "${REQ_PKGS[@]}"; do
    [[ -n "${pack##*.*}" ]]  && pack="${BASE_DOM}.${pack}"
    pkg_is_installed "$pack" && (( pkgs_installed++ ))
  done
  pkgs_missing=$(( num_req_pkgs - pkgs_installed ))
  if [[ $pkgs_missing -eq 0 ]]; then
    return 0
  else
    printf "[MISSPKG]: %d missing packages\n" "$pkgs_missing"
    return $pkgs_missing
  fi
}

# find out if Command Line Tools are available
ctls_already_installed() {
  DEV_DIR=$(/usr/bin/xcode-select -print-path 2>/dev/null)
  [[ "$DEV_DIR" == "$XCODE_PATH" ]] && return 0
  if [[ -z "$DEV_DIR" && -d "$XCODE_PATH" ]]; then
    pkgs_review "/" || return $?  # check for CLT packages
    xc_switch       || return $?  # run xcode-select --switch
  fi
}

xc_switch() { /usr/bin/sudo /usr/bin/xcode-select --switch "$XCODE_PATH" || return $? ; }

xc_install() {
  /usr/bin/xcode-select --install || return $?
  printf "[XCINSTALL]: %s\ninstalled using xcode-select --install\n" "$CLT_TEXT"
}

swupd_list() {
  SWUPNAME="$(/usr/sbin/softwareupdate --list 2>/dev/null
            | /usr/bin/awk '/[\*] Command Line Tools/ {sub("^([[:space:]])*[\*][ ]","",$0);print}')"
  if [[ -z "$SWUPNAME" && -z "$1" ]]; then
    check_network || exit $?
    swupd_list "onemoretime"
  fi
  [[ -n "$SWUPNAME" ]] && return 0 || return 9
}

# install Homebrew if not already available
install_brew() {
  if check_brew ; then
    printf "[BREWING]: Homebrew is already installed\n"
    return 1
  else
    yes | /usr/bin/ruby -e "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    return $?
  fi
}

check_brew() {
  # check if Homebrew is already installed
  # check if /usr/local/bin is in $PATH
  # check user login files $PATH if "logins" passed as $1
  set_brew_path "$1"
  [[ -z "$(/usr/bin/which brew)" && -z "$(command -v brew)" ]] && return 1
}

set_brew_path() {
  # check $PATH includes /usr/local/bin for Homebrew utilities
  # check login files have $PATH set if "logins" is passed as $1
  local +r file
  local -r pulb="/usr/local/bin"
  if [[ ( $(/bin/echo "$PATH" | /usr/bin/grep -Fc "$pulb" ) -ne 1 ) ]]; then
    PATH="${pulb}:${PATH}"
    printf "[APATH]: %s added to environment for Homebrew\n" "$pulb"
    printf "[UPATH]: %s\n" "$PATH"
  fi
  [[ "$1" != "logins" ]] && return  # only continue if "logins" is passed as $1

  # ensure Homebrew PATH is also defined in user's login files
  for file in "${HOME}/.bashrc" "${HOME}/.bash_profile"; do
    if [[ -O "$file" ]]; then  # file exists and is owned by effective userid
      if [[ ( $(/usr/bin/grep -F "PATH" "$file" | /usr/bin/grep -F "$pulb" ) = "" )  ]]; then
        printf "[BASHPATH]: updating PATH for Homebrew in %s\n" "$file"
        update_bash_login_path "$file" || return $?
      fi
    elif [[ ! -e "$file" ]]; then # file doesnt exist, create and protect it
        printf "[NOBASHFILE]: login file not found, creating new %s\n" "$file"
        update_bash_login_path "$file" || return $?
        /bin/chmod 600 "$file"
    else
      printf "[BASHFILES]: bash login file problem, %s not added to PATH\n" "$pulb"
      printf "[FILEOWNER]: check ownership of file %s\n" "$file" 
      return 1
    fi
  done

return 0
}

update_bash_login_path() {
  # append code to bash login file passed as $1 to ensure PATH is maintained at login
  if [[ -z "$1" ]]; then
    printf "[PARAMERR]: %s no filename passed\n" "${FUNCNAME}"
    return 3
  elif [[ ! -e "$1" ]]; then
    /bin/cat <<EOF > "$1"
if [[ ( "\$(/bin/echo "\$PATH" | /usr/bin/grep -c "usr/local/bin" )" -eq 0 ) ]]; then
  [[ -d "/usr/local/bin" ]] && PATH="/usr/local/bin:\$PATH"
fi
if [[ ( "\$(/bin/echo "\$PATH" | /usr/bin/grep -c "usr/local/opt/openssl/bin" )" -eq 0 ) ]]; then
  [[ -d "/usr/local/opt/openssl/bin" ]] && PATH="/usr/local/opt/openssl/bin:\$PATH"
fi
EOF
    return $?
  elif [[ -w "$1" ]]; then
    /bin/cat <<EOF >> "$1"
if [[ ( "\$(/bin/echo "\$PATH" | /usr/bin/grep -c "usr/local/bin" )" -eq 0 ) ]]; then
  [[ -d "/usr/local/bin" ]] && PATH="/usr/local/bin:\$PATH"
fi
if [[ ( "\$(/bin/echo "\$PATH" | /usr/bin/grep -c "usr/local/opt/openssl/bin" )" -eq 0 ) ]]; then
  [[ -d "/usr/local/opt/openssl/bin" ]] && PATH="/usr/local/opt/openssl/bin:\$PATH"
fi
EOF
    return $?
  else
    printf "[BADBASHFILE]: unable to update bash login file: %s\n" "$1"
    return 3
  fi
}

change_user_shell() {
  # change user shell to use Homebrew bash
  if [[ -z "$1" ]]; then
    local chguser="$USER"
  else
    local chguser="$1"
  fi

  # check Homebrew bash shell is available
  if [[ ! -x "$BREWSHEL" ]]; then
    printf "[SHELLMIS]: we can not use %s as a bash shell\n" "$BREWSHEL"
    return 3
  fi

  # append Homebrew bash shell to /etc/shells
  if [[ ( $(/usr/bin/grep -c "$BREWSHEL" /etc/shells ) -eq 0 ) ]] ; then
    printf "[NEWSHELL]: Appending %s to /etc/shells using sudo\n" "$BREWSHEL"
    get_sudo || return $?
#    /usr/bin/sudo /bin/bash -c "echo $BREWSHEL >> /etc/shells"
    /bin/echo "$BREWSHEL" | /usr/bin/sudo /usr/bin/tee -a /etc/shells
  fi

  # doublecheck Homebrew bash shell is now available for logins
  if [[ ( $(/usr/bin/grep -c "$BREWSHEL" /etc/shells ) -eq 0 ) ]] ; then
    printf "that didnt work so please do this command manually in terminal\n"
    printf "$ echo %s | sudo tee -a /etc/shells\n" "$BREWSHEL"
    return 2
  else
    # update users login shell to use Homebrew bash for new logins
    old_shell="$(/usr/bin/dscl . -read /Users/"$chguser" UserShell 2>/dev/null)"
    if [[ -n "$old_shell" ]]; then
      old_shell="${old_shell/'UserShell: '/}"
      if [[ "$old_shell" != "$BREWSHEL" ]]; then
        /usr/bin/sudo /usr/bin/dscl . -change /Users/"$chguser" UserShell "$old_shell" "$BREWSHEL" && return
      else
        printf "[BASHINFO]: User %s is already using bash shell %s\n" "$chguser" "$BREWSHEL"
        return
      fi
    else
      printf "[DSCLERR]: dscl error reading user %s UserShell\n" "$chguser"
    fi
  fi
  return 1
}

# check for Homebrew and install formulae if found
get_brew() {
  if check_brew ; then
    printf "[BREWINFO]: Homebrew was already installed\n"
    if install_formulae ; then     # make sure we have all required brew packages
      check_brew "logins"          # ensure user's logins will have Homebrew PATH
      change_user_shell "$USER"    # update user to use latest brew version of bash
      return $?                    # return the exit status from change_user_shell
    else
      printf "[FORMERR]: problem installing Homebrew formulae\n"
      return 2
    fi
  fi

  # check for Command Line Tools packages and if not found attempt to install them
  if ! provide_CLTs ; then
    printf "[INSTERR]: unable to provide %s\n" "$CLT_TEXT"
    if ! check_brew ; then
      printf "[NOTBREW]: Homebrew is still not installed\n"
    fi
    printf "[UREVIEW]: Please review the logs\n"
    printf "[BADEXIT]: Bad exit !\n"
    exit 4
  fi
  /bin/date

  # attempt to install Homebrew and required formulae then update user's bash shell
  install_brew                     # install Homebrew
  case $? in
  0|1)                             # Homebrew is available
    if install_formulae ; then     # Homebrew formulae have been installed
      check_brew "logins"          # ensure user's logins will have Homebrew PATH
      change_user_shell "$USER"    # update UserShell & /etc/shells to new bash
      return $?                    # return the exit status from change_user_shell
    else
      printf "[FORMERROR]: problems installing Homebrew formulae\n"
      return 2
    fi
    ;;
  *)
    printf "[BREWERR]: unable to complete Homebrew installation\n"
    return 3
    ;;
  esac
}

# check if Command Line Tools are already installed
provide_CLTs() {
  if ctls_already_installed ; then
    printf "[CLTSHERE]: %s already installed\n" "$CLT_TEXT"
    pkgs_review "/"  # review installed CLT packages
    return $?
  else
    trap "bye_yo" EXIT             # trap exit for cleanup
    dont_sleep                     # stay awake for the duration

    #  create placeholder file for softwareupdate --list
    if [[ ( $(touch_new_file "$TMP_TRIGF") -gt 1 ) ]]; then
      printf "[TERROR]: unable to create placeholder file %s\n" "$TMP_TRIGF"
      return 3
    fi

    # run softwareupdate --list to prime the installation
    swupd_list

    # run software update installation of Command Line Tools
    printf "[SWUPDATE]: installing %s\n" "$SWUPNAME"
    /usr/sbin/softwareupdate --install "$SWUPNAME"
    local -i install_rtn="$?"

    # run a check on CLT packages and save the return status
    pkgs_review "/"
    local -i pkgs_missing="$?"

    # if both previous return status were 0 then also return 0
    if [[ $(( install_rtn + pkgs_missing )) = 0 ]]; then
      printf "[SWUPDATED]: successfully installed %s\n" "$CLT_TEXT"
      return 0
    else
      # check again to see if Command Line Tools are installed
      ctls_already_installed && return
      # attempt Command Line Tools install using xcode-select --install
      xc_install
      return $?
    fi
  fi
}

install_formulae() {
  # install required brew Formulae
  if check_brew ; then
    if [[ "$HOMEBREW_NO_ANALYTICS" = "" ]]; then
      brew analytics on
    else
      brew analytics off
    fi
    brew doctor
    #
    ##
    #########################################################################
    ####
    ##                        :: OPTIONS NOTICE ::
    #
    #  You don't have to install the list of formulae I've hard coded in here
    #  Just add a file called brew_formulae to the same folder with a list of
    #  your favorite formulae, or define env brew_formulae to point to a file
    #  then this script will install your chosen formulae, instead of my ones
    #
    ##
    ####
    ########################################################################
    ##
    #

    # install formulae provided in ./brew_formulae file or $brew_formulae env
    [[ -z "$brew_formulae" ]] && brew_formulae="./brew_formulae"
    if [[ -r "$brew_formulae" ]]; then
      printf "[OPTINSTAL]: using your optional brew formulae file %s\n" "$brew_formulae"
      while IFS='' read -r formula || [[ -n "$formula" ]]; do
        if [[ -n "$formula" ]]; then
          printf "[FORMINFO]: installing your chosen brew formula %s\n" "$formula"
          eval brew install "$formula"
        fi
      done < "$brew_formulae"
    # otherwise install the following formulae by default
    else
      brew install makedepend autoconf
      brew install readline openssl
      brew install curl --with-openssl
      brew install git --with-curl --with-openssl
      brew install bash libtool sphinx-doc libuv
      brew install libev libyaml libevent libidn 
      brew install getdns --with-libuv --with-libev
      brew install stubby
      brew install openssh sqlite shellcheck
      brew install imagemagick fontconfig
    fi
  fi

return 0
}
#
#————————
main(){ #
#––––––——
#
# »›-~-~-~-~-~-€ ¥¥ ∞•∞•∞⇉≠⤵︎
                            #>
  check_privs    || exit $?  #
  check_energy   || exit $?  ##
  check_memory   || exit $?  ###\–➤
  check_network  || exit $?  ###/–➤
  get_sudo       || exit $?  ##
  get_brew       || exit $?  #
                            #>
# »›-~-~-~-~-~-€ ŸŸ •∞≈»•Ô∫⤴︎
#
}
#
#–––––––––––––––––––––––––––––––––––––––––––∆
[[ ${BASH_SOURCE[0]} = "$0" ]] && main "$@" #
#–––––––––––––––––––––––––––––––––––––––––––Ω
#
#
#########################################################
#########################################################
####################         ############################
###########################  ############################
###########################  ##################      ####
###        ##  ####  ##      ##      ##      #####   ####
###  ####  ##  ####  ##  ##  ##  ##  ##  ##  ####  # ####
###  ####  ##  ####  ##  ##  ##  ##  ##      ###  ## ####
###  ####  ##  ####  ##  ##  ##  ##  ##  ######  ########
###  ####  ##        ##      ##      ##         #########
###################################  ####################
###################################  ####################
########################             ####################
#########################################################
#########################################################
