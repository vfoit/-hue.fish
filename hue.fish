function hue --description "Philips Hue CLI controller for Fish shell"
    # Display usage if no arguments provided or help requested
    if test (count $argv) -eq 0; or contains -- $argv[1] help h
        echo "Usage:"
        echo "  hue help|h               Show this help"
        echo "  hue on | off             Turn all lights on/off"
        echo "  hue brightness|b <0-100> Set brightness in percent (0 turns lights off)"
        echo "  hue color|c <rrggbb>     Set color as RGB hex, e.g. ff0000 for red"
        echo "  hue white warm | cool    Set white to warm (2700 K) or cool (6500 K)"
        echo "  hue white|t <temp>       Set white color temperature: Kelvin from 2000 (e.g. 2700), mireds below (e.g. 370)"
        echo "  hue list|l               List all available scenes with an index"
        echo "  hue scene|s <#>          Activate a scene by its index from 'hue list'"
        echo "  hue scene|s <name>       Activate a scene by its name (case-insensitive)"
        echo "  hue <id> <settings>      Apply settings to a single light, e.g. hue 1 off"
        echo
        echo "Settings can be combined: hue t 2700 b 50, hue 1 c ff0000 b 50"
        # Explicit help succeeds; bare 'hue' is a usage error
        test (count $argv) -gt 0
        return
    end

    # Bridge configuration comes from universal variables set by hue_setup
    if not set -q HUE_BRIDGE_IP; or not set -q HUE_API_KEY
        echo "Error: HUE_BRIDGE_IP or HUE_API_KEY not set. Run 'hue_setup' first."
        return 1
    end
    set -l bridge_ip $HUE_BRIDGE_IP
    set -l api_key $HUE_API_KEY

    switch $argv[1]
        case list l
            # Scenes sorted by name (then ID) so indexes stay stable between calls
            set -l scenes (curl -s "http://$bridge_ip/api/$api_key/scenes" | \
                jq -r 'to_entries | sort_by(.value.name, .key)[] | "\(.key)\t\(.value.name)"')
            if test (count $scenes) -eq 0
                echo "Error: No scenes found (is the bridge reachable?)"
                return 1
            end
            printf "%3s  %s\n" "#" "NAME"
            printf "%3s  %s\n" "--" "----"
            for i in (seq (count $scenes))
                printf "%3d  %s\n" $i (string split -m1 \t -- $scenes[$i])[2]
            end

        case scene s
            if test (count $argv) -lt 2
                echo "Error: Missing scene. Usage: hue scene <#|name>"
                return 1
            end
            # Allow multi-word names without quoting: hue scene Bright Evening
            set -l query (string join ' ' -- $argv[2..-1])
            set -l scenes (curl -s "http://$bridge_ip/api/$api_key/scenes" | \
                jq -r 'to_entries | sort_by(.value.name, .key)[] | "\(.key)\t\(.value.name)"')
            set -l match
            if string match -qr '^[0-9]+$' -- $query
                if test $query -ge 1 -a $query -le (count $scenes)
                    set match (string split -m1 \t -- $scenes[$query])
                end
            else
                for line in $scenes
                    set -l parts (string split -m1 \t -- $line)
                    if test (string lower -- $parts[2]) = (string lower -- $query)
                        set match $parts
                        break
                    end
                end
            end
            if test (count $match) -lt 2
                echo "Error: No scene matching '$query'. Run 'hue list' to see available scenes."
                return 1
            end
            # Group 0 targets all lights connected to the bridge
            curl -s -X PUT -d "{\"scene\":\"$match[1]\"}" "http://$bridge_ip/api/$api_key/groups/0/action" > /dev/null
            echo "Applied scene: $match[2]"

        case '*'
            # Light settings: hue [<id>] <setting> [<setting> ...]
            # Group 0 is all lights; one group command is more reliable than one per light
            set -l path groups/0/action
            set -l target "All lights"
            set -l args $argv
            if string match -qr '^[0-9]+$' -- $args[1]
                set path lights/$args[1]/state
                set target "Light $args[1]"
                set -e args[1]
            end
            if test (count $args) -eq 0
                echo "Error: Missing setting. Usage: hue $argv[1] <on|off|b|c|white|t> ..."
                return 1
            end

            set -l power
            set -l fields
            set -l desc
            while test (count $args) -gt 0
                set -l opt $args[1]
                set -e args[1]
                switch $opt
                    case on
                        set power true
                    case off
                        set power false
                    case brightness b
                        set -l pct (string replace '%' '' -- "$args[1]")
                        set -e args[1]
                        if not string match -qr '^[0-9]+$' -- $pct; or test $pct -gt 100
                            echo "Error: Brightness must be 0-100, e.g. hue b 50"
                            return 1
                        end
                        if test $pct -eq 0
                            set power false
                        else
                            # Hue brightness runs from 1 to 254
                            set -l bri (math "round($pct * 254 / 100)")
                            test $bri -lt 1; and set bri 1
                            set -a fields "\"bri\":$bri"
                            set -a desc "brightness $pct%"
                        end
                    case white t
                        set -l temp (string lower -- "$args[1]")
                        set -e args[1]
                        set -l mired
                        set -l kelvin
                        switch $temp
                            case warm
                                set temp 2700
                            case cool
                                set temp 6500
                        end
                        if not string match -qr '^[0-9]+$' -- $temp
                            echo "Error: Invalid color temperature '$temp'. Use warm, cool, Kelvin (e.g. 2700) or mireds (153-500)."
                            return 1
                        end
                        # Numbers from 2000 up are Kelvin, smaller ones are mireds
                        if test $temp -ge 2000
                            set kelvin $temp
                            set mired (math "round(1000000 / $temp)")
                        else
                            set mired $temp
                        end
                        # Hue white range: 153 mireds (6500 K) to 500 mireds (2000 K)
                        if test $mired -lt 153
                            echo "Note: $temp is cooler than the lights support, using 6500 K."
                            set mired 153
                            set kelvin 6500
                        else if test $mired -gt 500
                            echo "Note: $temp is warmer than the lights support, using 2000 K."
                            set mired 500
                            set kelvin 2000
                        end
                        set -a fields "\"ct\":$mired"
                        if test -n "$kelvin"
                            set -a desc "$kelvin K"
                        else
                            set -a desc "$mired mireds ("(math "round(1000000 / $mired)")" K)"
                        end
                    case color c
                        # Optional '#' must be quoted in fish, e.g. hue c '#ff0000'
                        set -l hex (string lower -- (string replace -r '^#' '' -- "$args[1]"))
                        set -e args[1]
                        if string match -qr '^[0-9a-f]{3}$' -- $hex
                            set hex (string replace -ra '(.)' '$1$1' -- $hex)
                        end
                        if not string match -qr '^[0-9a-f]{6}$' -- $hex
                            echo "Error: Color must be RGB hex, e.g. hue c ff0000"
                            return 1
                        end
                        if test $hex = 000000
                            echo "Error: 000000 is black; use 'hue off' instead."
                            return 1
                        end
                        # The bridge takes CIE xy color: undo sRGB gamma, convert to XYZ, normalize.
                        # Brightness is set separately with 'b'; the bridge fits xy to the lights' gamut.
                        set -l lin
                        for i in 1 3 5
                            set -l v (math 0x(string sub -s $i -l 2 -- $hex))
                            if test $v -gt 10
                                set -a lin (math "(($v / 255 + 0.055) / 1.055) ^ 2.4")
                            else
                                set -a lin (math "$v / 255 / 12.92")
                            end
                        end
                        set -l X (math "$lin[1] * 0.4124 + $lin[2] * 0.3576 + $lin[3] * 0.1805")
                        set -l Y (math "$lin[1] * 0.2126 + $lin[2] * 0.7152 + $lin[3] * 0.0722")
                        set -l Z (math "$lin[1] * 0.0193 + $lin[2] * 0.1192 + $lin[3] * 0.9505")
                        set -l x (math -s4 "$X / ($X + $Y + $Z)")
                        set -l y (math -s4 "$Y / ($X + $Y + $Z)")
                        set -a fields "\"xy\":[$x,$y]"
                        set -a desc "color $hex"
                    case '*'
                        echo "Unknown command or setting: '$opt'. Run 'hue help' for usage."
                        return 1
                end
            end

            if string match -q '"ct":*' -- $fields; and string match -q '"xy":*' -- $fields
                echo "Error: Use either a color (c) or a white temperature (white/t), not both."
                return 1
            end

            # Brightness and color can only be changed while a light is on
            if test "$power" = false
                set fields
                set desc off
            else
                set desc on $desc
            end
            set -l body (string join ',' -- "\"on\":"(test "$power" = false; and echo false; or echo true) $fields)

            set -l reply (curl -s -m 5 -X PUT -d "{$body}" "http://$bridge_ip/api/$api_key/$path" | string collect)
            if test -z "$reply"
                echo "Error: No response from the bridge at $bridge_ip."
                return 1
            end
            set -l errors (echo $reply | jq -r '.[]? | .error.description // empty' 2>/dev/null)
            if test (count $errors) -gt 0
                printf "Error from bridge: %s\n" $errors
                return 1
            end
            echo "$target: "(string join ', ' -- $desc)
    end
end
