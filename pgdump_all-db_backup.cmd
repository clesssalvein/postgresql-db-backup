REM
REM It's necessary to install:
REM 7zip, putty (plink, psftp)
REM

echo OFF

:: vars

set pgsqlServerHostToConnect=127.0.0.1
set pgsqlServerIp=192.168.199.36
set PATH=%PATH%;"C:\Program Files\PostgreSQL 1C\9.6\bin";%ProgramFiles%\7-Zip

REM Year
set year=%date:~-4%

REM Month
set month=%date:~3,2%
REM Remove leading space if single digit
if "%month:~0,1%" == " " set month=0%month:~1,1%

REM Day
set day=%date:~0,2%
REM Remove leading space
if "%day:~0,1%" == " " set day=0%day:~1,1%

REM Capture Hour
set hour=%time:~0,2%
REM Remove leading space if single digit
if "%hour:~0,1%" == " " set hour=0%hour:~1,1%

REM Minutes
set min=%time:~3,2%
REM Remove leading space
if "%min:~0,1%" == " " set min=0%min:~1,1%

set dateTimeCurrent=%year%-%month%-%day%_%hour%-%min%

set PGPASSWORD=PassWord
set scriptPath=D:\POSTGRESQL\SCRIPTS
set backupPathLocal=D:\POSTGRESQL\BACKUP
set pgsqlDbList=%scriptPath%\pgsqlDbList.txt
set backupServerIp=192.168.199.250
set backupServerUser=admin
set backupServerPass=PassWord
set backupServerBackupPathDaily=/mnt/raid2/bkup/servers/%pgsqlServerIp%/pgsql/daily
set backupServerBackupPathMonthly=/mnt/raid2/bkup/servers/%pgsqlServerIp%/pgsql/monthly

:: get pg db list and store it to file

psql -h %pgsqlServerHostToConnect% -U postgres -qXtc "SELECT datname FROM pg_database WHERE datistemplate = false;" > %pgsqlDbList%

:: each db name put to array

setlocal EnableDelayedExpansion

set i=0
for /F %%a in (%pgsqlDbList%) do (
   set /A i+=1
   set array[!i!]=%%a
)
set n=%i%

:: debug

for /L %%i in (1,1,%n%) do echo !array[%%i]!

:: daily backup

for /L %%i in (1,1,%n%) do (

	:: create backup
	pg_dump -h %pgsqlServerHostToConnect% -U postgres !array[%%i]! > %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup

	:: arch backup
	7z a -tzip %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup

	:: send db arch to sftp server
	echo "put" "%backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip" "%backupServerBackupPathDaily%/!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip" | D:\POSTGRESQL\SCRIPTS\putty\psftp.exe -pw %backupServerPass% %backupServerUser%@%backupServerIp%

	:: del backup
	del %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup
	del %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip
)

:: monthly backup - day 01 of every month

if %day% EQU 01 (

	for /L %%i in (1,1,%n%) do (

		:: create backup
		pg_dump -U postgres !array[%%i]! > %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup

		:: arch backup
		7z a -tzip %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup

		:: send db arch to sftp server
		echo "put" "%backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip" "%backupServerBackupPathMonthly%/!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip" | D:\POSTGRESQL\SCRIPTS\putty\psftp.exe -pw %backupServerPass% %backupServerUser%@%backupServerIp%

		:: del backup
		del %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup
		del %backupPathLocal%\!array[%%i]!_%dateTimeCurrent%.pgsql.backup.zip
	)
)

:: remove old backups

echo y | D:\POSTGRESQL\SCRIPTS\putty\plink.exe -pw %backupServerPass% %backupServerUser%@%backupServerIp% "find %backupServerBackupPathDaily%/ -mtime +6 -type f -exec rm -rf {} \;"
