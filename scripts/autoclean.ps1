# autoclean.ps1 - PowerShell function for running the autoclean EEG processing pipeline

function autoclean {
    param(
        [Parameter()]
        [string]$DataPath,
        
        [Parameter()]
        [string]$Task,
        
        [Parameter()]
        [string]$ConfigPath,
        
        [Parameter()]
        [string]$OutputPath = "./output",
        
        [Parameter()]
        [switch]$Help
    )
    
    # Show help if requested or if no parameters are provided
    if ($Help -or (!$DataPath -and !$Task -and !$ConfigPath)) {
        Write-Host "EEG Data Autoclean Pipeline"
        Write-Host ""
        Write-Host "USAGE:"
        Write-Host "  autoclean -DataPath <path> -Task <task_type> -ConfigPath <config_path> [-OutputPath <output_dir>]"
        Write-Host ""
        Write-Host "PARAMETERS:"
        Write-Host "  -DataPath    Directory containing raw EEG data or path to single data file"
        Write-Host "  -Task        Processing task type (RestingEyesOpen, ASSR, ChirpDefault, etc.)"
        Write-Host "  -ConfigPath  Path to configuration YAML file"
        Write-Host "  -OutputPath  (Optional) Output directory, defaults to './output'"
        Write-Host "  -Help        Display this help message"
        return
    }
    
    # Validate parameters
    if (-not $DataPath) {
        Write-Host "Error: DataPath parameter is required." -ForegroundColor Red
        return
    }
    
    if (-not $Task) {
        Write-Host "Error: Task parameter is required." -ForegroundColor Red
        return
    }
    
    if (-not $ConfigPath) {
        Write-Host "Error: ConfigPath parameter is required." -ForegroundColor Red
        return
    }
    
    # Check if paths exist
    if (-not (Test-Path $DataPath)) {
        Write-Host "Error: Data path does not exist: $DataPath" -ForegroundColor Red
        return
    }
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Error: Configuration file does not exist: $ConfigPath" -ForegroundColor Red
        return
    }
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
        Write-Host "Created output directory: $OutputPath"
    }
    
    # Convert Windows paths to Docker-compatible paths
    $dataPathAbs = (Resolve-Path $DataPath).Path
    $configPathAbs = (Resolve-Path $ConfigPath).Path
    $outputPathAbs = (Resolve-Path $OutputPath).Path
    
    $dataDir = Split-Path -Parent $dataPathAbs
    $dataFile = Split-Path -Leaf $dataPathAbs
    $configDir = Split-Path -Parent $configPathAbs
    $configFile = Split-Path -Leaf $configPathAbs
    
    # Replace Windows backslashes with forward slashes for Docker
    $dataDirDocker = $dataDir.Replace('\', '/').Replace(':', '')
    $configDirDocker = $configDir.Replace('\', '/').Replace(':', '')
    $outputPathDocker = $outputPathAbs.Replace('\', '/').Replace(':', '')
    
    # Run the Docker command
    Write-Host "Processing EEG data: $dataPathAbs"
    Write-Host "Task: $Task"
    Write-Host "Config: $configPathAbs"
    Write-Host "Output directory: $outputPathAbs"
    
    try {
        # Check if Docker is running
        $dockerStatus = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Docker is not running. Please start Docker Desktop and try again." -ForegroundColor Red
            return
        }
        
        # Run the Docker command
        docker run --rm `
            -v "${dataDirDocker}:/data" `
            -v "${configDirDocker}:/config" `
            -v "${outputPathDocker}:/output" `
            autoclean-image `
            -DataPath "/data/$dataFile" `
            -Task $Task `
            -ConfigPath "/config/$configFile" `
            -OutputPath "/output"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Processing completed successfully" -ForegroundColor Green
        } else {
            Write-Host "Error during processing" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

# Export the function to make it available in the PowerShell session
Export-ModuleMember -Function autoclean
