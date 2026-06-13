# deploy.ps1 - Deploy Ops Encyclopedia Agent len GreenNode AgentBase
# Chay: .\deploy.ps1
# Yeu cau: Docker Desktop dang chay

$ErrorActionPreference = "Stop"

$CLIENT_ID     = "ce9e3da8-5262-466b-931e-99df6c43aa29"
$CLIENT_SECRET = "9131c9c6-6cd6-4558-99b2-b084183b5326"
$RUNTIME_NAME  = "ops-encyclopedia"
$ENV_FILE      = ".env.agentbase"

Write-Host ""
Write-Host "=== Bach Khoa Toan Thu Ops - Deploy Script ===" -ForegroundColor Cyan
Write-Host "Runtime: $RUNTIME_NAME"
Write-Host ""

# Step 1: Lay IAM token
Write-Host "[1/8] Lay IAM token..." -ForegroundColor Yellow
$CREDENTIALS = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${CLIENT_ID}:${CLIENT_SECRET}"))
$TOKEN_RESPONSE = Invoke-RestMethod `
    -Method POST `
    -Uri "https://iam.api.vngcloud.vn/accounts-api/v2/auth/token" `
    -Headers @{ Authorization = "Basic $CREDENTIALS" } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body "grant_type=client_credentials"

$TOKEN = $TOKEN_RESPONSE.access_token
if (-not $TOKEN) { Write-Error "Khong lay duoc IAM token!"; exit 1 }
Write-Host "  OK" -ForegroundColor Green

$HEADERS = @{ Authorization = "Bearer $TOKEN" }

# Step 2: Lay Container Registry info
Write-Host "[2/8] Lay Container Registry info..." -ForegroundColor Yellow
$REPO = Invoke-RestMethod `
    -Method GET `
    -Uri "https://agentbase.api.vngcloud.vn/cr/api/v1/repository" `
    -Headers $HEADERS

$REGISTRY_URL = $REPO.registryUrl
$REPO_NAME    = $REPO.name
Write-Host "  Registry: $REGISTRY_URL" -ForegroundColor Green
Write-Host "  Repo:     $REPO_NAME" -ForegroundColor Green

$CREDS = Invoke-RestMethod `
    -Method GET `
    -Uri "https://agentbase.api.vngcloud.vn/cr/api/v1/registry-credential" `
    -Headers $HEADERS

$CR_USER   = $CREDS.username
$CR_SECRET = $CREDS.secret
Write-Host "  CR User:  $CR_USER" -ForegroundColor Green

# Step 3: Docker login
Write-Host "[3/8] Docker login..." -ForegroundColor Yellow
$CR_SECRET | docker login $REGISTRY_URL -u $CR_USER --password-stdin
if ($LASTEXITCODE -ne 0) { Write-Error "Docker login that bai!"; exit 1 }
Write-Host "  OK" -ForegroundColor Green

# Step 4: Build Docker image
Write-Host "[4/8] Build Docker image (linux/amd64)..." -ForegroundColor Yellow
$TAG        = "v$(Get-Date -Format 'yyyyMMddHHmmss')"
$IMAGE_FULL = "$REGISTRY_URL/$REPO_NAME/${RUNTIME_NAME}:$TAG"
Write-Host "  Image: $IMAGE_FULL"

docker build -t $IMAGE_FULL .
if ($LASTEXITCODE -ne 0) { Write-Error "Docker build that bai!"; exit 1 }
Write-Host "  Build OK" -ForegroundColor Green

# Step 5: Push image
Write-Host "[5/8] Push image len registry..." -ForegroundColor Yellow
docker push $IMAGE_FULL
if ($LASTEXITCODE -ne 0) { Write-Error "Docker push that bai!"; exit 1 }
Write-Host "  Push OK" -ForegroundColor Green

# Step 6: Lay flavor
Write-Host "[6/8] Lay compute flavor..." -ForegroundColor Yellow
$FLAVORS_RESP = Invoke-RestMethod `
    -Method GET `
    -Uri "https://agentbase.api.vngcloud.vn/runtime/flavors" `
    -Headers $HEADERS

$FLAVOR = $FLAVORS_RESP.listData | Where-Object {
    $_.name -eq "1x1-general" -and $_.supportedResourceTypes -contains "agent-runtime"
} | Select-Object -First 1

if (-not $FLAVOR) {
    $FLAVOR = $FLAVORS_RESP.listData | Where-Object {
        $_.supportedResourceTypes -contains "agent-runtime"
    } | Select-Object -First 1
}

if (-not $FLAVOR) { Write-Error "Khong tim thay flavor!"; exit 1 }
$FLAVOR_ID = $FLAVOR.id
Write-Host "  Flavor: $($FLAVOR.name) (ID: $FLAVOR_ID)" -ForegroundColor Green

# Step 7: Doc env file
Write-Host "[7/8] Doc env file: $ENV_FILE..." -ForegroundColor Yellow
if (-not (Test-Path $ENV_FILE)) { Write-Error "Khong tim thay $ENV_FILE!"; exit 1 }

$ENV_VARS = @{}
Get-Content $ENV_FILE | Where-Object {
    $_ -notmatch "^\s*#" -and $_ -match "="
} | ForEach-Object {
    $idx = $_.IndexOf("=")
    $key = $_.Substring(0, $idx).Trim()
    $val = $_.Substring($idx + 1).Trim()
    if ($key) { $ENV_VARS[$key] = $val }
}
Write-Host "  Doc duoc $($ENV_VARS.Count) bien moi truong" -ForegroundColor Green

# Step 8: Tao runtime
Write-Host "[8/8] Tao AgentBase runtime..." -ForegroundColor Yellow

$EXISTING = $null
try {
    $LIST = Invoke-RestMethod `
        -Method GET `
        -Uri "https://agentbase.api.vngcloud.vn/runtime/agent-runtimes?page=1&size=100" `
        -Headers $HEADERS
    $EXISTING = $LIST.listData | Where-Object { $_.name -eq $RUNTIME_NAME } | Select-Object -First 1
} catch {}

$AUTOSCALING = @{
    minReplicas       = 1
    maxReplicas       = 1
    cpuUtilization    = 50
    memoryUtilization = 50
}
$IMAGE_AUTH = @{
    enabled  = $true
    username = $CR_USER
    password = $CR_SECRET
}
$RUNTIME_BODY = @{
    name                 = $RUNTIME_NAME
    description          = "Ops Encyclopedia AI Agent"
    imageUrl             = $IMAGE_FULL
    flavorId             = $FLAVOR_ID
    command              = @()
    args                 = @()
    environmentVariables = $ENV_VARS
    autoscaling          = $AUTOSCALING
    imageAuth            = $IMAGE_AUTH
} | ConvertTo-Json -Depth 6

$DEPLOY_HEADERS = @{
    Authorization  = "Bearer $TOKEN"
    "Content-Type" = "application/json"
}

if ($EXISTING) {
    Write-Host "  Runtime da ton tai (ID: $($EXISTING.id)) - dang update..." -ForegroundColor Yellow
    $RESULT = Invoke-RestMethod `
        -Method PATCH `
        -Uri "https://agentbase.api.vngcloud.vn/runtime/agent-runtimes/$($EXISTING.id)" `
        -Headers $DEPLOY_HEADERS `
        -Body $RUNTIME_BODY
    $RUNTIME_ID = $EXISTING.id
} else {
    $RESULT = Invoke-RestMethod `
        -Method POST `
        -Uri "https://agentbase.api.vngcloud.vn/runtime/agent-runtimes" `
        -Headers $DEPLOY_HEADERS `
        -Body $RUNTIME_BODY
    $RUNTIME_ID = $RESULT.id
}

if (-not $RUNTIME_ID) { Write-Error "Tao runtime that bai! Response: $($RESULT | ConvertTo-Json)"; exit 1 }
Write-Host "  Runtime ID: $RUNTIME_ID" -ForegroundColor Green

# Cho ACTIVE
Write-Host ""
Write-Host "Cho container khoi dong (toi da 5 phut)..." -ForegroundColor Cyan
$MAX_WAIT = 300
$ELAPSED  = 0
$STATUS   = ""

while ($ELAPSED -lt $MAX_WAIT) {
    Start-Sleep 10
    $ELAPSED += 10
    try {
        $RT     = Invoke-RestMethod -Method GET -Uri "https://agentbase.api.vngcloud.vn/runtime/agent-runtimes/$RUNTIME_ID" -Headers $HEADERS
        $STATUS = $RT.status
    } catch { $STATUS = "POLLING..." }
    Write-Host "  [$ELAPSED s] Status: $STATUS"
    if ($STATUS -eq "ACTIVE") { break }
    if ($STATUS -eq "ERROR")  { Write-Host "  FAILED - check dashboard!" -ForegroundColor Red; break }
}

# Lay endpoint
$EP_RESP     = Invoke-RestMethod -Method GET -Uri "https://agentbase.api.vngcloud.vn/runtime/agent-runtimes/$RUNTIME_ID/endpoints?page=1&size=10" -Headers $HEADERS
$ENDPOINT_URL = ($EP_RESP.listData | Where-Object { $_.name -eq "DEFAULT" } | Select-Object -First 1).url

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " DEPLOY HOAN TAT!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Runtime:  $RUNTIME_NAME"
Write-Host " ID:       $RUNTIME_ID"
Write-Host " Status:   $STATUS"
if ($ENDPOINT_URL) {
    Write-Host " Endpoint: $ENDPOINT_URL" -ForegroundColor Green
    Write-Host " Health:   $ENDPOINT_URL/health"
    Write-Host " App:      $ENDPOINT_URL/"
}
Write-Host " Console:  https://aiplatform.console.vngcloud.vn/agent-runtime?tab=runtime"
Write-Host "======================================" -ForegroundColor Cyan
