FROM postgres:18-alpine

# Install AWS CLI and curl
RUN apk add --no-cache aws-cli curl bash

WORKDIR /app

# Combine logic into one script for simplicity
COPY manage.sh /app/manage.sh
RUN chmod +x /app/manage.sh

# Keep alive for Railway shell access
CMD ["sleep", "infinity"]
