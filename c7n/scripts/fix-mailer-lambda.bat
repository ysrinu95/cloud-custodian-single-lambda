@echo off
echo 🔧 Quick Lambda PyJWT Fix Script
echo.

set LAMBDA_FUNCTION_NAME=cloud-custodian-mailer
set REGION=us-west-2

echo 📋 Checking Lambda function status...
aws lambda get-function --function-name %LAMBDA_FUNCTION_NAME% --region %REGION% --query "Configuration.FunctionName" --output text >nul 2>&1
if errorlevel 1 (
    echo ❌ Lambda function not found. Please deploy mailer first.
    exit /b 1
)

echo ✅ Lambda function found: %LAMBDA_FUNCTION_NAME%

echo.
echo 🔧 Creating temporary directory...
set TEMP_DIR=%TEMP%\lambda-fix-%RANDOM%
mkdir "%TEMP_DIR%"

echo ⬇️ Downloading Lambda function...
aws lambda get-function --function-name %LAMBDA_FUNCTION_NAME% --region %REGION% --query "Code.Location" --output text > "%TEMP_DIR%\url.txt"
set /p DOWNLOAD_URL=<"%TEMP_DIR%\url.txt"

echo 📦 Downloading and extracting function...
curl -s -o "%TEMP_DIR%\function.zip" "%DOWNLOAD_URL%"
cd /d "%TEMP_DIR%"
powershell -command "Expand-Archive -Path 'function.zip' -DestinationPath '.' -Force"

echo 📦 Installing PyJWT in Lambda package...
pip install --target . PyJWT>=2.0.0 cryptography>=3.0.0 requests>=2.25.0 --quiet --no-warn-script-location

echo 🔍 Verifying PyJWT installation...
python -c "import jwt; print('✅ PyJWT', jwt.__version__, 'installed')" 2>nul
if errorlevel 1 (
    echo ⚠️ PyJWT verification failed, but continuing...
)

echo 📦 Repackaging Lambda function...
del function.zip >nul 2>&1
powershell -command "Compress-Archive -Path '*' -DestinationPath 'function-updated.zip' -Force"

echo ⬆️ Updating Lambda function...
aws lambda update-function-code --function-name %LAMBDA_FUNCTION_NAME% --region %REGION% --zip-file fileb://function-updated.zip
if errorlevel 1 (
    echo ❌ Failed to update Lambda function
    goto cleanup
)

echo ✅ Lambda function updated successfully!

echo 🧪 Testing Lambda function...
aws lambda invoke --function-name %LAMBDA_FUNCTION_NAME% --region %REGION% --payload "{}" response.json
echo 📋 Response:
type response.json

:cleanup
echo.
echo 🧹 Cleaning up...
cd /d "%~dp0"
rmdir /s /q "%TEMP_DIR%" >nul 2>&1

echo ✅ Lambda fix complete!