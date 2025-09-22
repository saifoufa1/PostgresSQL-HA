@echo off
REM Windows batch script to run PostgreSQL HA failover tests
REM This script provides an easy way to run the comprehensive test suite

echo Starting PostgreSQL HA Failover Test Suite...
echo.

REM Check if we're in the right directory
if not exist "docker-compose.yml" (
    echo Error: docker-compose.yml not found. Please run this script from the project root.
    pause
    exit /b 1
)

REM Check if .env file exists
if not exist ".env" (
    echo Creating .env file from .env.test...
    copy .env.test .env
)

echo Starting PostgreSQL HA cluster...
docker compose --env-file .env up -d --build

echo Waiting for cluster to initialize (60 seconds)...
timeout /t 60 /nobreak > nul

echo.
echo Running comprehensive failover tests...
echo Test results will be saved to test-results-*.log
echo.

REM Run the comprehensive test script
bash scripts/test-comprehensive-failover.sh

echo.
echo Test execution completed!
echo Check the log file for detailed results.
echo.

pause