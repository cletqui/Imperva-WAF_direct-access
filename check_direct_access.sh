#!/bin/bash

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
verbose=false # Verbose option
output_file="" # Output file option (initialized with Imperva account ID by default after the parsing of the options)
websites_only=false # Extract only the websites option
timeout_value="10" # Time before a request is considered as a timeout (in seconds, by default 10 seconds)
env_file=".env" # Environment file path option

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      verbose=true
      shift
      ;;
    -o|--output)
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
    -t|--timeout)
      if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
        timeout_value="$2"
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
    -h|--help)
      print_help
      ;;
    *)
      echo "Error: Unknown option $1" >&2
      exit 1
      ;;
  esac
done

# Retrieve global environment variables stored in env_file
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

# Now you can use the parsed options
echo "Verbose: $verbose"
echo "Output File: $output_file"
echo "Websites Only: $websites_only"
echo "Timeout: $timeout_value seconds"
echo "Env File: $env_file"

# Print ASCII art
echo -e "\e[0;34m   ,---,          ____                                                                     .---.   ,---,           ,---,.\n,\`--.' |        ,'  , \`.,-.----.                                                          /. ./|  '  .' \        ,'  .' |\n|   :  :     ,-+-,.' _ |\    /  \             __  ,-.                                 .--'.  ' ; /  ;    '.    ,---.'   |\n:   |  '  ,-+-. ;   , |||   :    |          ,' ,'/ /|    .---.                       /__./ \ : |:  :       \   |   |   .'\n|   :  | ,--.'|'   |  |||   | .\ :   ,---.  '  | |' |  /.  ./|   ,--.--.         .--'.  '   \' .:  |   /\   \  :   :  :  \n'   '  ;|   |  ,', |  |,.   : |: |  /     \ |  |   ,'.-' . ' |  /       \       /___/ \ |    ' '|  :  ' ;.   : :   |  |-,\n|   |  ||   | /  | |--' |   |  \ : /    /  |'  :  / /___/ \: | .--.  .-. |      ;   \  \;      :|  |  ;/  \   \|   :  ;/|\n'   :  ;|   : |  | ,    |   : .  |.    ' / ||  | '  .   \  ' .  \__\/: . .       \   ;  \`      |'  :  | \  \ ,'|   |   .'\n|   |  '|   : |  |/     :     |\`-''   ;   /|;  : |   \   \   '  ,\" .--.; |        .   \    .\  ;|  |  '  '--'  '   :  '  \n'   :  ||   | |\`-'      :   : :   '   |  / ||  , ;    \   \    /  /  ,.  |         \   \   ' \ ||  :  :        |   |  |  \n;   |.' |   ;/          |   | :   |   :    | ---'      \   \ |;  :   .'   \\         :   '  |--\" |  | ,'        |   :  \  \n'---'   '---'           \`---'.|    \   \  /             '---\" |  ,     .-./          \   \ ;    \`--''          |   | ,'  \n                          \`---\`     \`----'                     \`--\`---'               '---\"                    \`----'    \e[0m\n"

# List websites from Imperva account
echo -e "Retrieving websites from Imperva account (\e[1;30m$ACCOUNT_ID\e[0m)...\n"
exit
# Make an Imperva API request to list account websites
response=$(curl -s -X POST -H "accept: application/json" "$API_ENDPOINT/sites/list?api_id=$API_ID&api_key=$API_KEY&account_id=$ACCOUNT_ID")

# Iterate through the websites
echo "$response" | jq -c '.sites[]' | while IFS=$'\t' read -r site; do
  # Initialize local values
  origin_ip_accessible=false # Boolean to check if the website is directly accessible
  waf_ip_accessible=false # Boolean to check if the website is accessible through Imperva WAF

  # Extract the fields from the API response
  domain=$(echo "$site" | jq -r ".domain") # The account domain
  account_id=$(echo "$site" | jq -r ".account_id") # The Imperva account ID
  ips=$(echo "$site" | jq -r ".ips[]" | tr '\n' ' ') # The original IP for the account
  dns=$(echo "$site" | jq -r ".dns[].set_data_to[]" | tr '\n' ' ') # The current DNS record
  original_dns=$(echo "$site" | jq -r ".original_dns[].set_data_to[]" | tr "\n" " ") # The original DNS response for the account
  display_name=$(echo "$site" | jq -r ".display_name") # The Imperva account display name

  echo -e "  (\e[1m$account_id\e[0m) \e[1m$domain\e[0m"

  echo -e "    - Original IPs: \e[2m$ips\e[0m      Original DNS: \e[2m$original_dns\e[0m"

  # Split ips into an array
  IFS=" " read -r -a ips_array <<< "$ips"

  # Iterate through each IP or CNAME in DNS
  for entry in $original_dns; do
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
      IFS=$'\n' read -r -a ip_array <<< "$ip"
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
    result=$(timeout "${timeout_duration}" curl -sILk "https://${domain}" --resolve "${domain}:443:${ip}" -o /dev/null -w "%{http_code}")

    if [[ "${result}" == "200" ]]; then
      echo -e "        \e[31m❗\e[0m Origin IP \e[2m${ip}\e[0m is directly accessible (\e[2mHTTP_CODE $result\e[0m)."
      origin_ip_accessible=true
    else
      echo -e "        \e[32m✅\e[0m Origin IP \e[2m${ip}\e[0m is not directly accessible (\e[2mHTTP_CODE $result\e[0m)." 
    fi
  done

  # Check DNS to find the online IPs for the WAF
  waf_ips=$(dig +short "${domain}" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tr "\n" " ")
  echo -e "    - WAF IPs: \e[2m$waf_ips\e[0m      DNS: \e[2m$dns\e[0m"

  # Append all DNS entries from the WAF to the online extracted list
  # Split waf_ip into an array
  IFS=" " read -r -a waf_ip_array <<< "$waf_ips"

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
      IFS=$'\n' read -r -a ip_array <<< "$ip"
      # Loop through each IP obtained from the CNAME
      for ip_entry in "${ip_array[@]}"; do
        # Check if the IP is not already in waf_ips
        if [[ ! " ${waf_ip_array[@]} " =~ " ${ip_entry} " ]]; then
          waf_ips="$waf_ips $ip_entry"
        fi
      done
    fi
  done

  # Check accessibility of WAF IPs
  for waf_ip in $waf_ips; do
    result=$(timeout "${timeout_duration}" curl -sILk  "https://${domain}" --resolve "${domain}:443:${waf_ip}" -o /dev/null -w "%{http_code}")

    if [[ "${result}" == "200" ]]; then
      echo -e "        \e[32m✅\e[0m WAF IP \e[2m${waf_ip}\e[0m is accessible (\e[2mHTTP_CODE $result\e[0m)."
      waf_ip_accessible=true
    else
      echo -e "        \e[31m❌\e[0m WAF IP \e[2m${waf_ip}\e[0m is not accessible (\e[2mHTTP_CODE $result\e[0m)."
    fi
  done

  # Print the final result
  if [ "$waf_ip_accessible" = true ]; then
    if [ "$origin_ip_accessible" = true ]; then
      echo -e "  \e[31m❗ Failure\e[0m: Origin IP is directly accessible, WAF IP is accessible too."
    else
      echo -e "  \e[32m✅ Success\e[0m: WAF IP is accessible and Origin IP is not accessible."
    fi
  else
    if [ "$origin_ip_accessible" = true ]; then
      echo -e "  \e[31m❌ Error\e[0m: Something is strange, WAF IP is not accessible but Origin IP is accessible."
    else
      echo -e "  \e[31m❌ Error\e[0m: Something is strange, WAF IP and Origin IP are not accessible."
    fi
  fi

  echo
done
