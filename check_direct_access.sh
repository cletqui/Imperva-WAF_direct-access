#!/bin/bash

# Check command line arguments
print_help() {
  echo "Usage: ./check_direct_access.sh [OPTIONS]"
  echo "Options:"
  echo "  -v, --verbose           Enable verbose mode (logs it into logs.txt)"
  echo "  -a, --all               Print all websites (only unsafe websites by default)"
  echo "  -o, --output FILE.json  Specify the output file (with a .json extension)"
  echo "  -t, --timeout SECONDS   Specify the timeout in seconds (positive integer)"
  echo "  --websites-only         List only websites (no check is performed)"
  echo "  --env FILE              Specify the path to a .env file for environment variables"
  echo "  -h, --help              Display this help message"
  exit 0
}

# Declare local variables for this script
verbose=false       # Verbose mode option
all=false           # All websites option (TODO)
output_file=""      # Output file path variable
websites_only=false # Websites-only option
timeout=10          # Default timeout value if not provided
env_file=".env"     # Environment file path variable

# Declare local variables for printing output
RESET="\e[0m"   # Reset text color
GREY="\e[2m"    # Grey text color
RED="\e[31m"    # Red text color
GREEN="\e[32m"  # Green text color
YELLOW="\e[33m" # Yellow text color
BLUE="\e[34m"   # Blue text color
BOLD="\e[1m"    # Bold text

# Parse environment variables from .env file if provided
while [[ $# -gt 0 ]]; do
  case "$1" in
  -v | --verbose)
    verbose=true
    shift
    ;;
  -a | --all)
    all=true
    shift
    ;;
  -o | --output)
    if [[ -n "$2" ]]; then
      # Check if the output file has a .json extension
      if [[ "$2" == *.json ]]; then
        output_file="$2"
        shift 2
      else
        echo "Error: Output file must have a .json extension" >&2
        exit 1
      fi
    else
      echo "Error: Missing argument for $1" >&2
      exit 1
    fi
    ;;
  -t | --timeout)
    if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
      timeout="$2"
      shift 2
    else
      echo "Error: Timeout must be a positive integer" >&2
      exit 1
    fi
    ;;
  --websites-only)
    websites_only=true
    shift
    ;;
  --env)
    if [[ -n "$2" ]]; then
      if [[ -f "$2" ]]; then
        env_file="$2"
        shift 2
      else
        echo "Error: .env file not found at the specified path: $2" >&2
        exit 1
      fi
    else
      echo "Error: Missing argument for $1" >&2
      exit 1
    fi
    ;;
  -h | --help)
    print_help
    ;;
  *)
    echo "Error: Unknown option $1" >&2
    print_help
    exit 1
    ;;
  esac
done

# Parse environment variables from .env file
source $env_file

# Check if the output file is still empty, in that case use ACCOUNT_ID from env file to name the output file
if [[ -z "${output_file}" ]]; then
  if [[ -n "${env_file}" && -f "${env_file}" ]]; then
    if [[ -n "${ACCOUNT_ID}" ]]; then
      output_file="${ACCOUNT_ID}.json"
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
echo "[]" >"${output_file}"
>"logs.txt"

# Echo and write text to output file
log() {
  local message="$1"                                                                  # Message to log
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
  if [ -n "$id" ]; then
    json_output=$(jq --arg id "$id" '.id = $id' <<<"$json_output")
  fi
  if [ -n "$name" ]; then
    json_output=$(jq --arg name "$name" '.name = $name' <<<"$json_output")
  fi
  if [ "${#origin_ip_status[@]}" -gt 0 ]; then
    origin_json=$(jq -n '[]')
    for origin_entry in "${origin_ip_status[@]}"; do
      origin_json=$(jq --argjson entry "$origin_entry" '. += [$entry]' <<<"$origin_json")
    done
    json_output=$(jq --argjson origin "$origin_json" '.origin = $origin' <<<"$json_output")
  fi
  if [ "${#waf_ip_status[@]}" -gt 0 ]; then
    waf_json=$(jq -n '[]')
    for waf_entry in "${waf_ip_status[@]}"; do
      waf_json=$(jq --argjson entry "$waf_entry" '. += [$entry]' <<<"$waf_json")
    done
    json_output=$(jq --argjson waf "$waf_json" '.waf = $waf' <<<"$json_output")
  fi
  if [ -n "$origin_access" ]; then
    json_output=$(jq --argjson origin_access "$origin_access" '.origin_access = $origin_access' <<<"$json_output")
  fi
  if [ -n "$waf_access" ]; then
    json_output=$(jq --argjson waf_access "$waf_access" '.waf_access = $waf_access' <<<"$json_output")
  fi
  if [ -n "$status" ]; then
    json_output=$(jq --arg status "$status" '.status = $status' <<<"$json_output")
  fi

  # Read the existing JSON data from the file
  existing_json=$(cat "${output_file}")
  # Append the new JSON object to the array
  updated_json=$(echo "$existing_json" | jq --argjson new_entry "$json_output" '. += [$new_entry]')
  # Write the updated JSON data back to the file
  echo "$updated_json" >"${output_file}"
}

# Function to append JSON object to the array
append_ip() {
  local -n array="$1"
  local ip="$2"
  local code="$3"
  local direct_access="$4"

  # Construct JSON object for IP entry
  local ip_entry=$(jq -n \
    --arg ip "$ip" \
    --arg code "$code" \
    --argjson direct_access "$direct_access" \
    '{ip: $ip, code: $code | tonumber, direct_access: $direct_access}')

  # Append the JSON object to the array
  array+=("$ip_entry")
}

# If websitest only option enabled, only print the websites names
if ! $websites_only; then
  # Print ASCII art banner
  echo -e "${BOLD}${BLUE}Y   ,---,          ____                                                                     .---.   ,---,           ,---,.\n,\`--.' |        ,'  , \`.,-.----.                                                          /. ./|  '  .' \        ,'  .' |\n|   :  :     ,-+-,.' _ |\    /  \             __  ,-.                                 .--'.  ' ; /  ;    '.    ,---.'   |\n:   |  '  ,-+-. ;   , |||   :    |          ,' ,'/ /|    .---.                       /__./ \ : |:  :       \   |   |   .'\n|   :  | ,--.'|'   |  |||   | .\ :   ,---.  '  | |' |  /.  ./|   ,--.--.         .--'.  '   \' .:  |   /\   \  :   :  :  \n'   '  ;|   |  ,', |  |,.   : |: |  /     \ |  |   ,'.-' . ' |  /       \       /___/ \ |    ' '|  :  ' ;.   : :   |  |-,\n|   |  ||   | /  | |--' |   |  \ : /    /  |'  :  / /___/ \: | .--.  .-. |      ;   \  \;      :|  |  ;/  \   \|   :  ;/|\n'   :  ;|   : |  | ,    |   : .  |.    ' / ||  | '  .   \  ' .  \__\/: . .       \   ;  \`      |'  :  | \  \ ,'|   |   .'\n|   |  '|   : |  |/     :     |\`-''   ;   /|;  : |   \   \   '  ,\" .--.; |        .   \    .\  ;|  |  '  '--'  '   :  '  \n'   :  ||   | |\`-'      :   : :   '   |  / ||  , ;    \   \    /  /  ,.  |         \   \   ' \ ||  :  :        |   |  |  \n;   |.' |   ;/          |   | :   |   :    | ---'      \   \ |;  :   .'   \\         :   '  |--\" |  | ,'        |   :  \  \n'---'   '---'           \`---'.|    \   \  /             '---\" |  ,     .-./          \   \ ;    \`--''          |   | ,'  \n                          \`---\`     \`----'                     \`--\`---'               '---\"                    \`----'    ${RESET}\n"

  # List account websites from Imperva API
  if $verbose; then
    echo -e "Retrieving websites from Imperva account (${GREY}${ACCOUNT_ID}${RESET})..."
  fi
fi

# Make API request to list account websites
response=$(curl -s -X POST -H "accept: application/json" "${API_ENDPOINT}/sites/list?api_id=${API_ID}&api_key=${API_KEY}&account_id=${ACCOUNT_ID}")

if ! $websites_only; then
  if $verbose; then
    # Iterate through the Imperva websites
    echo -e "Sending requests to check direct access for Imperva protected websites..."
    # Write output to output file
    echo -e "Write output to output file ${GREY}${output_file}${RESET}..."
    echo
  fi
fi

# Check if the origin IP is directly accessible
echo "$response" | jq -c '.sites[]' | while IFS=$'\t' read -r site; do
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
  log "- ${BOLD}${domain}${RESET}"

  if ! $websites_only; then
    if $verbose; then
      log " (${GREY}${account_id}${RESET})\n"
    fi
    # Check accessibility of each origin IP
    if $verbose; then
      log "      💻 Origin IPs ( ${GREY}${ips}${RESET}) & DNS ( ${GREY}${origin_dns}${RESET})\n"
    fi

    # Split IPs into an array
    IFS=" " read -r -a ips_array <<<"${ips}"
    # Iterate through each IP or CNAME in DNS
    for entry in $origin_dns; do
      # Check if the entry is an IP address
      if [[ $entry =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Check if the IP is not already in waf_ip
        if [[ ! " ${ips_array[@]} " =~ " ${entry} " ]]; then
          ips="${ips} ${entry}"
        fi
      else
        # Perform recursive dig to obtain IP behind the CNAME
        ip=$(dig +short $entry | grep -v CNAME)
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
    for ip in $ips; do
      # Print the Origin IP being checked
      if $verbose; then
        log "            Origin IP ${GREY}${ip}${RESET}"
      fi

      # Check if the IP is directly accessible
      result=$(timeout "${timeout}" curl -sILk "https://${domain}" --resolve "${domain}:443:${ip}" -o /dev/null -w "%{http_code}")

      if [[ "${result}" == "200" ]]; then
        # Origin IP is directly accessible
        if $verbose; then
          log " is directly accessible (${GREY}HTTP_CODE ${result}${RESET}) 👎\n"
        fi
        direct_access=true
        origin_ip_accessible=true
      else
        # Origin IP is not directly accessible
        if [ -z "$result" ]; then
          result=0
        fi
        if $verbose; then
          log " is not directly accessible (${GREY}HTTP_CODE ${result}${RESET}) 👍\n"
        fi
        direct_access=false
      fi

      append_ip origin_ip_status "${ip}" $result $direct_access
    done

    # Extract WAF IPs from DNS records
    waf_ips=$(dig +short "${domain}" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tr "\n" " ")

    # Check accessibility of each WAF IPs
    if $verbose; then
      log "      🌐 WAF IPs ( ${GREY}${waf_ips}${RESET}) & DNS ( ${GREY}${dns}${RESET})\n"
    fi

    # Append all DNS entries from the WAF to the online extracted list
    # Split waf_ip into an array
    IFS=" " read -r -a waf_ip_array <<<"${waf_ips}"
    # Iterate through each IP or CNAME in dns
    for entry in $dns; do
      # Check if the entry is an IP address
      if [[ $entry =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Check if the IP is not already in waf_ips
        if [[ ! " ${waf_ip_array[@]} " =~ " ${entry} " ]]; then
          waf_ips="${waf_ips} ${entry}"
        fi
      else
        # Perform recursive dig to obtain IP behind the CNAME
        ip=$(dig +short $entry | grep -v CNAME)
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
    for waf_ip in $waf_ips; do
      # Print the WAF IP being checked
      if $verbose; then
        log "            WAF IP ${GREY}${waf_ip}${RESET}"
      fi

      # Check if the IP is directly accessible
      result=$(timeout "${timeout}" curl -sILk "https://${domain}" --resolve "${domain}:443:${waf_ip}" -o /dev/null -w "%{http_code}")

      if [[ "${result}" == "200" ]]; then
        # WAF IP is directly accessible
        if $verbose; then
          log " is accessible (${GREY}HTTP_CODE ${result}${RESET}) 👍\n"
        fi
        direct_access=true
        waf_ip_accessible=true
      else
        # WAF IP is not directly accessible
        if [ -z "$result" ]; then
          result=0
        fi
        if $verbose; then
          log " is not accessible (${GREY}HTTP_CODE ${result}${RESET}) 🤔\n"
        fi
        direct_access=false
      fi

      append_ip waf_ip_status "${waf_ip}" $result $direct_access
    done

    # Print summary
    if [ "${waf_ip_accessible}" = true ]; then
      if [ "${origin_ip_accessible}" = true ]; then
        # Both IP are accessible, the configuration is a failure
        log "    ${BOLD}${RED}🚩 Failure${RESET}"
        if $verbose; then
          log " (${GREY}Origin IP is directly accessible, WAF IP is accessible too${RESET})\n"

        fi
        status="bypassed"
      else
        # WAF IP is accessible but origin IP is not, the configuration is valid
        log "    ${BOLD}${GREEN}🔒 Success${RESET}"
        if $verbose; then
          log " (${GREY}WAF IP is accessible and Origin IP is not accessible${RESET})\n"
        fi
        status="safe"
      fi
    else
      if [ "${origin_ip_accessible}" = true ]; then
        # WAF IP is not accessible but origin IP is, the configuration is strange (WAF down?)
        log "    ${BOLD}${YELLOW}🤔 Error${RESET}"
        if $verbose; then
          log " (${GREY}Something is strange, WAF IP is not accessible but Origin IP is accessible${RESET})\n"
        fi
        status="error"
      else
        # WAF IP is not accessible and origin IP is not accessible either, the configuration is strange (network down?)
        log "    ${BOLD}${YELLOW}🤔 Error${RESET}"
        if $verbose; then
          log " (${GREY}Something is strange, WAF IP and Origin IP are not accessible${RESET})\n"
        fi
        status="unreachable"
      fi
    fi
  fi

  # Append data in output JSON file depending on --all flag
  if $all; then
    json $account_id $domain origin_ip_status[@] waf_ip_status[@] $origin_ip_accessible $waf_ip_accessible $status
  else
    if [ "$status" != "safe" ]; then
      json $account_id $domain origin_ip_status[@] waf_ip_status[@] $origin_ip_accessible $waf_ip_accessible $status
    fi
  fi

  log "\n"
done
