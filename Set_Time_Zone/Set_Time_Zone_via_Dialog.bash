#!/bin/bash

####################################################################################################
#
#    Set Time Zone
#
#    Purpose: Set Time Zone to Auto or manually set to a specific time zone
#
####################################################################################################
#
# HISTORY
#
#   Version 1.0.0, 29-Nov-2022, Andrew Spokes (@andrewsp)
#        Original version
#
####################################################################################################

####################################################################################################
#
# Variables
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Version
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

scriptVersion="1.0.0"

dialogApp="/usr/local/bin/dialog"
LogLocation="/Library/Logs/Set_Time_Zone.log"

####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check for / install swiftDialog
# https://github.com/acodega/dialog-scripts/blob/main/dialogCheckFunction.sh
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
function dialogCheck(){
	# Get the URL of the latest PKG From the Dialog GitHub repo
	dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	#dialogURL="https://github.com/bartreardon/swiftDialog/releases/download/v2.0RC2/dialog-2.0-3810.pkg"
	# Expected Team ID of the downloaded PKG
	expectedDialogTeamID="PWA5E9TQ59"
	# Check for Dialog and install if not found
	if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
		ScriptLogging "Dialog not found. Installing..."
		# Create temporary working directory
		workDirectory=$( /usr/bin/basename "$0" )
		tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )
		# Download the installer package
		/usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"
		# Verify the download
		teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
		# Install the package if Team ID validates
		if [ "$expectedDialogTeamID" = "$teamID" ] || [ "$expectedDialogTeamID" = "" ]; then
			
			/usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
		else
			jamfDisplayMessage "Dialog Team ID verification failed."
			exit 1
		fi
		
		# Remove the temporary working directory when done
		/bin/rm -Rf "$tempDirectory"  
	else
		ScriptLogging "swiftDialog version $($dialogApp --version) found; proceeding..."
		echo "swiftDialog version $($dialogApp --version) found; proceeding..."
	fi
}

ScriptLogging(){
	
	DATE=$(date +%Y-%m-%d\ %H:%M:%S)
	LOG="$LogLocation"
	
	echo "$DATE" " $1" >> $LOG
}

#When user chooses to set their time zone Automatically
setAutomatic()
{
	ScriptLogging "Setting Time Zone to Automatic"
	# Sets auto time zone active to true
	/usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool TRUE
	
	#Temp disable networktime to re-trigger location based time setup
	ScriptLogging "Temporarily disabling network time to reset"
	systemsetup -setusingnetworktime off
	# sleep to give the system a chance to update
	sleep 1
	systemsetup -setusingnetworktime on
	sleep 1
	$dialogApp \
	--small \
	--title "Set Time Zone" \
	--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
	--message "Your Mac's time zone was set to Automatic. You may need to reboot in order for the location to update to the correct time zone."
	
	exit 0
}

# When a user chooses to set their time zone Manually
setManual()
{
	# short time zone list
	name0="London (+0:00)"
	zone[0]="Europe/London"
	
	name1="US Atlantic (-5:00)"
	zone[1]="America/New_York"
	
	name2="US Central (-6:00)"
	zone[2]="America/Chicago"
	
	name3="US Mountain (-7:00)"
	zone[3]="America/Denver"
	
	name4="US Arizona (-7:00/8:00)"
	zone[4]="America/Phoenix"
	
	name5="US Pacific (-8:00)"
	zone[5]="America/Los_Angeles"
	
	name6="More Choices..."
	zone[6]="More Choices"
	
	
	# Display dialog asking to pick from the pre-determined time zone list, or to view more choices
# # # # # # ## # # # # # # - Need to figure out how to properly capture the cancel/info button - # # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # #
	choiceOption=$($dialogApp \
		--small \
		--title "Set Time Zone" \
		--button2text "Cancel" \
		--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
		--message "Your Mac's time zone is currently set to $( date +%Z ). Please choose a new Time Zone, or select More Choices to see an expanded list" \
		--selecttitle "Select a Time Zone" \
		--selectvalues "$name0,$name1,$name2,$name3,$name4,$name5,$name6" | grep "SelectedOption" | awk -F ": " '{print $NF}')
			
	echo "The user chose $choiceOption"
	ScriptLogging "The user chose $choiceOption"
	#Case statement to determine which time zone to set, or to display more choices
	case $choiceOption in
		"London (+0:00)")
			selectedTimeZone="Europe/London"
		;;
		"US Atlantic (-5:00)")
			selectedTimeZone="America/New_York"
		;;
		"US Central (-6:00)")
			selectedTimeZone="America/Chicago"
		;;
		"US Mountain (-7:00)")
			selectedTimeZone="America/Denver"
		;;
		"US Arizona (-7:00/8:00)")
			selectedTimeZone="America/Phoenix"
		;;
		"US Pacific (-8:00)")
			selectedTimeZone="America/Los_Angeles"
		;;
		"More Choices...")
			selectedTimeZone="runDetailedChooser"
		;;
		*)
			exit 0
		;;
	esac
	
	if [[ $selectedTimeZone == "runDetailedChooser" ]];then
		DetailedChooser
	else
		echo "Your time zone will be set to $selectedTimeZone"
		# disable setting time zone automatically
		/usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool False
		
		# set the time zone manually to chosen time zone
		/usr/sbin/systemsetup -settimezone "$selectedTimeZone"
		# sleep to give the system a chance to update
		sleep 1
		$dialogApp \
		--small \
		--title "Set Time Zone" \
		--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
		--message "Your Mac's time zone was manually set to $( date +%Z )."
		
		exit 0
		
	fi

}

#Detailed Chooser logic if the user needs more time zone choices
DetailedChooser()
{
	#This pulls the entire time zone list from systemsetup and only displays the list of regions displayed at the beginning of each time zone
	timeZoneRegion=$(systemsetup -listtimezones | awk -F ' |/' '(NF >= 3) { if ($2 != last_region) { if (last_region) { printf "," } printf $2 } last_region = $2 }')

		# # # # # # ## # # # # # # - Need to figure out how to properly capture the cancel button from this dialog to quit - # # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # ## # # # # # #
	selectedTimeZoneRegion=$($dialogApp \
		--small \
		--title "Set Time Zone" \
		--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
		--message "Please choose your Region to see a list of cities available in that region" \
		--button2text "Cancel" \
		--selecttitle "Select a Region" \
		--selectvalues $timeZoneRegion \ # | grep "SelectedOption" | awk -F " : " '{print $NF}' \

)		
	if [[ $selectedTimeZoneRegion == "" ]]; then 
		exit 0
	fi
	#this takes the region previously selected and filters the available cities from the time zone  list
	timeZoneSubRegions=$(systemsetup -listtimezones | grep "^ ${selectedTimeZoneRegion}/" | cut -d '/' -f 2-)
	timeZoneSubRegions="${timeZoneSubRegions//$'\n'/,}"
		
	selectedTimeZoneCity=$($dialogApp \
		--small \
		--title "Set Time Zone" \
		--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
		--message "Please choose your city for the Time Zone you wish to use" \
		--button2text "Cancel" \
		--selecttitle "Select a City" \
		--selectvalues $timeZoneSubRegions \ # | grep "SelectedOption" | awk -F " : " '{print $NF}'

)
	if [[ $selectedTimeZoneCity == "" ]]; then
		exit 0
	fi
				
	#This combines the selected Region and City back into the format from the Time Zone list in order to set it in the system
	chosenTimeZone="$selectedTimeZoneRegion/$selectedTimeZoneCity"
				
	echo "Your time zone will be set to $chosenTimeZone"
	# disable setting time zone automatically
	/usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool False
	
	# set the time zone manually to chosen time zone
	/usr/sbin/systemsetup -settimezone "$chosenTimeZone"
	# sleep to give the system a chance to update
	sleep 1
	$dialogApp \
		--small \
		--title "Set Time Zone" \
		--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
		--message "Your Mac's time zone was manually set to $( date +%Z )."
				
	exit 0
	
}

#Main Script
dialogCheck

# determine whether time zone is set automatically
setAutomatically=$( /usr/bin/defaults read /Library/Preferences/com.apple.timezone.auto Active )
		
if [ "$setAutomatically" = 0 ]; then # time zone is set manually, offer to set it automatically
	
	$dialogApp \
	--small \
	--title "Set Time Zone" \
	--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
	--message "Your Mac's time zone was manually set to $( date +%Z ). Would you like to try automatically setting it?" \
	--button1text "Automatic" \
	--button2text "Manual" \
	--infobuttontext "Cancel"
	case $? in
		0)
			echo "Pressed Automatic"
			setAutomatic
		;;
		2)
			echo "Pressed Manual"
			setManual
		;;
		3)
			echo "Pressed Cancel"
			exit 0
		;;
		*)
			echo "Something else happened"
		;;
	esac
	
else
	$dialogApp \
	--small \
	--title "Set Time Zone" \
	--icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns \
	--message "Your Mac's time zone was automatically set to $( date +%Z ). Would you like to try manually setting it?" \
	--button1text "Automatic" \
	--button2text "Manual" \
	--infobuttontext "Cancel"
	case $? in
		0)
			echo "Pressed Automatic"
			setAutomatic
		;;
		2)
			echo "Pressed Manual"
			setManual
		;;
		3)
			echo "Pressed Cancel"
			exit 0
		;;
		*)
			echo "Something else happened"
		;;
	esac
fi

