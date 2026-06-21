# Load .env file and export variables to the current process
if (Test-Path .env) {
    Get-Content .env | ForEach-Object {
        $line = $_.Trim()
        # Skip empty lines and comments
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $key, $value = $line -split '=', 2
            if ($key -and $value) {
                [System.Environment]::SetEnvironmentVariable($key.Trim(), $value.Trim(), "Process")
                Write-Host "Loaded variable: $key"
            }
        }
    }
} else {
    Write-Warning ".env file not found."
}

# Check if Mix/Elixir is available on the system PATH
if (Get-Command mix -ErrorAction SilentlyContinue) {
    Write-Host "Fetching dependencies..."
    mix deps.get
    
    Write-Host "Running database migrations..."
    mix ecto.migrate
    
    Write-Host "Starting GitMind server..."
    iex.bat -S mix
} else {
    Write-Warning "Elixir/Mix is not found on your system PATH."
    Write-Host "Environment variables have been exported. Please run the application in your Elixir-enabled environment."
}
