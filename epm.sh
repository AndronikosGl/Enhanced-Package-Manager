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
  local show_all="$1"
  local gui_apps cli_pkgs

  if [[ "$show_all" == "--showall" ]]; then
    # Show ALL enabled GUI packages (system + user) and ALL installed CLI packages
    gui_apps=$(cmd package list packages -e 2>/dev/null | sed 's/^package://' | sort -u)
    cli_pkgs=$(dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | sort -u)
  else
    # Filtered user-installed apps + whitelisted pre-installed apps
    gui_apps=$( {
      cmd package list packages -3 -e 2>/dev/null | sed 's/^package://' \
        | grep -Ev '^(com\.android\.|com\.google\.android\.(gms|gsf|webview|trichrome|networkstack|permissioncontroller|ext\.|modulemetadata|ondevicepersonalization|adservices|federatedcompute|captiveportallogin|cellbroadcast|configupdater|partnersetup|printspooler|packageinstaller|documentsui|inputmethod|tts|marvin|projection|as|odad|verifier|contactkeys|apps\.restore|apps\.setupwizard|apps\.wellbeing|ambient\.streaming)|com\.google\.mainline\.|com\.google\.ar\.|android\.autoinstalls|com\.aura\.|com\.lenovo\.|com\.mediatek\.|com\.qualcomm\.)'

      cmd package list packages -e 2>/dev/null | sed 's/^package://' \
        | grep -E '^(com\.android\.chrome|com\.google\.android\.youtube|com\.google\.android\.apps\.youtube\.music|com\.google\.android\.dialer|com\.google\.android\.apps\.messaging|com\.google\.android\.apps\.photos|com\.google\.android\.apps\.docs|com\.google\.android\.apps\.maps|com\.google\.android\.gm|com\.google\.android\.calendar|com\.google\.android\.deskclock|com\.google\.android\.calculator)$'
    } | sort -u )

    cli_pkgs=$(apt-mark showmanual 2>/dev/null)
  fi

  local count_gui count_cli
  count_gui=$(printf "%s\n" "$gui_apps" | grep -c .)
  count_cli=$(printf "%s\n" "$cli_pkgs" | grep -c .)

  if [[ "$show_all" == "--showall" ]]; then
    echo -e "\e[1;33m$count_gui \e[1;37mGUI application(s) and \e[1;33m$count_cli \e[1;37mCLI package(s) found (all)\n\e[0m"
  else
    echo -e "\e[1;33m$count_gui \e[1;37mGUI application(s) found and \e[1;33m$count_cli \e[1;37mterminal package(s) installed by the user\n\e[0m"
  fi

  echo "$gui_apps"
  echo "$cli_pkgs"
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
       echo -e "Removal prompt opened."
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

    rm -f "$tmp"

    local term_width
    term_width=$(tput cols)
    local reserved=22
    local bar_length=$(( term_width - reserved ))
    (( bar_length < 10 )) && bar_length=10

    # Get exact file size in bytes from server headers
    local total_bytes
    total_bytes=$(curl -sIL "$url" | awk -F': ' 'tolower($1)=="content-length" {size=$2} END {print size}' | tr -cd '0-9')

    curl -sL "$url" -o "$tmp" &
    local curl_pid=$!

    while kill -0 "$curl_pid" 2>/dev/null; do
        if [[ -f "$tmp" && -n "$total_bytes" && "$total_bytes" -gt 0 ]]; then
            local current_bytes
            current_bytes=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
            local perc=$(( current_bytes * 100 / total_bytes ))
            (( perc > 99 )) && perc=99

            local filled=$(( perc * bar_length / 100 ))
            local empty=$(( bar_length - filled ))
            local left right
            left=$(printf '%0.s#' $(seq 1 $filled 2>/dev/null))
            right=$(printf '%0.s.' $(seq 1 $empty 2>/dev/null))

            printf "\r\033[42;30mProgress: [%3d%%]\033[0m [%s%s]" "$perc" "$left" "$right"
        	printf "%s\033[K" "${line//]]/]}"
        fi
        sleep 0.2
    done

    wait "$curl_pid"
    local exit_code=$?

    if [[ $exit_code -eq 0 && -s "$tmp" ]]; then
        local left
        left=$(printf '%0.s#' $(seq 1 $bar_length))
        printf "\r\033[42;30mProgress: [100%%]\033[0m [%s]\n" "$left"
        mv -f "$tmp" "$output"
        echo "Download complete!"
    else
        echo -e "\nDownload failed."
        rm -f "$tmp"
    fi

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
local apk_path="$(pwd)/${package_name}.apk"

if command -v su &> /dev/null && su -c true &> /dev/null; then
    local pm_output
    pm_output=$(su -c "pm install -r \"$apk_path\"" 2>&1)
    local pm_status=$?

    if [[ $pm_status -eq 0 && "$pm_output" == *"Success"* ]]; then
        echo -e "Installation complete"
    else
        echo -e "\033[31mE:\033[0m Installation failed:"
        echo -e "$pm_output"
        return 1
    fi
    else
        # Fallback for non-rooted devices
        if ! termux-share -d -c "application/vnd.android.package-archive" "$apk_path"; then
            echo -e "\033[31mE:\033[0m Failed to launch Android package installer."
            return 1
        fi
        echo -e "Installer prompt opened."
    fi

    else
        echo -e "\n\033[31mE:\033[0m Unable to locate package '${app_name}'."
        return 1
    fi
}



update() {
 # Step-by-step overview of update():
# 1. Checks network connectivity and mirror reachability (Termux repo & Aptoide API),
#    printing :bad or :ok statuses in place using tput cuu.
# 2. Detects root (su) availability and defines helpers to read local versionCode/
#    versionName (get_local_info) and compare dotted version strings (is_newer_vername).
# 3. Refreshes apt metadata and counts upgradable CLI packages.
# 4. Collects filtered third-party and allowlisted system GUI packages (excluding GMS),
#    then checks Aptoide (aptoide-web store) for higher versionCode + newer versionName
#    (skipping dummy 9999999+ builds) and queues matching packages.
# 5. Prints the bold/yellow CLI and GUI update counts; if any exist, prompts [y/n],
#    runs `pkg update -y` for CLI updates, and calls `install_app` for each GUI update.
   echo "Checking for updates on repositories..."
   local host="ws75.aptoide.com"
    local store="aptoide-web"
    local has_root=0
    echo -ne "[*] https://packages.termux.dev/:\n"
    echo -ne "[*] https://ws75.aptoide.com/:\n"
    tput cuu 2

    if ! ping -c 1 -W 2 www.google.com &> /dev/null; then
        echo -ne "[*] https://packages.termux.dev/: bad\n"
        echo -ne "[*] https://ws75.aptoide.com/: bad\n"
        echo -ne "\n\033[31mE:\033[0m Unable to reach the API. Please check your connection.\n"
        exit 1
    fi

    if curl -sf --head "https://packages.termux.dev/apt/termux-main/" > /dev/null 2>&1 || curl -sf "https://packages.termux.dev/apt/termux-main/dists/stable/Release" > /dev/null 2>&1; then
        echo -ne "[*] https://packages.termux.dev/: ok\n"
    else
        echo -ne "[*] https://packages.termux.dev/: bad\n"
        
    fi

    # Option A: Use the reliable apps/search endpoint (Recommended)
	if curl -sf -A "Mozilla/5.0" "https://${host}/api/7/apps/search?query=chrome&limit=1" | jq -e '.info.status == "OK"' > /dev/null 2>&1; then
    	echo -ne "[*] https://ws75.aptoide.com/: ok\n"
	else
    	echo -ne "[*] https://ws75.aptoide.com/: bad\n"
	fi

		
    if command -v su &> /dev/null && su -c true 2>/dev/null; then
        has_root=1
    fi
        if ! command -v su &> /dev/null || ! su -c true 2>/dev/null; then
        echo -e "\033[31mE:\033[0m updating GUI packages requires root access"
        read -rp $'\033[33mDo you want to only perform a partial update on the CLI packages? [y/n] \033[0m' answer
         case "$answer" in
            [Yy]*)
                pkg update -y
                exit 0
                ;;
            *)
                echo "Update cancelled."
                exit 1
                ;;
        esac
    fi


    get_local_info() {
        local pkg="$1"
        local out
        if [[ "$has_root" -eq 1 ]]; then
            out=$(su -c "dumpsys package $pkg" 2>/dev/null)
        elif adb get-state >/dev/null 2>&1; then
            out=$(adb shell dumpsys package "$pkg" 2>/dev/null)
        else
            out=$(cmd package dump "$pkg" 2>/dev/null)
        fi

        local vcode vname
        vcode=$(echo "$out" | grep -m1 "versionCode=" | awk '{print $1}' | cut -d'=' -f2 | tr -d '\r')
        vname=$(echo "$out" | grep -m1 "versionName=" | awk '{print $1}' | cut -d'=' -f2 | tr -d '\r')
        echo "${vcode}|${vname}"
    }

    is_newer_vername() {
        local local_ver="$1"
        local remote_ver="$2"
        [[ -z "$local_ver" || -z "$remote_ver" ]] && return 1
        [[ "$local_ver" == "$remote_ver" ]] && return 1

        local IFS='.'
        local -a l_parts r_parts
        read -ra l_parts <<< "$local_ver"
        read -ra r_parts <<< "$remote_ver"

        local max_len=${#l_parts[@]}
        [[ "${#r_parts[@]}" -gt "$max_len" ]] && max_len=${#r_parts[@]}

        local i l_num r_num
        for (( i = 0; i < max_len; i++ )); do
            l_num=$(echo "${l_parts[i]:-0}" | tr -cd '0-9')
            r_num=$(echo "${r_parts[i]:-0}" | tr -cd '0-9')
            l_num=${l_num:-0}
            r_num=${r_num:-0}

            if (( 10#$r_num > 10#$l_num )); then
                return 0
            elif (( 10#$r_num < 10#$l_num )); then
                return 1
            fi
        done

        return 1
    }

    local cli_count=0
    local gui_count=0
    local -a gui_queue=()
    local ignore_file="$HOME/.pkgignore"
    local ignore_list=""
    if [[ -f "$ignore_file" ]]; then
        # Strip comments (#...), blank lines, and Windows \r
        ignore_list=$(grep -Ev '^\s*(#|$)' "$ignore_file" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

        apt-get update -qq 2>/dev/null

    local -a cli_queue=()
    local cli_upgradable=""
    local raw_apt
    raw_apt=$(apt list --upgradable 2>/dev/null | awk 'NR>1 {
        split($1, a, "/");
        pkg = a[1];
        new_ver = $2;
        old_ver = $NF;
        gsub(/\]/, "", old_ver);
        if (pkg != "") print pkg "|" old_ver "|" new_ver;
    }')

    while IFS='|' read -r pkg old_ver new_ver; do
        [[ -z "$pkg" ]] && continue
        if [[ -n "$ignore_list" ]] && printf "%s\n" "$ignore_list" | grep -qxF "$pkg"; then
            continue
        fi
        cli_queue+=("${pkg}|${old_ver}|${new_ver}")
        cli_upgradable+="${pkg}"$'\n'
        ((cli_count++))
    done <<< "$raw_apt"

    local gui_apps
    gui_apps=$( {
        cmd package list packages -3 -e 2>/dev/null | sed 's/^package://' \
            | grep -Ev '^(com\.android\.|com\.google\.android\.(gms|gsf|webview|trichrome|networkstack|permissioncontroller|ext\.|modulemetadata|ondevicepersonalization|adservices|federatedcompute|captiveportallogin|cellbroadcast|configupdater|partnersetup|printspooler|packageinstaller|documentsui|inputmethod|tts|marvin|projection|as|odad|verifier|contactkeys|apps\.restore|apps\.setupwizard|apps\.wellbeing|ambient\.streaming)|com\.google\.mainline\.|com\.google\.ar\.|android\.autoinstalls|com\.aura\.|com\.lenovo\.|com\.mediatek\.|com\.qualcomm\.)'

        cmd package list packages -e 2>/dev/null | sed 's/^package://' \
            | grep -E '^(com\.android\.chrome|com\.google\.android\.youtube|com\.google\.android\.apps\.youtube\.music|com\.google\.android\.dialer|com\.google\.android\.apps\.messaging|com\.google\.android\.apps\.photos|com\.google\.android\.apps\.docs|com\.google\.android\.apps\.maps|com\.google\.android\.gm|com\.google\.android\.calendar|com\.google\.android\.deskclock|com\.google\.android\.calculator)$'
    } | grep -v '^com\.google\.android\.gms$' | sort -u )

    local abi sdk density q_raw q_b64
    abi=$(getprop ro.product.cpu.abi 2>/dev/null); abi=${abi:-arm64-v8a}
    sdk=$(getprop ro.build.version.sdk 2>/dev/null); sdk=${sdk:-34}
    density=$(wm density 2>/dev/null | awk '{print $NF}' | tr -cd '0-9'); density=${density:-480}
    q_raw="maxSdk=${sdk}&maxScreen=xlarge&maxGles=3.2&myCPU=${abi}&myDensity=${density}"
    q_b64=$(printf '%s' "$q_raw" | base64 -w 0 | tr '+/' '-_' | tr -d '=')
	local pross=0
    local current=0
    local total_apps=$(printf "%s\n" "$gui_apps" | grep -c .)
        if [[ -n "$ignore_list" && -n "$gui_apps" ]]; then
        gui_apps=$(printf "%s\n" "$gui_apps" | grep -vxFf <(printf "%s\n" "$ignore_list") || true)
    fi

    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        ((current++))
		pross=$(( current * 100 / total_apps ))
        echo -ne "\r\033[33m[$pross%] Comparing versions with server...\033[0m\033[K"
        local local_info local_ver local_name
        local_info=$(get_local_info "$pkg")
        IFS='|' read -r local_ver local_name <<< "$local_info"
        [[ ! "$local_ver" =~ ^[0-9]+$ ]] && continue

        local meta remote_ver remote_name
        
        meta=$(curl -s "https://${host}/api/7/app/getMeta?package_name=${pkg}&store_name=${store}&q=${q_b64}")
        remote_ver=$(echo "$meta" | jq -r '.data.file.vercode // empty' | tr -d '\r')
        if [[ ! "$remote_ver" =~ ^[0-9]+$ ]] || [[ "$remote_ver" -le "$local_ver" ]]; then
            meta=$(curl -s "https://${host}/api/7/app/getMeta?package_name=${pkg}&q=${q_b64}")
        fi
        
        remote_ver=$(echo "$meta" | jq -r '.data.file.vercode // empty' | tr -d '\r')
        remote_name=$(echo "$meta" | jq -r '.data.file.vername // empty' | tr -d '\r')

        [[ ! "$remote_ver" =~ ^[0-9]+$ ]] && continue
        [[ "$remote_ver" =~ ^9{7,}$ ]] && continue

        if [[ "$remote_ver" -gt "$local_ver" ]] && is_newer_vername "$local_name" "$remote_name"; then
           gui_queue+=("${pkg}|${local_name}|${local_ver}|${remote_name}|${remote_ver}")
            ((gui_count++))
        fi
    done <<< "$gui_apps"
		echo -ne "\r\033[K"
        if [[ "$cli_count" -eq 0 && "$gui_count" -eq 0 ]]; then
        echo -e "\n\033[1;37mNo updates found.\033[0m"
        return 0
    fi

    echo -e "\n\033[1;37m\033[1;33m${cli_count}\033[1;37m CLI package(s) and \033[1;33m${gui_count}\033[1;37m GUI application(s) need to be updated\033[0m"
       if [[ "$cli_count" -gt 0 ]]; then
        for item in "${cli_queue[@]}"; do
            IFS='|' read -r pkg lver rver <<< "$item"
            echo "  - $pkg: $lver -> $rver"
        done
    fi

    if [[ "$gui_count" -gt 0 ]]; then
        for item in "${gui_queue[@]}"; do
            IFS='|' read -r pkg lname lver rname rver <<< "$item"
            echo "  - $pkg: $lname ($lver) -> $rname ($rver)"
        done
    fi


    
    read -rp "Do you want to install updates? [y/n] " answer
    case "$answer" in
        [Yy]*)
            if [[ "$cli_count" -gt 0 ]]; then
                printf "%s\n" "$cli_upgradable" | xargs -r pkg install -y
            fi

            for item in "${gui_queue[@]}"; do
                IFS='|' read -r pkg lname lver rname rver <<< "$item"
                install_app "$pkg" || true
            done
            ;;
        *)
            echo "Update cancelled."
            ;;
    esac
}
about() {
    echo -e "\n\e[90m\e[47m████████████████████\e[0m"
    echo -e "\e[90m\e[47m█▀▄ ██▄ ▄▄▀█▄ ▀█▀ ▄█\e[0m"
    echo -e "\e[90m\e[47m█ ▄█▀██ ▄▄███ █▄█ ██\e[0m"
    echo -e "\e[90m\e[47m██▄▄██▄▄▄███▄▄▄█▄▄▄█\e[0m"
    echo -e "\e[90m\e[47m████████████████████\e[0m"

    echo -e "\n\e[0;33mThis is an unofficial repo based package manager for Android."
    echo -e "It enhances the native android package manager (pm) with online repos like any other distro."
    echo -e "\nVersion 1.5 2026\nType \"epm help\" for usage\nPowered by Aptoide and Termux repos\e[0m"
}

# Main script logic
if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "Invalid number of arguments."
    echo "Usage: epm {search|install|remove} <package_name>"
    echo -e "\nOr use:"
    echo "clean -> cleans all downloaded apk files in the current directory"
    echo "list -> List all user installed packages, if --showall it includes system ones"
    echo "help -> Displays usage"
    echo "update -> Updates all packages on the system"
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
    list)
        if [[ -n "$app_name" && "$app_name" != "--showall" ]]; then
            echo "Error: Invalid option '$app_name' for 'list'. Use '--showall' or no arguments."
            exit 1
        fi
        list_apps "$app_name"
        ;;

    about) about ;;
    update) [[ -n "$app_name" ]] && echo "Error: 'update' does not accept arguments." && exit 1; update ;;
    help)
        echo "Usage: epm {search|install|remove} <package_name>"
        echo -e "\nOr use:"
        echo "clean -> cleans all downloaded apk files in the current directory"
        echo "list -> List user installed packages, if  --showall it includes system ones"
        echo "help -> Displays usage"
        echo "update -> Updates all packages on the system"   
        echo "about -> Displays information for this service"
        ;;
    *) echo "Invalid action: $action"; echo "Usage: epm {search|install|remove} <package_name>"; ;;
esac
