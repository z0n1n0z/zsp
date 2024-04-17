#!/bin/bash
#
# ZigzagScan&Print (zsp)
#
# This program is free software: you can redistribute it and/or modify it 
# under the terms of the GNU General Public License as published 
# by the Free Software Foundation; either version 3 of the License, 
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License 
# along with this program. If not, see http://www.gnu.org/licenses/. 
# 
# Copyright (C) 2019: Gianluca Zoni (zoninoz) <zoninoz@inventati.org>
# 
# Gianluca Zoni
# http://inventati.org/zoninoz
# zoninoz@inventati.org
#

TEXT="<b>ZigzagScan&amp;Print (zsp)</b>\n"
ICON="$share"/images/zsp-24x24.png
YAD_ZSP=(
    --window-icon="$ICON"
)
YAD_ZSP_TAB=(
    --text-align=center
    --align=left
    --scroll
    --cycle-read
)
YAD_ZSP_FORM=(
    --separator="\n"
)


function display_console_gui {
    import_all

    local pid=$(get_pid_regex "yad\0--title=Console ZSP\0--image=.+${PWD//\//\\/}\\\n")
    if [[ "$pid" =~ ^[0-9]+$ ]]
    then
        return 1
    fi

    exec 99<&-    
    rm -f ${fifo}099
    mkfifo ${fifo}099
    exec 99<> ${fifo}099
    {
        cat < ${fifo}099 |
            yad --title="ZSP: Console" \
                --image="scriptnew" \
                --text="${TEXT}<i>$(gettext "ZSP process console")</i>\n" \
                --text-info \
                --show-uri \
                --uri-color=blue \
                --tail \
                "${YAD_ZSP[@]}" \
                --button="$(gettext "Clean")!gtk-refresh":"bash -c \"echo -e '\f' >>'$gui_log'\"" \
                --button="$(gettext "Close")!gtk-close:0" \
                --width=800 --height=600 &
        pid=$!
        tail -f "$gui_log" --pid=$pid >> ${fifo}099 2>/dev/null
    } &
}
export -f display_console_gui

function edit_conf_file_gui {
    import_all
    {
        text="$TEXT<i>$(gettext "Edit the configuration file")</i>\n"   
        res=$(yad --title="ZSP: $(gettext "Configuration Editor")" \
                  --image="gtk-edit" \
                  --text="$text" \
                  --text-info \
                  --editable \
                  --show-uri \
                  --uri-color=blue \
                  --listen \
                  --tail \
                  --width=800 --height=600 \
                  --filename="$conf_file" \
                  --width=800 \
                  "${YAD_ZSP[@]}" \
                  --button="$(gettext "Save")!gtk-save":0 \
                  --button="$(gettext "Close")!gtk-close":1)
              
        ret="$?"
        case "$ret" in
            0)
                if [ -n "$res" ]
                then
                    echo "$res" >"$conf_file"
                    init_setting_tabs
                else
                    rm -f "$conf_file"
                fi
                ;;
        esac    
    } &
}
export -f edit_conf_file_gui

function edit_conf_file_dev_gui {
    import_all
    local dev="$1"
    local conf_file_dev="$(get_conf_file_dev "$dev")"
    touch "$conf_file_dev"
    {
        scanner_device="$dev"
        text="$TEXT<i>$(gettext "Edit the configuration file for device")</i>\n<b>$(get_name scanner_device)</b> (${dev//'&'/'&amp;'})\n"       
        local res=$(yad --title="ZSP: $(gettext "Configuration Editor")" \
                        --image="gtk-edit" \
                        --text="$text" \
                        --text-info \
                        --editable \
                        --show-uri \
                        --uri-color=blue \
                        --listen \
                        --tail \
                        --width=800 --height=600 \
                        --filename="$conf_file_dev" \
                        --width=800 \
                        --button="$(gettext "Save")!gtk-save":0 \
                        --button="$(gettext "Close")!gtk-close":2 \
                        "${YAD_ZSP[@]}" 2>/dev/null)
        ret="$?"
        case "$ret" in
            0)
                if [ -n "$res" ]
                then
                    echo "$res" >"$conf_file_dev"
                else
                    rm -f "$conf_file_dev"
                fi
                return 0
                ;;
            2)
                return 1
                ;;
        esac    
    } &
}
export -f edit_conf_file_dev_gui

function brscan_skey_gui {
    import_all
    {
        case "$1" in
            start)
                start_brscan_skey
                ;;
            stop)
                stop_brscan_skey
                ;;
            restart)
                restart_brscan_skey             
                ;;
        esac
    } >>"$gui_log"
}
export -f brscan_skey_gui

function print_file_gui {
    local inputf="$1" type

    if test -f "$inputf"
    then
        local mime=$(file --mime-type "$inputf")
        
        case "$mime" in
            *text*) type=TEXT ;;
            *image*) type=IMAGE ;;
            *) type=RAW ;;
        esac
        yad --title="ZSP: $(gettext "Print")" \
            --print \
            --type="$type" \
            "${YAD_ZSP[@]}" \
            --filename="$inputf" &
        return 0
        
    else
        display_msg_gui \
            "$(gettext "Error: a printable file was not selected")" \
            "gtk-dialog-error"  
        return 1
    fi
    
}
export -f print_file_gui

function display_progress_gui {
    import_all
    local cmd="$2"
    local text="$1"

    exec 88<&-    
    rm -f ${fifo}088
    mkfifo ${fifo}088
    exec 88<> ${fifo}088

    echo >"$gui_log"
    stdbuf -oL -eL \
           awk '{if($0 ~ /^[0-9]+$/){print $0}else{print "# "$0}}' < ${fifo}088 2>>$gui_log |
        yad --title="ZSP: Processing" \
            --class="ZigzagScanPrint-progress" \
            --center \
            --on-top \
            --text="<b>$text</b>" \
            --text-align=center \
            --progress \
            --pulsate \
            --enable-log \
            --log-expanded \
            --width=550 \
            --log-height=350 \
            "${YAD_ZSP[@]}" \
            --button="$(gettext "Cancel")":"bash -c \"kill_cmd_in_progress_gui '$cmd'\"" \
            --button="$(gettext "Close")":0 &
    local yad_pid=$!
    tail -f "$gui_log" --pid=$yad_pid 2>&1 1>> ${fifo}088 &
    local tail_pid=$!

    {
        until get_pid_cmd "$cmd" 
        do
            sleep 0.1
        done
        
        while get_pid_cmd "$cmd"
        do
            sleep 0.1
        done
        kill $tail_pid 2>/dev/null
        for i in 100 100 100
        do
            ## closing pulse alarm:
            #echo "$i" >>${fifo}088
            sleep 1
        done
        kill $yad_pid 2>/dev/null
        for pid in $(awk 'BEGINFILE{if(ERRNO != "")nextfile}/awk/{if ($0 == "awk\0{if($0 ~ /^[0-9]+$/){print $0}else{print \"# \"$0}}\0") {match(FILENAME,/[0-9]+/,matched); print matched[0]}}' /proc/*/cmdline)
        do
            [ -n "$pid" ] &&
                kill $pid
        done
    } #>>$gui_log ## for testing
}
export -f display_progress_gui


# function kill_cmd_in_progress_gui {
#     import_all
#     pkill "$1" && kill "$YAD_PID" 2>/dev/null
# }
# export -f kill_cmd_in_progress_gui

function kill_cmd_in_progress_gui {
    import_all
    local pid
    for pid in $(ps -ef |
                     grep -P "$1" 2>/dev/null |
                     grep -v grep |
                     awk '{print $2}')
    do
        kill "$pid"
    done &&
        kill "$YAD_PID" 2>/dev/null
}
export -f kill_cmd_in_progress_gui

function display_msg_gui {
    local text="$TEXT\n$1" \
          dialog_image="$2"
    
    [ -z "$dialog_image" ] &&
        dialog_image="gtk-dialog-info"

    yad --center \
        --title="ZSP: $(gettext "Message")" \
        --on-top \
        --image="$dialog_image" \
        --text="$text" \
        --fixed \
        --border=5 \
        --height=10 --width=450 \
        "${YAD_ZSP[@]}" \
        --button="$(gettext "Close")":0 &
}
export -f display_msg_gui

function display_question_gui {
    local text="$TEXT\n$1" \
          dialog_image="$2"
    
    [ -z "$dialog_image" ] &&
        dialog_image="gtk-dialog-info"

    yad --center \
        --title="ZSP: $(gettext "Question")" \
        --on-top \
        --image="$dialog_image" \
        --text="$text" \
        --vscroll-policy=never \
        --hscroll-policy=never \
        --border=5 \
        --height=10 --width=450 \
        "${YAD_ZSP[@]}" \
        --button="Yes!gtk-ok":0 \
        --button="No!gtk-no":1
    case "$?" in
        1)
            return 1
            ;;
        0)
            return 0
            ;;
    esac
}
export -f display_question_gui

function display_commands_tab {
    local msg_reconfigure="$(gettext "This operation will delete any user setting: do you really want to continue?")"
    yad --plug=$nbkey \
        --tabnum=1 \
        --form \
        --columns=2 \
        --image="/usr/local/share/zsp/images/zsp-64x64.png" \
        --vscroll-policy=never \
        --hscroll-policy=never \
        --text="<i>$(gettext "Commands")</i>\n" \
        --field="<i>$(gettext "Scan"):</i>":LBL LBL \
        --field="<b>$(gettext "Scan to PC mode:")</b>":CB 'FILE!IMAGE!EMAIL!OCR' \
        --field="$(gettext "Run Scan-to-PC")"'!scanner!'"$(gettext "Run brscan-to-pc mode")":FBTN "bash -c \"run_brscan_to_pc %2 & display_progress_gui 'Scan to PC: %2' $scanner_cmd\"" \
        --field="$(gettext "Open folder")"'!gtk-directory':FBTN "bash -c 'open_dir $directory/'" \
        --field=" ":LBL LBL \
        --field=" ":LBL LBL \
        --field="<i>$(gettext "Server brscan-skey"):</i>":LBL LBL \
        --field="<b>$(gettext "Action"):</b>":CB 'start!stop!restart' \
        --field="$(gettext "Run brscan-skey")"'!network-server!'"$(gettext "Start/Stop/Restart brscan-skey")":FBTN "bash -c 'brscan_skey_gui %8'" \
        --field=" ":LBL LBL \
        --field="<i>$(gettext "Print"):</i>":LBL LBL \
        --field="<b>$(gettext "Select file"):</b>":FL "\--$(gettext "Not selected")--" \
        --field="$(gettext "Set &amp; print")"'!printer!'"$(gettext "Set and print the seleted file")":FBTN "bash -c \"print_file_gui '%12' >>$gui_log\"" \
        --field="$(gettext "Print")"'!printer!'"$(gettext "Print the seleted file")":FBTN "bash -c \"print_pdf '%12' gui >>$gui_log\"" \
        --field="$(gettext "Admin CUPS")"'!printer!'"$(gettext "Print the seleted file")":FBTN "$cmd_open http://localhost:631/printers/$lp_device" \
        --field=" ":LBL LBL \
        --field="<i>$(gettext "Setting commands"):</i>":LBL LBL \
        --field="$(gettext "Edit")"'!gtk-edit!'"$(gettext "Edit the configuration file")":FBTN "bash -c edit_conf_file_gui" \
        --field="$(gettext "Reconfigure")"'!gtk-refresh!'"$(gettext "Set default configuration")":FBTN "bash -c 'display_question_gui \"$msg_reconfigure\" \"gtk-dialog-question\" && reconfigure; init_setting_tabs'" \
        "${YAD_ZSP[@]}" \
        "${YAD_ZSP_TAB[@]}" \
        "${YAD_ZSP_FORM[@]}" 2>/dev/null
}

function load_scanner_tab {
    import_all
    get_configuration
    {
        local scanner_device_list
        while [ -z "$scanner_device_list" ]
        do
            scanner_device_list="$(get_form_list 'scanner_device')"
            sleep 1
        done
        local data="\f
^$filename
LBL
LBL
${directory}
${scanner_device_list}
bash -c \"display_scanner_device_opts %5 \"
LBL
$(get_form_list 'scanner_cmd')
$(get_form_list 'scanner_sides')
$(get_form_list 'scanner_orientation')
$(get_form_list 'scanner_geometry_mode')
LBL
$(get_form_list 'convert_format')
$(get_form_list 'convert_pdf_mode')
LBL
LBL
$convert_clean_up
$lp_print_pdf
LBL
bash -c \"display_email_gui\"
LBL
bash -c \"save_setting_tabs scanner %1 %4 %5 %8 %9 %10 %11 %13 %14 %17 %18\""

        if [ -s "$load_scanner_tab_file" ]
        then
            local data_test
            read -d '' data_test < "$load_scanner_tab_file"

            if [ "$data" != "$data_test" ]
            then
                echo -e "$data" |tee "$load_scanner_tab_file"
            fi
        else
            echo -e "$data" |tee "$load_scanner_tab_file"
        fi
        
    } >> ${fifo}011
    ## se ci sono spazi --e solo in quel caso!-- yad aggiunge gli apici: attenzione nel ciclarli con un array!
}
export -f load_scanner_tab

function display_scanner_tab {
    exec 11<&-    
    rm -f ${fifo}011
    mkfifo ${fifo}011
    exec 11<> ${fifo}011
    cat ${fifo}011 |
        yad --plug=$nbkey \
            --tabnum=2 \
            --form \
            --columns=2 \
            --cycle-read \
            --image="scanner" \
            --vscroll-policy=never \
            --hscroll-policy=never \
            --text="<i>$(gettext "Scanner settings")</i>\n" \
            --field="<b>$(gettext "Filename:")</b>":CE \
            --field="<i>\t\t$(gettext "If empty, it will be like this"):\t </i>$(date | sed -r 's|[ :,]+|_|g')\t ":LBL \
            --field=' ':LBL \
            --field="<b>$(gettext "Folder:")</b>":DIR \
            --field="<b>$(gettext "Device:")</b>":CB \
            --field="<b>$(gettext "Device settings")</b>"'!scanner':FBTN \
            --field=" ":LBL \
            --field="<b>$(gettext "Program:")</b>":CB \
            --field="<b>$(gettext "Sides:")</b>":CB \
            --field="<b>$(gettext "Orientation:")</b>":CB \
            --field="<b>$(gettext "Geometry mode:")</b>":CB \
            --field="<i>$(gettext "File convertion:")</i>":LBL \
            --field="<b>$(gettext "File format:")</b>":CB \
            --field="<b>$(gettext "PNM to PDF mode:")</b>":CB \
            --field=' ':LBL \
            --field="<i>$(gettext "Final operations:")</i>":LBL \
            --field="$(gettext "Delete temporary files")":CHK \
            --field="$(gettext "Print PDF")":CHK \
            --field=' ':LBL \
            --field="<b>$(gettext "Email settings")</b>"'!emblem-mail':FBTN \
            --field=' ':LBL \
            --field="<b>$(gettext "Save")</b>"'!gtk-save':FBTN \
            "${YAD_ZSP[@]}" \
            "${YAD_ZSP_TAB[@]}" \
            "${YAD_ZSP_FORM[@]}" & 
    load_scanner_tab
}

function display_email_gui {
    import_all
    get_configuration
    {
        oIFS="$IFS"
        IFS="
"
        res=($(yad --title="ZSP: $(gettext "Mail manager")" \
                   --form \
                   --columns=1 \
                   --center \
                   --on-top \
                   --borders=10 \
                   --width=500 \
                   --vscroll-policy=never \
                   --hscroll-policy=never \
                   --image="emblem-mail" \
                   --text="<b>$(gettext "<i>SCAN-TO-PC EMAIL</i> settings")</b>\n" \
                   --field="$(gettext "Sender email/Username")":CE "^$email_username" \
                   --field="$(gettext "Password")":H "$email_password" \
                   --field="$(gettext "Server address")":CE "^$email_server" \
                   --field="$(gettext "Server port")":CB "^$email_port!587!465!25" \
                   --field="$(gettext "Recipient email")":CE "^$email_recipient" \
                   --button="$(gettext "Save")"'!gtk-save!'"$(gettext "Save")":0 \
                   --button="$(gettext "Close")"'!gtk-close!'"$(gettext "Don't save and exit")":2 \
                   "${YAD_ZSP[@]}" \
                   "${YAD_ZSP_TAB[@]}" \
                   "${YAD_ZSP_FORM[@]}"))
        ret="$?"
        IFS="$oIFS"
        case "$ret" in
            0)
                set_conf email_username "${res[0]}"
                set_conf email_password "${res[1]}"
                set_conf email_server "${res[2]}"
                set_conf email_port "${res[3]}"
                set_conf email_recipient "${res[4]}"
                if test "${res[3]}" == 465
                then
                    email_proto="smtps"
                else
                    email_proto="smtp"
                fi
                set_conf email_proto "$email_proto"
                ;;
        esac
    } &

}
export -f display_email_gui

function display_scanner_device_opts {
    import_all

    local name_dev="$1" field_value type
    local scanner_dev=$(get_value scanner_device "$name_dev")
    local scanner_dev_sanitized="${scanner_dev//'&'/'&amp;'}"

    conf_file_dev="$(get_conf_file_dev "$scanner_dev")"
    [ -s "$conf_file_dev" ] &&
        source "$conf_file_dev" ||
            echo 'scanner_source=""' >"$conf_file_dev"

    source "$share"/data.sh
    get_default_values_scanner "$scanner_dev"

    if [ -n "$scanner_dev" ]
    then
        declare -a scanner_device_fields=()
        while read line
        do
            field_value=$(get_form_list scanner_"${line//\-/_}" "$line" "$scanner_dev")
            
            if [[ "$field_value" =~ [0-9\-]+\.\.[0-9\-]+ ]]
            then
                type=NUM
            else
                type=CB
            fi

            scanner_device_fields+=(
                --field="<b>$(tr '[:lower:]' '[:upper:]' <<< "${line:0:1}")${line:1}</b>":"$type" "$field_value"
            )
        done < <(get_scanner_device_options "$scanner_dev")
        
        if [ -z "${scanner_device_fields[*]}" ]
        then
            display_msg_gui "$(gettext "Scanner device not found")"
            return 1
        fi
        
        scanner_device_fields+=(
            --field=" ":LBL LBL
            --field="<i>$(gettext "Scan-area geometry") (mm):</i>":LBL LBL
        )

        local item label
        for item in l t x y
        do
            case "$item" in
                l)
                    label="<b>$(gettext "Left"):</b>"
                    ;;
                t)
                    label="<b>$(gettext "Top"):</b>"
                    ;;
                x)
                    label="<b>$(gettext "Width"):</b>"
                    ;;
                y)
                    label="<b>$(gettext "Height"):</b>"
                    ;;
            esac

            scanner_device_fields+=(
                --field="$label":NUM "$(get_form_list scanner_$item $item $scanner_dev)"
            )
        done
    fi

    if [ -z "${scanner_device_fields[*]}" ]
    then
        display_msg_gui "$(gettext "Scanner device not found")"
        return 1
    fi
    
    {
        oIFS="$IFS"
        IFS="
"
        res=($(yad --title="ZSP: $(gettext "Device manager")" \
                   --form \
                   --columns=1 \
                   --center \
                   --on-top \
                   --borders=10 \
                   --width=600 \
                   --vscroll-policy=never \
                   --hscroll-policy=never \
                   --image="scanner" \
                   --text="<i>$(gettext "Options specific to device")</i>\n<b>$name_dev</b>\n(${scanner_dev_sanitized})\n" \
                   "${scanner_device_fields[@]}" \
                   --button="$(gettext "Edit")"'!gtk-edit!'"$(gettext "Edit the configuration file")":1 \
                   --button="$(gettext "Save")"'!gtk-save!'"$(gettext "Save")":0 \
                   --button="$(gettext "Close")"'!gtk-close!'"$(gettext "Don't save and exit")":2 \
                   "${YAD_ZSP[@]}" \
                   "${YAD_ZSP_TAB[@]}" \
                   "${YAD_ZSP_FORM[@]}"))
        ret="$?"
        IFS="$oIFS"
        case "$ret" in
            0)
                get_conf_vars_scanner_spec "$scanner_dev"
                for ((i=0; i<"${#res[@]}"; i++))
                do
                    if test "${res[i]}" != LBL
                    then
                        if [[ "${res[i]}" =~ ^([0-9,]+)$ ]]
                        then
                            res[i]="${res[i]//\,/.}"

                        elif [ "${res[i]}" == "-- default --" ]
                        then
                            res[i]=""
                        fi
                        set_conf "${conf_vars_scanner_spec[i]}" "${res[i]}" "$scanner_dev"
                    fi
                done
                ;;
            1)
                edit_conf_file_dev_gui "$scanner_dev"
                ;;
        esac
    } &
}
export -f display_scanner_device_opts


function load_printer_tab {
    import_all
    get_configuration
    local field_print_pdf=$(tr '[:lower:]' '[:upper:]' <<< "$lp_print_pdf")    
    {
        echo -e "\f
$(get_form_list 'lp_device')
$(get_form_list 'lp_page_set')
$lp_pages
$(get_form_list 'lp_sides')
$lp_copies
LBL
bash -c \"save_setting_tabs printer %1 %2 %3 %4 %5 \""
        
    } >> ${fifo}022 
}
export -f load_printer_tab

function display_printer_tab {
    exec 22<&-    
    rm -f ${fifo}022
    mkfifo ${fifo}022
    exec 22<> ${fifo}022
        
    cat ${fifo}022 |
    yad --plug=$nbkey \
        --tabnum=3 \
        --form \
        --columns=1 \
        --cycle-read \
        --image="printer" \
        --text="<i>$(gettext "Printer settings")</i>\n" \
        --field="<b>$(gettext "Device:")</b>":CB \
        --field="<b>$(gettext "Page set:")</b>":CB \
        --field="<b>$(gettext "Pages:")</b>":CE \
        --field="<b>$(gettext "Sides:")</b>":CB \
        --field="<b>$(gettext "Copies:")</b>":NUM \
        --field=' ':LBL \
        --field="<b>$(gettext "Save")</b>":FBTN \
        "${YAD_ZSP[@]}" \
        "${YAD_ZSP_TAB[@]}" \
        "${YAD_ZSP_FORM[@]}" &
    load_printer_tab
}

function display_console_tab {
    exec 99<&-
    touch "$gui_log"    
    rm -f ${fifo}099
    mkfifo ${fifo}099
    exec 99<> ${fifo}099
    #   --image="scriptnew" \

    local text=$(gettext "Process console")
    yad --plug=$nbkey \
        --tabnum=4 \
        --image="utilities-terminal" \
        --show-cursor \
        --text="<i>$text</i>" \
        --text-info \
        --show-uri \
        --back=black --fore='#C0C0C0' \
        --wrap \
        --uri-color=blue \
        --tail \
        "${YAD_ZSP[@]}" \
        "${YAD_ZSP_TAB[@]}" < ${fifo}099 2>/dev/null &
    pid=$!    
    tail -f "$gui_log" --pid=$pid >> ${fifo}099 2>/dev/null
}

function update_zsp_gui {
    import_all
    update_zsp gui & display_progress_gui "$(gettext "Updating ZigzagScan&Print")" 'bash -c update_zsp_gui' &
}
export -f update_zsp_gui

function display_main_gui {
    local text="${TEXT}<i>$(gettext "Commands and settings")</i>\n"
    nbkey=$(($RANDOM * $$))
    
    get_configuration
    {
        display_commands_tab & \
            display_scanner_tab & \
            display_printer_tab & \
            display_console_tab & \
            yad --class="ZigzagScanPrint" \
                --center \
                --notebook \
                --vscroll-policy=never \
                --hscroll-policy=never \
                --key=$nbkey \
                --tab="$(gettext "Commands")" \
                --tab="$(gettext "Scanner settings")" \
                --tab="$(gettext "Printer settings")" \
                --tab="$(gettext "Console")" \
                --title="ZigzagScan&Print (ZSP)" \
                --image="/usr/local/share/zsp/images/zsp-header.png" \
                --image-on-top \
                --height=650 \
                --width=800 \
                --button="$(gettext "Clean console")!gtk-refresh":"bash -c \"echo -e '\f' >>'$gui_log'\"" \
                --button="$(gettext "Update ZSP")!gtk-save":"bash -c update_zsp_gui" \
                --button="$(gettext "Quit")"'!gtk-close':0 \
                "${YAD_ZSP[@]}"
            case "$?" in
                0)
                    for pid in $(awk 'BEGINFILE{if(ERRNO != "")nextfile} /cat\0\/tmp\/zsp\/fifo/{match(FILENAME, /[0-9]+/, matched); print matched[0]}' /proc/[0-9]*/cmdline)
                    do
                        [[ "$pid" =~ ^([0-9]+)$ ]] &&
                            kill $pid
                    done
                ;;
            esac
    } &>/dev/null &
    pid_prog=$!
    get_devices_in_loop 
}

function open_dir {
    import_all
    get_configuration

    if [ -d "$1" ]
    then
        $filemanager "$1" 2>&1 1>/dev/null ||
            $cmd_open "$1" 2>&1 1>/dev/null 
    fi
}
export -f open_dir

function run_gui {
    hash yad &>/dev/null ||
        exit 1

    path_tmp="/tmp/$prog"
    mkdir -p "$path_tmp"
    
    rm -f "$lp_devfile" "$scanner_devfile"
    kill_fifo_all
    display_main_gui
}


function get_form_list {
    local var="$1" \
          opt="$2" \
          scanner_dev="$3" \
          name form_type

    declare -n val="$var"    
    declare -a names=()
    local default="$(get_name "$var")"

    if [ -n "$default" ]
    then
        names=( "^$default" )
    fi
    
    if [ -n "$val" ]       
    then
        [ "$var" == scanner_device ] && [ -z "$default" ] &&
            names=( "^${val:0:40}" )

    else        
        [ "$var" == lp_page_set ] &&
                names=( "^$(gettext All)" ) ||
                    names=( "^-- default --" )
    fi
    
    case "$var" in
        scanner_device)
            declare -a names_scanner=()
            if [ -s "$scanner_data_file" ]
            then
                while read line
                do
                    if [[ "$line" =~ ^(NAME\=\'.+\') ]]
                    then
                        eval "${BASH_REMATCH[1]}"
                        test_scanner_options=$(get_scanner_device_options "$(get_value scanner_device "$NAME")")
                        
                        if [ -n "$test_scanner_options" ]
                        then
                            check_value_in_array "^$NAME" "${names[@]}" ||
                                names_scanner+=( "$NAME" )
                        fi
                        unset NAME test_scanner_options
                    fi
                    
                done < "$scanner_data_file"
            fi

            if (( "${#names_scanner[@]}" >0))
            then
                names+=( "${names_scanner[@]}" )
            fi

            if [ -z "${names[*]}" ]
            then
                names=( "$waiting_devices_msg" )
            fi

            ;;  
        scanner_cmd)
            for item in scanimage scanadf
            do
                check_value_in_array "^$item" "${names[@]}" ||
                    names+=( "$item" )
            done
            ;;
        scanner_sides)
            for item in "$(gettext "One sided")" "$(gettext "Two sided")" 
            do
                check_value_in_array "^$item" "${names[@]}" ||
                    names+=( "$item" )
            done
            ;;
        scanner_orientation)
            for item in "$(gettext "Portrait")" "$(gettext "Landscape")"
            do
                check_value_in_array "^$item" "${names[@]}" ||
                    names+=( "$item" )
            done
            ;;
        scanner_geometry_mode)
            for item in "normal" "brother-adf-a4" "rescaling-a4" 
            do
                check_value_in_array "^$item" "${names[@]}" ||
                    names+=( "$item" )
            done
            ;;
        convert_format)
            if [ "$scanner_cmd" == scanimage ]
            then
                for item in tiff pdf pnm jpeg png
                do
                    check_value_in_array "^$item" "${names[@]}" ||
                        names+=( "$item" )
                done        

            elif [ "$scanner_cmd" == scanadf ]
            then
                names=()
                for item in pnm pdf
                do
                    check_value_in_array "^$item" "${names[@]}" ||
                        names+=( "$item" )
                done
            fi
            ;;
        convert_pdf_mode)
            for item in "resampling" "normal" "rescaling-1" "rescaling-2" 
            do
                check_value_in_array "^$item" "${names[@]}" ||
                    names+=( "$item" )
            done            
            ;;
        lp_device)
            if [ -s "$lp_devfile" ]
            then
                local out=$(awk -v d="$lp_device" '!/destination/&&(NR%2){if($0 == d){prefix="^"}else{prefix=""};if(a==""){a=prefix$0}else{a=a"!"prefix$0}}END{printf a}' "$lp_devfile")
            fi
            [ -z "$out" ] &&
                echo -e "$waiting_devices_msg" ||
                    echo -e "$out"
            return
            ;;
        lp_page_set)
            for item in "$(gettext "All")" "$(gettext "Even")" "$(gettext "Odd")"
            do
                check_value_in_array "^$item" "${names[@]}" ||
                    names+=( "$item" )          
            done
            ;;      
        lp_sides)
            for item in "$(gettext "One sided")" "$(gettext "Two sided - Portrait")" "$(gettext "Two sided - Landscape")"
            do
                check_value_in_array "^$item" "${names[@]}" ||
                    names+=( "$item" )
            done
            ;;
        scanner_*)
            if [ -n "$scanner_dev" ] &&
                   [ -n "$opt" ]
            then
                case "$opt" in
                    l|t|x|y)
                        names=($(get_scanner_geometry_values "$scanner_dev" "$opt"))
                        declare -n ref_varopt="scanner_$opt"
                        test -n "$ref_varopt" &&
                            names[0]="$ref_varopt"
                        (( "${#names[@]}" >3 )) &&
                            names[3]=7
                        ;;
                    *)
                        while read line
                        do
                            [ "$opt" == resolution ] && line="${line%dpi}"
                            
                            check_value_in_array "$line" "${names[@]}" ||
                                names+=( "$line" )

                            if [[ "$line" =~ [0-9]+\.\.[0-9]+ ]]
                            then
                                names[0]="${names[0]#^}"
                                if [[ ! "${names[0]}" =~ ^([0-9.]+)$ ]]
                                then                                
                                    names[0]="${default_values[$var]}"
                                fi
                                form_type=NUM
                                [ "${default_values[$var]}" == inactive ] && break
                            fi
                            
                        done < <(get_scanner_option_values "$scanner_dev" "${opt}")
                        ;;
                esac
            fi
            ;;
    esac

    if [ "${default_values[$var]}" == inactive ]
    then
        names+=( "@disabled@" )

    elif [ "${names[0]}" != "$waiting_devices_msg" ] &&
             [ "$form_type" != NUM ]
    then
        names+=( "-- default --" )
    fi

    local pattern
    if (( ${#names[@]} >0 ))
    then

        for ((i=0; i<${#names[@]}; i++))
        do
            if [ -n "$pattern" ]
            then
                pattern+="!"
            fi
            pattern+="%s"
        done
        printf "$pattern" "${names[@]}"
    fi
}

function get_devices_in_loop {
    local test1 test2 winid scanner_data_counter=0
    until [ -n "$winid" ]
    do
        winid=$(get_main_winid)
        sleep 0.1
    done

    while [ -n "$(get_main_winid)" ] &&
              check_pid "$pid_prog"
    do
        test_printer1="$(get_form_list lp_device)"
        get_printer_devices     
        test_printer2="$(get_form_list lp_device)"

        if [ "$test_printer1" != "$test_printer2" ]
        then
            load_printer_tab
        fi

        test_scanner1="$(get_form_list scanner_device)"
        get_scanner_data_file "$scanner_data_counter" scanner_data_counter 
        test_scanner2="$(get_form_list scanner_device)"

        if [ "$test_scanner1" != "$test_scanner2" ]
        then
            load_scanner_tab
        fi

        sleep 3
    done &    
}

function init_setting_tabs {
    import_all
    get_configuration
    mkdir -p "$directory"
    cd "$directory"
    load_scanner_tab
    load_printer_tab
}
export -f init_setting_tabs

function save_setting_tabs {
    import_all
    
    local item="$1" var i
    shift    
    declare -a names=( "$@" )

    ## set_value {var} {name}:
    case "$item" in
        scanner)
            vars=( "${conf_vars_scanner[@]}" )
            ;;
        printer)
            vars=( "${conf_vars_printer[@]}" )
            ;;
    esac
    for ((i=0; i<${#vars[@]}; i++))
    do
        names[i]="${names[i]//\'}"

        set_value "${vars[i]}" "${names[i]}"

        declare -n val="${vars[i]}"
        set_conf "${vars[i]}" "$val"
    done
    
    init_setting_tabs
}
export -f save_setting_tabs

function kill_fifo_all {
    for pid_fifo in $(ps -ef | grep -F 'cat /tmp/zsp' | grep -v grep | awk '{print $2}')
    do
        kill -9 $pid_fifo
    done
    
    for pid_fifo in $(ps -ef | grep -F 'awk {if($0 ~ /^[0-9]+$/){print $0}else{print "# "$0}}' | grep -v grep | awk '{print $2}')
    do
        kill -9 $pid_fifo 
    done
                    
    {
        exec 11<&-
        exec 22<&-
        exec 88<&-
        exec 99<&-
    } 
    rm -f ${fifo}099 ${fifo}088 ${fifo}011 ${fifo}022
}


