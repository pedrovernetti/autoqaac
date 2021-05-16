#!/bin/bash

# CONSTANTS -----------------------------------------------------------------
min_bitrate=224
desired_bitrate=256

# REGEXES -------------------------------------------------------------------
audio_rx='^.*\.(m(p[+234c]|4[abpv]|k[av])|wa?v|a(pe|ac|sf|if[fc]?|u|mr|wb)|flac|'
audio_rx+='o(g[ag]|pus)|w(ebm|ma)|flv|r(a|a?m)|pls|s(px|nd)|m(pe?ga?|idi?)|kar|'
audio_rx+='tta|3g(p[p2]?|2))$'

# INTERNAL SHNSPLIT ---------------------------------------------------------

auto_shnplit()
{
    audio=''
    for f in "${1%.cue}"*; do
        if [[ "$f" == "$1" ]]; then continue; fi
        if [[ "$f" =~ $audio_rx ]]; then audio+="$f\n"; fi
        done
    if [[ $(echo -n -e "$audio" | wc -l) -ne 1 ]]; then return 0; fi
    audio=$(echo -n -e "$audio" | tr -d '\n')
    bdepth=$(mediainfo --language=raw --full --inform="Audio;%BitDepth%" "$audio")
    echo -e -n "\n-----------------------------------------------\n$audio\n"
    if ! [[ "${audio,,}" == *.flac ]]; then
        ffmpeg -hide_banner -v warning -stats -nostdin -i "$audio" -sn -vn \
            -acodec flac -sample_fmt s16 "${audio%.*}.flac"
        if [[ $? -ne 0 ]]; then rm -f "${audio%.*}.flac" &> /dev/null; exit $?; fi
        FLACED=true
        actual_audio="$audio"
        audio="${audio%.*}.flac"
    elif [[ "$bdepth" -ne 16 ]]; then
        ffmpeg -hide_banner -v warning -stats -nostdin -i "$audio" -sn -vn \
            -acodec flac -sample_fmt s16 "$audio.flac"
        if [[ $? -ne 0 ]]; then rm -f "$audio.flac" &> /dev/null; exit $?; fi
        mv -f "$audio.flac" "$audio" &> /dev/null
        fi
    cue_enc=$(chardet3 "$1" | sed -r 's/^.*\.cue: (.+?) with confidence [01]\.[0-9]{1,2}[\t ]*$/\U\1/')
    iconv -f "$cue_enc" -t UTF-8 "$1" > "${1%.cue}.u8.cue"
    sed -i -r "s/^FILE.*$/FILE \"${audio##*/}\" FLAC/" "${1%.cue}.u8.cue"
    sed -i -r 's/([0-9]{2}:[0-9]{2}:[0-9]{2})([^0-9])?/\1''0\2/g' "${1%.cue}.u8.cue"
    if [[ $? -ne 0 ]]; then rm -f "${1%.cue}.u8.cue" &> /dev/null; exit $?; fi
    OLD_PWD="$PWD"
    cd "${audio%/*}/"
    MARK="$RANDOM$RANDOM"
    shntool split -i flac -o flac -f "${1%.cue}.u8.cue" -t "%n - %t.$MARK" "$audio"
    if [[ $? -ne 0 ]]; then
        WHAT_TO_RETURN=$?
        if [[ "$FLACED" == true ]]; then rm -f "$actual_audio" &> /dev/null; fi
        for f in *."$MARK.flac"; do rm -f "$f" &> /dev/null; done
        exit $WHAT_TO_RETURN
    elif [[ "$FLACED" == true ]]; then
        rm -f "$actual_audio" &> /dev/null
        fi
    for f in *."$MARK.flac"; do rename "s/.$MARK.flac/.flac/" "$f"; done
    rm -fr "$audio" "${1%.cue}.u8.cue" "$1" &> /dev/null
    cd "$OLD_PWD"
    echo -e -n "-----------------------------------------------\n\n"
}

# DEPENDENCIES FETCHING -----------------------------------------------------
if [[ "${!#}" == '--prepare' ]]; then
	if ! dpkg -l mediainfo &> /dev/null; then sudo apt-get install mediainfo; fi
	if ! dpkg -l ffmpeg &> /dev/null; then sudo apt-get install ffmpeg; fi
	if ! dpkg -l shntool &> /dev/null; then sudo apt-get install shntool; fi
	if ! dpkg -l sed &> /dev/null; then sudo apt-get install sed; fi
	if ! dpkg -l grep &> /dev/null; then sudo apt-get install grep; fi
	if ! dpkg -l python3-chardet &> /dev/null; then sudo apt-get install python3-chardet; fi
	if ! dpkg -l flac &> /dev/null; then sudo apt-get install flac; fi
    if ! hash wine &> /dev/null; then
        echo -e -n "\033[31mWINE IS MISSING!\n\033[0m\n"; fi
    if ! [[ -f "$HOME/.wine/drive_c/qaac/qaac.exe" ]]; then
        echo -e -n "\033[31mQAAC IS MISSING!!!\n\033[0m\n"; fi
    fi

# MULTIPLE ARGUMENTS --------------------------------------------------------
if [[ $# -gt 1 ]]; then
    for i in `seq 1 $#`; do "$0" "${!i}"; done
    fi

# RECURSIVE MODE ------------------------------------------------------------
if [[ -d "$1" ]]; then
    while read -r i; do
        echo -e -n "\n\033[1m$i\033[0m ...\n"
        while read -r j; do
            if [[ "${j,,}" == *.cue ]]; then auto_shnplit "$j"; fi
            done <<< $(find "$i" -maxdepth 1 -type f | sort -b -f -i)
        while read -r j; do
            if [[ "${j,,}" =~ $audio_rx ]]; then "$0" "$j"; fi
            done <<< $(find "$i" -maxdepth 1 -type f | sort -b -f -i)
        done <<< $(find "$1" -type d)
    echo
    exit
    fi

# VARIABLES -----------------------------------------------------------------
INPUT="$1"
export WINEDEBUG=-all
qaac_exe="wine '$HOME/.wine/drive_c/Program Files (x86)/qaac/qaac.exe'"
music_dir="$HOME/Music/"
size_old=$(du -b "$INPUT" | grep -Eo '^[0-9]+')
bitrate=$(mediainfo --language=raw "$INPUT" | grep -m 1 '^BitRate/String' | \
                sed -r 's/^.*: ([[:digit:].]+) [Kk].*$/\1/')
format=$(mediainfo --language=raw --full --inform="Audio;%Format%" "$INPUT")
is_itunes=$(head -c8 "$INPUT" | tail -c4 | tr -c -d '[:graph:]')
if [[ "$is_itunes" == ftyp ]]; then is_itunes=true; else is_itunes=false; fi
artwork="--copy-artwork --artwork-size 500"

# CONVERSION ----------------------------------------------------------------
if [[ "$bitrate" == "" ]]; then exit
elif [[ ${bitrate%%.*} -lt $((min_bitrate-(min_bitrate/10))) ]]; then
    echo -e -n "\n$INPUT\n\033[31;1mBAD INPUT QUALITY: $bitrate kbps\033[0m\n\n"
    exit
elif [[ ( "$format" == "AAC" ) && ( ${bitrate%%.*} -le $((desired_bitrate+(desired_bitrate/10))) ) ]]; then
    if [[ "$is_itunes" == true ]]; then
        echo -e -n "\n$INPUT\n\033[33;1mNO APPLICABLE CHANGES\033[0m\n\n"
        exit
    else
        echo -e -n "\n-----------------------------------------------\n$INPUT\n"
        ffmpeg -hide_banner -v warning -stats -nostdin -i "$INPUT" -sn -vn \
            -acodec copy "$INPUT.m4a"
        if [[ $? -ne 0 ]]; then rm -f "${INPUT%.*}.m4a" &> /dev/null; exit $?; fi
        rm -f "$INPUT" &> /dev/null
        mv -f "$INPUT.m4a" "${INPUT%.*}.m4a" &> /dev/null
        echo -e -n "-----------------------------------------------\n\n"
        exit
        fi
    fi
echo -e -n "\n-----------------------------------------------\n$INPUT\n"

if [[ "${INPUT,,}" == *.flac ]]; then
    ffmpeg -hide_banner -v warning -stats -nostdin -i "$INPUT" -sn -vn \
        -acodec copy "$INPUT.flac"
    if [[ $? -ne 0 ]]; then rm -f "$INPUT.flac" &> /dev/null; exit $?; fi
    mv -f "$INPUT.flac" "$INPUT" &> /dev/null
    artwork=""
elif ! [[ "${INPUT,,}" =~ ^.*\.(m(4[avpb]|p4)|wav) ]]; then
    ffmpeg -hide_banner -v warning -stats -nostdin -i "$INPUT" -sn -vn \
        -acodec flac "${INPUT%.*}.flac"
    if [[ $? -ne 0 ]]; then rm -f "${INPUT%.*}.flac" &> /dev/null; exit $?; fi
    FLACED=true
    OLD_INPUT="$INPUT"
    INPUT="${INPUT%.*}.flac"
    fi
final_bitrate=$((bitrate < desired_bitrate ? bitrate : desired_bitrate))
$qaac_exe -v "$final_bitrate"k -q 2 --no-smart-padding --threading \
    --text-codepage 65001 $artwork -o "$INPUT.m4a" "$INPUT"
if [[ $? -ne 0 ]]; then
    WHAT_TO_RETURN=$?
    if [[ "$FLACED" == true ]]; then rm -f "$INPUT" &> /dev/null; fi
    rm -f "$INPUT.m4a" &> /dev/null
    exit $WHAT_TO_RETURN
elif [[ "$FLACED" == true ]]; then
    rm -f "$OLD_INPUT" &> /dev/null
    fi
final_bitrate=$(mediainfo --language=raw "$INPUT.m4a" | grep -m 1 '^BitRate/String' | \
                sed -r 's/^.*: ([[:digit:].]+) [Kk].*$/\1/')
if [[ ( "$format" == "AAC" ) && ("$bitrate" -le "$final_bitrate") ]]; then
    rm -f "$INPUT.m4a" &> /dev/null
    if [[ "$is_itunes" == true ]]; then
        echo -e -n "\n$INPUT\n\033[33;1mNO CHANGES APPLIED\033[0m\n\n"
        echo -e -n "-----------------------------------------------\n\n"
        exit
    else
        ffmpeg -hide_banner -v warning -stats -nostdin -i "$INPUT" -sn -vn \
            -acodec copy "$INPUT.m4a"
        if [[ $? -ne 0 ]]; then rm -f "$INPUT.m4a" &> /dev/null; exit $?; fi
        rm -f "$INPUT" &> /dev/null
        mv -f "$INPUT.m4a" "${INPUT%.*}.m4a" &> /dev/null
        fi
else
    rm -f "$INPUT" &> /dev/null
    mv -f "$INPUT.m4a" "${INPUT%.*}.m4a"
    fi

# SIZE REDUCTION MESSAGE ----------------------------------------------------
if [[ $? -eq 0 ]]; then
    size_new=$(du -b "${INPUT%.*}.m4a" | grep -Eo '^[0-9]+')
    percentage=$((100 - ((size_new * 100) / size_old)))
    if [[ "$percentage" -gt 5 ]]; then
        echo -e -n "\033[32;7m$percentage% smaller\033[0;0m\n"
    else
        echo -e -n "\033[33;7m$percentage% smaller\033[0;0m\n"
        fi
    echo -e -n "-----------------------------------------------\n\n"
    fi
