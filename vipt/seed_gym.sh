#!/usr/bin/env bash
# Usage:
# EMAIL=admin@example.com PASSWORD=yourpassword BASE_URL=http://192.168.1.8:3000/api ./seed_gym.sh

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Please set EMAIL and PASSWORD environment variables"
  exit 1
fi

BASE=${BASE_URL:-http://192.168.1.8:3000/api}

echo "Installing dependencies..."
npm install axios >/dev/null 2>&1 || true

echo "Running node seeder..."
EMAIL="$EMAIL" PASSWORD="$PASSWORD" BASE_URL="$BASE" node seed_gym.js



