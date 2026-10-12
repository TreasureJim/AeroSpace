#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

rebuild=1
while (($# > 0)); do
    case "$1" in
        --dont-rebuild)
            rebuild=0
            shift
            ;;
        *)
            echo "Usage: $0 [--dont-rebuild]" >&2
            exit 2
            ;;
    esac
done

if ((rebuild)); then
    ./build-release.sh
fi

app_source=".release/AeroSpace.app"
cli_source=".release/aerospace"
app_destination="${AEROSPACE_APP_PATH:-/Applications/AeroSpace.app}"
cli_destination="${AEROSPACE_CLI_PATH:-$HOME/.local/bin/aerospace}"

if [[ ! -d "$app_source" || ! -x "$cli_source" ]]; then
    echo "Release artifacts are missing. Run without --dont-rebuild." >&2
    exit 1
fi

osascript -e 'tell application "AeroSpace" to quit' >/dev/null 2>&1 || true

if [[ -e "$app_destination" && ! -w "$(dirname "$app_destination")" ]]; then
    echo "Cannot write to $(dirname "$app_destination"). Remove the old app or rerun with an appropriate install path." >&2
    exit 1
fi

rm -rf "$app_destination"
ditto "$app_source" "$app_destination"

mkdir -p "$(dirname "$cli_destination")"
install -m 755 "$cli_source" "$cli_destination"

open -a "$app_destination"

echo "Installed $app_destination"
echo "Installed $cli_destination"
