param(
  [int]$Port = 5500,
  [string]$Root = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    ".html" { return "text/html; charset=utf-8" }
    ".htm"  { return "text/html; charset=utf-8" }
    ".css"  { return "text/css; charset=utf-8" }
    ".js"   { return "application/javascript; charset=utf-8" }
    ".json" { return "application/json; charset=utf-8" }
    ".csv"  { return "text/csv; charset=utf-8" }
    ".jpg"  { return "image/jpeg" }
    ".jpeg" { return "image/jpeg" }
    ".png"  { return "image/png" }
    ".svg"  { return "image/svg+xml" }
    ".kml"  { return "application/vnd.google-earth.kml+xml" }
    default { return "application/octet-stream" }
  }
}

function Write-HttpResponse(
  [System.Net.Sockets.NetworkStream]$Stream,
  [int]$StatusCode,
  [string]$StatusText,
  [byte[]]$BodyBytes,
  [string]$ContentType = "text/plain; charset=utf-8"
) {
  $header =
    "HTTP/1.1 $StatusCode $StatusText`r`n" +
    "Content-Type: $ContentType`r`n" +
    "Content-Length: $($BodyBytes.Length)`r`n" +
    "Connection: close`r`n`r`n"
  $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($BodyBytes.Length -gt 0) {
    $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
  }
}

$rootFull = [IO.Path]::GetFullPath($Root)
$ip = [System.Net.IPAddress]::Parse("127.0.0.1")
$listener = [System.Net.Sockets.TcpListener]::new($ip, $Port)
$listener.Start()
Write-Host "Serving $rootFull at http://127.0.0.1:$Port/"

while ($true) {
  $client = $null
  try {
    $client = $listener.AcceptTcpClient()
    $client.ReceiveTimeout = 5000
    $client.SendTimeout = 5000
    $stream = $client.GetStream()
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 1024, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }

    while ($true) {
      $line = $reader.ReadLine()
      if ($null -eq $line -or $line -eq "") { break }
    }

    $parts = $requestLine.Split(" ")
    if ($parts.Length -lt 2) {
      $body = [Text.Encoding]::UTF8.GetBytes("400 Bad Request")
      Write-HttpResponse -Stream $stream -StatusCode 400 -StatusText "Bad Request" -BodyBytes $body
      $client.Close()
      continue
    }

    $method = $parts[0].ToUpperInvariant()
    if ($method -ne "GET" -and $method -ne "HEAD") {
      $body = [Text.Encoding]::UTF8.GetBytes("405 Method Not Allowed")
      Write-HttpResponse -Stream $stream -StatusCode 405 -StatusText "Method Not Allowed" -BodyBytes $body
      $client.Close()
      continue
    }

    $rawPath = $parts[1].Split("?")[0]
    $relPath = [System.Uri]::UnescapeDataString($rawPath.TrimStart("/"))
    if ([string]::IsNullOrWhiteSpace($relPath)) { $relPath = "index.html" }

    $fullPath = [IO.Path]::GetFullPath((Join-Path $rootFull $relPath))
    if (-not $fullPath.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      $body = [Text.Encoding]::UTF8.GetBytes("403 Forbidden")
      Write-HttpResponse -Stream $stream -StatusCode 403 -StatusText "Forbidden" -BodyBytes $body
      $client.Close()
      continue
    }

    if (Test-Path $fullPath -PathType Container) {
      $fullPath = Join-Path $fullPath "index.html"
    }

    if (-not (Test-Path $fullPath -PathType Leaf)) {
      $body = [Text.Encoding]::UTF8.GetBytes("404 Not Found")
      Write-HttpResponse -Stream $stream -StatusCode 404 -StatusText "Not Found" -BodyBytes $body
      $client.Close()
      continue
    }

    $bytes = [IO.File]::ReadAllBytes($fullPath)
    $ctype = Get-ContentType $fullPath
    if ($method -eq "HEAD") {
      Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText "OK" -BodyBytes @() -ContentType $ctype
    } else {
      Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText "OK" -BodyBytes $bytes -ContentType $ctype
    }
    $client.Close()
  } catch {
    if ($client) { $client.Close() }
  }
}
