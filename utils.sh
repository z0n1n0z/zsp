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

function convert_tiffs2pdf {
    local tiff_file
    declare -a files_pdf=()
    
    echo -e "
======================================
tiff2pdf:
$(gettext "Creating individual PDF pages"):
--------------------------------------
"
    for tiff_file in $(ls "$output_tmp"*.tiff)
    do
	if [[ "$tiff_file" =~ ^"$output_tmp"_[0-9]{4}.tiff ]]
	then
	    echo "$tiff_file -> ${tiff_file%tiff}pdf"
	    
	    tiff2pdf -zFo "${tiff_file%tiff}pdf" "$tiff_file" 2>&1
	    files_pdf+=( "${tiff_file%tiff}pdf" )
	fi
    done

    echo -e "
=============================
pdfjam: 
$(gettext "Creation of the book in PDF")...
-----------------------------
"
    pdfjam "${files_pdf[@]}" --fitpaper 'true' --no-landscape -o "$output_tmp".pdf 2>&1
    rm "${files_pdf[@]}"
}

function convert_orientation_tiff {
    local item
    
    for item in "$output_tmp"*.tiff
    do
	if [[ "$item" =~ ^"$output_tmp"_[0-9]{4}.tiff ]]
	then
	    echo "$item -> $item".rotated90
	    
	    tiffcrop -R 270 "$item" "$item".rotated90 2>&1
	    [ -f "$item".rotated90 ] && mv "$item".rotated90 "$item"
	fi
    done
}

function convert_orientation_pnm {
    for item in "$output_tmp"*.pnm
    do
	$pnmflip -rotate90 "$item" > "$item".rotated90
	[ -f "$item".rotated90 ] && mv "$item".rotated90 "$item"
    done
}

function convert_orientation_images {
    for item in "$output_tmp"*."$scanner_format"
    do
	convert "$item" -rotate 90 "$item"
    done
}
	
function convert_pnm2ps2pdf {
    for pnmfile in $(ls "$output_tmp"*)
    do
	echo "pnmtops: $pnmfile -> $pnmfile.ps"
	pnmtops "$pnmfile" > "$pnmfile".ps 2>&1
	rm -f "$pnmfile"
    done
    
    echo -e "psmerge -o$output_tmp.ps:\n$(ls "$output_tmp"*.ps)"
    psmerge -o"$output_tmp".ps $(ls "$output_tmp"*.ps) 2>&1
    
    echo "ps2pdf: $output_tmp.ps -> $output_tmp.pdf"
    ps2pdf "$output_tmp".ps   "$output_tmp".pdf 2>&1
}

function convert_pnm2pdf_resampling {
    if [[ "$scanner_resolution" =~ ^[0-9]+$ ]]
    then
	convert -density $(( resolution / 2 )) "$output_tmp"*.pnm -resample "$scanner_resolution" "$output_tmp".pdf 2>&1
    else
	echo "WARNING: images cannot be resampled: set the dpi resolution"
	convert_pnm2pdf
    fi
}

function convert_pnm2pdf_normal {
    if [[ "$scanner_resolution" =~ ^[0-9]+$ ]]
    then
    	convert -page A4 -density "$scanner_resolution" "$output_tmp"*.pnm "$output_tmp".pdf 2>&1
    else
    	echo "WARNING: set the dpi resolution"
	convert "$output_tmp"*.pnm "$output_tmp".pdf 2>&1
    fi
}

function convert_pnm2pdf_rescaling {
    gm convert "$output_tmp"*.pnm "$output_tmp".pdf 2>&1
}

function print_pdf {
    import_all
    get_configuration
    local input_pdf="$1"

    test -f "$input_pdf" || {
	display_msg_gui \
	    "$(gettext "Error: a printable file was not selected")" \
	    "gtk-dialog-error"
	return 1
    }
    
    lp_opts=(
	-o 'media=a4'
	-o 'fit-to-page'
	-o 'prettyprint'
	-o 'fitplot=TRUE'
	-o 'page-bottom=0'
	-o 'page-top=0'
	-o 'page-left=0'
	-o 'page-right=0'
    )

    if [[ "$lp_page_set" =~ ^(even|odd)$ ]]
    then
	lp_opts+=( -o "page-set=$lp_page_set" )
    fi
    
    if [ -z "${lp_pages//[0-9,\-]}" ] &&
	   [ -n "$lp_pages" ]
    then
    	lp_opts+=( -P "$lp_pages" )
    fi
    
    if [[ "${lp_copies}" =~ ^[0-9]+$ ]]
    then
    	lp_opts+=( -n "$lp_copies" )
    fi

    if [[ "$lp_sides" =~ ^(one-sided|two-sided-long-edge|two-sided-short-edge)$ ]]
    then
	lp_opts+=( -o "sides=$lp_sides" )
    fi

    if [ -n "$lp_device" ] &&
	   [[ "$(lpstat -a | cut -d' ' -f1)" =~ "$lp_device" ]]
    then
	lp_opts+=( -d "$lp_device" )
    fi
    
    local lp_cmd="lp "$(for ((i=0; i<${#lp_opts[@]}; i=i+2)); do echo -en "\t${lp_opts[i]} ${lp_opts[i+1]}\n"; done)"\t${input_pdf}"
    
    if lp ${lp_opts[@]} ${input_pdf} 2>&1 | tee -a "$gui_log"
    then
	local print_msg="<b>$(gettext "Print command sent to CUPS"):</b>\n$lp_cmd"
	res=0
    else
	local print_msg="<b>$(gettext "Incorrect print command"):</b>\n$lp_cmd"
	res=1
    fi

    if [ "$2" == gui ]
    then
	[ "$res" == 0 ] && print_image="gtk-dialog-info"
	[ "$res" == 1 ] && print_image="gtk-dialog-error"
	display_msg_gui "$print_msg" "$print_image"
    fi
    echo "$display_msg" | tee -a "$gui_log"

    return $res
}
export -f print_pdf

function run_brscan_to_pc {
    import_all
    if [ -z "$1" ]
    then
	source "$conf_file"
	local mode_to_var=$(tr '[:lower:]' '[:upper:]' <<< "$brscan_to_pc_mode")
    else
	local mode_to_var=$(tr '[:lower:]' '[:upper:]' <<< "$1")
    fi
    declare -n mode_to_val="$mode_to_var"
    source "$brscan_skey_cfg"

    ${mode_to_val} 2>&1 | tee -a "$gui_log"
}
export -f run_brscan_to_pc

function run_scanner {
    ## create scanner opts:
    declare -a scanner_opts=()
    local opt test_def

    for opt in $(get_scanner_device_options "$scanner_device")
    do
	var="scanner_${opt//\-/_}"
	test_def="${default_values[${var}]}"

	declare -n val="$var"

	if [ -n "$val" ] &&
	       [ "$val" != "inactive" ]
	then
	    printf "%s: %s\n" "${var}" "$val" 
	    scanner_opts+=( "--${opt}" "${val}" )
	fi
    done

    unset scanning_side
    
    if [ "$scanner_sides" == two-sided ]
    then
	if [ -n "$(ls "$directory"/*_zsp-ODD_*."$scanner_format" 2>/dev/null)" ]
	then
	    ## second side
	    scanning_side=_zsp-EVEN
	    output_tmp=$(ls "$directory"/*_zsp-ODD_*."$scanner_format" |
			     head -n1 |
			     sed -r 's|^(.+)_zsp-ODD_[0-9]{4}\.[a-zA-Z]{3,4}$|\1|g')
	else
	    ## first side
	    scanning_side=_zsp-ODD
	    unset convert_format
	fi
    fi

    err_scanner_msg="$scanner_cmd $(gettext "not running"): 
DEVICE: $scanner_device 
OPTIONS: ${scanner_opts[@]} 
GEOMETRY: $scanner_geometry
BATCH: ${output_tmp}${scanning_side}_%04d"

    case "$scanner_cmd" in
	scanimage)
	    run_scanimage || return 1
	    ;;
	scanadf)
	    run_scanadf || return 1
	    ;;
    esac

    if [ "$scanner_sides" == two-sided ] &&
	   [ "$scanning_side" == _zsp-EVEN ] &&
	   [ -n "$(ls "$output_tmp"_zsp-ODD*."$scanner_format" 2>/dev/null)" ] &&
	   [ -n "$(ls "$output_tmp"_zsp-EVEN*."$scanner_format" 2>/dev/null)" ]
    then
	renumber_pages "$output_tmp" ||
	    echo "$(gettext "Error in renumbering pages")"

    elif [ "$scanner_sides" == two-sided ] &&
	   [ "$scanning_side" == _zsp-ODD ]
    then
	exit
    fi
}

function run_scanimage {    
    # scanner_opts+=(	
    # 	--batch-start "$scanner_start"
    # 	--batch-count "$scanner_count"
    # 	--batch-increment "$scanner_increment"
    # )
    cat >$gui_log <<EOF
scanimage -v -d "$scanner_device" 
          --progress $scanner_geometry
          --format="$scanner_format"
          --batch="${output_tmp}${scanning_side}"_%04d."$scanner_format"
          ${scanner_opts[@]}
EOF
    local stdout=$(mktemp)
#	      --progress \
    scanimage -v -d "$scanner_device" \
	      $scanner_geometry \
	      --format="$scanner_format" \
	      --batch="${output_tmp}${scanning_side}"_%04d."$scanner_format" \
	      "${scanner_opts[@]}" 2>&1 |
	stdbuf -oL -eL tr '\r' '\n' |
	stdbuf -oL -eL tee "$stdout"
    
    if [[ "$(grep 'scanner status =' "$stdout" |tail -n1)" =~ (scanner\ status\ =\ 5) ]]
    then
	return 0
    else
	return 1
    fi
}

function run_scanadf {
    scanadf -v -d "$scanner_device" \
	    "${scanner_opts[@]}" \
	    $scanner_geometry \
	    -o "${output_tmp}${scanning_side}"_%04d.pnm \
	    2>&1 ||
	return 1
    return 0
}

function renumber_pages {
    local output_tmp="$1"
    
    if [ -z "$(ls "$output_tmp"_zsp-ODD_* 2>/dev/null)" ] ||
	   [ -z "$(ls "$output_tmp"_zsp-EVEN_* 2>/dev/null)" ]
    then
	return 1
    fi
    
    local last_odd=$(ls "$output_tmp"_zsp-ODD_* |
			 tail -n1 |
			 sed -r 's|^.+_([0-9]{4})\.[a-zA-Z]{3,4}$|\1|g')
    last_odd=$(expr ${last_odd} + 0)

    local last_even=$(ls "$output_tmp"_zsp-EVEN_* |
			  tail -n1 |
			  sed -r 's|^.+_([0-9]{4})\.[a-zA-Z]{3,4}$|\1|g')
    last_even=$(expr ${last_even} + 0)

    local ext=$(ls "$output_tmp"_zsp-ODD_* |
		    head -n1 |
		    sed -r 's|^.+_[0-9]{4}\.([a-zA-Z]{3,4})$|\1|g')

    if (( last_even == last_odd )) ||
	   (( last_odd == last_even + 1 ))
    then
	local odds=1 evens=$last_even side=evens id
	
	for ((i=1; i <= last_odd + last_even; i++))
	do
	    case "$side" in
		evens)		    
		    side=odds
		    id=_zsp-ODD ;;
		odds)
		    side=evens
		    id=_zsp-EVEN ;;
	    esac
	    
	    declare -n num="$side"
	    
	    if [ -f "${output_tmp}${id}"_$(printf "%04d" $num)\.$ext ]
	    then
		cp "${output_tmp}${id}"_$(printf "%04d" $num)\.$ext "${output_tmp}"_$(printf "%04d" $i)\.$ext
	    else
                echo "interno: even=$last_even  odd=$last_odd"
		return 1
	    fi

	    case "$side" in
		odds)
		    ((num++)) ;;
		evens)
		    ((num--)) ;;
	    esac
	done

	rm -f "$output_tmp"_zsp-*.$ext
    else
        echo "esterno: even=$last_even  odd=$last_odd"
	return 1
    fi
    return 0	    
}

function convert_pnms2pdf {
    [ -n "$convert_pdf_mode" ] &&
	msg="(mode: $convert_pdf_mode)"
    echo "$(gettext "Reformatting") ${msg} ..." 
    unset msg
    
    case "$convert_pdf_mode" in
	resampling)
	    convert_pnm2pdf_resampling
	    ;;
	rescaling-1)
	    convert_pnm2pdf_rescaling
	    ;;
	rescaling-2)
	    convert_pnm2ps2pdf
	    ;;
	normal|*)
	    convert_pnm2pdf_normal
	    ;;
    esac
}

function convert2pdf {
    case "$scanner_format" in
	tiff)
	    convert_tiffs2pdf
	    ;;
	pnm)
	    convert_pnms2pdf
	    ;;
    esac
}
