#!/bin/bash

# Check command line arguments
print_help() {
  echo "Usage: ./check_direct_access.sh [OPTIONS]"
  echo "Options:"
  echo "  -v, --verbose           Enable verbose mode"
  echo "  -o, --output FILE.txt   Specify the output file with a .txt extension"
  echo "  -t, --timeout SECONDS   Specify the timeout in seconds (positive integer)"
  echo "  --websites-only         List only websites, no check is performed"
  echo "  --env FILE              Specify the path to a .env file for environment variables"
  echo "  -h, --help              Display this help message"
  exit 0
}

# Declare local variables for this script
declare -A options=(
  [verbose]=false       # Verbose mode option
  [output_file]=""      # Output file path variable
  [websites_only]=false # Websites-only option
  [timeout]=10          # Default timeout value if not provided
  [env_file]=".env"     # Environment file path variable
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
while getopts ":v:o:t:h-:" opt; do
  case "$opt" in
  v) options[verbose]=true ;;
  o) options[output_file]=$OPTARG ;;
  t) options[timeout]=$OPTARG ;;
  h) print_help ;;
  -)
    case "${OPTARG}" in
    verbose) options[verbose]=true ;;
    output)
      options[output_file]="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      ;;
    timeout)
      options[timeout]="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      ;;
    websites-only) options[websites_only]=true ;;
    env)
      options[env_file]="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
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
source $env_file

# Check if the output file is still empty, in that case use ACCOUNT_ID from env file to name the output file
if [[ -z "${output_file}" ]]; then
  if [[ -n "${env_file}" && -f "${env_file}" ]]; then
    if [[ -n "${ACCOUNT_ID}" ]]; then
      output_file="${ACCOUNT_ID}.txt"
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
>"${output_file}"

# Echo and write text to output file
log() {
  local message="$1"
  local color="${2:-reset}"
  echo -en "${colors[$color]}${message}${colors[reset]}"
  echo -e "$message" >>"${options[output_file]}"
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
        origin_ip_accessible=true
      else
        # Origin IP is not directly accessible
        if $verbose; then
          log " is not directly accessible (${GREY}HTTP_CODE ${result}${RESET}) 👍\n"
        fi
      fi
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
        waf_ip_accessible=true
      else
        # WAF IP is not directly accessible
        if $verbose; then
          log " is not accessible (${GREY}HTTP_CODE ${result}${RESET}) 🤔\n"
        fi
      fi
    done

    # Print summary
    if [ "${waf_ip_accessible}" = true ]; then
      if [ "${origin_ip_accessible}" = true ]; then
        # Both IP are accessible, the configuration is a failure
        log "    ${BOLD}${RED}🚩 Failure${RESET}"
        if $verbose; then
          log " (${GREY}Origin IP is directly accessible, WAF IP is accessible too${RESET})\n"
        fi
      else
        # WAF IP is accessible but origin IP is not, the configuration is valid
        log "    ${BOLD}${GREEN}🔒 Success${RESET}"
        if $verbose; then
          log " (${GREY}WAF IP is accessible and Origin IP is not accessible${RESET})\n"
        fi
      fi
    else
      if [ "${origin_ip_accessible}" = true ]; then
        # WAF IP is not accessible but origin IP is, the configuration is strange (WAF down?)
        log "    ${BOLD}${YELLOW}🤔 Error${RESET}"
        if $verbose; then
          log " (${GREY}Something is strange, WAF IP is not accessible but Origin IP is accessible${RESET})\n"
        fi
      else
        # WAF IP is not accessible and origin IP is not accessible either, the configuration is strange (network down?)
        log "    ${BOLD}${YELLOW}🤔 Error${RESET}"
        if $verbose; then
          log " (${GREY}Something is strange, WAF IP and Origin IP are not accessible${RESET})\n"
        fi
      fi
    fi
  fi

  log "\n"
done
