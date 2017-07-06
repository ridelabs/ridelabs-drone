#!/bin/sh
# ---------------------------------------
# copyright RideLabs (www.ridelabs.net/opensource-software/)
# Apache 2.0 license, see LICENSE file in this repo
# how to use: 
# turn on your bebop2
# connect to it's wifi
# upload the script via ftp to 192.168.42.1
#   ncftp 192.168.42.1
#   cd /internal_000/Debug/
#   mput shortpress_3.sh
# enable telnet: shortpress the power button 4 times
# put the script in place
#   telnet 192.168.42.1
#     mv /data/ftp/internal_000/Debug/shortpress_3.sh /bin/ononebutton/
#     chmod a+rx /bin/ononebutton/shortpress_3.sh
# get an OTG (on the go) cable and plug it into your bebop2
# get a USB thumbdrive and plug it into your OTG cable
# shortpress the power buton 3 times 
# you will see 2 or so short flashes to start the copy
# you will see long blinking while copying each file, with a short pause between files 
# you will see 2 or so short flashes when it ends
# if there is a problem you will see 10 or so short flashes
# There will be a log deposited of the copy in ftp://192.168.42.1/internal_000/Debug/shortpress_3.log
# We copy file by file and don't delete from the bebop2 until we know that the file made it to the external usb drive
# therefore you can pull the batter at any time to end the process and you will have moved as much as possible up to that point
# ---------------------------------------

LOG=/data/ftp/internal_000/Debug/shortpress_3.log
INTERNAL_DISK=$(mount | grep data.ftp | grep internal | awk '{print $3}')
INTERNAL_MEDIA=$INTERNAL_DISK/Bebop_2/media
INTERNAL_THUMB=$INTERNAL_DISK/Bebop_2/thumb

EXTERNAL_DISK=$(mount | grep data.ftp | grep -v internal | awk '{print $3}')
EXTERNAL_MEDIA=$EXTERNAL_DISK/Bebop_2/media


blink_light_on() {
    sprop "system.shutdown" "1"
}

blink_light_off() {
    sprop "system.shutdown" "0"
}

blink_light_and_block(){
    # blink and then don't blink for n microseconds
    local microseconds=$1
    blink_light_on
    usleep $microseconds
    blink_light_off
    usleep $microseconds
}

stutter_blink() {
    local stutters=$1
    while [ $stutters -gt 0 ]; do
        stutters=$((stutters-1))
        blink_light_and_block 2500
        blink_light_and_block 2500
        # stutter blinks have 1 second between them
        sleep 1
    done
}

delete_source() {
    local filename=$1
    rm -f $INTERNAL_MEDIA/$filename
    rm -f $INTERNAL_THUMB/${filename}
    rm -f $INTERNAL_THUMB/${filename}.jpg
}

checksum_file() {
    # quick file size check
    ls -lah $1 | awk '{print $5}'
    # LONG md5sum check
    #md5sum $dest 2>/dev/null | awk '{print $1}'
}

move_file() {
    local source=$1
    local dest=$2
    mkdir -p `dirname $dest` >> $LOG 2>&1
    # cp the file, checksum and delete source if good, else delete dest if bad
    
    blink_light_on
    local ssum=$(checksum_file $source )
    local dsum=$(checksum_file $dest )
    
    stutter_blink 1
    blink_light_on
    
    if [ "$ssum" != "$dsum" ]; then
        rm -f $dest >> $LOG 2>&1
        if cp -rf $source $dest >> $LOG 2>&1 && sync >> $LOG 2>&1 ; then
        
            stutter_blink 1
            blink_light_on
        
            dsum=$(checksum_file $dest )
            
            stutter_blink 1
            blink_light_on
            
            
            if [ "$ssum" != "$dsum" ]; then
                echo "checksum's don't match for $source and $dest ($ssum != $dsum) exiting now!" >> $LOG
                rm -f $dest # remove the bad file
                stutter_blink 8
                exit 2
            else
                echo "checksum's match for $source and $dest ($ssum == $dsum) success for this file!" >> $LOG
                delete_source `basename $source`
                blink_light_off
            fi 
        else
            echo "Failed to copy $source to $dest" >> $LOG
            stutter_blink 10
            exit 2
        fi
    else
        delete_source `basename $source`
        blink_light_off
    fi
    
}

remount_external_disk() {
    local counter=10
    while [ $counter -gt 0 ] ; do 
        if touch $EXTERNAL_DISK/writable.txt echo "TEST RW" > $EXTERNAL_DISK/writable.txt && ls -lah $EXTERNAL_DISK/writable.txt >> $LOG && rm $EXTERNAL_DISK/writable.txt ; then        
            echo "OK, we can now write to the disk, continuting..." >> $LOG
            break
        else
            sleep 1
            echo "Trying to remount $EXTERNAL_DISK $counter" >> $LOG
            mount -o rw,remount $EXTERNAL_DISK >> $LOG 2>&1 # remount just in case you rebooted your bebop w/the disk inserted (they make it mounted RO for some reason) 
        fi
        counter=$((counter-1))
    done
}

main() {
    echo "+---------> moving files now: `date` <----------+" >> $LOG

    stutter_blink 1
    sleep 1

    d=$(date +"%Y-%m-%d-%H-%M")
    if [ ! -z "$INTERNAL_DISK" ] && [ ! -z "$EXTERNAL_DISK" ]; then
        echo "Remounting disk $EXTERNAL_DISK for r/w operation" >> $LOG
        echo "INTERNAL_DISK='$INTERNAL_DISK' EXTERNAL_DISK='$EXTERNAL_DISK' : `date` " >> $LOG
        remount_external_disk
        mkdir -p $EXTERNAL_MEDIA
        for internal_file in `ls $INTERNAL_MEDIA/* | grep -v '.dat$' | grep -v '.tmp$' ` ; do
            external_file=$EXTERNAL_MEDIA/`basename $internal_file`   
            remount_external_disk # just in case the status has changed... remount it again
            move_file $internal_file $external_file
            sleep 1 # for blink feedback to settle
        done
    else
        echo "SORRY a disk is missing: INTERNAL_DISK=$INTERNAL_DISK `date` " >> $LOG
        echo "SORRY a disk is missing: EXTERNAL_DISK=$EXTERNAL_DISK `date` " >> $LOG
        stutter_blink 3
        exit 4
    fi

    stutter_blink 1
}

trap  "blink_light_off; exit" TERM QUIT

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------
echo "start" > $LOG # overwrite the log
main
echo "end" >> $LOG

