# PowerShell seeder wrapper
# Usage:
# $env:EMAIL="admin@example.com"; $env:PASSWORD="yourpassword"; $env:BASE_URL="http://192.168.1.8:3000/api"; node seed_gym.js

if (-not $env:EMAIL -or -not $env:PASSWORD) {
  Write-Error "Please set EMAIL and PASSWORD environment variables"
  exit 1
}

Write-Output "Running node seeder..."
node seed_gym.cjs


