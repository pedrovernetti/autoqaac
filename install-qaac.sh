#!/bin/bash

sudo dpkg --add-architecture i386
sudo dpkg --add-architecture amd64
sudo apt-get update
sudo apt-get -f install
if ! hash wine &> /dev/null; then sudo apt-get install wine32; fi
if ! hash unzip &> /dev/null; then sudo apt-get install unzip; fi
if ! hash 7z &> /dev/null; then sudo apt-get install p7zip-full; fi

mkdir /tmp/qaac_build && \
cd /tmp/qaac_build && \
wget https://github.com/nu774/qaac/releases/download/v2.64/qaac_2.64.zip && \
mkdir -p "$HOME/.wine/drive_c/Program Files (x86)/qaac/" && \
unzip -j qaac_2.64.zip 'qaac_2.64/x86/*' -d "$HOME/.wine/drive_c/Program Files (x86)/qaac/"

wget -c https://secure-appldnld.apple.com/itunes12/031-86054-20161212-CC264356-BE1D-11E6-BD92-B3E982FDB0CC/iTunesSetup.exe && \
7z e -y iTunesSetup.exe AppleApplicationSupport.msi

7z e -y AppleApplicationSupport.msi \
     -i'!*AppleApplicationSupport_ASL.dll' \
     -i'!*AppleApplicationSupport_CoreAudioToolbox.dll' \
     -i'!*AppleApplicationSupport_CoreFoundation.dll' \
     -i'!*AppleApplicationSupport_icudt*.dll' \
     -i'!*AppleApplicationSupport_libdispatch.dll' \
     -i'!*AppleApplicationSupport_libicu*.dll' \
     -i'!*AppleApplicationSupport_objc.dll' \
     -i'!F_CENTRAL_msvc?100*' && \
for j in *.dll; do mv -v $j $(echo $j | sed 's/AppleApplicationSupport_//g'); done && \
for j in F_CENTRAL_msvcr100*; do mv -v "$j" msvcr100.dll; done && \
for j in F_CENTRAL_msvcp100*; do mv -v "$j" msvcp100.dll; done && \
mv -v *.dll "$HOME/.wine/drive_c/Program Files (x86)/qaac/" && \
rm -v AppleApplicationSupport.msi

wget http://www.andrews-corner.org/downloads/x32DLLs_20161112.zip && \
unzip -j x32DLLs_20161112.zip 'x32DLLs_20161112/*' -d "$HOME/.wine/drive_c/Program Files (x86)/qaac/"

rm -fr /tmp/qaac_build &> /dev/null && cd

sudo bash -c "echo -e -n \"#\!/bin/bash\nexport WINEDEBUG=-all\nwine \\\"\\\$HOME/.wine/drive_c/Program Files (x86)/qaac/qaac.exe\\\" \\\$@\n\" > /usr/bin/qaac"
sudo bash -c "echo -e -n \"#\!/bin/bash\nexport WINEDEBUG=-all\nwine \\\"\\\$HOME/.wine/drive_c/Program Files (x86)/qaac/refalac.exe\\\" \\\$@\n\" > /usr/bin/refalac"
sudo chmod +x /usr/bin/qaac /usr/bin/refalac
