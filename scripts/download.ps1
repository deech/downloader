param (
  [string]$url,
  [string]$queryParams = "",
  [string]$outputPath,
  [string]$userAgent,
  [string]$proxy = "",
  [string]$auth = "",
  [string]$user = "",
  [string]$pass = ""
)

Add-Type -AssemblyName System.Web

Try {
  $wc = New-Object System.Net.WebClient;
  $wc.Headers.Add("User-Agent", $userAgent);
  If ($queryParams -ne "") {
    $encodedParams = [System.Web.HttpUtility]::UrlEncode($queryParams);
    $url = $url + '?' + $encodedParams
  }
  if ($proxy -ne "") {
    $proxyUri = New-Object System.Uri -ArgumentList $proxy
    $proxyObject = New-Object System.Net.WebProxy -ArgumentList $proxyUri
    if ($auth -eq "basic") {
      $creds = New-Object System.Net.NetworkCredential -ArgumentList $user, $pass;
      $proxyObject.Credentials = $creds;
    }
    elseif ($auth -eq "digest") {
      $creds = New-Object System.Net.NetworkCredential -ArgumentList $user, $pass;
      $proxyObject.Credentials = $creds;
    }
    else {}
    $wc.Proxy = $proxyObject;
  }
  $wc.DownloadFile($url, $outputPath);
  Write-Host "200";
}
Catch {
  $ex = $_.Exception;
  While ($ex -ne $null) {
    Write-Host $ex.Message;
    $ex = $ex.InnerException;
  }
}
