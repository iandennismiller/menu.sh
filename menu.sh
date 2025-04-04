#!/bin/bash
# Ian Dennis Miller
# https://github.com/iandennismiller/menu.sh
# menu.sh 0.2
# 2025-04-05

# for the current menu path, set this prefix for fzf's preview
function get_path_fzf_preview() {
    local menu_path
    menu_path=$1

    if [ "$menu_path" == '.' ]; then
        echo ""
    else
        echo "$menu_path"
    fi
}

# if the current menu path has a __cmd__, return it
function get_path_cmd() {
    local menu_filename
    menu_filename=$1

    local menu_path
    menu_path=$2

    local cmd
    if [ "$menu_path" == '.' ]; then
        cmd=$(yq ".__cmd__" "$menu_filename")
    else
        cmd=$(yq "${menu_path}.__cmd__" "$menu_filename")
    fi

    if [ ! -z "$cmd" ] && [ "$cmd" != "null" ]; then
        echo "$cmd"
    fi
}

function check_if_one_option() {
    local options
    options=$1

    [ $(echo "$options" | wc -l) -eq 1 ] && echo "true"
}

function get_options() {
    local menu_filename
    menu_filename=$1

    local menu_path
    menu_path=$2

    # get the list of options from the menu file
    local options
    options=$(yq "$menu_path | keys | .[]" "$menu_filename" 2> /dev/null) && {
        # remove __cmd__ from options if it is there
        options=$(echo "$options" | grep -v '__cmd__')

        echo "$options"
    }
}

# append the navigation options to the menu
function append_navigation() {
    local menu_path
    menu_path=$1

    local options
    options=$2

    # otherwise, show the menu; add a newline and quit option
    if [ "$menu_path" == '.' ]; then
        printf -v options "%s\nquit" "$options"
    else
        printf -v options "%s\nquit-back" "$options"
    fi

    echo "$options"
}

# evaluate the category command with the arguments
function eval_cmd() {
    local category_cmd
    category_cmd=$1

    local args
    args=$2

    rm -f /tmp/cmd.sh
    touch /tmp/cmd.sh    
    chmod 600 /tmp/cmd.sh || {
        echo "ERROR: unable to create /tmp/cmd.sh"
        exit 1
    }

    {
        echo "function _cmd() {";
        echo "  $category_cmd";
        echo "}";
        echo "_cmd $args";
    } >> /tmp/cmd.sh

    /bin/bash /tmp/cmd.sh
    rm /tmp/cmd.sh
}

# identify the category command and its arguments, then run it if possible
function apply_cmd() {
    local menu_filename
    menu_filename=$1

    local menu_path
    menu_path=$2

    local category_cmd
    category_cmd=$(get_path_cmd "$menu_filename" "$menu_path")
    if [ ! -z "$category_cmd" ]; then
        local args
        args=$(yq "$menu_path.cmd" "$menu_filename")
        eval_cmd "$category_cmd" "$args"
    else
        echo "ERROR: $menu_path.__cmd__ not found in menu file"
    fi
}

# render the current menu path with fzf and return the user's selection
function get_selection() {
    local menu_filename
    menu_filename=$1

    local menu_path
    menu_path=$2

    local fzf_preview
    fzf_preview=$(get_path_fzf_preview "$menu_path")

    local options
    options=$(get_options "$menu_filename" "$menu_path")

    # if there is only one option, then that is automatically our selection
    if [ "$(check_if_one_option "$options")" ]; then
        echo "$options"
    # otherwise, use fzf to show the menu and obtain the user's selection
    else
        options=$(append_navigation "$menu_path" "$options")
        fzf \
            --height=~75 \
            --margin=4,10,0,10 \
            --no-color \
            --reverse \
            --border=sharp \
            --border-label="╢${menu_path}╟" \
            --border-label-pos=3 \
            --prompt=": " \
            --preview="yq '$fzf_preview.{}' $menu_filename" \
            --preview-window=down:3:wrap \
        <<< "$options"
    fi
}

function render_menu() {
    local menu_filename
    menu_filename=$1

    local menu_path
    menu_path='.'

    while true; do
        local choice
        choice=$(get_selection "$menu_filename" "$menu_path")

        if [ "$choice" == "" ]; then
            exit 0
        fi

        case $choice in
            run)
                /bin/bash -c "$(yq "$menu_path".run "$menu_filename")"
                menu_path='.'
                clear
                ;;
            run-wait)
                /bin/bash -c "$(yq $menu_path.run-wait $menu_filename)"
                read -p "Press enter to continue"
                menu_path='.'
                clear
                ;;
            cmd)
                apply_cmd "$menu_filename" "$menu_path"
                menu_path='.'
                clear
                ;;
            quit)
                exit 0
                ;;
            quit-back)
                menu_path=$(echo "$menu_path" | rev | cut -d. -f2- | rev)
                if [ -z "$MENU_PATH" ]; then
                    menu_path='.'
                fi
                ;;
            *) 
                # otherwise, descend into the next level
                local fzf_preview
                fzf_preview=$(get_path_fzf_preview "$menu_path")
                menu_path="$fzf_preview.$choice"
                ;;
        esac
    done
}

if [ -n "$1" ]; then
    clear
    render_menu "$1"
fi
