#!/bin/bash

# Function to search for apps
search_app() {
    local app_name="$1"

    echo -e "Checking availability in mirrors:"
    echo -ne "[*] https://packages.termux.dev/:\n"
    echo -ne "[*] https://ws75.aptoide.com/:\n"

    tput cuu 2

    # Check internet connection
    if ! ping -c 1 -W 2 www.google.com &> /dev/null; then
        echo -ne "[*] https://packages.termux.dev/: bad\n"
        echo -ne "[*] https://ws75.aptoide.com/: bad\n"
        echo -ne "\n\033[31mE:\033[0m Unable to reach the API. Please check your connection."
        exit 1
    fi

    # Termux repo
    local response1=$(curl -s "https://packages.termux.dev/apt/termux-main/pool/main/${app_name:0:1}/" \
        | grep '<a href=' | sed -n 's/.*<a href="\([^/]*\)\/">.*/\1/p' \
        | grep -w "$app_name")

    # Aptoide API
    local response2=$(curl -s "https://ws75.aptoide.com/api/7/apps/search?query=$(echo "$app_name" | sed 's/ /%20/g')&limit=10")

    # Count results properly
    local result_count1=$(echo "$response1" | wc -w)
    local result_count2=$(echo "$response2" | jq -r --arg app "$app_name" '.datalist.list[] | select(.uname | test($app)) | .uname' | wc -l)

    # Show availability
    if [[ "$result_count1" -eq 0 ]]; then
        echo -ne "[*] https://packages.termux.dev/: bad\n"
    else
        echo -ne "[*] https://packages.termux.dev/: ok\n"
    fi

    if [[ "$result_count2" -eq 0 ]]; then
        echo -ne "[*] https://ws75.aptoide.com/: bad\n"
    else
        echo -ne "[*] https://ws75.aptoide.com/: ok\n"
    fi

    echo -e "\n\033[1;37m\033[1;33m$((result_count1 + result_count2)) \033[1;37mresult(s) for '${app_name}':\033[0m\n"

    # List Termux packages with maintainer
    for item in $response1; do
        pkg_auth=$(pkg show -a "$item" 2>/dev/null | awk '/^Maintainer:/ {name=substr($0, index($0, ":") + 2); if (name ~ /^@/) fallback=name; else {print name; found=1}} END {if (!found && fallback) print fallback}')
        echo -e "$item from $pkg_auth\n"
    done

    # List Aptoide results
    echo "$response2" | jq -r --arg app "$app_name" '.datalist.list[] | select(.uname | test($app)) | "\(.uname) from \(.developer.name)"' | sed G
}

list_apps() {
    count=$(cmd package list packages -3 | sed 's/^package://' | wc -l)
    count_cli=$(apt-mark showmanual | wc -l)
    echo -e "\e[1;33m$count \e[1;37mGUI applications found and \e[1;33m$count_cli \e[1;37mterminal packages installed by the user\n\e[0m"
    cmd package list packages -3 2>&1 | awk '/^package:/{sub(/^package:/,""); print}'
    
    apt-mark showmanual
}

delete_app() {
    local app_name="$1"
    if [[ "$app_name" != *.* && "$app_name" != *com* ]]; then
        pkg remove -y "$app_name"
        return
    fi
    
    echo -e "Removing package..."
    if command -v su &> /dev/null && su -c "pm uninstall \"$app_name\"" &> /dev/null; then
        echo -e "Removal complete"
    else
        am start -a android.intent.action.DELETE -d "package:$app_name" > /dev/null
       echo -e "Removal complete"
    fi
}

clean_apks() {
    pkg clean
    if ls *.apk 1> /dev/null 2>&1; then
        rm -f *.apk
        rm -f *.part
        echo -e "Garbage files removed successfully."
    else
        echo -e "No leftovers are left, nothing to clean."
    fi
    
}

download() {
    echo -ne "\033[?25l"

    local url="$1"
    local output="$2"
    local tmp="${output}.part"
    local progress_file="$HOME/.curl_progress_$$.log"

    rm -f "$tmp" "$progress_file"

    local term_width
    term_width=$(tput cols)
    local reserved=22
    local bar_length=$(( term_width - reserved ))
    (( bar_length < 10 )) && bar_length=10

    curl -L -# "$url" -o "$tmp" 2> "$progress_file" &

    local curl_pid=$!

    while kill -0 "$curl_pid" 2>/dev/null; do
        if [[ -s "$progress_file" ]]; then
            local raw
            raw=$(tail -n 1 "$progress_file" | tr -d '\r')
            local raw_filled
            raw_filled=$(grep -o "#" <<< "$raw" | wc -l)

            if (( raw_filled > 0 )); then
                local max_curl_bar=50
                local perc=$(( raw_filled * 100 / max_curl_bar))
                (( perc > 99 )) && perc=99

                local filled=$(( perc * bar_length / 101 ))
                local empty=$(( bar_length - filled))
                local left=$(printf '%0.s#' $(seq 1 $filled))
                local right=$(printf '%0.s.' $(seq 1 $empty))

                printf "\r\033[42;30mProgress: [%3d%%]\033[0m [%s%s]" "$perc" "$left" "$right"
            fi
        fi
        sleep 0.2
    done

    wait "$curl_pid"
    local left=$(printf '%0.s#' $(seq 1 $bar_length))
    printf "\r\033[42;30mProgress: [100%%]\033[0m [%s]\n" "$left"
         
    if [[ -f "$tmp" ]]; then
        mv -f "$tmp" "$output"
        echo "Download complete!"
        
    else
        echo "Download failed: file not found."
    fi

    rm -f "$progress_file"
    echo -ne "\033[?25h"
    

}

install_app() {

    local app_name="$1"

    echo -e "Checking availability of current mirrors:"
    echo -ne "[*] https://packages.termux.dev/:\n"
    echo -ne "[*] https://ws75.aptoide.com/:\n"

    tput cuu 2

    if ! ping -c 1 -W 2 www.google.com &> /dev/null; then
        echo -ne "[*] https://packages.termux.dev/: bad\n"
        echo -ne "[*] https://ws75.aptoide.com/: bad\n"
        echo -ne "\n\033[31mE:\033[0m Unable to reach the API. Please check your connection."
        exit 1
    fi

    local responce1=$(curl -s "https://packages.termux.dev/apt/termux-main/pool/main/${app_name:0:1}/" \
        | grep '<a href=' \
        | sed -n 's/.*<a href="\([^/]*\)\/">.*/\1/p' \
        | grep -x "$app_name")

    local result_count1=$(echo "$responce1" | wc -w)
    local response2=""
    local result_count2=0

    if [[ "$result_count1" -eq 0 ]]; then
        response2=$(curl -s "https://ws75.aptoide.com/api/7/apps/search?query=$(echo "$app_name" | sed 's/ /%20/g')&limit=4")
        result_count2=$(echo "$response2" | jq -r '.datalist.total')
    fi

    if [[ "$result_count1" -gt 0 ]]; then
        echo -ne "[*] https://packages.termux.dev/: ok\n"
    else
        echo -ne "[*] https://packages.termux.dev/: bad\n"
    fi

    if [[ "$result_count2" -gt 0 ]]; then
        echo -ne "[*] https://ws75.aptoide.com/: ok\n"
    else
        echo -ne "[*] https://ws75.aptoide.com/: bad\n"
    fi

    if [[ "$result_count1" -gt 0 ]]; then
        echo -ne "\033[1A\r\033[K"  # Installing...
echo -ne "\033[1A\r\033[K"  # ws75.aptoide.com
echo -ne "\033[1A\r\033[K"  # packages.termux.dev
        pkg install -y "$app_name"
        return
    fi

    if [[ "$result_count2" -gt 0 ]]; then
        echo -e "\nInstalling '${app_name}' from Aptoide store...\n"
        local app_info=$(echo "$response2" | jq -r '.datalist.list[0]')
        local package_name=$(echo "$app_info" | jq -r '.package')
        local download_url=$(echo "$app_info" | jq -r '.file.path')
        local version=$(echo "$app_info" | jq -r '.file.vername')

        echo -e "\033[2J"  # clear screen
echo "Downloading ${app_name} (${version})..."

# Get total rows of terminal
# Print verbose info once, scrolls naturally
curl --verbose --range 0-0 -L "$download_url" -o /dev/null 2>&1 | head -n $(( $(tput lines) - 1 ))


# Call download, passing progress_row
download "$download_url" "${package_name}.apk" "$progress_row"
echo -ne "\033[?25h"
sleep 1
local term_height=$(tput lines)
tput cup $((term_height - 1)) 0
tput el
echo -ne "\033[1A"

# Καθάρισε τη γραμμή
echo -ne "\r\033[K"

# Πήγαινε άλλη μία γραμμή πάνω
echo -ne "\033[1A"

# Καθάρισε και αυτή
echo -ne "\r\033[K"
echo -e "Installing package..."
if command -v su &> /dev/null && su -c "pm install -r \"$(pwd)/${package_name}.apk\"" &> /dev/null; then
echo -e "Installation complete"
else
    termux-share -d -c "application/vnd.android.package-archive" "${package_name}.apk"
    echo -e "Installation complete"
fi
    else
        echo -e "\n\033[31mE:\033[0m Unable to locate package '${app_name}'."
        exit 1
    fi
}

about() {
    echo -e "\n\e[90m\e[47m████████████████████\e[0m"
    echo -e "\e[90m\e[47m█▀▄ ██▄ ▄▄▀█▄ ▀█▀ ▄█\e[0m"
    echo -e "\e[90m\e[47m█ ▄█▀██ ▄▄███ █▄█ ██\e[0m"
    echo -e "\e[90m\e[47m██▄▄██▄▄▄███▄▄▄█▄▄▄█\e[0m"
    echo -e "\e[90m\e[47m████████████████████\e[0m"

    echo -e "\n\e[0;33mThis is an unofficial repo based package manager for Android."
    echo -e "It enhances the native android package manager (pm) with online repos like any other distro."
    echo -e "\nVersion 1.0 2026\nType \"epm help\" for usage\nPowered by Aptoide and Termux repos\e[0m"
}

# Main script logic
if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "Invalid number of arguments."
    echo "Usage: epm {search|install|remove} <package_name>"
    echo -e "\nOr use:"
    echo "clean -> cleans all downloaded apk files in the current directory"
    echo "list -> List all user installed packages"
    echo "help -> Displays usage"
    echo "about -> Displays information for this service"
    exit 1
fi

action="$1"
app_name="$2"

case "$action" in
    search) [[ -z "$app_name" ]] && echo "Error: 'search' requires a package name." && exit 1; search_app "$app_name" ;;
    install) [[ -z "$app_name" ]] && echo "Error: 'install' requires a package name." && exit 1; install_app "$app_name" ;;
    remove) [[ -z "$app_name" ]] && echo "Error: 'remove' requires a package name." && exit 1; delete_app "$app_name" ;;
    clean) [[ -n "$app_name" ]] && echo "Error: 'clean' does not accept arguments." && exit 1; clean_apks ;;
    list) [[ -n "$app_name" ]] && echo "Error: 'list' does not accept arguments." && exit 1; list_apps ;;
    about) about ;;
    help)
        echo "Usage: epm {search|install|remove} <package_name>"
        echo -e "\nOr use:"
        echo "clean -> cleans all downloaded apk files in the current directory"
        echo "list -> List all user installed packages"
        echo "help -> Displays usage"
        echo "about -> Displays information for this service"
        ;;
    *) echo "Invalid action: $action"; echo "Usage: epm {search|install|remove} <package_name>"; ;;
esac
