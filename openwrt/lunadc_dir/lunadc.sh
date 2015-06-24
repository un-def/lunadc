#!/bin/sh

LUA="lua"
LUNADC="./lunadc.lua"
LOG="/var/log/lunadc.log"
SEPARATOR="------------------------------"

stop() {
	kill -TERM "$(pidof $LUA $LUNADC)"
	log_date stopped
	exit
}

log_date() {
	echo $SEPARATOR >> $LOG
	echo "$1 on $(date '+%d-%m-%Y %H:%M:%S')" >> $LOG
}

trap "stop" INT TERM KILL
cd "$(dirname "$0")"
log_date started
while true
do
	echo $SEPARATOR >> $LOG
	$LUA "-e io.stdout:setvbuf('line')" $LUNADC >> $LOG &
	wait $!
	sleep 5
done
