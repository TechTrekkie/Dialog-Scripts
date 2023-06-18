#!/bin/bash

####################################################################################################
#
# Jamf Connect User Name Change via swiftDialog
#
####################################################################################################
#
# HISTORY
#
#   Version 1.0.0, 20-Jan-2023, Andrew Spokes (@TechTrekkie)
#   - Initial Version
#	Version 1.1.0, 22-Jan-2023, Andrew Spokes (@TechTrekkie)
#	- Converted to Swift Dialog, built in logging and error messaging
#	Version 1.2.0, 19-Feb-2023, Andrew Spokes (@TechTrekkie)
#	- Added logic to update additional user name attributes (necessary to fix password change issues)
#	- Updated icons for hardware type, sucess and failure messaging
#	- Updated logic for testing Full Disk Access to prevent TCC database contents from appearing in the logs
#
####################################################################################################

####################################################################################################
#
# Variables
#
####################################################################################################


scriptLog="${4:-"/var/log/org.applecomputer.log"}"                        # Parameter 4: Script Log Location [ /var/log/org.applecomputer.log ] (i.e., Your organization's default location for client-side logs)
scriptVersion="1.2.0"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin/
dialogApp="/usr/local/bin/dialog"
loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
loggedInUserFullname=$( id -F "${loggedInUser}" )
loggedInUserFirstname=$( echo "$loggedInUserFullname" | cut -d " " -f 1 )

####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Run command as logged-in user (thanks, @scriptingosx!)
# shellcheck disable=SC2145
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function runAsUser() {
	
	updateScriptLog "Run \"$@\" as \"$loggedInUserID\" … "
	launchctl asuser "$loggedInUserID" sudo -u "$loggedInUser" "$@"
	
}


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check for / install swiftDialog (Thanks, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogCheck() {
	
	# Get the URL of the latest PKG From the Dialog GitHub repo
	dialogURL=$(curl --silent --fail "https://api.github.com/repos/bartreardon/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	
	# Expected Team ID of the downloaded PKG
	expectedDialogTeamID="PWA5E9TQ59"
	
	# Check for Dialog and install if not found
	if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
		
		updateScriptLog "Dialog not found. Installing..."
		
		# Create temporary working directory
		workDirectory=$( /usr/bin/basename "$0" )
		tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )
		
		# Download the installer package
		/usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"
		
		# Verify the download
		teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
		
		# Install the package if Team ID validates
		if [[ "$expectedDialogTeamID" == "$teamID" ]]; then
			
			/usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
			sleep 2
			updateScriptLog "swiftDialog version $(dialog --version) installed; proceeding..."
			
		else
			
			# Display a so-called "simple" dialog if Team ID fails to validate
			runAsUser osascript -e 'display dialog "Error:\r\r• Dialog Team ID verification failed\r\r" with title "User Name Change: Error" buttons {"Close"} with icon caution'
			exit 1
			
		fi
		
		# Remove the temporary working directory when done
		/bin/rm -Rf "$tempDirectory"  
		
	else
		
		updateScriptLog "swiftDialog version $(dialog --version) found; proceeding..."
		
	fi
	
}
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Script Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
	echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

function errorMessaging() {
	
	icon="SF=xmark.circle.fill,weight=bold,colour1=#BB1717,colour2=#F31F1F"
	
	echo "an error has occurred, display error message"
	title="Error Occurred"
	dialogCMD="$dialogApp -p --title \"$title\" \
	--icon \"$icon\" \
	--message \"$message\" \
	--small \
	--button1 \"Exit\""
	
	eval "$dialogCMD"
	exit 0
}

function exitMessaging() {

	icon="SF=checkmark.circle.fill,weight=bold,colour1=#00ff44,colour2=#075c1e"

	title="User Name Change Successful"
	dialogCMD="$dialogApp -p --title \"$title\" \
	--icon \"$icon\" \
	--message \"$message\" \
	--small \
	--button1 \"Exit\""

	eval "$dialogCMD"
	exit 0
}


function userNameChange() {
	
	echo "Running User Name Change"
	updateScriptLog "Running User Name Change"
	
	oldUserName=$(echo "$userInput"| grep "Old User Name" | awk -F " : " '{print $NF}')
	newUserName=$(echo "$userInput"| grep "New User Name" | awk -F " : " '{print $NF}')
	newFullName=$(echo "$userInput"| grep "Users Full Name" | awk -F " : " '{print $NF}')
	
	d=$(date +%Y-%m-%d--%I:%M:%S)
	log="${d} JC_RENAME:"
	LogLocation="/Library/Logs/user_name_change.log"
	# Create the log file
	touch $LogLocation
	# Open permissions to account for all error catching
	chmod 777 $LogLocation
	
	# Ensures that script is run as ROOT
	if [[ "${UID}" != 0 ]]; then
		echo "${log} Error: $0 script must be run as root" 2>&1 | tee -a $LogLocation
		message="Script must be run as root"
		errorMessaging
	fi
	
	# Begin Logging
	echo "${log} ## Rename Script Begin ##" 2>&1 | tee -a $LogLocation
	echo "${log} Old User Name set as $oldUserName" 2>&1 | tee -a $LogLocation
	echo "${log} New User Name set as $newUserName" 2>&1 | tee -a $LogLocation
	echo "${log} Full Name set as $newFullName" 2>&1 | tee -a $LogLocation
	
	oldUserAlias=$(dscl . read /Users/$oldUserName RecordName | awk {'print $3'})
	echo "${log} Old User Alias set to $oldUserAlias" 2>&1 | tee -a $LogLocation
	
	#Unmigrate old username from current IPD
	echo "${log} Unmigrating $oldUserName from Jamf Connect" 2>&1 | tee -a $LogLocation
	dscl . delete /Users/$oldUserName RecordName $oldUserAlias
	dscl . delete /Users/$oldUserName dsAttrTypeStandard:NetworkUser
	dscl . delete /Users/$oldUserName dsAttrTypeStandard:OIDCProvider
	dscl . delete /Users/$oldUserName dsAttrTypeStandard:OktaUser
	dscl . delete /Users/$oldUserName dsAttrTypeStandard:AzureUser
	
	#Test for IDP disconnection from user name
	IDP=$(dscl . -read /Users/$oldUserName | grep "OIDCProvider: " | awk {'print $2'})
	
	if [[ -z $IDP ]]; then
		echo "User account $oldUserName disconnected from IDP user name successfully"
		echo "${log} User account $oldUserName disconnected from IDP user name successfully" 2>&1 | tee -a $LogLocation
		echo "${log} Continuing with User Name Change" 2>&1 | tee -a $LogLocation
	else
		echo "User account $oldUserName was not disconnected from IDP user name"
		echo "${log} Error: User account $oldUserName failed to disconnect from IDP, exiting" 2>&1 | tee -a $LogLocation
		message="User account $oldUserName failed to disconnect from IDP user name"
		errorMessaging
	fi


	# Ensure Script has been granted Full Disk Access
	access=$(sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db 'SELECT * from access')
	if [[ $? -ne 0 ]]; then
		echo "${log} Error: This tool does not appear to have the correct access!" 2>&1 | tee -a $LogLocation
		echo "${log} Error: Please grant this tool Full Disk Access and try again." 2>&1 | tee -a $LogLocation
		message="Error: This tool does not appear to have the correct access! Please grant Full Disk Access and try again"
		errorMessaging
	fi
	
	#Variable mapping from merging multiple scripts into one
	oldUser=$oldUserName
	newUser=$newUserName
	
	# Test to ensure logged in user is not being renamed
	readonly loggedInUser=$(ls -la /dev/console | cut -d " " -f 4)
	if [[ "${loggedInUser}" == "${oldUser}" ]]; then
		echo "${log} Error: Cannot rename active GUI logged in user. Log in with another admin account and try again." 2>&1 | tee -a $LogLocation
		message="Cannot rename active GUI logged in user. Log in with another admin account and try again."
		errorMessaging
	fi
	
	# Verify valid usernames
	if [[ -z "${newUser}" ]]; then
		echo "${log} Error: New user name must not be empty!" 2>&1 | tee -a $LogLocation
		message="New user name must not be empty!"
		errorMessaging
	fi
	
	# Test to ensure account update is needed
	if [[ "${oldUser}" == "${newUser}" ]]; then
		echo "${log} Error: Account ${oldUser} is the same name ${newUser}" 2>&1 | tee -a $LogLocation
		message="Account ${oldUser} is the same name ${newUser}"
		errorMessaging
	fi
	
	# Query existing user accounts
	readonly existingUsers=($(dscl . -list /Users | grep -Ev "^_|com\..*|root|nobody|daemon|\/" | cut -d, -f1 | sed 's|CN=||g'))
	
	# Ensure old user account is correct and account exists on system
	if [[ ! " ${existingUsers[@]} " =~ " ${oldUser} " ]]; then
		echo "${log} Error: ${oldUser} account not present on system to update" 2>&1 | tee -a $LogLocation
		message="${oldUser} account not present on system to update"
		errorMessaging
	fi
	
	# Ensure new user account is not already in use
	if [[ " ${existingUsers[@]} " =~ " ${newUser} " ]]; then
		echo "${log} Error: ${newUser} account already present on system. Cannot add duplicate" 2>&1 | tee -a $LogLocation
		message="${newUser} account already present on system. Cannot add duplicate"
		errorMessaging
	fi
	
	# Query existing home folders
	readonly existingHomeFolders=($(ls /Users))
	
	# Ensure existing home folder is not in use
	if [[ " ${existingHomeFolders[@]} " =~ " ${newUser} " ]]; then
		echo "${log} Error: ${newUser} home folder already in use on system. Cannot add duplicate" 2>&1 | tee -a $LogLocation
		message="${newUser} home folder already in use on system. Cannot add duplicate"
		errorMessaging
	fi
	
	# Check if username differs from home directory name
	actual=$(eval echo "~${oldUser}")
	if [[ "/Users/${oldUser}" != "$actual" ]]; then
		echo "${log} Error: Username differs from home directory name!" 2>&1 | tee -a $LogLocation
		echo "${log} Error: home directory: ${actual} should be: /Users/${oldUser}, aborting." 2>&1 | tee -a $LogLocation
		message="Username differs from home directory. home directory: ${actual} should be: /Users/${oldUser}, aborting."
		errorMessaging
	fi
	
	# Checks if user is logged in
	loginCheck=$(ps -Ajc | grep -w ${oldUser} | grep loginwindow | awk '{print $2}')
	
	# Logs out user if they are logged in
	timeoutCounter='0'
	while [[ "${loginCheck}" ]]; do
		echo "${log} Notice: ${oldUser} account logged in. Logging user off to complete username update" 2>&1 | tee -a $LogLocation
		sudo launchctl bootout gui/$(id -u ${oldUser})
		Sleep 5
		loginCheck=$(ps -Ajc | grep -w ${oldUser} | grep loginwindow | awk '{print $2}')
		timeoutCounter=$((${timeoutCounter} + 1))
		if [[ ${timeoutCounter} -eq 4 ]]; then
			echo "${log} Error: Timeout unable to log out ${oldUser} account" 2>&1 | tee -a $LogLocation
			message="Timeout unable to log out ${oldUser} account"
			errorMessaging
		fi
	done
	
	# Captures current NFS home directory
	readonly origHomeDir=$(dscl . -read "/Users/${oldUser}" NFSHomeDirectory | awk '{print $2}' -)
	
	if [[ -z "${origHomeDir}" ]]; then
		echo "${log} Error: Cannot obtain the original home directory name, is the ${oldUser} name correct?" 2>&1 | tee -a $LogLocation
		message="Cannot obtain the original home directory name, is the ${oldUser} name correct?"
		errorMessaging
	fi
	
	# Updates NFS home directory
	sudo dscl . -change "/Users/${oldUser}" NFSHomeDirectory "${origHomeDir}" "/Users/${newUser}"
	
	if [[ $? -ne 0 ]]; then
		echo "${log} Error: Could not rename the user's home directory pointer, aborting further changes! - err=$?" 2>&1 | tee -a $LogLocation
		echo "${log} Notice: Reverting Home Directory changes" 2>&1 | tee -a $LogLocation
		sudo dscl . -change "/Users/${oldUser}" NFSHomeDirectory "/Users/${newUser}" "${origHomeDir}"
		message="Could not rename the user's home directory pointer, aborting changes and reverting Home Directory changes."
		errorMessaging
	fi
	
	# Updates name of home directory to new username
	mv "${origHomeDir}" "/Users/${newUser}"
	
	if [[ $? -ne 0 ]]; then
		echo "${log} Error: Could not rename the user's home directory in /Users" 2>&1 | tee -a $LogLocation
		echo "${log} Notice: Reverting Home Directory changes" 2>&1 | tee -a $LogLocation
		mv "/Users/${newUser}" "${origHomeDir}"
		sudo dscl . -change "/Users/${oldUser}" NFSHomeDirectory "/Users/${newUser}" "${origHomeDir}"
		message="Could not rename the user's home directory in /Users. Reverting Home Directory changes."
		errorMessaging
	fi
	
	#Changes the users full name
	oldFullName=$(dscl . -read "/Users/${oldUser}" RealName | sed -n 's/^ //g;2p')
	sudo dscl . -change "/Users/${oldUser}" RealName "${oldFullName}" "${newFullName}"
	
	# Actual username change
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_AvatarRepresentation "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_hint "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_inputSources "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_jpegphoto "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_passwd "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_picture "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_unlockOptions "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_UserCertificate "${oldUser}" "${newUser}"
	sudo dscl . -change "/Users/${oldUser}" RecordName "${oldUser}" "${newUser}"
	
	if [[ $? -ne 0 ]]; then
		echo "${log} Error: Could not rename the user's RecordName in dscl - the user should still be able to login, but with user name ${oldUser}" 2>&1 | tee -a $LogLocation
		echo "${log} Notice: Reverting username change" 2>&1 | tee -a $LogLocation
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_AvatarRepresentation "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_hint "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_inputSources "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_jpegphoto "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_passwd "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_picture "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_unlockOptions "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" dsAttrTypeNative:_writers_UserCertificate "${newUser}" "${oldUser}"
		sudo dscl . -change "/Users/${oldUser}" RecordName "${newUser}" "${oldUser}"
		echo "${log} Notice: Reverting Home Directory changes" 2>&1 | tee -a $LogLocation
		mv "/Users/${newUser}" "${origHomeDir}"
		sudo dscl . -change "/Users/${oldUser}" NFSHomeDirectory "/Users/${newUser}" "${origHomeDir}"
		message="Could not rename the user's RecordName in dscl - the user should still be able to login, but with user name ${oldUser}. Reverting username change."
		errorMessaging
	fi
	
	# Links old home directory to new. Fixes dock mapping issue
	ln -s "/Users/${newUser}" "${origHomeDir}"
	# Success message
	read -r -d '' successOutput <<EOM
${log} Success ${oldUser} username has been updated to ${newUser}
${log} Folder "${origHomeDir}" has been renamed to "/Users/${newUser}"
${log} RecordName: ${newUser}
${log} NFSHomeDirectory: "/Users/${newUser}"
${log} Please restart the system to complete username update.
EOM
	
	echo "${successOutput}" 2>&1 | tee -a $LogLocation
	
	message="The username $oldUserName has been successfully changed to $newUserName . Please make sure the local password for this account matches the IDP password to avoid login issues
Please restart the system to complete the username update."
	exitMessaging
	

	#Check a User's SecureToken Status
	#sudo sysadminctl -secureTokenStatus [user being checked]
	
	#dscl Alternative to Check a User's SecureToken Status
	#dscl . -read /Users/[user being checked] AuthenticationAuthority
	
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate logged-in user
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ -z "${loggedInUser}" || "${loggedInUser}" == "loginwindow" ]]; then
	echo "No user logged-in; exiting."
	exit 1
else
	loggedInUserID=$(id -u "${loggedInUser}")
fi

dialogCheck


title="User Name Change"
message="Enter the user information below"

# Set initial icon based on whether the Mac is a desktop or laptop
if system_profiler SPPowerDataType | grep -q "Battery Power"; then
	icon="SF=laptopcomputer.and.arrow.down,weight=semibold,colour1=#ef9d51,colour2=#ef7951"
else
	icon="SF=desktopcomputer.and.arrow.down,weight=semibold,colour1=#ef9d51,colour2=#ef7951"
fi

dialogCMD="$dialogApp -p --title \"$title\" \
--icon \"$icon\" \
--message \"$message\" \
--small \
--button2 \"Cancel\" \
--textfield \"Old User Name:,required\" \
--textfield \"New User Name:,required\" \
--textfield \"Users Full Name:,required\""


userInput=$( eval "$dialogCMD" )
case $? in
	0)
		echo "Pressed OK"
		userNameChange
	;;
	2)
		echo "Pressed Cancel Button (button 2)"
	;;
	4)
		echo "Timer Expired"
	;;
	10)
		echo "Quit"
	;;
	20)
		echo "Do Not Disturb is Enabled"
	;;
esac