#!/usr/bin/env bash
# check_DoT.sh by :nudge>
# tests DNS over TLS (stubby)
# debug levels 1 - 3 set with positional param $1

unset break printf read || exit $?
# check bash version is sufficient for associative arrays
if [[ "$(/usr/bin/awk -F. '{print $1$2}' <<< "$BASH_VERSION")" -lt 42 ]]; then
  printf "\n[ABORT]: your bash version is too old to run this script"
  printf "\nMinimum bash 4.2 is required, maybe check your PATH & shebang\n"
  exit 42
fi
# will only run on macOS (darwin)
if [[ "${OSTYPE:0:6}" != "darwin" ]]; then
  printf "\n[ABORT]: this script is only intended for macOS systems\n"
  exit 9
fi

declare -r STBFILE="/usr/local/etc/stubby/stubby.yml"           # stubby's yaml config file...
declare -x getdns_server_mon="/usr/local/bin/getdns_server_mon" # adjust these if necessary
declare -A STB_YML
declare -r red="\e[1;31m%s\e[0m"
declare -r blue="\e[1;34m%s\e[0m"
declare -r green="\e[1;32m%s\e[0m"
declare -r yellow="\e[1;33m%s\e[0m"
declare -r magenta="\e[1;35m%s\e[0m"
declare -r rktemoji="\xf0\x9f\x9a\x80"
declare -i beg_time rtn_val=0 STB_IPS=0
# just some random domains used for DNS testing
declare -r test_doms=( ietf.org goo.gl reddit.com brew.sh github.io swift.org ibm.com php.net \
                       apple.com bbc.com youtu.be bit.ly amazon.de apache.org telegram.me )
LC_ALL=C
beg_time="$(date +%s)"

# make sure we can access required files
[[ -r "$STBFILE" ]] || { printf "[$red]: stubby config file not found\n" "FATAL" ; exit 3 ; }
if [[ ! -x "$getdns_server_mon" ]]; then
  getdns_server_mon="$(/usr/bin/command -v  getdns_server_mon)"
  declare -x getdns_server_mon="$getdns_server_mon"
  [[ -x "$getdns_server_mon" ]] || {
    printf "\n[$red]: getdns_server_mon utility is not available, check your PATH\n" "FATAL"
    exit 4
  }
fi

# parse debugging level, pass 1, 2 or 3 as $1 for increasingly verbose output
case $1 in
  1|2|3)  declare -i LETS_DEBUG="$1"
          printf "\n[$green]: level %s\n\n" "DEBUG" "$LETS_DEBUG" ;;
  *)      declare -i LETS_DEBUG=0 ;;
esac

# exit routine
bellaciao() {
  [[ -n "$1" ]] && rtn_val="$1"
  if [[ $LETS_DEBUG -gt 0 ]] ; then
    if [[ "$rtn_val" -lt 9 ]]; then
      while read -r line ; do
        for word in $line ; do
          if [[ "${#word}" -gt 9 ]]; then
            printf "\n%s" "${word/'STB_YML=('/}"
          fi
        done
      done <<< "$(declare -p STB_YML)" | /usr/bin/sort
    fi
  fi
  dif_time=$(( $(date +%s) - beg_time ))
  printf "\n\n[$green]: Testing took $magenta seconds, exit-code $yellow\n\n" "TIME" "$dif_time" "$rtn_val"
  exit "$rtn_val"
}
[[ ${BASH_SOURCE[0]} = "$0" ]] && trap "bellaciao" EXIT

# load STB_YML with all stubby's yml config data except for upstream recursive server entries
load_stubby_yml() {
  local +r next_flag=""
  local +r line
  local -i i=1
  while read -r line; do
    line=${line/'-'/}
    [[ "$line" = "" ]] && continue
    for word in $line; do
      # dns_transport_list was given on previous line
      if [[ "$next_flag" = "dns_transport_list" ]]; then
        STB_YML[dns_transport_list]="${line:1}"
        next_flag="" # TODO: support multiple transports, TLS only is best anyhow
        continue
      elif [[ "$next_flag" = "listen_addresses" ]]; then
        if [[ $i -eq 1 ]]; then
          STB_YML[listen_addresses_${i}]="${line:2}"
          (( i++ ))
          continue
        fi
        if [[ $i -eq 2 ]]; then
          if [[ "$(/usr/bin/grep -c "${line:3}" /etc/hosts)" -eq 1 ]]; then
            STB_YML[listen_addresses_2]="${line:2}"
            (( i++ ))
            continue
          else
            STB_YML[listen_addresses_2]=""
            next_flag=""
          fi
        fi
        if [[ $i -gt 2 ]]; then
          next_flag="" # only 1 or 2 listen addresses currently supported e.g. IPv4,v6
        fi
      fi
      case $word in
        # the useful data is on the same line
        resolution_type: | tls_authentication: | tls_query_padding_blocksize: | \
        edns_client_subnet_private: | idle_timeout: | round_robin_upstreams: )
          STB_YML[${word/':'/}]="$(/bin/echo "$line" | /usr/bin/awk '{print $2}')"
          ;;
        # the useful data is on the next line(s)
        dns_transport_list: | listen_addresses: )
          next_flag="${word/':'/}"
          ;;
        *)
          ;;
      esac
    done
  done <<< "$(/usr/bin/grep -v '^#' "$STBFILE")"
  
  if [[ $LETS_DEBUG -gt 0 ]] ; then
    printf "\n"
    printf "STB_YML[resolution_type]             = %s\n" "${STB_YML[resolution_type]}"
    printf "STB_YML[dns_transport_list]          = %s\n" "${STB_YML[dns_transport_list]}"
    printf "STB_YML[tls_authentication]          = %s\n" "${STB_YML[tls_authentication]}"
    printf "STB_YML[tls_query_padding_blocksize] = %s\n" "${STB_YML[tls_query_padding_blocksize]}"
    printf "STB_YML[edns_client_subnet_private]  = %s\n" "${STB_YML[edns_client_subnet_private]}"
    printf "STB_YML[idle_timeout]                = %s\n" "${STB_YML[idle_timeout]}"
    printf "STB_YML[listen_addresses_1]          = %s\n" "${STB_YML[listen_addresses_1]}"
    printf "STB_YML[listen_addresses_2]          = %s\n" "${STB_YML[listen_addresses_2]}"
    printf "STB_YML[round_robin_upstreams]       = %s\n" "${STB_YML[round_robin_upstreams]}"
  fi
  return 0
}

# load STB_YML array with stubby's upstream recursive server data
load_recursives() {
  local -i i=0
  local -i ln_num=1
  local +r line
  while read -r line; do
    ln_data="$(/bin/echo "$line" | /usr/bin/awk -F: '{print $1}')"
    case $ln_data in
      address_data)
        (( i++ ))
        (( STB_IPS++ ))
        STB_YML[ups_rec_${i}]="${line#address_data:}"
        if [[ $LETS_DEBUG -gt 1 ]]; then
          [[ $ln_num -eq 1 ]] && printf "\nParsing upstream_recursive_servers:\n"
          printf "\nip_data\t\t\t = \t(%s)" "${STB_YML[ups_rec_${i}]}"
        fi
        ;;
      tls_auth_name)
        tls_name="$(/bin/echo "$line" | /usr/bin/awk -F: '{print $2}' | /usr/bin/sed 's/"//g')"
        STB_YML[ups_rec_${i}_tls_name]="${tls_name}"
        [[ $LETS_DEBUG -gt 1 ]] && printf "\ntls_name\t\t = \t(%s)" "$tls_name"
        ;;
      digest)
        tls_digest="$(/bin/echo "$line" | /usr/bin/awk -F: '{print $2}' | /usr/bin/sed 's/"//g')"
        STB_YML[ups_rec_${i}_tls_digest]="${tls_digest}"
        [[ $LETS_DEBUG -gt 2 ]] && printf "\ntls_digest\t\t = \t(%s)" "$tls_digest"
        ;;
      value)
        tls_value="$(/bin/echo "$line" | /usr/bin/awk -F: '{print $2}')"
        STB_YML[ups_rec_${i}_tls_value]="${tls_value}"
        [[ $LETS_DEBUG -gt 2 ]] && printf "\ntls_value\t\t = \t(%s)" "$tls_value"
        ;;
      *)
        printf "\n[$red]: parsing ln_data: (%s)\n" "ERROR" "$ln_data"
        return 9
        ;;
    esac
    (( ln_num++ ))
  done <<< "$(/usr/bin/grep -v '^#' "$STBFILE" \
            | /usr/bin/grep -E '(address_data|tls_auth_name|digest|value)' \
            | /usr/bin/sed 's/[[:space:]]//g;s/'-'//g')"

  [[ $LETS_DEBUG -eq 0 ]] && printf "\n"
  return 0
}

# run getdns_server_mon command from passed positional parameters
run_gsm_cmd() {
  rip_add="$1" ; shift
  tls_nam="$1" ; shift
  dot_tst="$1" ; shift
  if [[ $# -ne 1 ]]; then    # server without spki pinset (e.g. dns.quad9.net)
    format_gsm_cmd "$rip_add" "$tls_nam" "$dot_tst"
  elif [[ $# -eq 1 ]]; then  # server with spki pinset
    tls_val="$1" ; shift
    format_gsm_cmd "$tls_val" "$rip_add" "$tls_nam" "$dot_tst"
  else                       # should never reach here
    printf "\n[$red]: run_gsm_cmd error unexpected number of parameters received" "FATAL"
    printf "\nRemaining parameters:= %s\n" "$@"
    exit 5
  fi
  [[ $LETS_DEBUG -gt 2 ]] && printf "\ngetdns_server_mon%s\n\n" "$run_cmd"
  eval getdns_server_mon "$run_cmd"
  STB_YML[ups_rec_${n}.${dot_tst}]="$?"
  [[ "${STB_YML[ups_rec_$n.$dot_tst]}" != "0" ]] && (( rtn_val++ ))  # test failed
  [[ $LETS_DEBUG -gt 2 ]] && printf "\n%s = %s\n" "$dot_tst" "${STB_YML[ups_rec_$n.$dot_tst]}"
  return
}

# construct getdns_server_mon command options
format_gsm_cmd() {
  if [[ $# -eq 3 ]]; then    # server without spki pinset (e.g. dns.quad9.net)
    printf -v run_cmd "%s@%s:853#853~%s %s" "$gsm_cmd" "$1" "$2" "$3"
    [[ "$name_type" != "" ]] && run_cmd+="$name_type"  # optionally add [name] [type] params
  elif [[ $# -eq 4 ]]; then  # server with spki pinset
    printf -v run_cmd "%s%s%s\"\\' @%s#853~%s %s" "$gsm_cmd" "$spk_opt" "$1" "$2" "$3" "$4"
    [[ "$name_type" != "" ]] && run_cmd+="$name_type"  # optionally add [name] [type] params
  else                       # should never reach here
    printf "\n[$red]: format_gsm_cmd error: unexpected number of parameters received" "FATAL"
    printf "\nRemaining parameters:= %s\n" "$@"
    exit 6
  fi
}

# use getdns_server_mon to run tests on stubby's upstream recursive servers
test_DNSoverTLS() {
  rtn_val=0                                            # reset before each test
  run_cmd=""                                           # getdns_server_mon command options
  dot_tst=""                                           # getdns_server_mon test name
  lookup=" ${test_doms[$RANDOM % ${#test_doms[@]}]} A" # space + random domain [name] + [type = A]
  gsm_cmd=" -E -T -S "                                 # common options for gsm commands
  spk_opt="-K 'pin-sha256=\""                          # spki pinset option for gsm command
  if [[ -n "$1" ]]; then
    dot_tst="$1"
    case $dot_tst in
      # tests without [name] [type] parameters
      OOOR | qname-min | dnssec-validate | tls-1.3) name_type="" ;;
      # provide remaining tests with optional [name] [type] parameters
      *) name_type="$lookup" ;;
    esac
  else
    # default test if none was given, including [name] [type] options
    dot_tst="tls-cert-valid"
    name_type="$lookup"
  fi
  [[ $LETS_DEBUG -eq 0 ]] && printf "\n"
  # run test against each upstream recursive server
  for (( n=1; n <= STB_IPS ;n++ )) ; do
    if [[ -n "${STB_YML[ups_rec_${n}_tls_value]}" ]]; then  # server with spki pinset
      run_gsm_cmd "${STB_YML[ups_rec_${n}]}" "${STB_YML[ups_rec_${n}_tls_name]}" \
                  "$dot_tst" "$spk_opt" "${STB_YML[ups_rec_${n}_tls_value]}"
    elif [[ -n "${STB_YML[ups_rec_${n}]}" ]]; then
      # server without spki pinset (e.g. dns.quad9.net)
      run_gsm_cmd "${STB_YML[ups_rec_${n}]}" "${STB_YML[ups_rec_${n}_tls_name]}" "$dot_tst"
    else  # should never reach here
      printf "\n[$red]: no array data found for server STB_YML[ups_rec_%d]" "ERROR" "$n"
      printf "\n[$yellow]: total number of servers: STB_IPS = %d\n" "DEBUG" "$STB_IPS"
      exit 7
    fi
    printf "\n"
  done
  return "$rtn_val"
}

main() {
  load_stubby_yml || exit 8
  load_recursives || exit 9
  printf "\n  $blue $green $magenta $green $blue\n\n" "<===" "first checking DNS-over-TLS servers pass" \
                                                                              "tls-auth" "tests" "===>"
  test_DNSoverTLS "tls-auth"             # Check TLS authentication on all upstream recursive servers
  if [[ "$rtn_val" -eq 0 ]]; then        # continue testing only if previous tls-auth tests were successful
    printf "\n[$green]: The %d DNSoverTLS server(s) passed the tls-auth test ==> $rktemoji\n" "OK" "$STB_IPS"
    printf "\n  $blue $green $blue\n" "<===" "so now we are running all the remaining tests" "===>"
    for test in "tls-cert-valid" "rtt" "OOOR" "keepalive" "qname-min" "dnssec-validate" ; do
      printf "\n<== running $magenta test on $yellow upsteam recursives ==>\n\n" "$test" "$STB_IPS"
      test_DNSoverTLS "$test"
    done
    rtn_val=0
  else
    printf "\n[$red]: $magenta out of $magenta DNSoverTLS servers did not authenticate\n" \
            "WARNING" "$rtn_val"     "$STB_IPS"
  fi
  exit
}

#–––––––––––––––––––––––––––––––––––––––––––∆
[[ ${BASH_SOURCE[0]} = "$0" ]] && main "$@" #
#–––––––––––––––––––––––––––––––––––––––––––Ω
