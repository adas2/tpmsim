#!/bin/sh

# error handler
abort()
{
    echo >&2 '
***************
*** ABORTED ***
***************
'
    echo "An error occurred. Exiting..." >&2
    exit 1
}

trap 'abort' 0

set -e

# Add your script below....
# If an error occurs, the abort() function will be called.
#----------------------------------------------------------


user_token=$1
GHE_HOST="github.com"
OS_TYPE=$(uname)
#OS_VERSION=$(cat /etc/*release | grep "Version")
REPO_NAME="https://${user_token}@${GHE_HOST}/adas2/swtpm_1.2.git"


usage(){
	echo >&2 '
*******
USAGE    
*******
'
	echo $0 "[ OPTIONS ]"
	echo "\t -t <github user token>"
	echo "\t -d <install directpry>"
	exit 1
}


check_env() {
	echo "Checking environment"
	if [OS_TYPE != 'Linux']
	then
		exit 1;
	fi

}

clone_repos() {
	echo "Cloning SW TPM1.2 from $REPO_NAME"
}


# start activity

if [ "$#" -lt 2 ]; then
    echo "Please check usage and enter command line arguments"
    usage
fi

clone_repos





#----------------------------------------------------------
# Done!

trap : 0

echo >&2 '
************
*** DONE *** 
************
'