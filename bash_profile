# $DOTFILES/bash_profile by :nudge>
unset break printf source || return $?

export DOTFILES="${HOME}/.dot"

declare +r file
declare -i savit=0
for file in "env" "path" "colors" "func" "alias" "priv" "term"; do
  if [[ -r "${DOTFILES}/login_${file}" ]] ; then
    source "${DOTFILES}/login_${file}" || {
      savit=$?
      printf "[ERROR]: %s bash_profile when sourcing %s\n" "$savit" "${DOTFILES}/login_${file}"
      break
    }
  else
    savit=$?
    printf "[ERROR]: %s bash_profile unable to read: %s\n" "$savit" "${DOTFILES}/login_${file}"
    break
  fi
done

unset file
[[ $savit -ne 0 ]] && return $savit
unset savit
