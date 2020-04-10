#!/usr/bin/env bash
# symlinks.sh by :nudge>
# I keep dotfiles in a version controlled subfolder (DOTFILES) without the leading dots
# this script symlinks these un-dotted files to their usual location in the HOME folder
# note that the HOME and DOTFILES envirnonment variables must be defined before running

unset popd printf pushd test || exit $?
declare -x chmod="/bin/chmod"
declare -x dn="/dev/null"
declare -x ln="/bin/ln"
declare -x ls="/bin/ls"
declare -x rm="/bin/rm"

# array of dotfiles that'll be symlinked from the home folder into $DOTFILES/file
declare -r dots=( .bash_history .bash_logout .bash_profile .bashrc .bash_sessions \
                  .CFUserTextEncoding .config .curlrc .deno .editorconfig .getdns \
                  .gitconfig .gitignore_global .inputrc .mongorc.js .node_history \
                  .npmrc .pnpm-store .prettierignore .prettierrc .pubip .screenrc )

declare -r red="\e[1;31m%s\e[0m"
declare -r grn="\e[1;32m%s\e[0m"
declare -r ylo="\e[1;33m%s\e[0m"
declare -r pnk="\e[1;35m%d\e[0m"
declare -r cyn="\e[1;36m%s\e[0m"

check_runtime() {
  local -r os="Darwin"
  local -r uns=$(/usr/bin/uname -s)
  local -i mid=$(/usr/bin/id -u)
  [ "$uns" = "$os" ] || { printf "[$red]: $cyn $ylo\n"  "FATAL"  "This script can only run on:"  "macOS" ; return 1 ; }
  [ "$mid" -eq 0   ] && { printf "[$red]: $cyn $ylo\n"  "FATAL"  "This can not be run from user:" "root" ; return 2 ; }
  [ -z "$DOTFILES" ] && { printf "[$red]: $cyn $ylo\n"  "FATAL"  "Missing required variable:" "DOTFILES" ; return 3 ; }
  [ -d "$DOTFILES" ] || { printf "[$red]: $cyn $ylo\n"  "FATAL"  "Missing required folder:"  "$DOTFILES" ; return 4 ; }
}

symlink_dots() {
  local t="${DOTFILES##*/}/${1:1}"
  [[ $# -eq 0   ]]   && { printf "[$grn]: $cyn $rkt $ylo $snt\n" "Done" "Dotfiles symlinked into:" "$t"  ; return 6 ; }
  [[ -h "$1"    ]]   && { printf "[$ylo]: $cyn $red\n"           "Info" "Removed old symlink for:" "$1"  ; rm "$1"  ; }
  [[ -r "$1"    ]]   && { printf "[$red]: $cyn $ylo\n"  "Error"  "This file must be moved first: " "$1"  ; return 7 ; }
  [[ -e "$t"    ]]   || { printf "[$red]: $cyn $ylo\n"  "Error"  "This file seems to be missing: " "$t"  ; return 8 ; }
  ln -s "$t"   "$1"  &&   printf "[$ylo]: $cyn $red $g-> $ylo\n" "Info" "Created new symlink for:" "$1" "$t"
  chmod -h 700 "$1"  || { printf "[$red]: $cyn $pnk   $red\n"   "Error" "Chmod return code: " "$?" "$1"  ; return 9 ; }
}

main() {
  local -r g="\e[1;32m"
  local -r rkt="\xf0\x9f\x9a\x80"
  local -r snt="\xf0\x9f\x98\x87"
  local -i index=0
  local -i rtnvu=0
  check_runtime      || exit $?
  pushd "$HOME" >$dn || exit  5
  while symlink_dots ${dots[$index]}; do (( index++ )); done
  rtnvu=${PIPESTATUS[0]}
  popd          >$dn || exit 10
  [[ $rtnvu -eq 6 ]] && exit  0 \
                     || exit $rtnvu
}

#–––––––––––––––––––––––––––––––––––––––––––∆
[[ ${BASH_SOURCE[0]} = "$0" ]] && main "$@" #
#–––––––––––––––––––––––––––––––––––––––––––Ω
