#!/bin/bash
{
mode=headless
#mode=nested
case $mode in
  nested)
    fullscreen=0
    limit_fps=0
    ;;
  headless)
    fullscreen=1
    limit_fps=1
    ;;
esac

IFS=$'\n'
CHROMIUM_CONFIG=$HOME/.config/adopt-a-developer
DIRECTORY="$(dirname "$0")"

exit_restart() { #exit with code 2 to signify that this script wants to be restarted by the daemon
  exit 2
}

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

process_exists() { #return 0 if the $1 PID is running, otherwise 1
  [ -z "$1" ] && error "process_exists(): no PID given!"
  
  if [ -f "/proc/$1/status" ];then
    return 0
  else
    return 1
  fi
}

update_check() { #check for updates and reload the script if necessary
  localhash="$(cd "$DIRECTORY" ; git rev-parse HEAD)"
  latesthash="$(git ls-remote https://github.com/Botspot/adopt-a-developer HEAD | awk '{print $1}')"
  if [ "$localhash" != "$latesthash" ] && [ ! -z "$latesthash" ] && [ ! -z "$localhash" ];then
    echo "Auto-updating adopt-a-developer for the latest features and improvements..."
    cd "$DIRECTORY"
    git restore . #abandon changes to tracked files (otherwise users who modified this script are left behind)
    git pull | cat #piping through cat makes git noninteractive
    
    if [ "${PIPESTATUS[0]}" == 0 ];then
      cd
      echo "git pull finished. Reloading script..."
      #kill labwc if running
      kill $PID2KILL 2>/dev/null
      #request to be restarted by the daemon
      exit_restart
    else
      cd
      echo "git pull failed. Continuing..."
    fi
  fi
}

less_chromium() { #hide harmless errors from chromium
  grep --line-buffered -v '^close object .*: Invalid argument$\|DidStartWorkerFail chnccghejnflbccphgkncbmllhfljdfa\|Network service crashed, restarting service\|Unsupported pixel format\|Trying to Produce .* representation from a non-existent mailbox\|^libpng warning:\|Cannot create bo with format\|handshake failed; returned .*, SSL error code .*, net_error\|ReadExactly: expected .*, observed\|ERROR:wayland_event_watcher.cc\|database is locked\|Error while writing cjpalhdlnbpafiamejdnhcphjbkeiagm\.browser_action\|Failed to delete the database: Database IO error\|Message .* rejected by interface\|Failed to call method: org\.freedesktop\.ScreenSaver\.GetActive'
}

get_color_of_pixel() { #get the base64 hash of a 1x1 ppm image taken at the specified coordinates
  grim -g "$1,$2 1x1" -t ppm - | base64
}

#make sure I am being run by the daemon
if [ "$YOU_ARE_BEING_RUN_BY_DAEMON" != 1 ];then
  "${DIRECTORY}/daemon.sh"
  exit $?
fi

#check chromium dependency
if [ -f /usr/lib/chromium/chromium ];then
  #chromium deb installed
  chromium_version="$(package_installed_version chromium | sed 's/.*://g ; s/-.*//g')"
  [ -z "$chromium_version" ] && error "chromium deb is installed, but failed to get a version for it!"
  chromium_binary=('/usr/lib/chromium/chromium')
elif [ -f /snap/bin/chromium ];then
  #snap version of chromium is installed (most likely ubuntu)
  chromium_version="$(snap info chromium | grep installed | awk '{print $2}')"
  [ -z "$chromium_version" ] && error "chromium snap is installed, but failed to get a version for it!"
  chromium_binary=(/snap/bin/chromium)
else
  echo "chromium needs to be installed. trying to install it now..."
  sudo apt install -y chromium || error "install failed, exiting now"
  echo "Chromium should now be installed. Restarting script..."
  exit_restart
fi

#check dependencies
if ! command -v labwc >/dev/null ;then
  echo "labwc package needs to be installed. trying to install it now..."
  sudo apt install -y labwc || error "install failed, exiting now"
fi
if ! command -v wlr-randr >/dev/null ;then
  echo "wlr-randr package needs to be installed. trying to install it now..."
  sudo apt install -y wlr-randr || error "install failed, exiting now"
fi
if ! command -v grim >/dev/null ;then
  echo "grim package needs to be installed. trying to install it now..."
  sudo apt install -y grim || error "install failed, exiting now"
fi
#[ -z "$WAYLAND_DISPLAY" ] && error "For this script to work, your system needs to be using Wayland."

user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; ) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chromium_version Chrome/$chromium_version Not/A)Brand/8  Safari/537.36"
shared_flags=(--user-agent="$user_agent" --user-data-dir="$CHROMIUM_CONFIG" --password-store=basic --disable-hang-monitor \
  --disable-gpu-program-cache --disable-gpu-shader-disk-cache --disk-cache-size=$((10*1024*1024)) --media-cache-size=$((10*1024*1024)) \
  --enable-features=UseOzonePlatform --ozone-platform=wayland --disable-gpu-process-crash-limit --video-threads=1 --disable-accelerated-video-decode --disable-gpu-compositing \
  --num-raster-threads=1 --renderer-process-limit=1 --disable-low-res-tiling --mute-audio --no-first-run --enable-low-end-device-mode)
#GPU video decode disabled for stability reasons
#GPU compositing disabled to fix dmabuf errors on ubuntu with bad gpu drivers

#first run sequence
if [ ! -f "$CHROMIUM_CONFIG/acct-info" ];then
  
  [ -z "$uuid" ] && read -p "Paste the UUID that Botspot gives you, then press Enter."$'\n'"Format is XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXXXXXXXXXX"$'\n'"> " uuid
  if ! [[ $uuid =~ ^\{?[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{20}\}?$ ]]; then
    error "Unknown UUID format for input '$uuid'. Please run this script and try again."
  fi
  
  #compile wlrctl
  if [ ! -f /usr/local/bin/wlrctl ];then
    echo "Compiling wlrctl tool..."
    sudo apt install -y cmake libxkbcommon-dev libwayland-dev meson git || error "failed to install compile dependencies for wlrctl"
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
  echo -e "uuid=$uuid\nwidth=$width\nheight=$height" > "$CHROMIUM_CONFIG/acct-info" || error "Failed to create $CHROMIUM_CONFIG/acct-info file"
else #not first run
  #get saved values like uuid, width, height
  source "$CHROMIUM_CONFIG/acct-info"
  if [ -z "$uuid" ];then
    error "Failed to get uuid value from $CHROMIUM_CONFIG/acct-info - go check if that file went missing somehow."
  else
    echo "vid-viewer chosen UUID: $uuid"
  fi
  
  if [ ! -z "$PID2KILL" ] && process_exists "$PID2KILL" ;then
    #kill other running process (may be autostarted)
    echo "Another instance of this script was already running ($PID2KILL), killed it"
    kill "$PID2KILL"
  fi
fi

echo "vid-viewer chosen resolution: ${width}x${height}"

echo "Checking for updates..."
update_check
echo Done

#autostart, respect user's deletion from old runonce (don't create the file again if user already deleted it once)
export DIRECTORY
runonce <<"EOF"
if ! grep -q 'eaddbd9eef16066e454078ee0d6dda65f27ab5e9' "${DIRECTORY}/runonce_hashes" || [ -f ~/.config/autostart/adopt-a-developer.desktop ];then
  echo "Setting up autostart..."
  mkdir -p ~/.config/autostart
  echo "[Desktop Entry]
Name=Adopt a Developer
Exec=${DIRECTORY}/daemon.sh
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=false" > ~/.config/autostart/adopt-a-developer.desktop
  
  echo "To disable this running on next boot, remove this file: ~/.config/autostart/adopt-a-developer.desktop"
fi
true
EOF

(read line #get data values from labwc subprocess
  #echo "line was '$line'"
  if [[ "$line" == WAYLAND_DISPLAY=* ]];then
    eval $line #set the values of WAYLAND_DISPLAY and PID2KILL
    export WAYLAND_DISPLAY #needed for x11/headless systems, where this is not already an environment variable
    #run internal programs here
    
    #add PID of sleep command keeping labwc open, to acct-info to prevent multiple instances
    sed -i '/^PID2KILL/d' "$CHROMIUM_CONFIG/acct-info"
    echo "PID2KILL=$PID2KILL" >> "$CHROMIUM_CONFIG/acct-info"
    
    trap "kill $PID2KILL 2>/dev/null" EXIT #make sure labwc exits if this script is killed
    #resize screen in retry loop
    while ! wlr-randr | grep -qF "${width}x${height} px (current)" ;do
      wlr-randr --output $(wlr-randr | head -n1 | awk '{print $1}') --custom-mode ${width}x${height} || error "screen resize failed."
      sleep 1
    done
    
    echo -e "Launching hidden browser to donate to the developer...\nLeave this running as much as you can."
    while true;do
      #run browser with uuid to set cookies (slight chance of running again occasionally to fix issue where cookies went missing somehow)
      if [ "$cookies_set" != 1 ] || (( RANDOM % 40 == 0 ));then
        echo "Setting cookies... this should take less than 30 seconds"
        $chromium_binary "${shared_flags[@]}" --class=vid-viewer --start-maximized "https://mm-watch.com?u=$uuid" 2>&1 | less_chromium &
        wlrctl toplevel waitfor app_id:vid-viewer title:"MM Watch | Endless Entertainment - Chromium"
        sleep 10
        #check for cookie banner and dismiss it if present
        if [ "$(get_color_of_pixel $((width/2+50)) $((height-70)))" == UDYKMSAxCjI1NQpEiO4= ];then
          rm -rf ~/.config/adopt-a-developer ~/.config/autostart/adopt-a-developer.desktop
          error "Cookie banner detected. Most likely this means you are in the EU and the developer will get no income from your device. Go let Botspot know that your UUID can be given to someone else."
          
          echo "Dismissing cookie banner..."
          #shift-tab twice, then Enter
          wlrctl keyboard type $'\t' modifiers SHIFT
          sleep 0.5
          wlrctl keyboard type $'\t' modifiers SHIFT
          sleep 0.5
          wlrctl keyboard type $'\n'
          sleep 5
        fi
        wlrctl toplevel close app_id:vid-viewer
        echo "Cookies set successfully."
        if [ "$cookies_set" != 1 ];then
          cookies_set=1
          echo cookies_set=1 >> "$CHROMIUM_CONFIG/acct-info"
        fi
      fi
      
      #prevent "restore session" question
      sed -i 's/"exited_cleanly":false/"exited_cleanly":true/g ; s/"exit_type":"Crashed"/"exit_type":"Normal"/g ; s/"crashed":true/"crashed":false/g' "$CHROMIUM_CONFIG/Default/Preferences"
      #remove files left behind killed chromium
      rm -f "$CHROMIUM_CONFIG/Default/.org.chromium.Chromium."*
      
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
        #raise window, then lower it immediately for 6 frames per minute
        if [ "$limit_fps" == 1 ];then
          wlrctl toplevel focus app_id:vid-viewer
          if [ $inspect == false ];then
            wlrctl toplevel minimize app_id:vid-viewer
          fi
        fi
        #check for killed processes
        if ! process_exists "$chrpid" ;then
          #browser process killed, was anything else killed too?
          if process_exists "$LABWC_PID" && process_exists "$PID2KILL";then
            #labwc and sleep infinity subprocess still running
            (error "WARNING: browser process disappeared. Waiting 60 seconds and retrying...")
            sleep 60
            break
          elif process_exists "$PID2KILL" ;then
            #labwc killed, but its sleep infinity subprocess still running: labwc crashed
            kill "$PID2KILL"
            (error "LABWC CRASHED!! Restarting script in 60 seconds...")
            sleep 60
            exit_restart
          else
            #labwc and sleep infinity subprocess killed, so this script must have been killed by another process
            (error "browser and labwc killed, so likely another process was started. Exiting.")
            exit 0
          fi
        fi
        
        sleep 10
        i=$((i+1))
      done
      
      #close chromium nicely, then forcefully
      wlrctl toplevel close app_id:vid-viewer
      sleep 5
      kill "$chrpid" 2>/dev/null
      
      update_check #check for updates again
      [ "$i" == 300 ] && echo "50 minutes has elapsed, restarting browser"
    done
  else
    error "Unknown line from labwc: $line"
  fi
) < <(WLR_BACKENDS="${mode//nested/wayland}" labwc -C "$DIRECTORY/labwc" -s 'bash -c '\''echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY PID2KILL=$$ LABWC_PID=$LABWC_PID"; trap "kill $LABWC_PID 2>/dev/null" EXIT; sleep infinity'\' | \
  grep --line-buffered "^WAYLAND_DISPLAY=" ; labwc_exitcode=${PIPESTATUS[0]} ; if [ "$labwc_exitcode" != 0 ];then echo "labwc exitcode was $labwc_exitcode" 1>&2 ;fi)

}
