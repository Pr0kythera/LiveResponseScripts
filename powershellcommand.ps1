# Get all arguments passed to the script
$commandToExecute = $args -join ' '

# Check if the command variable is not empty
if ($commandToExecute) {
    # Execute the command and display the output
    Invoke-Expression $commandToExecute
} else {
    Write-Host "No command provided."
}