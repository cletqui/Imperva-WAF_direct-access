param (
  [switch]$Verbose,
  [string]$OutputFile,
  [int]$Timeout = 10,
  [switch]$WebsitesOnly,
  [string]$EnvFile = ".env"
)

function Show-Help {
  Write-Host "Usage: ./check_direct_access.ps1 [OPTIONS]"
  Write-Host "Options:"
  Write-Host "  -v, --verbose           Enable verbose mode"
  Write-Host "  -o, --output FILE.txt   Specify the output file with a .txt extension"
  Write-Host "  -t, --timeout SECONDS   Specify the timeout in seconds (positive integer)"
  Write-Host "  --websites-only         List only websites, no check is performed"
  Write-Host "  --env FILE              Specify the path to a .env file for environment variables"
  Write-Host "  -h, --help              Display this help message"
  exit 0
}

$Options = @{
  Verbose      = $Verbose
  OutputFile   = $OutputFile
  WebsitesOnly = $WebsitesOnly
  Timeout      = $Timeout
  EnvFile      = $EnvFile
}

function Log {
  param (
    [string]$Message,
    [string]$Color = "Reset"
  )
  $Colors = @{
    Reset  = [ConsoleColor]::White
    Grey   = [ConsoleColor]::DarkGray
    Red    = [ConsoleColor]::Red
    Green  = [ConsoleColor]::Green
    Yellow = [ConsoleColor]::Yellow
    Blue   = [ConsoleColor]::Blue
    Bold   = [ConsoleColor]::White
  }
  $OriginalColor = $Host.UI.RawUI.ForegroundColor
  $Host.UI.RawUI.ForegroundColor = $Colors[$Color]
  Write-Host $Message
  $Host.UI.RawUI.ForegroundColor = $OriginalColor
}

function Show-Verbose {
  param (
    [string]$Message
  )
  if ($Options.Verbose) {
    Log $Message
  }
}

function Get-EnvValue {
  param (
    [string]$Key
  )
  $EnvFileContent = Get-Content $EnvFile -ErrorAction SilentlyContinue
  $Value = $EnvFileContent | Where-Object { $_ -match "^$Key=" } | ForEach-Object { $_ -replace "^$Key=" }
  return $Value
}

function Get-WebsiteList {
  $ApiEndpoint = "https://api.imperva.com"
  $ApiId = Get-EnvValue -Key "API_ID"
  $ApiKey = Get-EnvValue -Key "API_KEY"
  $AccountId = Get-EnvValue -Key "ACCOUNT_ID"

  $RequestBody = @{
    api_id     = $ApiId
    api_key    = $ApiKey
    account_id = $AccountId
  } | ConvertTo-Json

  $Response = Invoke-RestMethod -Uri "$ApiEndpoint/sites/list" -Method POST -Headers @{ "accept" = "application/json" } -Body $RequestBody
  return $Response.sites
}

function Add-IpsFromDns {
  param (
    [string[]]$DnsEntries,
    [string[]]$CurrentIps
  )
  foreach ($entry in $DnsEntries) {
    if ($entry -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
      if ($CurrentIps -notcontains $entry) {
        $CurrentIps += $entry
      }
    }
    else {
      $ip = Resolve-DnsName $entry | Where-Object { $_.Type -ne "CNAME" } | Select-Object -ExpandProperty IPAddress
      foreach ($ipEntry in $ip) {
        if ($CurrentIps -notcontains $ipEntry) {
          $CurrentIps += $ipEntry
        }
      }
    }
  }
  return $CurrentIps
}

function Request-DirectAccess {
  param (
    [string]$Domain,
    [string[]]$Ips,
    [string[]]$Dns,
    [string[]]$OriginDns
  )

  $OriginIpAccessible = $false
  $WafIpAccessible = $false

  Log "- $Domain"

  if (-not $Options.WebsitesOnly) {
    Show-Verbose " (${Options.AccountId})"
    Show-Verbose "      💻 Origin IPs ( $($Ips -join ', ')) & DNS ( $($OriginDns -join ', '))"
    

    foreach ($entry in $OriginDns) {
      if ($entry -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        if ($Ips -notcontains $entry) {
          $Ips += $entry
        }
      }
      else {
        $ip = Resolve-DnsName $entry | Where-Object { $_.Type -ne "CNAME" } | Select-Object -ExpandProperty IPAddress
        foreach ($ipEntry in $ip) {
          if ($Ips -notcontains $ipEntry) {
            $Ips += $ipEntry
          }
        }
      }
    }

    foreach ($ip in $Ips) {
      Show-Verbose "            Origin IP $ip"

      $result = Invoke-WebRequest -Uri "https://$Domain" -Method Head -TimeoutSec $Options.Timeout -Resolve "$Domain:443:$ip" -UseBasicParsing -ErrorAction SilentlyContinue

      if ($result.StatusCode -eq 200) {
        if ($Options.Verbose) {
          Log " is directly accessible (HTTP_CODE $($result.StatusCode)) 👎"
        }
        $OriginIpAccessible = $true
      }
      else {
        Show-Verbose " is not directly accessible (HTTP_CODE $($result.StatusCode)) 👍"
        
      }
    }

    $wafIps = Resolve-DnsName $Domain | Where-Object { $_.Type -eq "A" } | Select-Object -ExpandProperty IPAddress

    Show-Verbose "      🌐 WAF IPs ( $($wafIps -join ', ')) & DNS ( $($Dns -join ', '))"

    foreach ($entry in $Dns) {
      if ($entry -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        if ($wafIps -notcontains $entry) {
          $wafIps += $entry
        }
      }
      else {
        $ip = Resolve-DnsName $entry | Where-Object { $_.Type -ne "CNAME" } | Select-Object -ExpandProperty IPAddress
        foreach ($ipEntry in $ip) {
          if ($wafIps -notcontains $ipEntry) {
            $wafIps += $ipEntry
          }
        }
      }
    }

    foreach ($wafIp in $wafIps) {
      Show-Verbose "            WAF IP $wafIp"

      $result = Invoke-WebRequest -Uri "https://$Domain" -Method Head -TimeoutSec $Options.Timeout -Resolve "$Domain:443:$wafIp" -UseBasicParsing -ErrorAction SilentlyContinue

      if ($result.StatusCode -eq 200) {
        Show-Verbose " is accessible (HTTP_CODE $($result.StatusCode)) 👍"
        
        $WafIpAccessible = $true
      }
      else {
        Show-Verbose " is not accessible (HTTP_CODE $($result.StatusCode)) 🤔"
        
      }
    }

    if ($WafIpAccessible) {
      if ($OriginIpAccessible) {
        Log "    🔒 Success"
        Show-Verbose " (WAF IP is accessible and Origin IP is not accessible)"
      }
      else {
        Log "    🚩 Failure"
        Show-Verbose " (Origin IP is directly accessible, WAF IP is accessible too)" 
      }
    }
    else {
      if ($OriginIpAccessible) {
        Log "    🤔 Error"
        Show-Verbose " (Something is strange, WAF IP is not accessible but Origin IP is accessible)"
      }
      else {
        Log "    🤔 Error"
        Show-Verbose " (Something is strange, WAF IP and Origin IP are not accessible)"
      }
    }
  }

  Log ""
}

if (-not $Options.WebsitesOnly) {
  Show-Verbose "Retrieving websites from Imperva account ($($Options.AccountId))..."
}

$Response = Get-WebsiteList

if (-not $Options.WebsitesOnly) {
  Show-Verbose "Sending requests to check direct access for Imperva protected websites..."
  Show-Verbose "Write output to output file $($Options.OutputFile)..."
  Show-Verbose ""
  
}

foreach ($site in $Response) {
  $domain = $site.domain
  $accountId = $site.account_id
  $ips = $site.ips
  $dns = $site.dns.set_data_to
  $originDns = $site.original_dns.set_data_to

  Request-DirectAccess -Domain $domain -Ips $ips -Dns $dns -OriginDns $originDns
}
