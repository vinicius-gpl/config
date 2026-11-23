Import-Module PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
(&mise activate pwsh) | Out-String | Invoke-Expression
oh-my-posh init pwsh --config ~/posh.json | Invoke-Expression

# Komodo CLI through the official image (there is no Windows binary); same version as the Core.
# Config (url, key, secret) lives in ~/.config/komodo, created by `km config`.
function km {
    $tty = if ([Console]::IsInputRedirected) { '-i' } else { '-it' }
    docker run --rm $tty -v "$HOME\.config\komodo:/config" ghcr.io/moghtech/komodo-cli:2.3.3 km @args
}
