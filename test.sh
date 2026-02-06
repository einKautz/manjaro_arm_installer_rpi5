#!/usr/bin/env bash

dialog_input() {
    local title="$1"
    shift
    local result

    result=$(dialog --clear \
        --title "$title" \
        --ok-label "Next" \
        --cancel-label "Back" \
        "$@" \
        2>&1 >/dev/tty)

    echo "$result"
}

result=$(dialog_input "Test" "Enter something:" --inputbox "Type:" 10 40)
echo "RESULT=[$result]"
