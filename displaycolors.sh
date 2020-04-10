#!/usr/bin/env bash
# displaycolors.sh by :nudge>

unset printf || exit $?

display_info() { printf  "\n%-18s -> \e[1;32m%-18s\e[0m\n\n"   "$SHELL"   "${0##*/}" ; }

display_colors() {
  local -r RED="\e[1;31m%s\e[0m"
  local -r RESET=$(/usr/bin/tput sgr0)
  [[ -n "$1" ]] || { printf "[$RED]: No start (param 1): $RED\n" "ERROR" $1 ; return 1 ; }
  [[ -n "$2" ]] || { printf "[$RED]: No end   (param 2): $RED\n" "ERROR" $2 ; return 2 ; }
  /usr/bin/tput civis
  for fgc in $(/usr/bin/seq -f "%03g"  $1 $2); do
    set_fgc=$(/usr/bin/tput setaf $fgc)
    for bgc in $(/usr/bin/seq -f "%03g"  $1 $2); do
      set_bgc=$(/usr/bin/tput setab $bgc)
      printf "%s%s BG:%s FG:%s " $set_bgc $set_fgc $bgc $fgc
    done
    printf "%s\n" $RESET
  done
  /usr/bin/tput cnorm
}

without_params(){
  local -i column_start=$start
  while [[ $column_start -lt $end ]]; do
    column_end=$(( column_start + columns - 1 ))
    [[ "$column_end" -gt $end ]] && (( column_end = end ))
    display_colors $column_start $column_end   || exit $?
    (( column_start += columns ))
  done
}

with_params(){
  start=$1
  [[ -z "$2" ]] || end=$2
  if [[ $(( end - start )) -lt $columns ]]; then
    display_colors $start $end
  else
    local -i column_start=$1
    local -i column_end=$(( column_start + columns - 1 ))
    [[   "$column_end"   -gt $end ]] && (( column_end   = end ))
    while [[ "$column_start" -lt $end ]]; do
      display_colors $column_start $column_end || exit $?
      (( column_start += columns ))
      [[ "$column_start" -gt $end ]] && (( column_start = end ))
      column_end=$(( column_start + columns - 1 ))
      [[ "$column_end"   -gt $end ]] && (( column_end   = end ))
    done
  fi
}

main() {
  local -i txtlen=15
  local -i start=0
  local -i width=$( /usr/bin/tput cols   )
  local -i colors=$(/usr/bin/tput colors )
  local -i end=$((     colors - 1       ))
  local -i columns=$(( width  / txtlen  ))
  local -r YLO="\e[1;33m%d\e[0m"
  display_info  || exit $?
  [[ -z "$1" ]] && without_params \
                || with_params "$@"
  printf "\nwidth: $YLO columns: $YLO colors: $YLO start: $YLO end: $YLO\n\n" \
                   $width        $columns     $colors     $start    $end
}

#–––––––––––––––––––––––––––––––––––––––––––∆
[[ ${BASH_SOURCE[0]} = "$0" ]] && main "$@" #
#–––––––––––––––––––––––––––––––––––––––––––Ω
