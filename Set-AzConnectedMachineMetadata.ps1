Param (
    [string]$location,
    [string]$platform
)

#Requires -Modules Az.Resources
#Requires -Modules Az.Accounts

function Get-AzHybridVMId {
    $medatada = Invoke-WebRequest -Uri http://localhost:40342/metadata/instance?api-version=2019-11-01 -Headers @{Metadata="True"}
    $medatada = $medatada.content | ConvertFrom-Json
    return $medatada.compute.vmId
}

function Get-AzHybridVMResourceId {
    $medatada = Invoke-WebRequest -Uri http://localhost:40342/metadata/instance?api-version=2019-11-01 -Headers @{Metadata="True"}
    $medatada = $medatada.content | ConvertFrom-Json
    return $medatada.compute.resourceId
}

function Get-AzArcToken {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:40342/metadata/identity/oauth2/token?api-version=2019-11-01&resource=https%3A%2F%2Fmanagement.azure.com%2F" -Headers @{ Metadata = "true" } -Verbose:0
    }
    catch {
        $response = $_.Exception.Response
    }

    $tokenpath = $response.Headers["WWW-Authenticate"].TrimStart("Basic realm=")
    $token = Get-Content $tokenpath

    $ArcToken = Invoke-RestMethod -UseBasicParsing -Uri "http://localhost:40342/metadata/identity/oauth2/token?api-version=2019-11-01&resource=https%3A%2F%2Fmanagement.azure.com%2F" -Headers @{ Metadata = "true"; Authorization = "Basic $token" } 
    return $ArcToken.access_token
}

$token = Get-AzArcToken
$vmId = Get-AzHybridVMId

Connect-AzAccount -AccessToken $token -AccountId $vmId | Out-Null

# collect cores
$physicalCores = 0
(Get-WmiObject Win32_Processor).NumberOfCores | %{ $physicalCores += $_}

# collect memories
$totalMemory = 0
Get-WmiObject Win32_PhysicalMemory | % {$totalMemory += $_.Capacity}
$totalMemory = [int]($totalMemory/1GB)

# Collect ip address
$defaultInterfaceIndex = (Get-NetRoute -DestinationPrefix 0.0.0.0/0).ifIndex
$defaultNic = Get-NetIPAddress -Type Unicast -AddressFamily IPv4 | Where-Object { $_.ifIndex -eq $defaultInterfaceIndex }
$defaultIpaddress = $defaultNic.IpAddress

$cmTag = @{
    "cmCore" = $physicalCores
    "cmMemory" = $totalMemory
    "cmIpaddress" = $defaultIpaddress
    "cmLocation" = $location
    "cmPlatform" = $platform   
}

New-AzTag -ResourceId (Get-AzHybridVMResourceId) -Tag $cmTag
