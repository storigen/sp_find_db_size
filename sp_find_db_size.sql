SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[sp_find_db_size] as

/*******************************************************************************************************************************************
OBJECT NAME:	Database Disk Space Utilization 

EXECUTED BY:	manual

CHILD OBJECT:	n/a
CHILD OBJECT:	n/a

DESCRIPTION:	Checks all databases for their allocation size and their actual used size in Gb.

HISTORY:
> 04/19/2018 - Created
***********************************************************************************************************************************/









------------------------------------------------------------------------------
-- 1. SET UP ITERATOR OF ACTIVE DATABASES ON SERVER
------------------------------------------------------------------------------
DECLARE @SQL varchar(max)
DECLARE @CurDb varchar(100)



DECLARE db_cursor CURSOR FOR 
	(
		SELECT name 
		FROM MASTER.dbo.sysdatabases 
		WHERE HAS_DBACCESS(name) = 1						--checks only db's we have access to
		and name NOT IN ('master','model','msdb','tempdb')  --excludes system dbs
	)





------------------------------------------------------------------------------
-- 2. GET FILE AND DB USE FOR EACH DB ON SERVER
------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#DbUse') IS NOT NULL BEGIN DROP TABLE #DbUse END

CREATE TABLE #DbUse
	(
		 DatabaseName VARCHAR(100)
		,TypeDesc VARCHAR(25)
		,UsedGB NUMERIC (10, 1)
	)





------------------------------------------------------------------------------
-- 3. ITERATE OVER TABLES
------------------------------------------------------------------------------

OPEN db_cursor 
FETCH NEXT FROM db_cursor INTO @CurDb
WHILE @@FETCH_STATUS = 0
	BEGIN
	
		SELECT @SQL = 
			'USE '+@CurDb
			+' INSERT INTO #DbUse'
			+' SELECT ''' + @CurDb + ''' as DatabaseName, ''allocated'' as typedesc, SUM(size) * 8.0 / power(1024,2) as UsedGB'
			+' FROM ' + @CurDb +'.sys.database_files';

		PRINT @SQL
		EXECUTE (@SQL)
	

		SET @SQL = 
			 ' INSERT INTO #DbUse'
			+' SELECT ''' + @CurDb + ''' as DatabaseName, ''used'', (SUM(used_pages)*8)/CAST(power(1024,2) AS FLOAT) AS UsedGb '
			+' FROM ' + @CurDb +'.sys.allocation_units'


		PRINT @SQL
		EXECUTE (@SQL)
	
		FETCH NEXT FROM db_cursor INTO @CurDb
	
	END
	
CLOSE db_cursor  
DEALLOCATE db_cursor

 

------------------------------------------------------------------------------
-- 4. REPORT OUT
------------------------------------------------------------------------------


SELECT 
	  al.DatabaseName as Database_Name
	, al.UsedGB as Allocated_GB
	, u.UsedGB AS Used_GB
	, al.UsedGB- u.UsedGB as Not_Used_Gb
	--, (al.UsedGB/ u.UsedGB)-1 as ReleasablePct
	, CAST(CAST(((al.UsedGB/ u.UsedGB)-1)*100 as NUMERIC(18,1)) as VARCHAR(5)) + ' %' as [Allocation_Shrinkable %]
	
	, CASE WHEN ((al.UsedGB/ u.UsedGB)-1) < .05 THEN '' ELSE
	'DBCC SHRINKDATABASE ('+al.DatabaseName+', 5);' END as Execute_To_Shrink_Allocation_To_5_Pct_Empty
	

FROM  #DbUse al
LEFT JOIN #DbUse u
		ON al.DatabaseName= u.DatabaseName 
		AND al.TypeDesc='allocated'
WHERE u.TypeDesc = 'used'
ORDER BY 1


