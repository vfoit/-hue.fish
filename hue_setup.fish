function hue_setup --description 'Find the Hue bridge and store HUE_BRIDGE_IP and HUE_API_KEY'
    # Universal variables are per-user; running as root would store them for root
    if fish_is_root_user
        echo "Error: Don't run hue_setup as root/sudo. Run it as the user who will use 'hue'."
        return 1
    end

    # 1. Bridge IP: use the argument if given, then a working stored IP, otherwise ask the Hue discovery service
    set -l bridge_ip $argv[1]
    if test -z "$bridge_ip"; and set -q HUE_BRIDGE_IP
        if curl -s -m 3 "http://$HUE_BRIDGE_IP/api/config" | jq -e '.bridgeid' >/dev/null 2>&1
            read -l -P "HUE_BRIDGE_IP is set to $HUE_BRIDGE_IP and the bridge answers. Search for a bridge again? [y/N] " answer
            if not string match -qi 'y*' -- $answer
                set bridge_ip $HUE_BRIDGE_IP
            end
        else
            echo "HUE_BRIDGE_IP is set to $HUE_BRIDGE_IP, but no bridge answers there."
        end
    end
    if test -z "$bridge_ip"
        echo "Searching for Hue bridge..."
        # Discovery can list stale addresses, so keep only bridges that answer
        set -l found
        for ip in (curl -s -m 10 https://discovery.meethue.com | jq -r '.[].internalipaddress' 2>/dev/null)
            if curl -s -m 3 "http://$ip/api/config" | jq -e '.bridgeid' >/dev/null 2>&1
                set -a found $ip
            end
        end
        if test (count $found) -gt 1
            echo "Found several bridges:"
            for i in (seq (count $found))
                echo "  $i) $found[$i]"
            end
            read -l -P "Which one? [1] " choice
            test -z "$choice"; and set choice 1
            if not string match -qr '^[0-9]+$' -- $choice; or test $choice -lt 1 -o $choice -gt (count $found)
                echo "Error: Invalid choice '$choice'."
                return 1
            end
            set bridge_ip $found[$choice]
        else
            set bridge_ip $found[1]
        end
    end
    # Discovery is rate-limited; fall back to a previously stored IP
    if test -z "$bridge_ip"; and set -q HUE_BRIDGE_IP
        echo "Discovery failed, trying previously stored IP $HUE_BRIDGE_IP"
        set bridge_ip $HUE_BRIDGE_IP
    end
    if test -z "$bridge_ip"
        echo "Error: No bridge found. Run 'hue_setup <ip>' with the bridge's IP address."
        return 1
    end

    # Confirm it's really a Hue bridge (this endpoint needs no key)
    set -l bridge_id (curl -s -m 5 "http://$bridge_ip/api/config" | jq -r '.bridgeid // empty' 2>/dev/null)
    if test -z "$bridge_id"
        echo "Error: No Hue bridge responded at $bridge_ip."
        return 1
    end
    set -Ux HUE_BRIDGE_IP $bridge_ip
    echo "Bridge found: $bridge_ip (id $bridge_id)"

    # 2. API key: keep an existing key unless the user wants a new one
    if set -q HUE_API_KEY
        set -l keep_key
        # An invalid key returns an error array instead of the lights object
        if curl -s -m 5 "http://$bridge_ip/api/$HUE_API_KEY/lights" | jq -e 'type == "object"' >/dev/null 2>&1
            read -l -P "HUE_API_KEY is already set and works. Get a new one? [y/N] " answer
            not string match -qi 'y*' -- $answer; and set keep_key 1
        else
            read -l -P "HUE_API_KEY is set, but the bridge doesn't accept it. Get a new one? [Y/n] " answer
            string match -qi 'n*' -- $answer; and set keep_key 1
        end
        if test -n "$keep_key"
            echo
            echo "HUE_BRIDGE_IP = $bridge_ip"
            echo "HUE_API_KEY   = $HUE_API_KEY"
            return 0
        end
    end

    echo "Press the round link button on top of the bridge now (waiting 30 seconds)..."
    set -l devicetype (string sub -l 19 -- "hue.fish#$hostname")
    set -l api_key
    for i in (seq 15)
        set -l reply (curl -s -m 5 -X POST -d "{\"devicetype\":\"$devicetype\"}" "http://$bridge_ip/api")
        set api_key (echo $reply | jq -r '.[0].success.username // empty' 2>/dev/null)
        if test -n "$api_key"
            break
        end
        # Error type 101 means the button hasn't been pressed yet; anything else is a real error
        set -l err_type (echo $reply | jq -r '.[0].error.type // empty' 2>/dev/null)
        if test -n "$err_type" -a "$err_type" != 101
            echo "Error from bridge: "(echo $reply | jq -r '.[0].error.description')
            return 1
        end
        sleep 2
    end
    if test -z "$api_key"
        echo "Error: Link button wasn't pressed in time. Run hue_setup again."
        return 1
    end
    set -Ux HUE_API_KEY $api_key

    echo
    echo "Saved for all fish sessions:"
    echo "HUE_BRIDGE_IP = $bridge_ip"
    echo "HUE_API_KEY   = $HUE_API_KEY"
end
