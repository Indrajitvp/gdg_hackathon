# Load .env file and export variables to the current process
$env_path = Join-Path $PSScriptRoot "..\.env"
if (Test-Path $env_path) {
    Get-Content $env_path | ForEach-Object {
        $line = $_.Trim()
        # Skip empty lines and comments
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $key, $value = $line -split '=', 2
            if ($key -and $value) {
                $cleanValue = $value.Trim().Trim('"', "'")
                [System.Environment]::SetEnvironmentVariable($key.Trim(), $cleanValue, "Process")
                Write-Host "Loaded variable: $key"
            }
        }
    }
} else {
    Write-Warning ".env file not found."
}

# Check if Mix/Elixir is available on the system PATH
if (Get-Command mix -ErrorAction SilentlyContinue) {
    Write-Host "Installing package managers..."
    mix local.hex --force
    mix local.rebar --force
    
    Write-Host "Fetching dependencies..."
    mix deps.get
    
    Write-Host "Running database migrations..."
    mix ecto.migrate
    
    Write-Host "Starting GitMind server..."
    mix run --no-halt
} else {
    Write-Warning "Elixir/Mix is not found on your system PATH."
    Write-Host "Environment variables have been exported. Please run the application in your Elixir-enabled environment."
}
