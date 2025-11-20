param (
    [string]$DistroName = "Guacamole"
)

function Write-TaskOutput {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$String = "",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ScreenWidth,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Black", "Blue", "Cyan", "DarkBlue", "DarkCyan", "DarkGray", "DarkGreen",
                     "DarkMagenta", "DarkRed", "DarkYellow", "Gray", "Green", "Magenta",
                     "Red", "White", "Yellow")]
        [string]$ForegroundColor = "White"
    )

    try {
        # Skip empty input
        if (-not $Label -and -not $String) {
            Write-Verbose "Empty label and string; skipping output."
            return
        }

        # Set ScreenWidth dynamically if not provided
        if (-not $PSBoundParameters.ContainsKey('ScreenWidth')) {
            try {
                $ScreenWidth = $Host.UI.RawUI.WindowSize.Width
                if (-not $ScreenWidth -or $ScreenWidth -lt 1) {
                    $ScreenWidth = 80
                }
            }
            catch {
                $ScreenWidth = 80
                Write-Verbose "Unable to detect console width; defaulting to 80."
            }
        }

        # Validate ScreenWidth
        if ($ScreenWidth -lt 10) {
            Write-Warning "ScreenWidth ($ScreenWidth) is too small for meaningful output. Using minimum of 10."
            $ScreenWidth = 10
        }

        # Construct base message
        $message = "$Label [ $String ] "
        $messageLength = $message.Length

        # Truncate if message exceeds ScreenWidth
        if ($messageLength -gt $ScreenWidth) {
            $availableLength = $ScreenWidth - $Label.Length - 8  # Account for " [ ", " ]", and "..."
            if ($availableLength -le 0) {
                Write-Warning "Label is too long for ScreenWidth ($ScreenWidth). Skipping output."
                return
            }
            $String = $String.Substring(0, [Math]::Min($String.Length, $availableLength)) + "..."
            $message = "$Label [ $String ]"
            $messageLength = $message.Length
        }

        # Pad with asterisks if needed
        $output = if ($messageLength -lt $ScreenWidth) {
            $fillCharacters = "*" * ($ScreenWidth - $messageLength)
            "$message$fillCharacters"
        } else {
            $message
        }

        # Write output with leading newline
        Write-Host -ForegroundColor $ForegroundColor "`n$output"
    }
    catch {
        Write-Warning "Failed to write task output: $_"
    }
}

# Set up variables
$wslFile   = "ubuntu-24.04.3-wsl-amd64.wsl"

$uri       = "https://releases.ubuntu.com/noble/$wslFile"

$wslPath   = Join-Path -Path (Get-Location) -ChildPath $wslFile

$hostName  = "guacamole"
# $userName  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[1]
$imagePath = "$HOME\AppData\Local\Packages\$DistroName\LocalState"

# Ensure WSL is installed and configured
Write-TaskOutput -Label "TASK" -String "Installing WSL..."
wsl --install --no-distribution

# Download WSL base image if needed
Write-TaskOutput -Label "TASK" -String "Downloading WSL base image..."
if (-Not (Test-Path $wslPath)) {
    Invoke-WebRequest -Uri $uri -OutFile $wslPath
} else {
    Write-Host  "ok: WSL base image already exists: $wslPath" -ForegroundColor Green
}

# Create install directory
Write-TaskOutput -Label "TASK" -String "Create WSL image directory: $imagePath"
if (-Not (Test-Path $imagePath)) {
    New-Item -ItemType Directory -Path $imagePath | Out-Null
} else {
    Write-Host  "ok: WSL image directory already exists: $imagePath" -ForegroundColor Green
}

# Import WSL base image as a new distro
Write-TaskOutput -Label "TASK" -String "Importing WSL distro '$DistroName' from image..."
wsl --import $DistroName $imagePath $wslPath

# Set WSL version to 1 (better network compatibility, no systemd)
Write-TaskOutput -Label "TASK" -String "Setting WSL version to 1..."
wsl --set-version $DistroName 1

# Run initial configuration script as root
Write-TaskOutput -Label "TASK" -String "Configuring distro (user and wsl.conf)..."
wsl -u root -d $DistroName bash scripts/root.sh $hostName

# Shutdown WSL to apply wsl.conf changes
Write-TaskOutput -Label "TASK" -String "Restarting WSL to apply configuration..."
wsl --shutdown
Start-Sleep -Seconds 3

# Install Guacamole
Write-TaskOutput -Label "TASK" -String "Installing Apache Guacamole..."
wsl -u root -d $DistroName bash scripts/guac-install.sh

# Shutdown WSL to apply changes
Write-TaskOutput -Label "TASK" -String "Shutting down WSL to apply changes..."
wsl --shutdown

# Start WSL distro
Write-TaskOutput -Label "TASK" -String "Starting WSL distro '$DistroName'..."
wsl -d $DistroName
