#!/bin/bash
#
# project: ZigzagScan&Print
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

#set -x
set +o history

ui_type="$1"

conf_file="$HOME"/.zsp.conf

url_path="https://inventati.org/zoninoz/zsp"

share_path="/usr/local/share/zsp"
tmp_path="/tmp/zsp"
if [ "$ui_type" == gui ]
then
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
fi

function try {
    cmdline=( "$@" )
    
    if ! "${cmdline[@]}" 2>/dev/null 
    then
	if ! sudo "${cmdline[@]}"
	then
	    su -c "${cmdline[@]}" || {
		echo "$(gettext Failure): ${cmdline[@]}"
		return 1
	    }
	fi
    fi
}

function install_dep {
    local dep="$1" cmd
    for cmd in "${!deps[@]}"
    do
	[ "$dep" == "${deps[$cmd]}" ] && break
    done

    while ! command -v $cmd &>/dev/null
    do
	printf "$(gettext "WARNING: %s is not installed on your system")\n" $dep
	DEBIAN_FRONTEND=noninteractive
	try apt-get --no-install-recommends -q -y install $dep
    done
}

function install_prog {
    try rm -f "$HOME"/.brscan.conf* /usr/local/bin/brscan2file*
    rm -fr "$tmp_path"/src
    try mkdir -p "$tmp_path"/src
    try rm -rf "$share_path"
    try mkdir -p "$share_path"

    oPWD="$PWD"
    cd "$tmp_path"/src
    wget --user-agent='' "$url_path"/zsp.tar.gz --show-progress -O zsp.tar.gz

    [ -f zsp.tar.gz ] || exit 1
    
    tar -xvzf zsp.tar.gz 2>&1

    source common.sh  2>&1
    source gui.sh  2>&1
    chmod +x zsp brscan_to_pc* zsp.completion  2>&1
    try cp -vr * "$share_path" 2>&1
    try cp -v zsp /usr/local/bin/ 2>&1

    ## bash completion
    try mkdir -p /etc/bash_completion.d 2>&1
    try install -T zsp.completion /etc/bash_completion.d/zsp 2>&1
    source "$HOME"/.bashrc 2>&1

    ## desktop icon
    mkdir -p "$HOME"/.local/share/applications/ 2>&1
    try cp /usr/local/share/zsp/zsp.desktop "$HOME"/.local/share/applications/ 2>&1
    try desktop-file-install "$HOME"/.local/share/applications/zsp.desktop 2>&1

    ## locale (gettext)
    for dir in locale/*
    do
	if [ -d "$dir" ]
	then
	    try mkdir -p /usr/local/share/locale/"${dir##*\/}"/LC_MESSAGES/
	    try install "$dir"/LC_MESSAGES/zsp.mo /usr/local/share/locale/"${dir##*\/}"/LC_MESSAGES/
	fi
    done

    if [ -s "$conf_file" ]
    then
	#zsp --reconfigure
        mv "$conf_file" "$conf_file".bak 2>/dev/null
        configure
        
        test -f "$conf_file" &&
	    read -d '' test_conf < "$conf_file"

        test -f "$conf_file".bak &&
	    read -d '' test_conf_bak < "$conf_file".bak
        
	if [ "$test_conf" != "$test_conf_bak" ]
	then
	    diff_question="
$(gettext "Choose the configuration file (which you can manually edit)"):
"
	    diff_header_text="
$(gettext "The user configuration file is different from the default one.\nCompare below the differences between the two files and choose which one to use")
"
	    diff_text="

1) $(gettext user)                                                         2) $(gettext default)
                                                              |
"
	    diff_text+="$(diff -yB --suppress-common-lines "$conf_file".bak "$conf_file")"
	
	    if [ "$ui_type" == gui ]
	    then
		inputdiff=$(mktemp)
		echo -e "${diff_text}" > "$inputdiff"
		
		yad --title="ZSP: $(gettext "Installing")" \
		    --image="scriptnew" \
		    --text="${TEXT}<i>$(gettext "ZSP installing process")</i>\n${diff_header_text}" \
		    --text-info \
		    --on-top \
		    --center \
		    --filename="$inputdiff" \
		    "${YAD_ZSP[@]}" \
		    --button="$(gettext "1) user")":0 \
		    --button="$(gettext "2) default")":1 \
		    --width=800 --height=600
		
		case "$?" in
		    0) opt_conf_file=1 ;;
		    1) opt_conf_file=2 ;;
		esac
	    else
		echo -e "
====================================================================================
$diff_header_text
------------------------------------------------------------------------------------
$diff_text
------------------------------------------------------------------------------------
"
		while [[ ! "$opt_conf_file" =~ ^[12]{1}$ ]]
		do
		    echo -e "$diff_question
1) $(gettext user)
2) $(gettext default)
"
		    read -ep '[1|2] >' opt_conf_file
		done
	    fi
	    
	    test "$opt_conf_file" == 1 &&
		mv "$conf_file".bak "$conf_file"
	fi
    else
        configure
    fi

    #################################
    ## dipendenze: [comando]=pachetto
    declare -A deps
    deps['psmerge']=psutils
    deps['scanadf']=sane
    deps['pnmtops']=netpbm
    deps['ps2pdf']=ghostscript
    deps['gm']=graphicsmagick
    deps['convert']=imagemagick
    deps['yad']=yad
    deps['tiffcrop']=libtiff-tools
    deps['pdfjam']="texlive-extra-utils texlive-latex-recommended"
    deps['mutt']=mutt

    for cmd in "${!deps[@]}" 
    do
	if ! command -v $cmd  &>/dev/null
	then
    	    echo "Installing: ${deps[$cmd]}"
    	    install_dep "${deps[$cmd]}"
	fi
    done

    for dep in tesseract-ocr sane-utils xdotool gnome-icon-theme
    do
	try apt-get --no-install-recommends -q -y install $dep
    done
    
    if grep PDF /etc/ImageMagick-6/policy.xml | grep -v '<!--'
    then
	try sed -r 's|^(.+PDF.+)$|<!-- \1 -->|g' -i /etc/ImageMagick-6/policy.xml
    fi

    cd "$oPWD"
}
export -f install_prog

if [ "$ui_type" == gui ]
then
    install_prog >>"$gui_log"
    echo "Restarting ZigzagScan&Print ..." >>"$gui_log"
    restart_brscan_skey >>"$gui_log"
    
    bash -c "restart_zsp $nbskey"
    
else
    install_prog
    restart_brscan_skey
fi

set -o history
