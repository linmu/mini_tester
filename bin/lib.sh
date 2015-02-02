#!/bin/bash

############################
##! @Author:Mu Lin
##! @Date:2014-01-06
##! @TODO:public functions
############################
FUNC_SUCC=0
FUNC_ERROR=1

RETRY_DOWNLOAD_COUNT=3
DOWNLOAD_NO_FILE=100
LOOP_TEST_COUNT=3

function getTime()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

function printMsg()
{
    echo "$1"
}

function loginfo()
{
    echo "`getTime` [`caller 0 | awk -F' ' '{print $1,$2}'`] $1" >> $LOG_FILE
}

function failExit()
{
    loginfo "Error: $1, exited, please check problem"
    exit $FUNC_ERROR
}

#input: ftpaddress ftpfile destpath tmpfile
function ftpDownload()
{
    if [[ $# -ne 4 ]];then
        loginfo "need params"
	failExit "ftpDownload invalid params [$*]"
    fi
	
    loginfo "start ftpDownload, params length:$#, params [$*]"
    loginfo "wget -t ${RETRY_DOWNLOAD_COUNT} -P $3 -o $4"
    wget -t ${RETRY_DOWNLOAD_COUNT} -P $3 -o $4 "$1/$2"

    local wgetRet=$?
    local noSuchFileRet=$(cat $4 | grep "No such file" | wc -l)
    rm -rf $4
    
    loginfo "wget return=$wgetRet, no such file return=$noSuchFileRet"
    if [[ $wgetRet -eq 0 && $noSuchFileRet -eq 0 ]];then
        loginfo "download $1/$2 success"
	return $FUNC_SUCC
    elif [[ $wgetRet -ne 0 && $noSuchFileRet -gt 0 ]];then
	loginfo "ftp addres $1 doesn't have file $2"
	return ${DOWNLOAD_NO_FILE}
    else
	loginfo "download $1/$2 failed"
	return $FUNC_ERROR
    fi	
}

#input: ftpaddress ftpfile destpath tmpfile
function getFilefromFtp()
{
    if [[ $# -ne 4 ]];then
        loginfo "need params"
	failExit "getFilefromFtp invalid params [$*]"
    fi

    loginfo "start wget file, params length:$#, params [$*]"
    if [[ -f $3/$2 ]];then
        loginfo "$3/$2 is already here, delete it"
        rm -rf "$3/$2"
    fi

    ftpDownload "$1" "$2" "$3" "$4"
    local ftpRet=$?
    [[ $ftpRet -eq $FUNC_SUCC ]] && return $FUNC_SUCC || return $ftpRet
}

#input: datafile md5file
function compareMD5()
{
    if [[ $# -ne 2 ]];then
        loginfo "need params"
	failExit "compareMD5 invalid params [$*]"
    fi

    loginfo "start compare md5 value, params length:$#, params [$*]"
    if [[ ! -e $1 ]];then
        loginfo "data file $1 doesn't exist"
	return $FUNC_ERROR
    fi
    if [[ ! -e $2 ]];then
        loginfo "md5 file $2 doesn't exist"
	return $FUNC_ERROR
    fi

    local newMD5val=$(md5sum $1 | awk -F' ' '{print $1}')
    local oldMD5val=$(awk -F' ' '{print $1}' $2)
    loginfo "data file md5:$newMD5val, md5 file md5:$oldMD5val"

    local compareRet=$FUNC_SUCC
    if [[ $newMD5val != $oldMD5val ]];then
        loginfo "compare MD5 value failed, data file md5:$newMD5val, md5 file md5:$oldMD5val"
	compareRet=$FUNC_ERROR
    else
        loginfo "compare MD5 value success"
    fi

    return $compareRet
}

function loopInvocation()
{
    local ret=$FUNC_SUCC
    local counter=1
    for((counter=1;counter<=${LOOP_TEST_COUNT};counter++))
    do
        loginfo "start exec $1 $counter times"
	$@
	local callRet=$?
	loginfo "call function [$1], return [$callRet]"
	if [[ $callRet -eq $FUNC_SUCC ]];then
            ret=$FUNC_SUCC
            break
	else
            ret=$callRet
	fi
        if [[ $counter -lt ${LOOP_TEST_COUNT} ]];then
            loginfo "loop invocation, sleep 2s"
	    sleep 2
	fi
    done

    return $ret
}

#input: ftpaddress datafile md5file destpath tmpfile
function loopGetFileandCompareMD5()
{
    if [[ $# -ne 5 ]];then
        loginfo "need params"
	failExit "loopGetFileandCompareMD5 invalid params [$*]"
    fi
    
    loopInvocation "getFilefromFtp $1 $2 $4 $5"
    if [[ $? -ne $FUNC_SUCC ]];then
        failExit "wget data file $2 failed"
    fi

    loopInvocation "getFilefromFtp $1 $3 $4 $5"
    if [[ $? -ne $FUNC_SUCC ]];then
        failExit "wget md5 file $3 failed"
    fi

    compareMD5 "$4/$2" "$4/$3"
    local ret=$?
    loginfo "call function [compareMD5 $2 $3], return [$ret]"

    [[ $ret -eq $FUNC_SUCC ]] && return $FUNC_SUCC || return $FUNC_ERROR
}

#input: requestURL response_result_file
function sendRequesttoHttpServer()
{
    if [[ $# -ne 2 ]];then
        loginfo "need params"
        failExit "sendRequesttoHttpServer invalid params [$*]"
    fi
    
    curl "$1" >> "$2" > /dev/null 2>&1
    local curlRet=$?
	
    if [[ $curlRet -eq $FUNC_SUCC ]];then
        loginfo "send request $1 to server successfully"
    else
        failExit "send request $1 to server failed"
    fi

    return $curlRet
}
