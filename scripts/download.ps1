param (
  [string]$url,
  [string]$queryParams = "",
  [string]$outputPath,
  [string]$userAgent
)

Add-Type -AssemblyName System.Web

Try {
  $wc = New-Object System.Net.WebClient;
  $wc.Headers.Add("User-Agent", $userAgent);
  If ($queryParams -ne "") {
    $encodedParams = [System.Web.HttpUtility]::UrlEncode($queryParams);
    $url = $url + '?' + $encodedParams
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
