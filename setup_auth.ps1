param (
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$Password
)

Write-Host "Generating htpasswd file using Docker..."

if (-not (Test-Path "certs\proxy.crt")) {
    Write-Host "Generating self-signed certificate..."
    New-Item -ItemType Directory -Force -Path "certs" | Out-Null
    # Call through wsl bash to ensure proper volume mounting paths
    wsl bash -c "docker run --rm -v `"`$(pwd)/certs:/certs`" alpine/openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /certs/proxy.key -out /certs/proxy.crt -subj '/CN=Proxy'"
}

# Run an Alpine container to use htpasswd and create the file
wsl docker run --rm -i alpine:latest sh -c "apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -bc /dev/stdout $Username $Password" | Out-File -Encoding ascii passwd

if ($LASTEXITCODE -eq 0) {
    Write-Host "passwd file generated successfully in the current directory."
} else {
    Write-Host "Error generating passwd file."
    exit $LASTEXITCODE
}
