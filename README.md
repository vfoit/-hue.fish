# hue.fish

A small [fish](https://fishshell.com) command for controlling Philips Hue lights from the terminal. It talks to the Hue bridge on your local network with `curl` (Hue API v1).


## Requirements

fish, `curl`, `jq`


## Install

```fish
ln -s (pwd)/hue.fish ~/.config/fish/functions/hue.fish
ln -s (pwd)/hue_setup.fish ~/.config/fish/functions/hue_setup.fish
hue_setup
```

Run this from the repo folder. `hue_setup` finds your bridge and asks you to press its link button to create an API key. Both are saved as fish universal variables (`HUE_BRIDGE_IP`, `HUE_API_KEY`).

Alternatively, set them up by hand:
```fish
# Find the bridge IP and save it
curl -s https://discovery.meethue.com | jq -r '.[].internalipaddress'
set -Ux HUE_BRIDGE_IP 192...
```
Press the link button on the bridge, then within 30 seconds run
```fish
curl -s -X POST -d '{"devicetype":"hue.fish#laptop"}' http://$HUE_BRIDGE_IP/api
set -Ux HUE_API_KEY AbCdEf...   # the "username" value from the reply
```


## Usage

```
hue on | off            Turn all lights on/off
hue brightness | b <%>  Set brightness in percent (0-100)
hue color | c <rrggbb>  Set color as RGB hex, e.g. ff0000
hue white warm | cool   Warm (2700 K) or cool (6500 K) white
hue white | t <temp>    White color temperature: 2700 (Kelvin) or 370 (mireds)
hue list | l            List scenes with an index
hue scene | s <#>       Activate a scene by index
hue scene | s <name>    Activate a scene by name
hue <id> <settings>     Apply settings to a single light, e.g. hue 1 off
hue help | h            Show help
```

Settings can be combined, e.g. `hue t 2700 b 50` or `hue 1 c ff0000 b 50` (light 1 red at 50%). Commands without a light ID apply to all lights on the bridge.

Tested with a 2nd generation Hue Bridge and 2 Hue Play light bars.
