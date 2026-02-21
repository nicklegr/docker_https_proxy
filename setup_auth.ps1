param (
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [Parameter(Mandatory=$true)]
    [string]$Password
)

Write-Host "Generating htpasswd file using Docker..."

# Run an Alpine container to use htpasswd and create the file
wsl docker run --rm -i alpine:latest sh -c "apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -bc /dev/stdout $Username $Password" | Out-File -Encoding ascii passwd

if ($LASTEXITCODE -eq 0) {
    Write-Host "passwd file generated successfully in the current directory."
} else {
    Write-Host "Error generating passwd file."
    exit $LASTEXITCODE
}
