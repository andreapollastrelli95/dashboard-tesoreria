/* =============================================================================
   Script 02 - popolamento calendario (dw.DimDate)
   Range 01/01/2022 - 31/12/2027, nomi in italiano, festivita' nazionali.
   La Pasquetta e' calcolata con l'algoritmo di Gauss (Meeus/Jones/Butcher).
   ============================================================================= */
USE TreasuryDW;
GO

SET DATEFIRST 1;   -- lunedi' = 1
SET NOCOUNT ON;

DELETE FROM dw.DimDate;

DECLARE @Start DATE = '2022-01-01',
        @End   DATE = '2027-12-31';

;WITH n AS (
    SELECT TOP (DATEDIFF(DAY, @Start, @End) + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
d AS (
    SELECT DATEADD(DAY, i, @Start) AS dt FROM n
)
INSERT INTO dw.DimDate (DateKey, [Date], [Year], [Quarter], QuarterLabel, [Month], MonthName, MonthShort,
                        YearMonth, YearMonthLabel, WeekOfYear, DayOfWeek, DayName, IsWeekend, IsHoliday,
                        IsWorkingDay, MonthStartDate, MonthEndDate)
SELECT
    CONVERT(INT, FORMAT(dt, 'yyyyMMdd')),
    dt,
    YEAR(dt),
    DATEPART(QUARTER, dt),
    'Q' + CAST(DATEPART(QUARTER, dt) AS CHAR(1)),
    MONTH(dt),
    m.MonthName,
    LEFT(m.MonthName, 3),
    YEAR(dt) * 100 + MONTH(dt),
    LEFT(m.MonthName, 3) + N' ' + CAST(YEAR(dt) AS NVARCHAR(4)),
    DATEPART(ISO_WEEK, dt),
    DATEPART(WEEKDAY, dt),
    w.DayName,
    CASE WHEN DATEPART(WEEKDAY, dt) IN (6, 7) THEN 1 ELSE 0 END,
    0,
    0,
    DATEFROMPARTS(YEAR(dt), MONTH(dt), 1),
    EOMONTH(dt)
FROM d
CROSS APPLY (SELECT CHOOSE(MONTH(dt), N'Gennaio', N'Febbraio', N'Marzo', N'Aprile', N'Maggio', N'Giugno',
                    N'Luglio', N'Agosto', N'Settembre', N'Ottobre', N'Novembre', N'Dicembre') AS MonthName) m
CROSS APPLY (SELECT CHOOSE(DATEPART(WEEKDAY, dt), N'Lunedì', N'Martedì', N'Mercoledì', N'Giovedì',
                    N'Venerdì', N'Sabato', N'Domenica') AS DayName) w;

-- festivita' fisse
UPDATE dw.DimDate
SET IsHoliday = 1
WHERE ([Month] = 1  AND DAY([Date]) IN (1, 6))
   OR ([Month] = 4  AND DAY([Date]) = 25)
   OR ([Month] = 5  AND DAY([Date]) = 1)
   OR ([Month] = 6  AND DAY([Date]) = 2)
   OR ([Month] = 8  AND DAY([Date]) = 15)
   OR ([Month] = 11 AND DAY([Date]) = 1)
   OR ([Month] = 12 AND DAY([Date]) IN (8, 25, 26));

-- Lunedi' dell'Angelo (Pasqua + 1)
DECLARE @y INT = YEAR(@Start);
WHILE @y <= YEAR(@End)
BEGIN
    DECLARE @a INT = @y % 19, @b INT = @y / 100, @c INT = @y % 100;
    DECLARE @dd INT = @b / 4, @e INT = @b % 4, @f INT = (@b + 8) / 25;
    DECLARE @g INT = (@b - @f + 1) / 3;
    DECLARE @h INT = (19 * @a + @b - @dd - @g + 15) % 30;
    DECLARE @i INT = @c / 4, @k INT = @c % 4;
    DECLARE @l INT = (32 + 2 * @e + 2 * @i - @h - @k) % 7;
    DECLARE @m INT = (@a + 11 * @h + 22 * @l) / 451;
    DECLARE @EasterMonth INT = (@h + @l - 7 * @m + 114) / 31;
    DECLARE @EasterDay   INT = ((@h + @l - 7 * @m + 114) % 31) + 1;

    UPDATE dw.DimDate
    SET IsHoliday = 1
    WHERE [Date] = DATEADD(DAY, 1, DATEFROMPARTS(@y, @EasterMonth, @EasterDay));

    SET @y += 1;
END;

UPDATE dw.DimDate
SET IsWorkingDay = CASE WHEN IsWeekend = 0 AND IsHoliday = 0 THEN 1 ELSE 0 END;

SELECT [Year], COUNT(*) AS Days, SUM(CAST(IsWorkingDay AS INT)) AS WorkingDays
FROM dw.DimDate
GROUP BY [Year]
ORDER BY [Year];
GO
