# $DOTFILES/bashrc by :nudge>
unset break printf source || return $?

export DOTFILES="${HOME}/.dot"

declare +r file
declare -i savit=0
for file in "env" "path" ; do
  if [[ -r "${DOTFILES}/login_${file}" ]] ; then
    source "${DOTFILES}/login_${file}" || {
      savit=$?
      printf "[ERROR]: %s bashrc when trying to source %s\n" "$savit" "${DOTFILES}/login_${file}" >/dev/stderr
      break
    }
  else
    savit=$?
    printf "[ERROR]: %s bashrc was unable to read file %s\n" "$savit" "${DOTFILES}/login_${file}" >/dev/stderr
    break
  fi
done

unset file
[[ $savit -ne 0 ]] && return $savit
unset savit
