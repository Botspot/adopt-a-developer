# Support open source at no cost to you
Adopt a Developer is a new, easy way to donate to open source software developers without needing to spend any money yourself. This watches video advertisements in a background web browser, and the revenue gets sent to your developer of choice.
## Current status of the project: *ON HOLD*

> Message from Botspot: adopt-a-developer has encountered more backlash than I was expecting. While it has worked flawlessly from the technical side, and earning roughly $2 per day from just 4 or so active devices, for now I have decided to pause it to think through what to do next.

While I have been working on this concept for several years, Adopt a Developer is **experimental** and needs a lot of work to be cross-platform and more importantly, *scalable*. Right now it takes an unreasonable amount of manual effort from developers who want to receive donations.  
Current system requirements:
- Recent Linux install based on Debian, most likely needs to be Debian version 12 (Bookworm) or newer to get a good version of `labwc`.
- Does not need a running desktop environment, but does need `chromium` and `labwc` packages installed. (Chromium installed from Snap is not supported, sorry Ubuntu users!)
- Linux install can be x86 or ARM. (Not limited to Raspberry Pi)

Adopt a Developer is optimized to use minimal RAM, CPU, and storage. It runs great on a Pi4/Pi5. Not tested yet on a Pi3, but it ought to work. Unlike a crypto miner, this does not use 100% CPU, and it does not slow down your system much at all. It's just running a hidden web browser to play low-resolution 360p videos with a few tricks to minimize resource usage.
Best used on:
- A device you own. (don't go installing this on other people's computers lol)
- A device that you leave turned on most of the time. 24/7 uptime is not necessary, but this is a bad fit for you if your device is only turned on occasionally.
- One device per IP address. (Earnings do not increase from running this on two devices in the same network)
- A device that is connected to home/school/work WiFi. Bad idea to use this on a mobile hotspot unless you have an unlimited data plan. It downloads a bit more than 1 GB of video per hour. An hour of YouTube playback uses far more than 1GB, but regardless, you should know this upfront.

## FAQ
- Is this illegal? **No.** It probably breaks somebody's terms of service, but there should be no way you could get punished for that.
- Is this unethical? **No.** This offers the same revenue stream that YouTubers have, to software developers.
- Is this risky to run on my personal device? **No.** This just goes to one website in an isolated web browser profile. All they get is your IP address and a fake screen resolution.
- Do I need a credit card, bank account, or Google account to run this? **No.**
- Can I become a developer who can receive donations using this? **Yes you can try, but good luck.** I am still working on finding ways to lower the barrier to entry.

## Try it out
Run these commands to get started:
```
sudo apt install chromium labwc wlr-randr grim git cmake libxkbcommon-dev libwayland-dev meson #These are already installed on Raspberry Pi OS
git clone https://github.com/Botspot/adopt-a-developer
$PWD/adopt-a-developer/run.sh
```
The script will ask for a UUID, which you will need to contact me for. I have a very limited number of UUIDs to hand out. Contact me on Discord "`botspot.`"  
