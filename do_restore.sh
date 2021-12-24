#!/bin/bash

PORT=5432
USERNAME='root'
SERVERNAME='localhost'
ARCHIVEDIR='/Backup'
NEWDBNAME=''
OLDDBNAME=''
ARCHIVEDATE=''
FILETORESTORE=''

if [[ $1 != '' ]]
then
    NEWDBNAME=$1
else
    echo "Enter new DB name as first parametr"
    exit
fi

if [[ $2 != '' ]]
then
    OLDDBNAME=$2
else
    echo "Enter DB name in archive"
    exit
fi

if [[ $3 != '' ]]
then
    ARCHIVEDATE=$3
else
    echo "Enter date in forman YYYY-mm-dd"
    exit
fi

if psql -U $USERNAME -h $SERVERNAME -p $PORT -lqt | cut -d \| -f 1 | grep -qw $NEWDBNAME
then
    echo "Database with this name exists on this cluster"
    exit
fi

CURR_DATE=$(date +%Y-%m-%d)

#echo $CURRENT_DATE

DAYS_AGO=$(( (($(date -d ${CURR_DATE} +%s) - $(date -d ${ARCHIVEDATE} +%s)) / 86400) - 1 ))

#echo $DAYS_AGO

#DBLIST="$(ls $ARCHIVEDIR/$OLDDBNAME | grep -E "^${OLDDBNAME}.*$ARCHIVEDATE.*(.delta|.dump.gz)\$")"

DBLIST="$(find $ARCHIVEDIR/$OLDDBNAME -mtime ${DAYS_AGO} -regex ".*\.\(delta\|dump.gz\)$" -type f -printf "%f\n")"

if [[ "$DBLIST" = '' ]]
then
    echo "There is no file to restore"
    exit
fi


index=1
for var in $DBLIST
do
    echo "${index} $var"
    index=$(($index+1))
done

echo -n "Enter the number of archive in this list "

read answer

index=1
for var in $DBLIST
do
    if [[ $index = $answer ]]
    then
        FILETORESTORE=$var
        echo "$FILETORESTORE"
        break
    fi
    index=$(($index+1))
done

if [[ "$FILETORESTORE" = '' ]]
then
    echo "$answer -- is incorrect answer"
    exit
fi

filetype=0

if file $ARCHIVEDIR/$OLDDBNAME/$FILETORESTORE | grep -qw "rdiff network-delta data"
then
    filetype=1
fi

if file $ARCHIVEDIR/$OLDDBNAME/$FILETORESTORE | grep -qw "PostgreSQL custom database dump"
then
    filetype=2
fi

if file $ARCHIVEDIR/$OLDDBNAME/$FILETORESTORE | grep -qw "gzip compressed data"
then
    filetype=3
fi


case "$filetype" in
    1)
        echo "rdiff network-delta data"
        SERIALNUM=$(echo "$FILETORESTORE" | sed 's/^.*'"${OLDDBNAME}"'_//;s/_daily.*//')
        echo $SERIALNUM
        ORIGINAL=$(find $ARCHIVEDIR/$OLDDBNAME/*$SERIALNUM*.dump.gz)
        echo $ORIGINAL
        gunzip -c $ORIGINAL > $ORIGINAL.decompressed
        /usr/bin/rdiff patch $ORIGINAL.decompressed $ARCHIVEDIR/$OLDDBNAME/$FILETORESTORE $ORIGINAL.restored
        rm $ORIGINAL.decompressed
        psql -U $USERNAME -h $SERVERNAME -p $PORT -c 'create database '$NEWDBNAME -d postgres
        psql -h $SERVERNAME -U $USERNAME -p $PORT -d $NEWDBNAME < $ORIGINAL.restored
        rm $ORIGINAL.restored
        ;;
    2)
        echo "PostgreSQL custom database dump"
        psql -U $USERNAME -h $SERVERNAME -p $PORT -c 'create database '$NEWDBNAME -d postgres
        pg_restore -h $SERVERNAME -U $USERNAME -p $PORT -d $NEWDBNAME -w -Fc $ARCHIVEDIR/$OLDDBNAME/$FILETORESTORE
        ;;
    3)
        echo "gzip compressed data"
        psql -U $USERNAME -h $SERVERNAME -p $PORT -c 'create database '$NEWDBNAME -d postgres
        gunzip < $ARCHIVEDIR/$OLDDBNAME/$FILETORESTORE | psql -h $SERVERNAME -U $USERNAME -p $PORT -d $NEWDBNAME
        ;;
    *)
        echo "Undefined file type"
        exit 0
        ;;
esac