#!/bin/bash

########################
##! @Author: Mu Lin
##! @Date: 2015-01-06
##! @TODO: auto_test
########################
PROGRAM=$(basename $0)
VERSION="1.0"
CURDATE=$(date "+%Y%m%d")

set -o pipefail

cd $(dirname $0)
BIN_DIR=$(pwd)
DEPLOY_DIR=${BIN_DIR%/*}

CONF_DIR=$(cd $DEPLOY_DIR/conf && pwd)
CONF_FILE_NAME=

##! @TODO: echo usage
##! @AUTHOR: Mu Lin
function usage()
{
    echo "$PROGRAM usage: [-h] [-v] [-c 'config file name']"
}

##! @TODO: echo usage and exit
##! @IN: $1 => exit code
##! @AUTHOR: Mu Lin
function usage_and_exit()
{
    usage
    exit $1
}

##! @TODO: echo program version
##! @AUTHOR: Mu Lin
function version()
{
    echo "$PROGRAM version $VERSION"
}

######### handle input parameters ##########
if [[ $# -lt 1 ]];then
    usage_and_exit 1
fi

while getopts :c:vh opt
do
    case $opt in
    c)  CONF_FILE_NAME=$OPTARG
        ;;
    v)  version
        exit 0
        ;;
    h)  usage_and_exit 0
        ;;
    ':') echo "$PROGRAM -$OPTARG requires an argument" >&2
        usage_and_exit 1
        ;;
    '?') echo "$PROGRAM: invalid option $OPTARG" >&2
        usage_and_exit 1
        ;;
    esac
done
shift $(($OPTIND-1))

###### load configures ######
source ${CONF_DIR}/${CONF_FILE_NAME}

LOGS_DIR="${DEPLOY_DIR}/${LOGS_PATH}"
LOG_FILE="${LOGS_DIR}/${LOG_FILE_NAME}.$CURDATE"
QUERY_LIST_DIR="${DEPLOY_DIR}/${QUERY_LIST_PATH}"
QUERY_LIST_FILE="${QUERY_LIST_DIR}/${QUERY_LIST_FILE_NAME}"
RESPONSE_RESULT_DIR="${DEPLOY_DIR}/${RESPONSE_RESULT_PATH}"
RESPONSE_RESULT_FILE="${RESPONSE_RESULT_DIR}/${RESPONSE_RESULT_FILE_NAME}"
PARSE_RESULT_DIR="${DEPLOY_DIR}/${PARSE_RESULT_PATH}"
PARSE_RESULT_FILE="${PARSE_RESULT_DIR}/${PARSE_RESULT_FILE_NAME}"

if [[ ! -d ${LOGS_DIR} ]];then
    mkdir -p ${LOGS_DIR}
fi
if [[ ! -d ${QUERY_LIST_DIR} ]];then
    mkdir -p ${QUERY_LIST_DIR}
fi
if [[ ! -d ${RESPONSE_RESULT_DIR} ]];then
    mkdir -p ${RESPONSE_RESULT_DIR}
fi
if [[ ! -d ${LOG_PARSE_RESULT_DIR} ]];then
    mkdir -p ${PARSE_RESULT_DIR}
fi

###### load public function #####
source ${BIN_DIR}/lib.sh

##! @TODO: start http server
##! @AUTHOR: Mu Lin
##! @IN: $1 => http server name
##! @OUT: $FUNC_SUCC => success; $FUNC_ERROR => failure
function startHttpServer()
{
    if [[ $# -ne 1 ]];then
        loginfo "need params"
        failExit "startHttpServer invalid params [$*]"
    fi

    cd ${DEPLOY_DIR}/$1 || failExit "cd ${DEPLOY_DIR}/$1 failed"
    loginfo "starting $1 ..."
    nohup ./$1 > /dev/null 2>&1 &
    sleep 2

    local PIDS=$(pgrep -f "$1")
    local ret=$FUNC_SUCC

    if [[ -z "$PIDS" ]];then
        ret=$FUNC_ERROR
    fi

    return $ret
}

##! @TODO: stop http server
##! @AUTHOR: Mu Lin
##! @IN: $1 => http server name
##! @OUT: $FUNC_SUCC => success; $FUNC_ERROR => failure
function killHttpServer()
{
    if [[ $# -ne 1 ]];then
        loginfo "need params"
        failExit "killHttpServer invalid params [$*]"
    fi
    
    loginfo "begin to kill http server $1"
    pgrep -f "$1" | xargs -i kill -2 {}
    local ret=$?
    sleep 2
    local count=$(pgrep -f "$1" | wc -l)
    if [[ $count -ne 0 ]];then
        loginfo "force to kill $1"
        pgrep -f "$1" | xargs -i kill -9 {}
        ret=$?
    fi

    if [[ $ret -ne $FUNC_SUCC ]];then
        failExit "kill $1 failed"
    else
        loginfo "kill $1 successfully"
    fi

    return $ret
}

##! @TODO: deploy http server and start it
##! @AUTHOR: Mu Lin
##! @IN: $1 => http server name
##! @IN: $2 => http server package name
##! @OUT: $FUNC_SUCC => success; $FUNC_ERROR => failure
function deployAndstartHttpServer()
{
    if [[ $# -ne 2 ]];then
        loginfo "need params"
        failExit "deployAndstartHttpServer invalid params [$*]"
    fi

    loginfo "look up if there already have process of $1"
    local count=$(pgrep -f "$1" | wc -l)
    if [[ $count -ne 0 ]];then
        loginfo "$1 has already started, kill $1"
        killHttpServer "$1"
        if [[ $? -ne $FUNC_SUCC ]];then
            failExit "kill $1 failed"
        fi
    fi

    loginfo "$1 is not started, begin to unzip package first ..."
    cd "${DEPLOY_DIR}" || failExit "cd ${DEPLOY_DIR} failed"
    if [[ -d $1 ]];then
        loginfo "directory of $1 has already exist, delete it"
        rm -rf $1
    fi

    if [[ ! -e $2 ]];then
        failExit "Packge $2 doesn't exist"
    fi

    tar -xzvf $2 > /dev/null 2>&1
    if [[ $? -ne $FUNC_SUCC ]];then
        failExit "unfold $2 failed"
    fi

    cd "$1" && cp ./bin/$1 . || failExit "cd $1 or cp $1 failed"

    loginfo "begin to localize config file ..."
    sed -i "s/^port:.*$/port: $PORT/g" ./conf/server.conf
    sed -i "s/^data_path:.*$/data_path: \.\/data\/${DICT_FILE}/g" ./conf/server.conf

    loopInvocation "startHttpServer $1"
    local ret=$?
    if [[ $ret -ne $FUNC_SUCC ]];then
        loginfo "$1 start failed"
        ret=$FUNC_ERROR
    else
        loginfo "$1 start successfully"
    fi

    return $ret
}

##! @TODO: get response from the http server
##! @AUTHOR: Mu Lin
##! @IN: $1 => query list file
##! @IN: $2 => response result file
##! @OUT: $FUNC_SUCC => success; $FUNC_ERROR => failure
function getResponsefromHttpServer()
{
    if [[ $# -ne 2 ]];then
        loginfo "need params"
        failExit "getResponsefromHttpServer invalid params [$*]"
    fi

    if [[ ! -e "$1" ]];then
        failExit "query list file $1 doesn't exist"
    fi

    if [[ -e "$2" ]];then
        loginfo "response result file $2 already exists, delete it"
        rm -rf "$2"
    fi

    while read line
    do
        sendRequesttoHttpServer "http://$HOST:$PORT$line" "$2"
    done < "$1"

    local ret=$?
    return $ret
}

##! @TODO: parse http server log file
##! @AUTHOR: Mu Lin
##! @IN: $1 => parse tool awk file
##! @IN: $2 => http server log file
##! @IN: $3 => parse result file
##! @OUT: $FUNC_SUCC => success; $FUNC_ERROR => failure
function parse_log()
{
    if [[ $# -ne 3 ]];then
        loginfo "need params"
        failExit "parse_log invalid params [$*]"
    fi

    if [[ ! -e "$1" ]];then
        failExit "parser awk file doesn't exist"
    fi

    if [[ ! -e "$2" ]];then
        failExit "server log file doesn't exist"
    fi
    
    if [[ -e "$3" ]];then
        loginfo "parse result file $3 already exists, delete it"
    fi

    cd "${BIN_DIR}" || failExit "cd ${BIN_DIR} failed"
    loginfo "begin to parse server log file, the result will be written to $3"
    awk -f "$1" "$2" > "$3"

    local ret=$?
    if [[ $ret -ne $FUNC_SUCC ]];then
        loginfo "parse server log file failed"
        ret=$FUNC_ERROR
    else
        loginfo "parse server log file finished"
    fi

    return $ret
}

loginfo "++++++++++++++++++++++++++  auto test begin ++++++++++++++++++++++++++"

printMsg "1. Get tested package from ftp server ..."
loopInvocation "getFilefromFtp ${MUT_FTP_PATH} ${MUT_FILE} ${DEPLOY_DIR} ${TMP_FILE}"
if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "get ${MUT_FILE} from FTP: ${MUT_FTP_PATH} failed"
    failExit "get ${MUT_FILE} from FTP: ${MUT_FTP_PATH} failed"
fi

printMsg "2. Get data dict and md5 file from ftp server ..."
loopGetFileandCompareMD5 "${QUERY_LIST_FTP_PATH}" \
                         "${QUERY_LIST_FILE_NAME}" \
                         "${QUERY_LIST_MD5_FILE_NAME}" \
                         "${QUERY_LIST_DIR}" \
                         "${TMP_FILE}"
if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "get ${QUERY_LIST_FILE_NAME} and ${QUERY_LIST_MD5_FILE_NAME} failed"
    failExit "get ${QUERY_LIST_FILE_NAME} and ${QUERY_LIST_MD5_FILE_NAME} failed"
fi

printMsg "3. Begin to deploy and start the http server ..."
deployAndstartHttpServer "${MUT_NAME}" "${MUT_FILE}"
if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "${MUT_NAME} start failed"
    failExit "${MUT_NAME} start failed"
else
    printMsg "${MUT_NAME} start successfully"
fi

sleep 2

printMsg "4. Begin to send requests to the http server ..."
getResponsefromHttpServer "${QUERY_LIST_FILE}" "${RESPONSE_RESULT_FILE}"

if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "Send requests to http server failed"
    failExit "Send requests to http server failed"
else
    printMsg "Send requests to http server done"
fi

sleep 2

printMsg "5. Kill ${MUT_NAME} after auto test ..."
killHttpServer "${MUT_NAME}" > /dev/null 2>&1
if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "kill ${MUT_NAME} failed"
    failExit "kill ${MUT_NAME} failed"
else
    printMsg "kill ${MUT_NAME} successfully"
fi

printMsg "6. Begin to parse server log file ..."
parse_log "${BIN_DIR}/${PARSER_FILE_NAME}" \
          "${DEPLOY_DIR}/${SERVER_LOG_PATH}/${SERVER_LOG_FILE_NAME}" \
          "${DEPLOY_DIR}/${PARSE_RESULT_PATH}/${PARSE_RESULT_FILE_NAME}"
if [[ $? -ne $FUNC_SUCC ]];then
    printMsg "parse server log file failed"
    failExit "parse server log file failed"
else
    printMsg "parse server log file finished, the result is written to '${DEPLOY_DIR}/${PARSE_RESULT_PATH}/${PARSE_RESULT_FILE_NAME}'"
fi

loginfo "++++++++++++++++++++++++++  auto test end ++++++++++++++++++++++++++"

exit $FUNC_SUCC
