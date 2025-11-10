# Script to delete all Lambda functions and EventBridge rules across all AWS regions

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AWS Cleanup Script - Lambda & EventBridge" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get all AWS regions
$regions = aws ec2 describe-regions --query 'Regions[].RegionName' --output text
$regionList = $regions -split '\s+'

Write-Host "Found $($regionList.Count) regions to check" -ForegroundColor Yellow
Write-Host ""

$totalLambdasDeleted = 0
$totalRulesDeleted = 0
$totalTargetsRemoved = 0

foreach ($region in $regionList) {
    Write-Host "Processing region: $region" -ForegroundColor Green
    Write-Host "-----------------------------------" -ForegroundColor Gray
    
    # List and delete Lambda functions
    Write-Host "  Checking Lambda functions..." -ForegroundColor White
    $lambdas = aws lambda list-functions --region $region --query 'Functions[].FunctionName' --output text 2>$null
    
    if ($LASTEXITCODE -eq 0 -and $lambdas) {
        $lambdaList = $lambdas -split '\s+'
        if ($lambdaList.Count -gt 0 -and $lambdaList[0] -ne "") {
            Write-Host "    Found $($lambdaList.Count) Lambda function(s)" -ForegroundColor Yellow
            
            foreach ($lambda in $lambdaList) {
                Write-Host "    Deleting Lambda: $lambda" -ForegroundColor Magenta
                aws lambda delete-function --function-name $lambda --region $region 2>$null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "      Deleted successfully" -ForegroundColor Green
                    $totalLambdasDeleted++
                } else {
                    Write-Host "      Failed to delete" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "    No Lambda functions found" -ForegroundColor Gray
        }
    } else {
        Write-Host "    No Lambda functions found or region not accessible" -ForegroundColor Gray
    }
    
    # List and delete EventBridge rules
    Write-Host "  Checking EventBridge rules..." -ForegroundColor White
    $rules = aws events list-rules --region $region --query 'Rules[].Name' --output text 2>$null
    
    if ($LASTEXITCODE -eq 0 -and $rules) {
        $ruleList = $rules -split '\s+'
        if ($ruleList.Count -gt 0 -and $ruleList[0] -ne "") {
            Write-Host "    Found $($ruleList.Count) EventBridge rule(s)" -ForegroundColor Yellow
            
            foreach ($rule in $ruleList) {
                Write-Host "    Processing rule: $rule" -ForegroundColor Magenta
                
                # First, remove all targets from the rule
                $targets = aws events list-targets-by-rule --rule $rule --region $region --query 'Targets[].Id' --output text 2>$null
                
                if ($targets -and $targets -ne "") {
                    $targetList = $targets -split '\s+'
                    Write-Host "      Removing $($targetList.Count) target(s)" -ForegroundColor Cyan
                    
                    aws events remove-targets --rule $rule --ids $targetList --region $region 2>$null
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "      Target(s) removed" -ForegroundColor Green
                        $totalTargetsRemoved += $targetList.Count
                    } else {
                        Write-Host "      Failed to remove targets" -ForegroundColor Red
                    }
                }
                
                # Then delete the rule
                Write-Host "      Deleting rule: $rule" -ForegroundColor Magenta
                aws events delete-rule --name $rule --region $region 2>$null
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "      Rule deleted successfully" -ForegroundColor Green
                    $totalRulesDeleted++
                } else {
                    Write-Host "      Failed to delete rule" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "    No EventBridge rules found" -ForegroundColor Gray
        }
    } else {
        Write-Host "    No EventBridge rules found or region not accessible" -ForegroundColor Gray
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cleanup Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Lambda functions deleted: $totalLambdasDeleted" -ForegroundColor Green
Write-Host "Total EventBridge rules deleted: $totalRulesDeleted" -ForegroundColor Green
Write-Host "Total EventBridge targets removed: $totalTargetsRemoved" -ForegroundColor Green
Write-Host ""
Write-Host "Cleanup completed!" -ForegroundColor Green
