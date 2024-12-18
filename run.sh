#!/bin/bash

mode=headless
#mode=nested
case $mode in
  nested)
    fullscreen=0
    limit_fps=1
    ;;
  headless)
    fullscreen=1
    limit_fps=1
    ;;
esac

IFS=$'\n'
CHROMIUM_CONFIG=$HOME/.config/adopt-a-developer
DIRECTORY="$(dirname "$0")"

error() { #red text and exit 1
  echo -e "\e[91m$1\e[0m" 1>&2
  exit 1
}

package_info() { #list everything dpkg knows about the $1 package. Note: the package has to be installed for this to show anything.
  local package="$1"
  [ -z "$package" ] && error "package_info(): no package specified!"
  #list lines in /var/lib/dpkg/status between the package name and the next empty line (empty line is then removed)
  sed -n -e '/^Package: '"$package"'$/,/^$/p' /var/lib/dpkg/status | head -n -1
  true #this may exit with code 141 if the pipe was closed early (to be expected with grep -v)
}

package_installed_version() { #returns the installed version of the specified package-name.
  local package="$1"
  [ -z "$package" ] && error "package_installed_version(): no package specified!"
  #find the package listed in /var/lib/dpkg/status
  package_info "$package" | grep '^Version: ' | awk '{print $2}'
}

runonce() { #run command only if it's never been run before. Useful for one-time migration or setting changes.
  #Runs a script in the form of stdin
  
  script="$(< /dev/stdin)"
  
  runonce_hash="$(sha1sum <<<"$script" | awk '{print $1}')"
  
  if [ -s "${DIRECTORY}/runonce_hashes" ] && while read line; do [[ $line == "$runonce_hash" ]] && break; done < "${DIRECTORY}/runonce_hashes"; then
    #hash found
    #echo "runonce: '$script' already run before. Skipping."
    true
  else
    #run the script.
    bash <(echo "$script")
    #if it succeeds, add the hash to the list to never run it again
    if [ $? == 0 ];then
      echo "$runonce_hash" >> "${DIRECTORY}/runonce_hashes"
    else
      echo "runonce(): '$script' failed. Not adding hash to list."
    fi
  fi
}

#check depends
chromium_version="$(package_installed_version chromium | sed 's/.*://g ; s/-.*//g')"
[ -z "$chromium_version" ] && error "chromium package needs to be installed."
chromium_binary='/usr/lib/chromium/chromium'
[ ! -f $chromium_binary ] && error "chromium package needs to be installed."

[ ! -f /usr/bin/labwc ] && error "labwc package needs to be installed."
[ ! -f /usr/bin/wlr-randr ] && error "wlr-randr package needs to be installed."
#[ -z "$WAYLAND_DISPLAY" ] && error "For this script to work, your system needs to be using Wayland."

user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; ) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chromium_version Chrome/$chromium_version Not/A)Brand/8  Safari/537.36"
shared_flags=(--user-agent="$user_agent" --user-data-dir="$CHROMIUM_CONFIG" --password-store=basic --disable-hang-monitor --disable-gpu-process-crash-limit \
  --disable-gpu-program-cache --disable-gpu-shader-disk-cache --disk-cache-size=$((10*1024*1024)) --media-cache-size=$((10*1024*1024)) --video-threads=1 \
  --disable-accelerated-video-decode --num-raster-threads=1 --renderer-process-limit=1 --disable-low-res-tiling --mute-audio --no-first-run --enable-low-end-device-mode)
#GPU video decode disabled for stability reasons

#first run sequence
if [ ! -f "$CHROMIUM_CONFIG/acct-info" ];then
  
  [ -z "$uuid" ] && read -p "Paste the UUID that Botspot gives you, then press Enter."$'\n'"Format is XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXXXXXXXXXX"$'\n'"> " uuid
  if ! [[ $uuid =~ ^\{?[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{20}\}?$ ]]; then
    error "Unknown UUID format for input '$uuid'. Please run this script and try again."
  fi
  
  if [ ! -f /usr/local/bin/wlrctl ];then
    sudo apt install -y cmake libxkbcommon-dev libwayland-dev || error "failed to install compile dependencies for wlrctl"
    rm -rf ./wlrctl
    git clone https://git.sr.ht/~brocellous/wlrctl || error "failed to download wlrctl repo"
    cd wlrctl
    meson setup --prefix=/usr/local build || error "failed to build wlrctl"
    sudo ninja -C build install || error "failed to install wlrctl"
    cd ..
    rm -rf ./wlrctl
  fi
  
  echo -n "Copying config... "
  rm -rf "$CHROMIUM_CONFIG"
  cp -a "$DIRECTORY/template-acct" "$CHROMIUM_CONFIG"
  echo Done
  
  #pick a screen resolution
  resolution="$(shuf "$DIRECTORY/resolutions" | grep -v '#' | head -n1)"
  [ -z "$resolution" ] && error "failed to pick a resolution"
  width="$(echo "$resolution" | sed 's/x.*//g')"
  height="$(echo "$resolution" | sed 's/.*x//g')"
  
  #save UUID and screen resolution for later runs
  echo -e "uuid=$uuid\nwidth=$width\nheight=$height" > "$CHROMIUM_CONFIG/acct-info"
else #not first run
  #get saved values like uuid, width, height
  source "$CHROMIUM_CONFIG/acct-info"
  if [ -z "$uuid" ];then
    error "Failed to get uuid value from $CHROMIUM_CONFIG/acct-info - go check if that file went missing somehow."
  else
    echo "vid-viewer chosen UUID: $uuid"
  fi
  
  #prevent "restore session" question
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/ ; s/"exit_type":"Crashed"/"exit_type":"Normal"/' "$CHROMIUM_CONFIG/Default/Preferences"
  #remove files left behind killed chromium
  rm -f "$CHROMIUM_CONFIG/Default/.org.chromium.Chromium."*
fi

echo "vid-viewer chosen resolution: ${width}x${height}"

echo "Checking for updates..."
update_check() {
  localhash="$(cd "$DIRECTORY" ; git rev-parse HEAD)"
  latesthash="$(git ls-remote https://github.com/Botspot/adopt-a-developer HEAD | awk '{print $1}')"
  if [ "$localhash" != "$latesthash" ] && [ ! -z "$latesthash" ] && [ ! -z "$localhash" ];then
    echo "Auto-updating adopt-a-developer for the latest features and improvements..."
    cd "$DIRECTORY"
    git pull | cat #piping through cat makes git noninteractive
    
    if [ "${PIPESTATUS[0]}" == 0 ];then
      cd
      echo "git pull finished. Reloading script..."
      #kill labwc if running
      kill $PID2KILL 2>/dev/null
      set -a #export all variables so the script can see them
      #run updated script
      "$DIRECTORY/run.sh" "$@"
      exit $?
    else
      cd
      echo "git pull failed. Continuing..."
    fi
  fi
}
update_check
echo Done

#autostart
runonce <<"EOF"
echo "Setting up autostart..."
mkdir -p ~/.config/autostart
echo "[Desktop Entry]
Name=Adopt a Developer
Exec=${DIRECTORY}/run.sh
Terminal=false
StartupWMClass=Pi-Apps
Type=Application
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false" > ~/.config/autostart/adopt-a-developer.desktop

echo "To disable this running on next boot, remove this file: ~/.config/autostart/adopt-a-developer.desktop"
EOF

less_chromium() {
  grep --line-buffered -v '^close object .*: Invalid argument$\|DidStartWorkerFail chnccghejnflbccphgkncbmllhfljdfa\|Network service crashed, restarting service\|Unsupported pixel format\|Trying to Produce a Skia representation from a non-existent mailbox\|^libpng warning:\|Cannot create bo with format\|handshake failed; returned .*, SSL error code .*, net_error\|ReadExactly: expected .*, observed'
}

(read line
  #echo "line was '$line'"
  if [[ "$line" == WAYLAND_DISPLAY=* ]];then
    eval $line #set the values of WAYLAND_DISPLAY and PID2KILL
    export WAYLAND_DISPLAY #needed for x11/headless systems, where this is not already an environment variable
    #run internal programs here
    trap "kill $PID2KILL 2>/dev/null" EXIT
    #resize screen
    wlr-randr --output $(wlr-randr | head -n1 | awk '{print $1}') --custom-mode ${width}x${height} || error "screen resize failed."
    
    #run browser with uuid to set cookies
    if [ "$cookies_set" != 1 ];then
      echo "Launching hidden browser to set cookies... this should take less than 20 seconds"
      $chromium_binary "${shared_flags[@]}" --class=vid-viewer --start-maximized "https://mm-watch.com?u=$uuid" 2>&1 | less_chromium &
      wlrctl toplevel waitfor app_id:vid-viewer title:"MM Watch | Endless Entertainment - Chromium"
      sleep 10
      wlrctl toplevel close app_id:vid-viewer title:"MM Watch | Endless Entertainment - Chromium"
      echo "Cookies set successfully."
      cookies_set=1
      echo cookies_set=1 >> "$CHROMIUM_CONFIG/acct-info"
    fi
    
    echo -e "Launching hidden browser to donate to the developer..."
    while true;do
      $chromium_binary "${shared_flags[@]}" --class=vid-viewer --start-maximized $([ $fullscreen == 1 ] && echo '--start-fullscreen') "$(shuf "$DIRECTORY/starting-links" | head -n1)" 2>&1 | less_chromium &
      chrpid=$!
      
      #wait until chromium is running, then minimize it to reduce GPU usage
      if [ "$limit_fps" == 1 ];then
        wlrctl toplevel waitfor app_id:vid-viewer
        echo "Browser window up and running as expected. All good."
        sleep 5
      fi
      
      i=0
      #every 10s, raise chromium window, every 50m restart chromium
      while [ $i -lt 300 ];do
        #inspect file allows troubleshooting without killing the browser
        if [ -f "$DIRECTORY/inspect" ];then
          inspect=true
        else
          inspect=false
        fi
        
        if [ "$limit_fps" == 1 ];then
          wlrctl toplevel focus app_id:vid-viewer
          #sleep 0.5
          if [ $inspect == false ];then
            wlrctl toplevel minimize app_id:vid-viewer
          fi
        fi
        if [ ! -f "/proc/$chrpid/status" ];then
          echo "WARNING: browser process disappeared. Waiting 1 minute and retrying."
          sleep 60
          break
        fi
        sleep 10
        i=$((i+1))
      done
      
      #close chromium nicely, then forcefully
      wlrctl toplevel close app_id:vid-viewer
      sleep 5
      kill "$chrpid" 2>/dev/null
      
      update_check
      [ "$i" == 300 ] && echo "50 minutes has elapsed, restarting browser"
    done
  else
    error "Unknown line from labwc: $line"
  fi
) < <(WLR_BACKENDS="$(echo "$mode" | sed 's/nested/wayland/g')" labwc -C "$DIRECTORY/labwc" -S 'bash -c "echo WAYLAND_DISPLAY=$WAYLAND_DISPLAY PID2KILL=$$ 1>&2;sleep infinity"' 2>&1 | \
  grep --line-buffered "^WAYLAND_DISPLAY="; echo "labwc exitcode was ${PIPESTATUS[0]}")


