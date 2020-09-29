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

# If an error occurs, the abort() function will be called.
#----------------------------------------------------------

PROJ_DIR=$(pwd)
GHE_HOST="github.com"
UNAME="a-das"
OS_TYPE=$(uname)
OS_NAME=$(cat /etc/*release | grep NAME | grep -v "_" | cut -d '=' -f 2)
OS_VERSION=$(cat /etc/*release | grep VERSION_ID  | cut -d '=' -f 2)
OS_NAME="${OS_NAME%\"}"
OS_NAME="${OS_NAME#\"}"
OS_VERSION="${OS_VERSION%\"}"
OS_VERSION="${OS_VERSION#\"}"
TPM_REPO="swtpm_1.2"
GOTPM_REPO="go-tpm"
LOG_FILE="build.log"
gotpm_branch="master"

usage(){
	echo >&2 '
*******
USAGE    
*******
'
	echo $0 '[ OPTIONS ] [ COMMAND ]
	Options:
		-t <github user token>
		-d <install directory, default: cwd>
		-p <tpm port, default: 6000>
        Commands:
		-b [ build, install and start SW-TPM 1.2 ]
	  	-r [ restart SW-TPM without fresh build ]
	  	-s [ stop SW-TPM without un-installing ]
	  	-i [ install go-tpm package for tpm operation ]
'
	echo ''
}

# Parse options
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
#output_file=""
verbose=0
user_token=""
tpm_port="6000"
install_dir=$PROJ_DIR
restart_op=false
stop_op=false
init_op=false
build_op=false

while getopts "h?t:p:d:brsi" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    t)  user_token=$OPTARG
        ;;
    d)  install_dir=$OPTARG
        ;;
    p)  tpm_port=$OPTARG
        ;;
    b)  build_op=true
        ;;
    r)  restart_op=true
        ;;
    s)  stop_op=true
        ;;
    i)  init_op=true
        ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

#echo 'Leftovers: ${@}'
# set fault handler
trap 'abort' 0
set -e

check_token() {
        #if Centos user token needs to be provided
        if [ $user_token = "" ]
        then
        	echo "Please provide a valid Git user token for $GHE_HOST"
        	usage
        	exit 1
        fi
}

# functions
install_pkgs_centos() {
	echo "Installing packages (need sudo access)"
	yum install -y screen openssl-devel trousers-devel automake autoconf libtool glibc-devel
}

install_pkgs_ubuntu() {
	echo "Installing packages (need sudo access)"
	apt-get install -y libtspi-dev trousers-dbg libssl-dev automake autoconf libtool
}

check_env() {
	echo "Checking environment"
	if [ "$OS_TYPE"=="Linux" ]
	then
		#echo "OS $OS_NAME"
		if [ "$OS_NAME" = "Ubuntu" ] && [ "$OS_VERSION" = "16.04" ]
		then
			#check_token
			install_pkgs_ubuntu
		elif [ "$OS_NAME" = "CentOS Linux" ] && [ "$OS_VERSION" = "7" ] 
		then
			check_token
			install_pkgs_centos
		else
			echo "Unsupported OS $OS_NAME $OS_VERSION"
			exit 1
		fi
	else 
		echo "Unsupported OS type $OS_TYPE"
		exit 1
	fi

}

cleanup() {
       cat /dev/null > ${install_dir}/$LOG_FILE
       rm -rf ${install_dir}/tpm*.log
       rm -rf ${install_dir}/tpm_state
}

clone_repos() {
	echo "Cloning from $TPM_REPO"
	rm -rf "$install_dir/$TPM_REPO"
	cd $install_dir
	if [ "$OS_NAME" != "Ubuntu" ]
	then
		git clone "https://${user_token}@${GHE_HOST}/${UNAME}/${TPM_REPO}.git"
	else
		git clone "git@${GHE_HOST}:${UNAME}/${TPM_REPO}.git"
	fi
}

check_tpm_server() {
	PID=`ps -eaf | grep tpm_server | grep -v grep | awk '{print $2}'`
	if [ "" =  "$PID" ] 
	then
		echo 'tpm_server launch error'
		exit 1
	fi

}

swtpm_start() {
	# start tpm_server
	mkdir -p "$install_dir/tpm_state"
	export TPM_PATH="$install_dir/tpm_state"
	export TPM_PORT=$tpm_port
	#screen -d -m -S tpm_server sh $PROJ_DIR/tpm_server.sh $tpm_port
	screen -d -m -S tpm_server  $install_dir/$TPM_REPO/tpm/tpm_server
	echo "tpm_server start success"
	sleep 3

	# start utils
	unset TPM_PATH
	unset TPM_PORT
	cd "$install_dir/$TPM_REPO/libtpm/utils"
	#su centos
	export TPM_SERVER_NAME=localhost
	export TPM_SERVER_PORT=$tpm_port
	./tpmbios
	#echo "tpmbios Success"
	#./createek
	./physicalpresence -c
	./physicalpresence -x 04
	./nv_definespace -in ffffffff -sz 0
	echo "Creating EK..."
	./createek
	echo "swtpm start success"
}

build_swtpm() {
	echo "Building SW TPM 1.2 ..."
	echo "Using build path $install_dir"
	echo "Using TPM_PORT = $tpm_port"

	# server
	cd "$install_dir/$TPM_REPO/tpm"
	# build TPM with default enabled, activatedoption (char device will not work in VM)
	make -f makefile-en-ac >> ${install_dir}/$LOG_FILE 2>&1 

	# lib, utils
	cd "$install_dir/$TPM_REPO/libtpm"
	./autogen 2>&1 >> ${install_dir}/$LOG_FILE
	./configure 2>&1 >> ${install_dir}/$LOG_FILE
	make 2>&1 >> ${install_dir}/$LOG_FILE
}

start_tcsd() {
	echo "Checking tcsd demon"
	export TCSD_TCP_DEVICE_PORT=$tpm_port
	screen -d -m -S tcsd /usr/sbin/tcsd -e -f &
}


restart_tpm() {
	#kill if running
	#PID=`ps -eaf | grep tpm_server | grep -v grep | awk '{print $2}'`
	#if [ "" !=  "$PID" ] 
	#then
	#	echo "killing $PID"
	#    	kill -9 $PID
	#fi
	stop_tpm
	#restart TPM Server
	#cd "$install_dir/$TPM_REPO/tpm"
	export TPM_PATH="$install_dir/tpm_state"
	export TPM_PORT=$tpm_port
	#screen -d -m -S tpm_server ./tpm_server
	screen -d -m -S tpm_server  $install_dir/$TPM_REPO/tpm/tpm_server >| tpm${tpm_port}.log
	sleep 3

	# libtpm/utils
	cd "$install_dir/$TPM_REPO/libtpm/utils"
	export TPM_SERVER_NAME=localhost
	export TPM_SERVER_PORT=$tpm_port
	./tpmbios
}

stop_tpm() {
        #kill if running
	PID=`ps -eaf | grep tpm_server | grep -v grep | awk '{print $2}'`
	if [ "" !=  "$PID" ] 
	then
		echo "killing $PID"
		kill -9 $PID
	fi
        PID=`ps -eaf | grep tcsd | grep -v grep | awk '{print $2}'`
	if [ "" !=  "$PID" ] 
	then
		echo "killing $PID"
		kill -9 $PID
	fi
	screen -wipe || true
        #screen -X -S tpm_server quit
        #screen -X -S tcsd quit
}



get_go_tpm() {
	# install go tpm tools for app layer
	echo "Cloning $GOTPM_REPO"
	rm -rf "$install_dir/$GOTPM_REPO"
	cd $install_dir
	if [ "$OS_NAME" != "Ubuntu" ]
	then
		git clone "https://${user_token}@${GHE_HOST}/${UNAME}/${GOTPM_REPO}.git" -b "$gotpm_branch"
	else
		git clone "git@${GHE_HOST}:${UNAME}/${GOTPM_REPO}.git" -b "$gotpm_branch"
	fi
	# build go tpm
}


build_go_tpm() {
	#yum install -y golang
	rm -rf ${install_dir}/build
	export BUILD_PATH=${install_dir}/build
	#  additional steps to install go-tpm
}

# main
if [ $build_op = true ]
then
	#cat /dev/null > ${install_dir}/$LOG_FILE
	cleanup
	check_env
	clone_repos
	build_swtpm
	swtpm_start
	start_tcsd
elif [ $restart_op = true ]
then
	restart_tpm
	start_tcsd
elif [ $stop_op = true ]
then
	stop_tpm
elif [ $init_op = true ]
then
	get_go_tpm
	build_go_tpm
else
    echo 'Unkown command. Please see usage'
    exit 1
fi


#----------------------------------------------------------
# Done!

trap : 0

echo >&2 '
************
*** DONE *** 
************
'