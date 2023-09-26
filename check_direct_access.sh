#!/bin/bash

# Check command line arguments
print_help() {
  echo "Usage: ./check_direct_access.sh [OPTIONS]"
  echo "Options:"
  echo "  -v, --verbose           Enable verbose mode"
  echo "  -o, --output FILE.txt   Specify the output file with a .txt extension"
  echo "  -t, --timeout SECONDS   Specify the timeout in seconds (positive integer)"
  echo "  --websites-only         Enable websites-only mode"
  echo "  --env FILE              Specify the path to a .env file for environment variables"
  echo "  -h, --help              Display this help message"
  exit 0
}

# Declare local variables for this script
verbose=false       # Verbose mode option
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
  -o | --output)
    if [[ -n "$2" ]]; then
      # Check if the output file has a .txt extension
      if [[ "$2" == *.txt ]]; then
        output_file="$2"
        shift 2
      else
        echo "Error: Output file must have a .txt extension" >&2
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
    exit 1
    ;;
  esac
done

# Parse environment variables from .env file
source $env_file

# Check if the output file is still empty, in that case use ACCOUNT_ID from env file to name the output file
if [[ -z "$output_file" ]]; then
  if [[ -n "$env_file" && -f "$env_file" ]]; then
    if [[ -n "$ACCOUNT_ID" ]]; then
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

# Print ASCII art banner
echo -e "${BOLD}${BLUE}Y   ,---,          ____                                                                     .---.   ,---,           ,---,.\n,\`--.' |        ,'  , \`.,-.----.                                                          /. ./|  '  .' \        ,'  .' |\n|   :  :     ,-+-,.' _ |\    /  \             __  ,-.                                 .--'.  ' ; /  ;    '.    ,---.'   |\n:   |  '  ,-+-. ;   , |||   :    |          ,' ,'/ /|    .---.                       /__./ \ : |:  :       \   |   |   .'\n|   :  | ,--.'|'   |  |||   | .\ :   ,---.  '  | |' |  /.  ./|   ,--.--.         .--'.  '   \' .:  |   /\   \  :   :  :  \n'   '  ;|   |  ,', |  |,.   : |: |  /     \ |  |   ,'.-' . ' |  /       \       /___/ \ |    ' '|  :  ' ;.   : :   |  |-,\n|   |  ||   | /  | |--' |   |  \ : /    /  |'  :  / /___/ \: | .--.  .-. |      ;   \  \;      :|  |  ;/  \   \|   :  ;/|\n'   :  ;|   : |  | ,    |   : .  |.    ' / ||  | '  .   \  ' .  \__\/: . .       \   ;  \`      |'  :  | \  \ ,'|   |   .'\n|   |  '|   : |  |/     :     |\`-''   ;   /|;  : |   \   \   '  ,\" .--.; |        .   \    .\  ;|  |  '  '--'  '   :  '  \n'   :  ||   | |\`-'      :   : :   '   |  / ||  , ;    \   \    /  /  ,.  |         \   \   ' \ ||  :  :        |   |  |  \n;   |.' |   ;/          |   | :   |   :    | ---'      \   \ |;  :   .'   \\         :   '  |--\" |  | ,'        |   :  \  \n'---'   '---'           \`---'.|    \   \  /             '---\" |  ,     .-./          \   \ ;    \`--''          |   | ,'  \n                          \`---\`     \`----'                     \`--\`---'               '---\"                    \`----'    ${RESET}\n"

# List account websites from Imperva API
echo -e "Retrieving websites from Imperva account (${GREY}${ACCOUNT_ID}${RESET})..."
response=$(curl -s -X POST -H "accept: application/json" "$API_ENDPOINT/sites/list?api_id=$API_ID&api_key=$API_KEY&account_id=$ACCOUNT_ID")

# Iterate through the Imperva websites
echo -e "Sending requests to check direct access for Imperva protected websites...\n"
echo "$response" | jq -c '.sites[]' | while IFS=$'\t' read -r site; do
  # Initialize variables
  origin_ip_accessible=false # Boolean to check if the origin IP is accessible
  waf_ip_accessible=false    # Boolean to check if the WAF IP is accessible

  # Extract the fields from the API response
  domain=$(echo "$site" | jq -r ".domain")                                         # The domain name
  account_id=$(echo "$site" | jq -r ".account_id")                                 # The Imperva account ID
  ips=$(echo "$site" | jq -r ".ips[]" | tr '\n' ' ')                               # The origin IP addresses
  dns=$(echo "$site" | jq -r ".dns[].set_data_to[]" | tr '\n' ' ')                 # The current DNS record
  origin_dns=$(echo "$site" | jq -r ".original_dns[].set_data_to[]" | tr "\n" " ") # The origin DNS record
  display_name=$(echo "$site" | jq -r ".display_name")                             # The display name for the site

  # Print account ID and domain
  echo -e "- ${BOLD}${domain}${RESET} (${GREY}${account_id}${RESET})"
  # Check accessibility of each origin IP
  echo -e "      💻 Origin IPs ( ${GREY}${ips}${RESET}) & DNS ( ${GREY}${origin_dns}${RESET})"

  # Split IPs into an array
  IFS=" " read -r -a ips_array <<<"$ips"
  # Iterate through each IP or CNAME in DNS
  for entry in $origin_dns; do
    # Check if the entry is an IP address
    if [[ $entry =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      # Check if the IP is not already in waf_ip
      if [[ ! " ${ips_array[@]} " =~ " ${entry} " ]]; then
        ips="$ips $entry"
      fi
    else
      # Perform recursive dig to obtain IP behind the CNAME
      ip=$(dig +short $entry | grep -v CNAME)
      # Split ip into an array
      IFS=$'\n' read -r -a ip_array <<<"$ip"
      # Loop through each IP obtained from the CNAME
      for ip_entry in "${ip_array[@]}"; do
        # Check if the IP is not already in waf_ip
        if [[ ! " ${ips_array[@]} " =~ " ${ip_entry} " ]]; then
          origin_ip="$ips $ip_entry"
        fi
      done
    fi
  done

  # Check direct accessibility of origin server IPs
  for ip in $ips; do
    # Print the Origin IP being checked
    echo -en "            Origin IP ${GREY}${ip}${RESET}"

    # Check if the IP is directly accessible
    result=$(timeout "${timeout}" curl -sILk "https://${domain}" --resolve "${domain}:443:${ip}" -o /dev/null -w "%{http_code}")

    if [[ "${result}" == "200" ]]; then
      # Origin IP is directly accessible
      echo -e " is directly accessible (${GREY}HTTP_CODE $result${RESET}) 👎"
      origin_ip_accessible=true
    else
      # Origin IP is not directly accessible
      echo -e " is not directly accessible (${GREY}HTTP_CODE $result${RESET}) 👍"
    fi
  done

  # Check accessibility of each WAF IPs
  waf_ips=$(dig +short "${domain}" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tr "\n" " ")
  echo -e "      🛡️ WAF IPs ( ${GREY}${waf_ips}${RESET}) & DNS ( ${GREY}${dns}${RESET})"

  # Append all DNS entries from the WAF to the online extracted list
  # Split waf_ip into an array
  IFS=" " read -r -a waf_ip_array <<<"$waf_ips"
  # Iterate through each IP or CNAME in dns
  for entry in $dns; do
    # Check if the entry is an IP address
    if [[ $entry =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      # Check if the IP is not already in waf_ips
      if [[ ! " ${waf_ip_array[@]} " =~ " ${entry} " ]]; then
        waf_ips="$waf_ips $entry"
      fi
    else
      # Perform recursive dig to obtain IP behind the CNAME
      ip=$(dig +short $entry | grep -v CNAME)
      # Split ip into an array
      IFS=$'\n' read -r -a ip_array <<<"$ip"
      # Loop through each IP obtained from the CNAME
      for ip_entry in "${ip_array[@]}"; do
        # Check if the IP is not already in waf_ips
        if [[ ! " ${waf_ip_array[@]} " =~ " ${ip_entry} " ]]; then
          waf_ips="$waf_ips $ip_entry"
        fi
      done
    fi
  done

  # Check direct accessibility of WAF IP
  for waf_ip in $waf_ips; do
    # Print the WAF IP being checked
    echo -en "            WAF IP ${GREY}${waf_ip}${RESET}"

    # Check if the IP is directly accessible
    result=$(timeout "${timeout}" curl -sILk "https://${domain}" --resolve "${domain}:443:${waf_ip}" -o /dev/null -w "%{http_code}")

    if [[ "${result}" == "200" ]]; then
      # WAF IP is directly accessible
      echo -e " is accessible (${GREY}HTTP_CODE $result${RESET}) 👍"
      waf_ip_accessible=true
    else
      # WAF IP is not directly accessible
      echo -e " is not accessible (${GREY}HTTP_CODE $result${RESET}) 🤔"
    fi
  done

  # Print summary
  if [ "$waf_ip_accessible" = true ]; then
    if [ "$origin_ip_accessible" = true ]; then
      # Both IP are accessible, the configuration is a failure
      echo -e "    ${RED}❌ Failure${RESET} (${GREY}Origin IP is directly accessible, WAF IP is accessible too${RESET})"
    else
      # WAF IP is accessible but origin IP is not, the configuration is valid
      echo -e "    ${GREEN}🔒 Success${RESET} (${GREY}WAF IP is accessible and Origin IP is not accessible${RESET})"
    fi
  else
    if [ "$origin_ip_accessible" = true ]; then
      # WAF IP is not accessible but origin IP is, the configuration is strange (WAF down?)
      echo -e "    ${YELLOW}🤔 Error${RESET} (${GREY}Something is strange, WAF IP is not accessible but Origin IP is accessible${RESET})"
    else
      # WAF IP is not accessible and origin IP is not accessible either, the configuration is strange (network down?)
      echo -e "    ${YELLOW}🤔 Error${RESET} (${GREY}Something is strange, WAF IP and Origin IP are not accessible${RESET})"
    fi
  fi

  echo
done
