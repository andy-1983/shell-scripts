#!/bin/bash

STARTSCRIPT=$(date +%s)
STOPSCRIPT=''
ListOfBases='dblist'
PORT='5432'
USERNAME='root'
SERVERNAME='localhost'
ARCHIVEDIR='/archive_dir'
MAXDBCOUNT='1000' #count of db names to select from cluster
TEMPDIR='/cache'
DAILYTIMEOUT='120' #timeout before start new series of rdiff deltas in minutes
RAMDISKSIZE='6144M'
ISIZE='1048576' #  -I, --input-size=BYTES    Input buffer size
OSIZE='1048576' #  -O, --output-size=BYTES   Output buffer size
BSIZE='1048576' # --block-size 1048576
SUFFIX=''
NETDIR='//192.168.0.110/PostgreSQL'
ERRLOG='/var/log/archive.log'
STARTFILE=''
SERIALNUM=''
SERVERLABEL=$(hostname)
CHATID='-325999999'
BOTID='bot1444444475:AAH1y14666tZtYMaP_N888Ew3DzzzzzzSJM'

if [[ 'daily' = $1 ]]
then
    SUFFIX='daily_'$(date +%Y-%m-%d-%H)
fi

if [[ 'monthly' = $1 ]]
then
    SUFFIX='monthly_'$(date +%Y-%m-%d)
fi

if [[ 'hot' = $1 ]]
then
    SUFFIX='hot_'$(date +%Y-%m-%d-%H%M)
fi

if [[ 'weekly' = $1 ]]
then
    SUFFIX='weekly_'$(date +%Y-%m-%d)
fi

if [[ $SUFFIX = '' ]]
then
    echo 'Type monthly, weekly, daily or hot as parametr'
    exit
fi


if mount | grep -qw $NETDIR
then
    echo "Network directory is mounted"
else
    echo "Network direcrory $NETDIR is not mounted" >> $ERRLOG
    MESSAGE="FAIL | pg_dump | ${SERVERLABEL} | ${SUFFIX}"
    /usr/bin/curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id": "'"$CHATID"'", "text": "'"$MESSAGE"'", "disable_notification": false}' https://api.telegram.org/$BOTID/sendMessage
    exit
fi

DBLIST=$(psql -U $USERNAME -p $PORT -l | q -d'|' "select c1 from - where c1 <> '' and c2 <> '' and c1 not like 'template%' and c1 not like '%_bak%' limit 1,$MAXDBCOUNT")

echo "$DBLIST" > ${ARCHIVEDIR}'/'$ListOfBases

mkdir -p "$TEMPDIR/temp"

cat $ARCHIVEDIR'/'$ListOfBases | while read DBNAME
do
    mkdir -p ${ARCHIVEDIR}'/'${DBNAME}

    if [[ 'weekly' = $1 ]]
    then
        > ${ARCHIVEDIR}/${DBNAME}'/start'
        STARTFILE=''
    fi

    if ! [[ -e ${ARCHIVEDIR}/${DBNAME}'/start' ]]
    then
        > ${ARCHIVEDIR}/${DBNAME}'/start'
    fi

    STARTFILE="$(cat ${ARCHIVEDIR}/${DBNAME}'/start')"

    if [[ $STARTFILE == '' ]]
    then
        SERIALNUM=$(/usr/bin/pwgen 15 1)
        STARTFILE="${DBNAME}_${SERIALNUM}_${SUFFIX}.dump"
        echo "$STARTFILE" > ${ARCHIVEDIR}'/'${DBNAME}'/start'
        nice -n 19 ionice -c3 pg_dump -d $DBNAME -h ${SERVERNAME} -p $PORT -U ${USERNAME} -w > ${TEMPDIR}/temp/${STARTFILE}
        if [[ $? -ne 0 ]]
        then
            echo "$DBNAME: pg_dump error code is "$? >> $ERRLOG
        fi
        /usr/bin/rdiff signature ${TEMPDIR}/temp/${STARTFILE} ${ARCHIVEDIR}/${DBNAME}/${STARTFILE}.signature
        if [[ $? -ne 0 ]]
        then
            echo "$DBNAME: signature creation error "$? >> $ERRLOG
        fi
        /usr/bin/pigz --keep -c ${TEMPDIR}/temp/${STARTFILE} > ${ARCHIVEDIR}/${DBNAME}/${STARTFILE}.gz
        if [[ $? -ne 0 ]]
        then
            echo "$DBNAME: start file archiving error "$? >> $ERRLOG
        fi
        rm -f ${TEMPDIR}/temp/${STARTFILE}
    else

        case $1 in
            hot|monthly)
                nice -n 19 ionice -c3 pg_dump -d $DBNAME -h ${SERVERNAME} -p $PORT -U ${USERNAME} -w | pigz > ${ARCHIVEDIR}'/'${DBNAME}'/'${DBNAME}'_'$SUFFIX.dump.gz;
                if [[ $? -ne 0 ]]
                then
                    echo "$DBNAME: pg_dump error code is "$? >> $ERRLOG
                fi
            ;;
            *)
                SERIALNUM=$(echo "$STARTFILE" | sed 's/^.*'"${DBNAME}"'_//;s/_weekly.*//')
                nice -n 19 \
                ionice -c3 \
                pg_dump -d $DBNAME -h ${SERVERNAME} -p $PORT -U ${USERNAME} -w | \
                /usr/bin/rdiff --block-size="$BSIZE" --input-size="$ISIZE" --output-size="$OSIZE" -- delta \
                ${ARCHIVEDIR}/${DBNAME}/$STARTFILE.signature \
                - \
                ${ARCHIVEDIR}/${DBNAME}/${DBNAME}_${SERIALNUM}_${SUFFIX}.dump.delta
                if [[ $? -ne 0 ]]
                then
                    echo "$DBNAME: delta creation error "$? >> $ERRLOG
                fi
                STOPSCRIPT=$(date +%s)
                EXECUTIONTIME=$(( ($STOPSCRIPT - $STARTSCRIPT) / 60 ))
                if [[ $EXECUTIONTIME -gt $DAILYTIMEOUT ]]
                then
                    MESSAGE="TIMEOUT | pg_dump | ${SERVERLABEL} | ${SUFFIX} | $EXECUTIONTIME min"
                    /usr/bin/curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id": "'"$CHATID"'", "text": "'"$MESSAGE"'", "disable_notification": false}' https://api.telegram.org/$BOTID/sendMessage
                    rm -R "$TEMPDIR"
                    $0 weekly
                    exit 1
                fi
            ;;
        esac
    fi
done


if [ -d "$TEMPDIR" ]; then
    rm -R "$TEMPDIR"
fi


BackupErr=$(stat $ERRLOG -c %s)

STOPSCRIPT=$(date +%s)

EXECUTIONTIME=$(( ($STOPSCRIPT - $STARTSCRIPT) / 60 ))

MESSAGE=''

if [[ $BackupErr = 0 ]]
then
    MESSAGE="OK | pg_dump | ${SERVERLABEL} | ${SUFFIX} | $EXECUTIONTIME min"
else
    MESSAGE="FAIL | pg_dump | ${SERVERLABEL} | ${SUFFIX} | $EXECUTIONTIME min"
    echo date >> $ERRLOG
fi

/usr/bin/curl -s -X POST -H 'Content-Type: application/json' -d '{"chat_id": "'"$CHATID"'", "text": "'"$MESSAGE"'", "disable_notification": false}' https://api.telegram.org/$BOTID/sendMessage
