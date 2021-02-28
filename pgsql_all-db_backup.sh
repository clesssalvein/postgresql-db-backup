#!/bin/bash

#####
#
#  It's necessary to install:
#
#  yum install -y https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
#  yum install -y postgresql96 pigz sshpass rsync
#
#####


# vars

dateTimeCurrent=`date +%Y-%m-%d_%H-%M-%S` # current date
dayOfMonth=`date +%d` # current day of month
pgsqlServerHostToConnect="127.0.0.1" # pgsql server IP or Hostname, to which we are connecting for making DB backup
pgsqlServerIp="192.168.17.167" # pgsql server unique IP in local network, we will create backup files to path including this IP (see vars "backupServerBackupPath*")
pgsqlUser="postgres" # postgresql admin user
pgsqlPass="P@ssWord" # postgresql admin password
backupPathLocal="/root/BACKUP" # dir for temp local DB backup
backupServerIp="192.168.199.250" # must be available by SFTP (SSH)
backupServerUser="admin" # ssh login with rw access to backupServerBackupPath*
backupServerPass="P@ssWord" # password for ssh login
backupServerBackupPathDaily="/mnt/raid2/bkup/servers/${pgsqlServerIp}/pgsql/daily" # path to daily backups at remote SFTP server, MUST exist
backupServerBackupPathMonthly="/mnt/raid2/bkup/servers/${pgsqlServerIp}/pgsql/monthly" # path to monthly backups at remote SFTP server, MUST exist

backupServerBackupFilesLeaveType="lastFiles" # remove old backups type. "lastDays" - keep files for the last N days; "lastFiles" - keep the last N files
backupServerBackupFilesLastN="7" # number of keeping backup files - last days OR last files (depending on option "backupFilesLeaveType")

pg_dump=`which pg_dump`
psql=`which psql`
pigz=`which pigz`
ssh=`which ssh`
sshpass=`which sshpass`
rsync=`which rsync`

sshParams="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" # SSH client params when connecting to SSH server
rsyncSshParams="--verbose --progress -ahe" # RSYNC client params when connecting to SSH server


# declare raw array of dbs (with increments like spaces and empty lines)
arrayDBsRaw=()

# put every output line to raw array
while IFS= read -r line;
  do
    arrayDBsRaw+=( "$line" )
  done < <( PGPASSWORD=${pgsqlPass} ${psql} -h ${pgsqlServerHostToConnect} -U ${pgsqlUser} -qXtc "SELECT datname FROM pg_database WHERE datistemplate = false;" )

# declare clean array of db names
arrayDBs=()

# array of db names create
for dbName in "${arrayDBsRaw[@]}";
  do
    # remove spaces from each db name
    dbName=`echo $dbName | sed -r '/^\s*$/d'`;

    # if dbName is not empty line - put it to array of dbs
    if ! [ -z ${dbName} ]; then
        arrayDBs+=(${dbName})
    fi

    # debug
    #echo "$dbName";
  done


# for each db name run actions

# backup
for dbName in "${arrayDBs[@]}";
  do
    # debug
    echo ${dbName}

    # full path to local temp db backup
    dbBackupFile="${backupPathLocal}/${dbName}_${dateTimeCurrent}.pgsql.backup"
    dbBackupFileArch="${backupPathLocal}/${dbName}_${dateTimeCurrent}.pgsql.backup.zip"

    # create not archived backup
    PGPASSWORD=${pgsqlPass} ${pg_dump} -h ${pgsqlServerHostToConnect} -U ${pgsqlUser} ${dbName} > ${dbBackupFile}

    # if last action success
    if [[ $? == 0 ]] ; then
        # arch db backup file
        ${pigz} -K ${backupPathLocal}/${dbName}_${dateTimeCurrent}.pgsql.backup

        # if arch success
        if [[ $? == 0 ]] ; then

            # send arch to ssh server

            # DAILY backup
            ${sshpass} -p "${backupServerPass}" ${rsync} ${rsyncSshParams} "${ssh} ${sshParams}" ${dbBackupFileArch} ${backupServerUser}@${backupServerIp}:${backupServerBackupPathDaily}/
            dailyBackupStatus=$?

            # MONTHLY backup
            if [[ ${dayOfMonth} == "01" ]]; then
                ${sshpass} -p "${backupServerPass}" ${rsync} ${rsyncSshParams} "${ssh} ${sshParams} "${dbBackupFileArch} ${backupServerUser}@${backupServerIp}:${backupServerBackupPathMonthly}/
                monthlyBackupStatus=$?
            fi
        fi

        # if send to ssh success
        if [[ ${dailyBackupStatus} == 0 ]] ; then

            # check if local temp db file-arch exist
            if test -f ${dbBackupFileArch}; then
                # remove local temp db file-arch
                rm -f ${dbBackupFileArch};
            fi
        fi
    fi
  done


# the following actions depend on value of var "backupServerBackupFilesLeaveType"

# remove old DAILY backups - older than N days
if [[ ${backupServerBackupFilesLeaveType} == "lastDays" ]]; then
 ${sshpass} -p "${backupServerPass}" ${ssh} ${sshParams} ${backupServerUser}@${backupServerIp} /bin/bash << HERE
    find ${backupServerBackupPathDaily}/ -mtime +${backupServerBackupFilesLastN} -type f -exec rm -rf {} \;
HERE
fi

# remove old DAILY backups - more than N last files
if [[ ${backupServerBackupFilesLeaveType} == "lastFiles" ]]; then
 ${sshpass} -p "${backupServerPass}" ${ssh} ${sshParams} ${backupServerUser}@${backupServerIp} /bin/bash << HERE
    if [[ -d /mnt/raid2/bkup/servers/192.168.17.167/pgsql/daily ]] ;then
        cd ${backupServerBackupPathDaily};
        ls -lt | sed /^total/d | awk 'FNR>${backupServerBackupFilesLastN} {print \$9}' | xargs rm -rf {};
    fi
HERE
fi
