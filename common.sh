#!/bin/bash
#
# project: ZigzagScan&Print (zsp)
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

TEXTDOMAINDIR=/usr/local/share/locale
TEXTDOMAIN=zsp
export TEXTDOMAINDIR
export TEXTDOMAIN
source /usr/bin/gettext.sh

share="/usr/local/share/zsp"

tmp_path="/tmp/$TEXTDOMAIN"
mkdir -p "$tmp_path"
gui_log="$tmp_path"/gui.log
touch "$gui_log"
load_scanner_tab_file="$tmp_path"/load_scanner_tab_data.txt
load_printer_tab_file="$tmp_path"/load_printer_tab_data.txt

conf_path="$HOME"/.$TEXTDOMAIN
mkdir -p "$conf_path"/scanner
conf_file="$conf_path"/$TEXTDOMAIN.conf

ls -1 /opt/brother/scanner/brscan-skey/brscan-skey*.cfg &>/dev/null &&
    ext=cfg ||
        ext=config

brscan_skey_cfg=$(ls -1 /opt/brother/scanner/brscan-skey/brscan-skey*.$ext | tail -n1)

url_path="https://www.inventati.org/zoninoz/$TEXTDOMAIN"
updater="${TEXTDOMAIN}_install.sh"

## odd lines: NAME, even lines: VALUE
#scanner_devfile="$tmp_path"/scanner_devices.txt
lp_devfile="$tmp_path"/lp_devices.txt

scanner_data_file="$tmp_path"/scanimage_data.txt
touch "$scanner_data_file"

fifo="$tmp_path"/fifo

pnmflip=$(command -v pnmflip 2>/dev/null)
test -x "$pnmflip" || {
    pnmflip=$(command -v pamflip 2>/dev/null) || {
            echo "$(gettext "Error: pnmflip/pamflip not found. Install netpbm package first.")"
            exit 1
    }
}

test -f "$share"/data.sh && source "$share"/data.sh

declare -ga conf_vars_scanner=(
    filename
    directory
    scanner_device
    scanner_cmd
    scanner_sides
    scanner_orientation
    scanner_geometry_mode
    convert_format
    convert_pdf_mode
    convert_clean_up
    lp_print_pdf
)

declare -ga conf_vars_email=(
    email_username
    email_password
    email_server
    email_port
    email_proto
    email_recipient
)

declare -ga conf_vars_printer=(
    lp_device
    lp_page_set
    lp_pages
    lp_sides
    lp_copies
)

declare -ga conf_vars=(
    filemanager
    "${conf_vars_scanner[@]}"
    "${conf_vars_email[@]}"
    "${conf_vars_printer[@]}"
)

function init_values {
    local scanner_dev="$1"
    
    local var ref_old
    ## scanner_device='brother4:net1;dev0' for BrotherL2710DW
    
    [ -n "$scanner_dev" ] &&
        scanner_device="$scanner_dev"

    [ -z "$scanner_device" ] &&
        scanner_device="${default_values[scanner_device]}"
    
    conf_vars=(
        filemanager
        "${conf_vars_scanner[@]}"
        "${conf_vars_email[@]}"
        "${conf_vars_printer[@]}"
    )
    get_conf_vars_scanner_spec "$scanner_device"

    [ -f "$share"/data.sh ] &&
        source "$share"/data.sh
    get_default_values_scanner "$scanner_device"

    conf_file_dev="$(get_conf_file_dev "$scanner_device")"
    [ -s "$conf_file_dev" ] && source "$conf_file_dev"

    for var in "${conf_vars[@]}" "${conf_vars_scanner_spec[@]}" 
    do
        declare -n ref="$var"
        if ( [ -z "$ref" ] && [ "$var" != scanner_source ] ) ||
               [ "${default_values[$var]}" == inactive ]
        then
            ref="${default_values[$var]}"
        fi
    done
}

function get_configuration {
    local scanner_dev="$1"
    [ -s "$conf_file" ] || configure

    ## old scanner dev setting:
    local var
    get_conf_vars_scanner_spec "$scanner_device"
    for var in "${conf_vars_scanner_spec[@]}"
    do
        unset $var
    done

    source "$conf_file"
    # [ -n "$scanner_dev" ] &&
    #   init_values "$scanner_dev" ||
    init_values "$scanner_dev"

    export waiting_devices_msg="$(gettext "No device found: ... wait ...")"

    [ -n "$directory" ] && [ -d "$directory" ] ||
        directory="${default_values[directory]}"

    for cmd_open in kde-open gnome-open xfce-open xdg-open
    do
        if hash $cmd_open 2>/dev/null
        then
            break
        else
            unset cmd_open
        fi
    done

    hash "$filemanager" 2>/dev/null || 
        filemanager="$cmd_open"
    
    if [ -z "$lp_device" ]
    then
        if hash lpstat &>/dev/null
        then
            # lpstat -a | grep -oP '[^0-9 ]+2710[^0-9 ]+' | head -n1
            lp_device=$(lpstat -t |grep -oP '[^ :]+\:\ ipp://BrotherL2710DW.local:631/ipp/print' |cut -d':' -f1)
        else
            echo "$(gettext "lpstat: command not found")" | tee -a "$gui_log"
        fi
    fi

    #### IMPORTANTE:
    ## è necessario indicare la geometria del formato A4, altrimenti lo scanner
    ## scansionerà anche una superficie intorno, definita dalle impostazioni
    ## predefinite di scanner (scanner --help --device ...)
    ##
    ## rescaling-a4: x=210 y=297 mm
    ## => ricalcolati in proporzione per riprodurre identico
    ## l'input cartaceo in pdf e nella stampa:
    ## l=2.95 x=203 y=287
    ## (la scansione ADF ruba qualche millimetro in alto tagliandolo in basso)

    case "$scanner_geometry_mode" in
        normal)
            if test -n "$scanner_geometry"
            then
                scanner_geometry="-t $scanner_t -l $scanner_l -y $scanner_y -x $scanner_x"
            fi
            ;;
        brother-adf-a4)
            scanner_geometry="-t 0 -l 2.95 -x 203 -y 287"
            ;;
        rescaling-a4)
            scanner_geometry="-t 0 -l 2.95 -x 210 -y 297"
            ;;
    esac
       
    if [ "$convert_format" == pdf ] ||
           [ -z "$convert_format" ]
    then
        [ "$scanner_cmd" == scanimage ] && scanner_format=tiff
        [ "$scanner_cmd" == scanadf ] && scanner_format=pnm
    else
        [ "$scanner_cmd" == scanadf ] &&
            scanner_format=pnm ||
                scanner_format="$convert_format"
    fi
}

function update_zsp {
    ui_type="$1"
    
    import_all
    if [ "$ui_type" == gui ]
    then
        wget --user-agent='' "$url_path/$updater" -O "$tmp_path"/"$updater" -o "$gui_log"
    else
        wget --user-agent='' "$url_path/$updater" -O "$tmp_path"/"$updater"
    fi
    
    echo "UPDATER: $tmp_path/$updater"

    if test -s "$tmp_path"/"$updater"
    then
        source "$tmp_path"/"$updater" &&
            exit 0 || exit 1
    fi
}
export -f update_zsp

function configure {
    if [ ! -s "$conf_file" ]
    then
        local default_conf=TRUE

        test -d "$directory" ||
            directory="${default_values[directory]}"

        if [[ "$LANG" =~ ^it ]]
        then
            cat > "$conf_file" <<EOF
#### Configurazione di ZigzagScan&Print (zsp) by zoninoz
##
## path dello script: /usr/local/bin/
## comando di riconfigurazione (predefinita): zsp --reconfigure
##
################## ISTRUZIONI: ##################################################
##
## Per assegnare valori alle variabili, cancellare il carattere '#' che le precede 
## e scrivere il valore tra le virgolette subito dopo '=' 
## (senza spazi intorno a '='), es.:
##
##   variabile="valore" 
##
## Tutto ciò che è scritto dopo '#' viene ignorato dal programma: 
## si può disabilitare l'assegnamento di una variabile 
## anteponendole il carattere '#'. 
## Ogni variabile disabilitata/vuota/nulla assumerà il valore predefinito 
## delle applicazioni in uso, indicato tra parentesi quadre. 
## Anche in queste istruzioni, il carattere jolly '*' sta per 'qualunque altra cosa'.
##
#################################################################################

#### nome del file riformattato oppure
## prefisso dei file immagine seguito da numerazione progressiva:

filename=""

#### directory di lavoro
## valori: [ $HOME/brscan ] | *

directory=""

#### filemanager
## valori: [ kde-open | gnome-open | xfce-open | xdg-open ] | *

filemanager=""

#### dispositivo scanner

scanner_device=""

#### programma per la scansione:
## valori: [ scanimage ] | scanadf

scanner_cmd=""

#### scansiona un-lato/fronte-retro
## valori: 
## [ one-sided ] | two-sided

scanner_sides=""

#### orienta la pagina
## valori: 
## [ portrait ] | landscape

scanner_orientation=""

#### modalità geometria:
## valori: [ normal ] | brother-adf-a4 | rescaling-a4

scanner_geometry_mode=""

#### IMPOSTAZIONI PER POST-PROCESSARE L'INPUT:

#### formato di output: 
## valori: [ tiff ] | pnm | jpeg | png | pdf

convert_format=""

#### tipo di post-processo per la riformattazione in PDF
## valori: resampling | [ normal ] | rescaling-1 | rescaling-2

convert_pdf_mode=""

#### cancella i file temporanei di riformattazione
## valori: 
## [ TRUE ] | FALSE

convert_clean_up=""

#### stampa il PDF
## valori: 
## TRUE | [ FALSE ]

lp_print_pdf=""

#### printer device / dispositivo stampante
## scegli un valore generato da:
## lpstat -a

lp_device=""

#### stampa set pari/dispari
## valori:
## even | odd | [ * ]

lp_page_set=""

#### stampa pagine
## valori, es.:
## 1-24,53,67-69
## se nullo, le stampa tutte

lp_pages=""

#### stampa un-lato/fronte-retro
## valori: 
## [ one-sided ] | two-sided-long-edge | two-sided-short-edge 

lp_sides=""

#### numero copie
## valori: [ 1 ] | altro numero

lp_copies=""

#### brscan_to_pc EMAIL:

## mittente:
## username e password 
## di registrazione al server smtp (di invio)

email_username=""
email_password=""

## destinatario

email_recipient=""

## protocollo: 
## smtp | smtps ("s" = sicuro: TLS/SSL/startTLS)

email_proto=""

## indirizzo e porta server smtp

email_server=""

## porta:
## 587 (non sicuro) | 465 (sicuro) 

email_port=""

EOF
        else
            cat > "$conf_file" <<EOF
#### Configuration of ZigzagScan&Print (zsp) by zoninoz
##
## script path: /usr/local/bin/
## reconfiguration command (default): zsp --reconfigure
##
################## INSTRUCTIONS: ################################################
##
## To assign values to variables, delete the preceding '#' character
## and write the value in quotes immediately after '='
## (without spaces around '='), eg:
##
## variable = "value"
##
## Everything written after '#' is ignored by the program:
## you can disable the assignment of a variable
## putting the '#' character in front of it.
## Each variable disabled/empty assumes the default value
## of the applications in use, indicated in square brackets.
## Also in these instructions, the wildcard '*' stands for 'anything else'.
##
#################################################################################

#### Reformatted file name or
## image file prefix followed by progressive numbering:

filename=""

#### working directory
## values: [ $HOME/brscan ] | *

directory=""

#### filemanager
## values: [ kde-open | gnome-open | xfce-open | xdg-open ] | *

filemanager=""

#### scanner device

scanner_device=""

#### program for scanning:
## values: [scanimage] | scanadf

scanner_cmd=""

#### one-sided/two-sided scanning
## values:
## [one-sided] | two-sided

scanner_sides=""

#### orients the page
## values:
## [portrait] | landscape

scanner_orientation=""

#### geometry mode:
## values: [ normal ] | brother-adf-a4 | rescaling-a4

scanner_geometry_mode=""

#### SETTINGS FOR POST-PROCESSING INPUT:

#### output format:
## values: [ tiff ] | pnm | jpeg | png | pdf

convert_format=""

#### type of post-process for PDF reformatting
## values: resampling | [ normal ] | rescaling-1 | rescaling-2

convert_pdf_mode=""

#### deletes temporary reformatting files
## values:
## [TRUE] | FALSE

convert_clean_up=""

#### print the PDF
## values:
## TRUE | [FALSE]

lp_print_pdf=""

#### printer device / printer device
## Choose a value generated by:
## lpstat -a

lp_device=""

#### print set odd / even
## values:
## even | odd | [*]

lp_page_set=""

#### print pages
## values, eg:
## 1-24,53,67-69
## if null, prints them all

lp_pages=""

#### one-sided/two-sided printing
## values:
## [ one-sided ] | two-sided-long-edge | two-sided-short-edge 

lp_sides=""

#### number of copies
## values: [1] | other number

lp_copies=""

#### brscan_to_pc EMAIL:

## sender:
## username and password
## registration to the smtp server (sending)

email_username=""
email_password=""

## recipient

email_recipient=""

## protocol:
## smtp | smtps ("s"=secure: TLS/SSL/startTLS)

email_proto=""

## address and smtp server port

EMAIL_SERVER=""

## server port:
## 587 (not safe) | 465 (secure)

email_port=""

EOF
        fi
    fi
    {
        echo
        date
        echo "$0 conf: $conf_file"

        configure_brscan_skey
        
    } 2>&1 | tee -a "$gui_log"
    
    [ "$default_conf" == TRUE ] || editor "$conf_file"
}

function configure_brscan_skey {
    #declare -n ref="$1"

    echo "brscan-skey.cfg: $brscan_skey_cfg"
    for item in FILE EMAIL IMAGE OCR
    do
        brscanopt=$(tr '[:upper:]' '[:lower:]' <<< "$item")
        if ! grep -qP "^$item=\"/usr/local/share/zsp/brscan_to_pc_$brscanopt\"" "$brscan_skey_cfg"
        then
            common_try sed -r "s|^$item=|#$item=|g" -i "$brscan_skey_cfg"
            
            echo -e "$(gettext "Configuration"):"
            echo "$item=\"/usr/local/share/zsp/brscan_to_pc_$brscanopt\"" | sudo tee -a "$brscan_skey_cfg"
            #ref=true
        fi
    done
}

function set_conf {
    {
        local conf_var="$1" \
              conf_val="$2" \
              dev="$3" \
              conf_source conf_file_to_set

        if [ -n "$dev" ]
        then
            conf_file_to_set="$(get_conf_file_dev "$dev")"
            touch "$conf_file_to_set"
        else
            conf_file_to_set="$conf_file"
        fi

        get_configuration
        get_conf_vars_scanner_spec "$dev"
        
        if check_val_in_array "$conf_var" "${conf_vars[@]}" ||
                check_val_in_array "$conf_var" "${conf_vars_scanner_spec[@]}"
        then
            declare -n conf_ref="$conf_var"
            conf_val_old="$conf_ref"
            
            read -d '' conf_source < "$conf_file_to_set"

            if [ "$conf_val" != "$conf_val_old" ]
            then
                if [[ ! "$conf_source" =~ ^[\ ]*"$conf_var=\"$conf_val\"" ]]
                then
                    sed -r "s|^[\ ]*($conf_var\=)\".*\"|\1\"${conf_val//\&/\\&}\"|g" -i "$conf_file_to_set"
                fi

                if [[ ! "$conf_source" =~ ^[\ ]*"$conf_var=\"$conf_val\"" ]]
                then
                    echo "$conf_var=\"$conf_val\"" >> "$conf_file_to_set"
                fi

                awk '!($0 in a) || /^(|[ ]*#.+)$/{a[$0]; print}' "$conf_file_to_set" >"$conf_file_to_set".bak
                mv "$conf_file_to_set".bak "$conf_file_to_set"

                echo -e "\n$(date) $conf_file_to_set:\n$conf_var=\"$conf_val_old\" --> $conf_var=\"$conf_val\""
            else
                echo -e "\n$(date) $conf_file_to_set:\n$(gettext "Value already set"): $conf_var=\"$conf_val_old\""             
            fi
            return 0

        else
            echo -e "\n$(date) $conf_file_to_set:\n$(eval_gettext "Error: \$conf_var does not exist\nAvailable parameters"): ${conf_vars[@]}"
            return 1
        fi

    } 2>&1 | tee -a "$gui_log"
}

function get_conf {
    {
        local conf_var="$1"
        if check_val_in_array "$conf_var" "${conf_vars[@]}"
        then
            source "$conf_file"
            declare -n conf_val="$conf_var"
            echo -e "\n$(date)\n$conf_var=\"$conf_val\""
            return 0
        else
            echo -e "\n$(date)\n$(eval_gettext "Error: \$conf_var does not exist\nAvailable parameters"): ${conf_vars[@]}"
            return 1
        fi

    } 2>&1 | tee -a "$gui_log"
}

function check_val_in_array {
    local val="$1"
    shift
    for scalar in "$@"
    do
        test "$val" == "$scalar" && return 0
    done
    return 1
}

function check_value_in_array {
    local value="$1"
    shift
    declare -a array=( "$@" )
    grep -q --line-regexp "$value" < <(printf "%s\n" "${array[@]}") &&
        return 0 || return 1
}


function get_pid_regex {
    awk "BEGINFILE{if (ERRNO != \"\") nextfile} /$1/{match(FILENAME, /[0-9]+/, matched); print matched[0]}" /proc/*/cmdline
}

function get_pid_cmd {
    local _cmd=$(command -v "$1" 2>/dev/null |sed -r 's|\/|\\/|g')
    if [ -n "_$cmd" ]
    then
        awk 'BEGINFILE{if(ERRNO!="")nextfile}/'"$_cmd"'/{split($0, cmd, "\0"); for(i=0; i<length(cmd); i++){if (cmd[i] ~ /^\_\='"$_cmd"'/){match(FILENAME,/[0-9]+/,matched); res = matched[0]; break}}}END{if(res != ""){print res " " cmd[i]; exit 0}else{exit 1}}' /proc/[0-9]*/environ &&
            return 0
    fi
    return 1
}

function check_pid_regex {
    local PID="$1" \
          REGEX="$2"
    if [[ "$PID" =~ ^([0-9]+)$ ]] &&
           [ -n "$REGEX" ]
    then
        awk "BEGINFILE{if (ERRNO != \"\") nextfile} /$REGEX/{match(FILENAME, /[0-9]+/, matched); print matched[0]}" /proc/$PID/cmdline
        return 0
    else
        return 1
    fi
}

function check_pid {
    local ck_pid=$1
    if [[ "$ck_pid" =~ ^[0-9]+$ ]] &&
           ps ax | grep -P '^[^0-9]*'$ck_pid'[^0-9]+' &>/dev/null
    then
        return 0 
    fi
    return 1
}

function check_pid_file {
    local pid

    if [ -s "$1" ] &&
           read pid < "$1" &&
           check_pid $pid
    then
        return 0
    else
        return 1
    fi
}

function check_instance_gui {
    [ -n "$1" ] && declare -n ref_pid="$1"

    res=$(awk 'BEGINFILE{
    if (ERRNO != "") nextfile
}
/zsp.*\-\-notebook/ {
    match(FILENAME, /([0-9]+)/, matched);
    print matched[0];
}' /proc/[0-9]*/cmdline)

    if [[ "$res" =~ ^[0-9]+$ ]]
    then
        [ -n "$1" ] && ref_pid="$res"
        return 0
    else
        unset ref_pid 
        return 1
    fi
}

function restart_instance_gui {
    import_all
    stop_instance_gui
    run_gui
}
export -f restart_instance_gui

function stop_instance_gui {
    import_all
    local pid
    check_instance_gui pid
    kill $pid
    [[ "$1" =~ ^[0-9]+$ ]] &&
        ipcrm -M $1
}
export -f restart_instance_gui

function check_brscan_skey {
    local res=$(ps aux |
                    grep -P '\/.+\/brscan-skey' |
                    grep -v grep)

    ## user:
    awk '{print $1}' <<< "$res"

    ## pid:
    awk '{print $2}' <<< "$res"

    ## tty:
    awk '{print $7}' <<< "$res"
    
    if [ -n "$res" ]
    then
        return 0
    else
        return 1
    fi
}

function start_brscan_skey {
    declare -a res
    if res=( $(check_brscan_skey) )
    then
        printf "\n$(date)\n$(gettext "brscan-skey already started by %s in %s") (pid: ${res[1]})\n" "${res[0]}" "${res[2]}"
    else
        brscan-skey &&
            echo -e "\n$(date)\nbrscan-skey $(gettext "started")"
    fi
}

function stop_brscan_skey {
    declare -a res
    if res=( $(check_brscan_skey) )
    then
        if [ "${res[0]}" == root ]
        then
            printf "\n$(date)\n$(gettext "brscan-skey started by %s in %s") (pid: ${res[1]})\n" "${res[0]}" "${res[2]}"
            gettext "Need root rights (sudo):"
            ( common_try brscan-skey -t || common_try kill ${res[1]} ) &&
                echo -e "\n$(date)\nbrscan-skey $(gettext "stopped")"
        else
            ( brscan-skey -t || kill ${res[1]} ) &&
                echo -e "\n$(date)\nbrscan-skey $(gettext "stopped")"
        fi
    else
        echo -e "\n$(date)\nbrscan-skey $(gettext "already stopped")"
    fi
}

function restart_brscan_skey {
    echo -e "\n$(gettext "Restarting brscan-skey"):"
    stop_brscan_skey

    for i in $(seq 0 3)
    do
        sleep 1
        echo ' |'
    done
    echo ' V'
    
    start_brscan_skey 
}

function import_all {
    if [ -z "$prog" ]
    then
        prog=zsp
        share="/usr/local/share/$prog"
        source "$share"/data.sh
        source "$share"/common.sh
        source "$share"/utils.sh
        source "$share"/gui.sh
    fi
}
export -f import_all

function reconfigure {
    import_all
    mv "$conf_file" "$conf_file".bak
    rm -f "$conf_path"/scanner/*
    # local f
    # for f in "$conf_path"/scanner/*
    # do
    #   echo >"$f"
    # done
    configure
}
export -f reconfigure

function get_printer_devices {
    import_all
    get_language_prog

    lpstat -s |
        awk '{
split($0, info, / :*/)
if(substr(info[3],0,length(info[3])-1) != "destination"){
    print substr(info[3],0,length(info[3])-1)
    print info[4]
}
}' >"$lp_devfile".new
    
    [ -f "$lp_devfile".new ] &&
        mv "$lp_devfile".new "$lp_devfile"
    
    # if [ -f "$lp_devfile".new ]
    # then
    #   if [ -f "$lp_devfile" ]
    #   then
    #       read -d '' test_new < "$lp_devfile".new
    #       read -d '' test_old < "$lp_devfile"

    #       if [ "$test_new" != "$test_old" ]
    #       then
    #           mv "$lp_devfile".new "$lp_devfile"
    #       else
    #           rm "$lp_devfile".new 
    #       fi
    #   else
    #       mv "$lp_devfile".new "$lp_devfile"
    #   fi
    # else
    #   rm -f "$lp_devfile"
    # fi

    get_language_user
}
export -f get_printer_devices

function get_language_prog {
    export oLANG="$LANG" \
           oLANGUAGE="$LANGUAGE" \
           LANG="C" \
           LANGUAGE="C"
}

function get_language_user {
    export LANG="$oLANG" \
           LANGUAGE="$oLANGUAGE"
}
    
function get_scanner_option_values {
    local dev="$1" \
          opt="$2"

    if [ -s "$scanner_data_file" ]
    then
        awk -v dev="$dev" "{
if (\$0 ~ /All options specific to device /) match (\$0, /All options specific to device \`(.+)'/,dev_test)
if (dev_test[1] == dev && \$0 ~ /\-\-$opt/){
    match(\$0, /\-\-$opt (.+)\$/,matched)
    split(matched[1], opts, /(\|| \[)/)
    for (i=0;i<length(opts) -1; i++) {
        if (opts[i] != \"\") {
            if (opts[i] ~ /[0-9]+\.\.[0-9]+/) {
                match(opts[i], /([0-9\-\.]+\.\.[0-9\-\.]+)/, matched)
                print matched[1]
                match(opts[i], /\(in steps of ([0-9]+)\)/, matched)
                if (matched[1] != \"\") {print matched[1]} else {print 1}
                print 0
            }       
            else print opts[i]
        }
    }
}
}" < "$scanner_data_file" &&
            return 0
    fi
    return 1
}

function get_scanner_data_file {
    import_all
    local dev test_new test_old \
          scanner_data_counter="$1"
    declare -n scanner_data_counter_ref="$2"
    
    get_language_prog
    
    scanimage -f "DEVICE='%d'%nVENDOR='%v'%nMODEL='%m'%nNAME='%v-%m'%n" 2>/dev/null |
        tee "$scanner_data_file".new |
        while read line
        do
            if [[ "$line" =~ DEVICE\=\'(.+)\'$ ]]
            then
                dev="${BASH_REMATCH[1]}"
                scanimage -d "$dev" -A 2>/dev/null
            fi
            
        done >> "$scanner_data_file.new"

    # if [ -f "$scanner_data_file".new ]
    # then
    #   mv "$scanner_data_file".new "$scanner_data_file"
    # fi

    if [ -f "$scanner_data_file".new ]
    then
        sed -e 's|*||g' -i "$scanner_data_file.new"

        if [ -f "$scanner_data_file" ]
        then
            read -d '' test_new < "$scanner_data_file".new
            read -d '' test_old < "$scanner_data_file"

            if [ -z "$test_new" ] &&
                   ((scanner_data_counter < 5))
            then
                scanner_data_counter_ref=$((scanner_data_counter + 1))
            else
                scanner_data_counter_ref=0
                
                if [ "$test_new" != "$test_old" ]
                then
                    mv "$scanner_data_file".new "$scanner_data_file"
                else
                    rm "$scanner_data_file".new 
                fi
            fi
        else
            mv "$scanner_data_file".new "$scanner_data_file"
        fi
    fi
    get_language_user
}
export -f get_scanner_data_file

function get_scanner_index_options {
    if [[ "$1" =~ ^([0-9]+)$ ]] &&
           [ -s "$scanner_data_file" ]
    then
        local index=$(( $1 +2))
        awk '{
split($0, data,"All options specific to device ")
split(data['$index'], items, "!")
for(i=0; i<length(items); i++){
    if(items[i] ~ /\-\-/){
        match(items[i],/\-\-([^ \[\(=]+)/,opts)
        print opts[1]
    }
}
}' < <(tr '\n' '!' < $scanner_data_file) &&
            return 0
    fi
    return 1
}

function get_scanner_device_index {
    local dev="$1"
    if [ -s "$scanner_data_file" ]
    then
        awk -v dev="$dev" "BEGIN{count=0}/All options specific to device /{
match (\$0, /All options specific to device \`(.+)'/,dev_test)
if (dev_test[1] == dev){print count}; count++}" < $scanner_data_file &&
            return 0
    fi
    return 1
}

function get_scanner_device_options {
    local dev="$1"
    get_scanner_index_options $(get_scanner_device_index "$dev") 
}

function get_scanner_devices {
    if [ -s "$scanner_data_file" ]
    then
        awk "/All options specific to device /{match (\$0, /All options specific to device \`(.+)'/,devs); print devs[1]}" < $scanner_data_file &&
            return 0
    fi
    return 1
}

function get_conf_vars_scanner_spec {
    local dev="$1"
    conf_vars_scanner_spec=()
    if [ -s "$scanner_data_file" ]
    then
        while read line
        do
            conf_vars_scanner_spec+=( $(printf "scanner_%s\n" "${line//\-/_}") )
        done < <(get_scanner_device_options "$dev")

        conf_vars_scanner_spec+=(
            scanner_l
            scanner_t
            scanner_y
            scanner_x
        )
                
        return 0
    fi
    return 1
}

function get_default_values_scanner {
    local dev="$1"
    
    if [ -s $scanner_data_file ]
    then
        eval "$(awk -v dev="$dev" "{
if (\$0 ~ /All options specific to device /) match (\$0, /All options specific to device \`(.+)'/,dev_test)
if (dev_test[1] == dev && \$0 ~ /\-\-[^ ]+/){
    match(\$0, /\-\-([^ ]+) (.+)\$/,matched)
    opt = matched[1]
    gsub(/\-/, \"_\", opt)
    split(matched[2], opts, /(\|| \[)/)
    d = substr(opts[length(opts)],0,length(opts[length(opts)])-1)
    code = code \"default_values[scanner_\" opt \"]='\" d \"';\n \"}}
END{print code}" < $scanner_data_file)" &&
            return 0
        ### prima di 'code = code...'
        #if (d == \"inactive\") d = 0
    fi
    return 1
}

function get_conf_file_dev {
    local NAME
    if [ -f "$scanner_data_file" ]
    then
        eval $(grep "DEVICE='$1'" -A3 "$scanner_data_file" |tail -n1)
        touch "$conf_path"/scanner/"$NAME".conf
        echo "$conf_path"/scanner/"$NAME".conf
        return 0
    else
        return 1
    fi
}

function get_name {
    local var="$1" NAME

    declare -n val="$var"
    local out

    case "$var" in
        scanner_device)
            if [ -s "$scanner_data_file" ]
            then
                eval $(grep "DEVICE='$val'" -A3 "$scanner_data_file" |tail -n1)
                out="$NAME"
            else
                out="$waiting_devices_msg"
            fi
            ;;
        scanner_sides)
            case "$val" in
                "one-sided")
                    out=$(gettext "One sided") ;;
                "two-sided")
                    out=$(gettext "Two sided") ;;
            esac            
            ;;
        scanner_orientation)
            case "$val" in
                "portrait")
                    out=$(gettext "Portrait") ;;
                "landscape")
                    out=$(gettext "Landscape") ;;
            esac
            ;;  
        lp_device)
            [ -s "$lp_devfile" ] && out="$val"
            ;;
        lp_page_set)
            case "$val" in
                "even")
                    out=$(gettext "Even") ;;
                "odd")
                    out=$(gettext "Odd") ;;
                *)
                    out=$(gettext "All") ;;
            esac
            ;;      
        lp_sides)
            case "$val" in
                "one-sided")
                    out=$(gettext "One sided") ;;
                "two-sided-long-edge")
                    out=$(gettext "Two sided - Portrait") ;;
                "two-sided-short-edge")
                    out=$(gettext "Two sided - Landscape") ;;
            esac
            ;;
        *)
            out="$val"
            ;;
    esac
    echo "$out"
}

function set_value {
    local var="$1" name="$2"     
    declare -n val="$var"
    val=$(get_value "$var" "$name")
}

function get_value {
    local var="$1" name="$2" val

    [ "$name" == '-- default --' ] &&
        val="" ||
            case "$var" in
                scanner_device)
                    if [ "$name" == "$waiting_devices_msg" ]
                    then
                        return 1
                    else
                        eval $(grep "NAME='$name'" "$scanner_data_file" -B3 | head -n1)
                        val="$DEVICE"
                    fi
                    ;;
                scanner_sides)
                    case "$name" in
                        "$(gettext "One sided")")
                            val="one-sided" ;;
                        "$(gettext "Two sided")")
                            val="two-sided" ;;
                    esac
                    ;;
                scanner_orientation)
                    case "$name" in
                        "$(gettext "Portrait")")
                            val="portrait";;
                        "$(gettext "Landscape")")
                            val="landscape" ;;
                    esac
                    ;;
                lp_device)
                    if [ "$name" == "$waiting_devices_msg" ]
                    then
                        val=""
                    else
                        val="$name"
                    fi
                    ;;
                lp_page_set)
                    case "$name" in
                        "$(gettext "Even")")
                            val="even" ;;
                        "$(gettext "Odd")")
                            val="odd" ;;
                        *)
                            val="";;            
                    esac
                    ;;      
                lp_sides)
                    case "$name" in
                        "$(gettext "One sided")")
                            val="one-sided" ;;
                        "$(gettext "Two sided - Portrait")")
                            val="two-sided-long-edge" ;;
                        "$(gettext "Two sided - Landscape")")
                            val="two-sided-short-edge";;
                    esac
                    ;;
                *)
                    val="$name"
                    ;;
            esac    
    echo "$val"
}

function get_scanner_geometry_values {
    local dev="$1" \
          opt="$2"
    
    if [ -s $scanner_data_file ]
    then
        awk -v dev="$dev" "{
if (\$0 ~ /All options specific to device /) match (\$0, /All options specific to device \`(.+)'/,dev_test)
if (dev_test[1] == dev && \$0 ~ /\-$opt/){
    match(\$0, /\-$opt (.+)\$/,matched)
    split(matched[1], opts, /(\|| \[)/)
    print substr(opts[length(opts)],0,length(opts[length(opts)])-1)
    for (i=0;i<length(opts) -1; i++) {
        if (opts[i] != \"\") {
            if (opts[i] ~ /[0-9]+\.\.[0-9]+/) {
                match(opts[i], /([0-9\.]+\.\.[0-9\.]+)/, matched)
                print matched[1]
                match(opts[i], /\(in steps of ([0-9\.]+)\)/, matched)
                if (matched[1] != \"\") {print matched[1]} else {print 1}
                print 0
            }       
        }
    }
}
}" < $scanner_data_file &&
            return 0
    fi
    return 1
}

function kill_winid {
    hash xdotool 2>/dev/null &&
        xdotool windowkill "$1" 2>/dev/null
}
export -f kill_winid

function get_main_winid {
    hash xdotool 2>/dev/null &&
        xdotool search --any --class "ZigzagScanPrint" 2>/dev/null |tail -n1
}
export -f get_main_winid

function get_winid {
    hash xdotool 2>/dev/null &&
        xdotool search --any --class "$1" 2>/dev/null |tail -n1
}
export -f get_winid

function get_main_winids {
    hash xdotool 2>/dev/null &&
        xdotool search --any --class "ZigzagScanPrint" 2>/dev/null
}
export -f get_main_winids

function kill_main_win {
    local id
    hash xdotool 2>/dev/null &&
        for id in $(get_main_winids)
        do
            xdotool windowkill $id 2>/dev/null
        done
    
    [[ "$1" =~ ^[0-9]+$ ]] &&
        ipcrm -M $1     
}
export -f kill_main_win

function sudo_gui {
    sudo_check=$(sudo -H -S -- echo SUDO_OK 2>&1 &)
    if [[ $sudo_check != "SUDO_OK" ]]
    then
        while :
        do
            pass=($(yad --title="ZSP: Password SUDO"                                \
                        --image="dialog-password"                                   \
                        --center                                                    \
                        --on-top                                                    \
                        --separator=""                                              \
                        --form                                                      \
                        --field="$(gettext "Enter the user password (sudo):")":H    \
                        --button="$(gettext "Cancel")":1 \
                        --button="$(gettext "Ok")":0 \
                        "${YAD_ZSP[@]}"))
            ret="$?"
            case "$ret" in
                0)
                    echo "${pass[*]}" | sudo -S "ls" &>/dev/null
                    if [ "$?" == 0 ]
                    then
                        break
                    fi
                    ;;
                1)
                    exit 1
                    ;;
            esac
        done
    fi    
}

function common_try {
    cmdline=( "$@" )
    
    if ! "${cmdline[@]}" 2>/dev/null 
    then
        if [ "$ui_type" == gui ]
        then
            sudo_gui
        fi

        if ! sudo "${cmdline[@]}"
        then
            su -c "${cmdline[@]}" || {
                echo "$(gettext Failure): ${cmdline[@]}"
                return 1
            }
        fi
    fi
}

function kill_zsp {
    kill_winid $(get_winid "ZigzagScanPrint-progress")
    kill_main_win
    kill_fifo_all
    
    for pid in $(ps -ef |
                     grep -F "yad --plug=$nbkey" |
                     grep -v grep |
                     awk '{print $2}')
    do
        kill $pid 2>/dev/null
    done

    for pid in $(ps -ef |
                     grep -F "bash -c update_zsp_gui" |
                     grep -v grep |
                     awk '{print $2}')
    do
        kill $pid 2>/dev/null &
    done
}

function restart_zsp {
    nbskey="$1"
    import_all
    {
        kill_zsp
        sleep 2
        zsp
    } & disown
}
export -f restart_zsp
