#!/bin/bash

# Check if both arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    exit 1
fi

USERNAME=$1
PASSWORD=$2

echo "Generating htpasswd file using Docker..."

# Run an Alpine container to use htpasswd and create the file
docker run --rm -i alpine:latest sh -c "apk add --no-cache apache2-utils >/dev/null 2>&1 && htpasswd -bc /dev/stdout $USERNAME $PASSWORD" > passwd

if [ $? -eq 0 ]; then
    echo "passwd file generated successfully in the current directory."
else
    echo "Error generating passwd file."
    exit 1
fi
