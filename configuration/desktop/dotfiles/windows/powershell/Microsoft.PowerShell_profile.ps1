Import-Module PSReadLine
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
(&mise activate pwsh) | Out-String | Invoke-Expression
oh-my-posh init pwsh --config ~/posh.json | Invoke-Expression

# Komodo CLI through the official image (there is no Windows binary); same version as the Core.
# Config (host, key, secret) lives in ~/.config/komodo/komodo.cli.toml. The distroless image has
# no CA certificates, so it borrows Git's bundle (scoop) for TLS.
function km {
    $tty = if ([Console]::IsInputRedirected) { '-i' } else { '-it' }
    $ca = "$HOME\scoop\apps\git\current\ucrt64\etc\ssl\certs\ca-bundle.crt"
    docker run --rm $tty -v "$HOME\.config\komodo:/config" -v "${ca}:/etc/ssl/certs/ca-certificates.crt:ro" ghcr.io/moghtech/komodo-cli:2.3.3 km @args
}
