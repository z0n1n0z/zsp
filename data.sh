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

declare -gA default_values=(
    [filename]=""
    [directory]="$HOME"/brscan
    [filemanager]=""
    [scanner_device]="$scanner_device"
    [scanner_cmd]="scanimage"
    [scanner_sides]="one-sided"
    [scanner_orientation]="portrait"
    [scanner_geometry_mode]="normal"
    [convert_format]="tiff"
    [convert_pdf_mode]="normal"
    [convert_clean_up]="TRUE"
    [lp_print_pdf]="FALSE"
    [lp_device]=""
    [lp_page_set]=""
    [lp_pages]=""
    [lp_sides]="one-sided"
    [lp_copies]=1
    [email_port]=587
)
