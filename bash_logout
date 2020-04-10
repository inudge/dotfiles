# $DOTFILES/bash_logout by :nudge>
unset printf || exit $?

printf "\n\e[1;32m%s\e[0m\n" "$(/bin/date)"
printf "User: \e[1;35m%s\e[0m logging out from: \e[1;33m%s\e[0m\n" "$USER" "${HOSTNAME:-UNDEFINEDHOST}"
