#!/bin/bash

# Imperva WAF API endpoint and access token
API_ENDPOINT="https://my.imperva.com/api/prov/v1"
API_ID="00000" # /!\ To replace with your Imperva API ID
API_KEY="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # /!\ To replace with your Imperva API Key 
ACCOUNT_ID="0000000" # To replace with your Imperva WAF Account ID

TIMEOUT_DURATION="10"

# Step 1: List sites from the account
echo "Retrieving sites from account ($ACCOUNT_ID)..."
echo

# Make the API request to list sites
response=$(curl -s -X POST -H "accept: application/json" "$API_ENDPOINT/sites/list?api_id=$API_ID&api_key=$API_KEY&account_id=$ACCOUNT_ID")

# Iterate through the sites
echo "$response" | jq -c '.sites[]' | while IFS=$'\t' read -r site; do
  # Initialize the values
  origin_ip_accessible=false
  waf_ip_accessible=false

  # Extract the fields
  domain=$(echo "$site" | jq -r ".domain")
  account_id=$(echo "$site" | jq -r ".account_id")
  ips=$(echo "$site" | jq -r ".ips[]" | tr '\n' ' ')
  dns=$(echo "$site" | jq -r ".dns[].set_data_to[]" | tr '\n' ' ')
  original_dns=$(echo "$site" | jq -r ".original_dns[].set_data_to[]" | tr "\n" " ")
  display_name=$(echo "$site" | jq -r ".display_name")

  echo -e "  (\e[1m$account_id\e[0m) \e[1m$domain\e[0m"

  echo -e "    - Original IPs: \e[2m$ips\e[0m      Original DNS: \e[2m$original_dns\e[0m"

  # Split ips into an array
  IFS=" " read -r -a ips_array <<< "$ips"

  # Loop through each IP or CNAME in dns
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

  # Loop through each IP or CNAME in dns
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
