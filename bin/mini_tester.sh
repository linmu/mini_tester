#!/bin/bash

########################
##! @Author:Mu Lin
##! @Date:2015-01-06
##! @TODO:auto_test
########################
CURDATE=$(date "+%Y%m%d")

cd $(dirname $0)
BIN_DIR=$(pwd)
DEPLOY_DIR=${BIN_DIR%/*}

CONF_DIR=$(cd $DEPLOY_DIR/conf && pwd)
CONF_FILE_NAME="tester.conf"

###### load configures ######
source $CONF_DIR/$CONF_FILE_NAME

LOGS_DIR="$DEPLOY_DIR/$LOGS_PATH"
LOG_FILE="$LOGS_DIR/${LOG_FILE_NAME}.$CURDATE"
QUERY_LIST_DIR="$DEPLOY_DIR/$QUERY_LIST_PATH"
QUERY_LIST_FILE="$QUERY_LIST_DIR/$QUERY_LIST_FILE_NAME"
RESPONSE_RESULT_DIR="$DEPLOY_DIR/$RESPONSE_RESULT_PATH"
RESPONSE_RESULT_FILE="$RESPONSE_RESULT_DIR/$RESPONSE_RESULT_FILE_NAME"
PARSE_RESULT_DIR="$DEPLOY_DIR/$PARSE_RESULT_PATH"
PARSE_RESULT_FILE="$PARSE_RESULT_DIR/$PARSE_RESULT_FILE_NAME"

if [[ ! -d $LOGS_DIR ]];then
    mkdir -p $LOGS_DIR
fi
if [[ ! -d $QUERY_LIST_DIR ]];then
    mkdir -p $QUERY_LIST_DIR
fi
if [[ ! -d $RESPONSE_RESULT_DIR ]];then
    mkdir -p $RESPONSE_RESULT_DIR
fi
if [[ ! -d $LOG_PARSE_RESULT_DIR ]];then
    mkdir -p $PARSE_RESULT_DIR
fi

###### load public function #####i
source $BIN_DIR/lib.sh

#input: http_server_name
function startHttpServer()
{
    if [[ $# -ne 1 ]];then 
	    loginfo "need params"
	    failExit "startHttpServer invalid params [$*]"
	fi

	cd $DEPLOY_DIR/$MUT_NAME
	loginfo "starting $1 ..."
	nohup ./$MUT_NAME >> $LOG_FILE > /dev/null 2>&1 &

	sleep 2
	PIDS=$(ps -ef | grep $MUT_NAME | grep -v "grep" | awk -F' ' '{print $2}')
	local ret=$FUNC_SUCC
	if [[ -z "$PIDS" ]];then
		ret=$FUNC_ERROR
	fi

	return $ret
}

#input: http_server_name
function killHttpServer()
{
    if [[ $# -ne 1 ]];then
	    loginfo "need params"
		failExit "killHttpServer ivalid params [$*]"
	fi
    
	loginfo "begin to kill http server $1"
    ps -ef | grep "$1" | grep -v "grep" | awk -F' ' '{print $2}' | xargs -i kill -2 {}
    local ret=$?
    if [[ $ret -ne 0 ]];then
        failExit "kill $1 failed"
    else
	    loginfo "kill $1 successfully"
	fi

	return $ret
}

#input: http_server_name
function deployAndstartHttpServer()
{
    if [[ $# -ne 1 ]];then
	    loginfo "need params"
		failExit "deployAndstartHttpServer invalid params [$*]"
	fi

	loginfo "look up if there already have process of $1"
	local count=$(ps -ef | grep "$1" | grep -v "grep" | wc -l)
    if [[ $count -ne 0 ]];then
        loginfo "$1 has already started, kill $1"
		killHttpServer "$1"
	fi

	loginfo "$1 is not started, begin to unzip package first ..."
	cd $DEPLOY_DIR
	if [[ -d $MUT_NAME ]];then
	    loginfo "directory of $MUT_NAME has already exist, delete it"
		rm -rf $MUT_NAME
	fi

	if [[ ! -e $MUT_FILE ]];then
	    failExit "Packge $MUT_FILE doesn't exist"
	fi
	tar -xzvf $MUT_FILE > /dev/null 2>&1
	cd $MUT_NAME
	cp ./bin/$MUT_NAME .

	loginfo "begin to localize config file ..."
	sed -i "s/^port:.*$/port: $PORT/g" ./conf/server.conf
	sed -i "s/^data_path:.*$/data_path: \.\/data\/$DICT_FILE/g" ./conf/server.conf

	loopInvocation "startHttpServer $1"
	ret=$?
	if [[ $ret -ne $FUNC_SUCC ]];then
	    loginfo "$1 start failed"
	    ret=$FUNC_ERROR
	else
	    loginfo "$1 start successfully"
	fi

	return $ret
}

#input: query_dict_file response_result_file
function getResponsefromHttpServer()
{
    if [[ $# -ne 2 ]];then
        loginfo "need params"
		failExit "getResponsefromHttpServer invalid params [$*]"
	fi

	if [[ -e "$2" ]];then
        loginfo "response result file $2 already exists, delete it"
		rm -rf "$2"
	fi

	while read line
	do
        sendRequesttoHttpServer "http://$HOST:$PORT$line" "$2"
	done < $1
}

loginfo "++++++++++++++++++++++++++  auto test begin ++++++++++++++++++++++++++"

printMsg "get tested package from ftp server"
loopInvocation "getFilefromFtp $MUT_FTP_PATH $MUT_FILE $DEPLOY_DIR $TMP_FILE"

printMsg "get data dict and md5 file from ftp server"
loopGetFileandCompareMD5 "$QUERY_LIST_FTP_PATH" "$QUERY_LIST_FILE_NAME" "$QUERY_LIST_MD5_FILE_NAME" "$QUERY_LIST_DIR" "$TMP_FILE"

printMsg "begin to deploy and start the http server ..."
deployAndstartHttpServer "$MUT_NAME"
if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "$MUT_NAME start failed"
	failExit "$MUT_NAME start failed"
else
    printMsg "$MUT_NAME start successfully"
fi

printMsg "Begin to send requests to the http server ..."
getResponsefromHttpServer "$QUERY_LIST_FILE" "$RESPONSE_RESULT_FILE"

if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "Send requests to http server failed"
	failExit "Send requests to http server failed"
else
    printMsg "Send requests to http server done"
fi

sleep 2

killHttpServer "$MUT_NAME"
if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "kill $1 failed"
	failExit "kill $1 failed"
else 
    printMsg "kill $1 successfully"
fi
	
loginfo "++++++++++++++++++++++++++  auto test end ++++++++++++++++++++++++++"


