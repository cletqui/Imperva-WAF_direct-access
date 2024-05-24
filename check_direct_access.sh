#!/bin/bash

# Check command line arguments
print_help() {
  echo "Usage: ./check_direct_access.sh [OPTIONS]"
  echo "Options:"
  echo "  -v, --verbose             Enable verbose mode (logs it into logs.txt)"
  echo "  -a, --all                 Print all websites (only unsafe websites by default)"
  echo "  -o, --output <file>.json  Specify the output file (with a .json extension)"
  echo "  -t, --timeout <timeout>   Specify the timeout in seconds (positive integer)"
  echo "  -l, --list-only           List only websites (no check is performed)"
  echo "  -e, --env <file>          Specify the path to a .env file for environment variables"
  echo "  -h, --help                Display this help message"
  exit 0
}

# Declare local variables for this script
declare -A options=(
  [verbose]=false   # Verbose mode option
  [all]=false       # All websites option
  [output_file]=""  # Output file path variable
  [list_only]=false # List-only option
  [timeout]=10      # Default timeout value if not provided
  [env_file]=".env" # Default environment file path variable
)

# Declare local variables for printing output
declare -A colors=(
  [reset]="\e[0m"
  [grey]="\e[2m"
  [red]="\e[31m"
  [green]="\e[32m"
  [yellow]="\e[33m"
  [blue]="\e[34m"
  [bold]="\e[1m"
)

# Parse environment variables from .env file if provided
while getopts ":vao:t:le:h-:" opt; do
  case "$opt" in
  v) options[verbose]=true ;;
  a) options[all]=true ;;
  o) options[output_file]=$OPTARG ;;
  t) options[timeout]=$OPTARG ;;
  l) options[list_only]=true ;;
  e) options[env_file]=$OPTARG ;;
  h) print_help ;;
  -)
    case "${OPTARG}" in
    verbose) options[verbose]=true ;;
    all) options[all]=true ;;
    output)
      val="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      options[output_file]=$val
      ;;
    timeout)
      val="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      options[timeout]=$val
      ;;
    list-only) options[list_only]=true ;;
    env)
      val="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      options[env_file]=$val
      ;;
    help) print_help ;;
    *)
      echo "Error: Unknown option --${OPTARG}" >&2
      exit 1
      ;;
    esac
    ;;
  \?)
    echo "Error: Unknown option -${OPTARG}" >&2
    exit 1
    ;;
  :)
    echo "Error: Missing argument for -${OPTARG}" >&2
    exit 1
    ;;
  esac
done

# Parse environment variables from .env file
source ${options[env_file]}

# Check if the output file is still empty, in that case use ACCOUNT_ID from env file to name the output file
if [[ -z "${options[output_file]}" ]]; then
  if [[ -n "${options[env_file]}" && -f "${options[env_file]}" ]]; then
    if [[ -n "${ACCOUNT_ID}" ]]; then
      options[output_file]="${ACCOUNT_ID}.json"
    else
      echo "Error: ACCOUNT_ID is not defined in the .env file" >&2
      exit 1
    fi
  else
    echo "Error: Output file not specified, and .env file is missing or not specified" >&2
    exit 1
  fi
fi

# Clear the output file if it exists (truncate)
echo "[]" >"${options[output_file]}"
>"logs.txt"

# Echo and write text to output file
log() {
  local message="${1}"                                                                # Message to log
  echo -en "${message}"                                                               # Echo to the terminal
  local sanitized_message="$(echo -e "${message}" | sed -r "s/\x1B\[[0-9;]*[mK]//g")" # Sanitize the message (remove ANSI color codes but not \n) for logging to the file
  echo -e "${sanitized_message}" >>"logs.txt"                                         # Write to the output file
}

# Function to add data to JSON file
json() {
  local id="${1}"                  # Website ID
  local name="${2}"                # Website name
  local origin_ip_status=("${!3}") # Origin IP status array
  local waf_ip_status=("${!4}")    # WAF IP status array
  local origin_access="${5}"       # Origin access
  local waf_access="${6}"          # WAF access
  local status="${7}"              # Global status

  # Create an empty JSON object
  json_output="{}"

  # Add properties conditionally
  if [ -n "${id}" ]; then
    json_output=$(jq --arg id "${id}" '.id = $id' <<<"${json_output}")
  fi
  if [ -n "${name}" ]; then
    json_output=$(jq --arg name "${name}" '.name = $name' <<<"${json_output}")
  fi
  if [ "${#origin_ip_status[@]}" -gt 0 ]; then
    origin_json=$(jq -n '[]')
    for origin_entry in "${origin_ip_status[@]}"; do
      origin_json=$(jq --argjson entry "${origin_entry}" '. += [$entry]' <<<"${origin_json}")
    done
    json_output=$(jq --argjson origin "${origin_json}" '.origin = $origin' <<<"${json_output}")
  fi
  if [ "${#waf_ip_status[@]}" -gt 0 ]; then
    waf_json=$(jq -n '[]')
    for waf_entry in "${waf_ip_status[@]}"; do
      waf_json=$(jq --argjson entry "${waf_entry}" '. += [$entry]' <<<"${waf_json}")
    done
    json_output=$(jq --argjson waf "${waf_json}" '.waf = $waf' <<<"${json_output}")
  fi
  if [ -n "${origin_access}" ]; then
    json_output=$(jq --argjson origin_access "${origin_access}" '.origin_access = $origin_access' <<<"${json_output}")
  fi
  if [ -n "${waf_access}" ]; then
    json_output=$(jq --argjson waf_access "${waf_access}" '.waf_access = $waf_access' <<<"${json_output}")
  fi
  if [ -n "${status}" ]; then
    json_output=$(jq --arg status "${status}" '.status = $status' <<<"${json_output}")
  fi

  # Read the existing JSON data from the file
  existing_json=$(cat "${options[output_file]}")
  # Append the new JSON object to the array
  updated_json=$(echo "${existing_json}" | jq --argjson new_entry "${json_output}" '. += [$new_entry]')
  # Write the updated JSON data back to the file
  echo "${updated_json}" >"${options[output_file]}"
}

# Function to append JSON object to the array
append_ip() {
  local -n array="${1}"
  local ip="${2}"
  local code="${3}"
  local direct_access="${4}"

  # Construct JSON object for IP entry
  local ip_entry=$(jq -n \
    --arg ip "${ip}" \
    --arg code "${code}" \
    --argjson direct_access "${direct_access}" \
    '{ip: $ip, code: $code | tonumber, direct_access: $direct_access}')

  # Append the JSON object to the array
  array+=("${ip_entry}")
}

# If list_only only option enabled, only print the websites names
if ! ${options[list_only]}; then
  # Print ASCII art banner
  echo -e "${colors[bold]}${colors[blue]}  ,----,          ____                                                                     .---.   ,---,           ,---,.\n,\`--.' |        ,'  , \`.,-.----.                                                          /. ./|  '  .' \        ,'  .' |\n|   :  :     ,-+-,.' _ |\    /  \             __  ,-.                                 .--'.  ' ; /  ;    '.    ,---.'   |\n:   |  '  ,-+-. ;   , |||   :    |          ,' ,'/ /|    .---.                       /__./ \ : |:  :       \   |   |   .'\n|   :  | ,--.'|'   |  |||   | .\ :   ,---.  '  | |' |  /.  ./|   ,--.--.         .--'.  '   \' .:  |   /\   \  :   :  :  \n'   '  ;|   |  ,', |  |,.   : |: |  /     \ |  |   ,'.-' . ' |  /       \       /___/ \ |    ' '|  :  ' ;.   : :   |  |-,\n|   |  ||   | /  | |--' |   |  \ : /    /  |'  :  / /___/ \: | .--.  .-. |      ;   \  \;      :|  |  ;/  \   \|   :  ;/|\n'   :  ;|   : |  | ,    |   : .  |.    ' / ||  | '  .   \  ' .  \__\/: . .       \   ;  \`      |'  :  | \  \ ,'|   |   .'\n|   |  '|   : |  |/     :     |\`-''   ;   /|;  : |   \   \   '  ,\" .--.; |        .   \    .\  ;|  |  '  '--'  '   :  '  \n'   :  ||   | |\`-'      :   : :   '   |  / ||  , ;    \   \    /  /  ,.  |         \   \   ' \ ||  :  :        |   |  |  \n;   |.' |   ;/          |   | :   |   :    | ---'      \   \ |;  :   .'   \\         :   '  |--\" |  | ,'        |   :  \  \n'---'   '---'           \`---'.|    \   \  /             '---\" |  ,     .-./          \   \ ;    \`--''          |   | ,'  \n                          \`---\`     \`----'                     \`--\`---'               '---\"                    \`----'    ${colors[reset]}\n"

  # List account websites from Imperva API
  if ${options[verbose]}; then
    echo -e "Retrieving websites from Imperva account (${colors[grey]}${ACCOUNT_ID}${colors[reset]})..."
  fi
fi

# Make API request to list account websites
response=$(curl -s -X POST -H "accept: application/json" "${API_ENDPOINT}/sites/list?api_id=${API_ID}&api_key=${API_KEY}&account_id=${ACCOUNT_ID}")

if ! ${options[list_only]}; then
  if ${options[verbose]}; then
    # Iterate through the Imperva websites
    echo -e "Sending requests to check direct access for Imperva protected websites..."
    # Write output to output file
    echo -e "Write output to output file ${colors[grey]}${options[output_file]}${colors[reset]} (and logs to ${colors[grey]}logs.txt${colors[reset]})..."
    echo
  fi
fi

# Check if the origin IP is directly accessible
echo "${response}" | jq -c '.sites[]' | while IFS=$'\t' read -r site; do
  # Initialize variables
  origin_ip_status=()        # List of origin IP and status
  waf_ip_status=()           # List of WAF IP and status
  origin_ip_accessible=false # Boolean to check if the origin IP is accessible
  waf_ip_accessible=false    # Boolean to check if the WAF IP is accessible

  # Extract the fields from the API response
  domain=$(echo "${site}" | jq -r ".domain")                                         # The domain name
  account_id=$(echo "${site}" | jq -r ".account_id")                                 # The Imperva account ID
  ips=$(echo "${site}" | jq -r ".ips[]" | tr '\n' ' ')                               # The origin IP addresses
  dns=$(echo "${site}" | jq -r ".dns[].set_data_to[]" | tr '\n' ' ')                 # The current DNS record
  origin_dns=$(echo "${site}" | jq -r ".original_dns[].set_data_to[]" | tr "\n" " ") # The origin DNS record
  display_name=$(echo "${site}" | jq -r ".display_name")                             # The display name for the site

  # Print account ID and domain
  log "- ${colors[bold]}${domain}${colors[reset]}"

  if ! ${options[list_only]}; then
    if ${options[verbose]}; then
      log " (${colors[grey]}${account_id}${colors[reset]})\n"
    fi
    # Check accessibility of each origin IP
    if ${options[verbose]}; then
      log "      💻 Origin IPs ( ${colors[grey]}${ips}${colors[reset]}) & DNS ( ${colors[grey]}${origin_dns}${colors[reset]})\n"
    fi

    # Split IPs into an array
    IFS=" " read -r -a ips_array <<<"${ips}"
    # Iterate through each IP or CNAME in DNS
    for entry in ${origin_dns}; do
      # Check if the entry is an IP address
      if [[ ${entry} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Check if the IP is not already in waf_ip
        if [[ ! " ${ips_array[@]} " =~ " ${entry} " ]]; then
          ips="${ips} ${entry}"
        fi
      else
        # Perform recursive dig to obtain IP behind the CNAME
        ip=$(dig +short ${entry} | grep -v CNAME)
        # Split ip into an array
        IFS=$'\n' read -r -a ip_array <<<"${ip}"
        # Loop through each IP obtained from the CNAME
        for ip_entry in "${ip_array[@]}"; do
          # Check if the IP is not already in waf_ip
          if [[ ! " ${ips_array[@]} " =~ " ${ip_entry} " ]]; then
            origin_ip="${ips} ${ip_entry}"
          fi
        done
      fi
    done

    # Check direct accessibility of origin server IPs
    for ip in ${ips}; do
      # Print the Origin IP being checked
      if ${options[verbose]}; then
        log "            Origin IP ${colors[grey]}${ip}${colors[reset]}"
      fi

      # Check if the IP is directly accessible
      result=$(timeout "${options[timeout]}" curl -sILk "https://${domain}" --resolve "${domain}:443:${ip}" -o /dev/null -w "%{http_code}")

      if [[ "${result}" == "200" ]]; then
        # Origin IP is directly accessible
        if ${options[verbose]}; then
          log " is directly accessible (${colors[grey]}HTTP_CODE ${result}${colors[reset]}) 👎\n"
        fi
        direct_access=true
        origin_ip_accessible=true
      else
        # Origin IP is not directly accessible
        if [ -z "$result" ]; then
          result=0
        fi
        if ${options[verbose]}; then
          log " is not directly accessible (${colors[grey]}HTTP_CODE ${result}${colors[reset]}) 👍\n"
        fi
        direct_access=false
      fi

      append_ip origin_ip_status "${ip}" ${result} ${direct_access}
    done

    # Extract WAF IPs from DNS records
    waf_ips=$(dig +short "${domain}" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tr "\n" " ")

    # Check accessibility of each WAF IPs
    if ${options[verbose]}; then
      log "      🌐 WAF IPs ( ${colors[grey]}${waf_ips}${colors[reset]}) & DNS ( ${colors[grey]}${dns}${colors[reset]})\n"
    fi

    # Append all DNS entries from the WAF to the online extracted list
    # Split waf_ip into an array
    IFS=" " read -r -a waf_ip_array <<<"${waf_ips}"
    # Iterate through each IP or CNAME in dns
    for entry in ${dns}; do
      # Check if the entry is an IP address
      if [[ ${entry} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Check if the IP is not already in waf_ips
        if [[ ! " ${waf_ip_array[@]} " =~ " ${entry} " ]]; then
          waf_ips="${waf_ips} ${entry}"
        fi
      else
        # Perform recursive dig to obtain IP behind the CNAME
        ip=$(dig +short ${entry} | grep -v CNAME)
        # Split ip into an array
        IFS=$'\n' read -r -a ip_array <<<"${ip}"
        # Loop through each IP obtained from the CNAME
        for ip_entry in "${ip_array[@]}"; do
          # Check if the IP is not already in waf_ips
          if [[ ! " ${waf_ip_array[@]} " =~ " ${ip_entry} " ]]; then
            waf_ips="${waf_ips} ${ip_entry}"
          fi
        done
      fi
    done

    # Check direct accessibility of WAF IP
    for waf_ip in ${waf_ips}; do
      # Print the WAF IP being checked
      if ${options[verbose]}; then
        log "            WAF IP ${colors[grey]}${waf_ip}${colors[reset]}"
      fi

      # Check if the IP is directly accessible
      result=$(timeout "${options[timeout]}" curl -sILk "https://${domain}" --resolve "${domain}:443:${waf_ip}" -o /dev/null -w "%{http_code}")

      if [[ "${result}" == "200" ]]; then
        # WAF IP is directly accessible
        if ${options[verbose]}; then
          log " is accessible (${colors[grey]}HTTP_CODE ${result}${colors[reset]}) 👍\n"
        fi
        direct_access=true
        waf_ip_accessible=true
      else
        # WAF IP is not directly accessible
        if [ -z "${result}" ]; then
          result=0
        fi
        if ${options[verbose]}; then
          log " is not accessible (${colors[grey]}HTTP_CODE ${result}${colors[reset]}) 🤔\n"
        fi
        direct_access=false
      fi

      append_ip waf_ip_status "${waf_ip}" ${result} ${direct_access}
    done

    # Print summary
    if [ "${waf_ip_accessible}" = true ]; then
      if [ "${origin_ip_accessible}" = true ]; then
        # Both IP are accessible, the configuration is a failure
        log "    ${colors[bold]}${colors[red]}🚩 Failure${colors[reset]}"
        if ${options[verbose]}; then
          log " (${colors[grey]}Origin IP is directly accessible, WAF IP is accessible too${colors[reset]})\n"

        fi
        status="bypassed"
      else
        # WAF IP is accessible but origin IP is not, the configuration is valid
        log "    ${colors[bold]}${colors[green]}🔒 Success${colors[reset]}"
        if ${options[verbose]}; then
          log " (${colors[grey]}WAF IP is accessible and Origin IP is not accessible${colors[reset]})\n"
        fi
        status="safe"
      fi
    else
      if [ "${origin_ip_accessible}" = true ]; then
        # WAF IP is not accessible but origin IP is, the configuration is strange (WAF down?)
        log "    ${colors[bold]}${colors[yellow]}🤔 Error${colors[reset]}"
        if ${options[verbose]}; then
          log " (${colors[grey]}Something is strange, WAF IP is not accessible but Origin IP is accessible${colors[reset]})\n"
        fi
        status="error"
      else
        # WAF IP is not accessible and origin IP is not accessible either, the configuration is strange (network down?)
        log "    ${colors[bold]}${colors[yellow]}🤔 Error${colors[reset]}"
        if ${options[verbose]}; then
          log " (${colors[grey]}Something is strange, WAF IP and Origin IP are not accessible${colors[reset]})\n"
        fi
        status="unreachable"
      fi
    fi
  fi

  # Append data in output JSON file depending on --all flag
  if ${options[all]}; then
    json ${account_id} ${domain} origin_ip_status[@] waf_ip_status[@] ${origin_ip_accessible} ${waf_ip_accessible} ${status}
  else
    if [ "$status" != "safe" ]; then
      json ${account_id} ${domain} origin_ip_status[@] waf_ip_status[@] ${origin_ip_accessible} ${waf_ip_accessible} ${status}
    fi
  fi

  log "\n"
done
