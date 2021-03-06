#!/bin/bash
#
# GamePanelX
# Steam Install Script
# Fetch hldsupdatetool, install steam in current dir, install game, then start template creation process
# NOTE: This script itself should be be run like: ./steaminstall.sh >> /dev/null 2>&1 & to it goes to the background, it takes a while to run.
#
# Steam(c) is a trademark owned by VALVe Corporation, and is in no way affiliated with GamePanelX.
# These are simply scripts to work alongside their provided server tools.
#
# Specify a callback URL and token to auto-update the database when completed
#
#source /etc/profile
steam_game=
tpl_id=
callback_url=
cback="wget -qO-"

while getopts "g:i:u:" OPTION
do
     case $OPTION in
         g)
             steam_game=$OPTARG
             ;;
	 i)
	     tpl_id=$OPTARG
	     ;;
	 u)
	     callback_url=$OPTARG
	     ;;
         ?)
             exit
             ;;
     esac
done

# Setup path
steam_tmp=$HOME/tmp/$tpl_id/

# Get to the right directory
if [ ! -d $HOME/tmp/$tpl_id ]
then
        mkdir -p $HOME/tmp/$tpl_id
fi

# Setup path / CD to it
steam_tmp=$HOME/tmp/$tpl_id/
cd $steam_tmp

# Reset steam log
echo > $steam_tmp/.gpxsteam.log
steam_log=$steam_tmp/.gpxsteam.log

if [ "$steam_game" == "" ]
then
	echo "SteamInstall: No game provided!"
	echo "SteamInstall: ($(date)) No game provided.  Use the -g option to set a game, and try again." >> $steam_log
	$cback "$callback_url&do=tpl_status&update=failed" >> /dev/null
	exit
elif [ "$tpl_id" == "" ]
then
	echo "SteamInstall: No template ID provided!"
	echo "SteamInstall: ($(date)) No template ID provided.  Use the -i option to set, and try again." >> $steam_log
	$cback "$callback_url&do=tpl_status&update=failed" >> /dev/null
	exit
fi

# Remove ./steam to start fresh
if [ -f ./steam ]
then
	echo "SteamInstall: ($(date))  Removing old steam binary ..." >> $steam_log
	rm -f ./steam
fi

if [ ! -f ./hldsupdatetool.bin ]
then
	echo "SteamInstall: ($(date)) Downloading hldsupdatetool.bin ..." >> $steam_log
	wget -q http://storefront.steampowered.com/download/hldsupdatetool.bin
	if [ ! -f ./hldsupdatetool.bin ]
	then
		echo "SteamInstall: ($(date)) Steam client download failed!  Please try again later."
		echo "SteamInstall: ($(date)) Steam client download failed!  Please try again later." >> $steam_log
		$cback "$callback_url&do=tpl_status&update=failed" >> /dev/null
		exit
	fi
fi

if [[ ! -f /usr/bin/uncompress && ! -f /usr/sbin/uncompress && ! -f /usr/local/bin/uncompress && ! -f /bin/uncompress ]]
then
	echo "SteamInstall: ($(date)) The 'uncompress' command (/usr/bin/uncompress) was not found!  Install it and try again."
	echo "SteamInstall: ($(date)) The 'uncompress' command (/usr/bin/uncompress) was not found!  Install it and try again." >> $steam_log
	$cback "$callback_url&do=tpl_status&update=failed" >> /dev/null
	exit
fi

# Run hldsupdatetool, extract steam
chmod u+x ./hldsupdatetool.bin

echo "SteamInstall: ($(date))  Running hldsupdatetool.bin ..." >> $steam_log

if [ ! "$(echo yes | ./hldsupdatetool.bin | grep 'extracting steam')" ]
then
	echo "SteamInstall: ($(date)) Failed to extract Steam client!"
	echo "SteamInstall: ($(date)) Failed to extract Steam client!" >> $steam_log
	$cback "$callback_url&do=tpl_status&update=failed" >> /dev/null
	exit
fi

# Setup steam client
sleep 1
chmod u+x ./steam

echo "SteamInstall: ($(date))  Running steam ..." >> $steam_log

# (send stderr to /dev/null)
if [ ! "$(./steam 2>>/dev/null | grep 'Steam Linux Client updated, please retry the command')" ]
then
	bad_steam_out="$(./steam 2>&1)"
        echo "SteamInstall: ($(date)) Steam client update failed:"
        echo "SteamInstall: $bad_steam_out"

	echo "SteamInstall: ($(date)) Failed to update steam client.  Please try again later." >> $steam_log
	$cback "$callback_url&do=tpl_status&update=failed" >> /dev/null
	exit
fi

# Final run, ensure client is working normally by checking for usage info
if [ ! "$(./steam 2>>/dev/null | grep 'Optional parameters for all commands')" ]
then
	sleep 3

	# Try one last time if Steam servers were busy...
	if [ ! "$(./steam 2>>/dev/null | grep 'Optional parameters for all commands')" ]
	then
		# Failed.  Get real output
		bad_steam_out="$(./steam 2>&1)"
		echo "SteamInstall: ($(date)) Steam Failed:"
                echo "SteamInstall: $bad_steam_out"

	        echo "SteamInstall: ($(date)) Steam Failed:" >> $steam_log
		echo "SteamInstall: $bad_steam_out" >> $steam_log
		echo "SteamInstall: -------------------------------" >> $steam_log

		$cback "$callback_url&do=tpl_status&update=failed" >> /dev/null
		exit
	fi 
fi

echo "SteamInstall: ($(date))  Steam is ready, starting game $steam_game update ..." >> $steam_log

##########################################################################

# Run steam install in background, and save PID
./steam -command update -game "$steam_game" -dir . >> $steam_log 2>&1 &
steam_pid=$!
touch $steam_tmp/.gpxsteam.pid
echo $steam_pid > $steam_tmp/.gpxsteam.pid

# Fork the checking on installation status, once done start template creation
while [ true ]
do
	# Check completed
	# if [ "$(tail ./.gpxsteam.log | grep 'HLDS installation up to date')" ]
	if [ "$(grep 'HLDS installation up to date' $steam_log)" ]
	then
		this_path="tmp/$tpl_id"

		# Done, start template creation process ("success" will output from this so no need to echo again)
		echo "SteamInstall: tpl_create_start" >> $steam_log
		echo "SteamInstall: ($(date)) Beginning template creation process (Path: $this_path, TplID: $tpl_id ..." >> $steam_log

		#cd
		#this_path=$HOME/tmp/$tpl_id

		$HOME/scripts/CreateTemplate -p $this_path -i $tpl_id -s yes -u "$callback_url"

		break
		exit
	# Not complete.  Update callback with steam install percentage every x seconds
	else
		# (this expects a modern `grep` which can handle regex)
		if [ "$callback_url" ]
                then
			cur_perc=$(tail $steam_log | awk '{print $2}' | grep '[0-9]%' | tail -1)

			if [ "$last_perc" != "$cur_perc" ]
			then
				last_perc=$cur_perc
				$cback "$callback_url&do=steam_progress&percent=$cur_perc" >> /dev/null
			fi
			
		fi
	fi

	sleep 5
done >> /dev/null 2>&1 &
check_tpl_pid=$!

touch $steam_tmp/.gpxtplcheck.pid
echo $check_tpl_pid > $steam_tmp/.gpxtplcheck.pid

echo "success"
