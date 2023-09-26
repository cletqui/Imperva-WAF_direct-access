#!/bin/bash

# Retrieve global environment variables stored in .env
source .env

# Declare global variables for this script
TIMEOUT_DURATION="10" # Time before a request is considered as a timeout (in seconds)

# Print ASCII art
echo -e "\e[0;34m   ,---,          ____                                                                     .---.   ,---,           ,---,.\n,\`--.' |        ,'  , \`.,-.----.                                                          /. ./|  '  .' \        ,'  .' |\n|   :  :     ,-+-,.' _ |\    /  \             __  ,-.                                 .--'.  ' ; /  ;    '.    ,---.'   |\n:   |  '  ,-+-. ;   , |||   :    |          ,' ,'/ /|    .---.                       /__./ \ : |:  :       \   |   |   .'\n|   :  | ,--.'|'   |  |||   | .\ :   ,---.  '  | |' |  /.  ./|   ,--.--.         .--'.  '   \' .:  |   /\   \  :   :  :  \n'   '  ;|   |  ,', |  |,.   : |: |  /     \ |  |   ,'.-' . ' |  /       \       /___/ \ |    ' '|  :  ' ;.   : :   |  |-,\n|   |  ||   | /  | |--' |   |  \ : /    /  |'  :  / /___/ \: | .--.  .-. |      ;   \  \;      :|  |  ;/  \   \|   :  ;/|\n'   :  ;|   : |  | ,    |   : .  |.    ' / ||  | '  .   \  ' .  \__\/: . .       \   ;  \`      |'  :  | \  \ ,'|   |   .'\n|   |  '|   : |  |/     :     |\`-''   ;   /|;  : |   \   \   '  ,\" .--.; |        .   \    .\  ;|  |  '  '--'  '   :  '  \n'   :  ||   | |\`-'      :   : :   '   |  / ||  , ;    \   \    /  /  ,.  |         \   \   ' \ ||  :  :        |   |  |  \n;   |.' |   ;/          |   | :   |   :    | ---'      \   \ |;  :   .'   \\         :   '  |--\" |  | ,'        |   :  \  \n'---'   '---'           \`---'.|    \   \  /             '---\" |  ,     .-./          \   \ ;    \`--''          |   | ,'  \n                          \`---\`     \`----'                     \`--\`---'               '---\"                    \`----'    \e[0m\n"

# List websites from Imperva account
echo -e "Retrieving websites from Imperva account (\e[1;30m$ACCOUNT_ID\e[0m)...\n"

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
    result=$(timeout "${TIMEOUT_DURATION}" curl -sILk "https://${domain}" --resolve "${domain}:443:${ip}" -o /dev/null -w "%{http_code}")

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
    result=$(timeout "${TIMEOUT_DURATION}" curl -sILk  "https://${domain}" --resolve "${domain}:443:${waf_ip}" -o /dev/null -w "%{http_code}")

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
