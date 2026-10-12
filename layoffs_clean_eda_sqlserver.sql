/* World_Layoffs data cleaning and exploratory analysis
   Dataset: Layoffs (Kaggle)
   Tool: SQL Server
   Author: Oladotun Olawale */

USE world_layoffs;
GO


/* --
   STEP 0: LOOK AT THE RAW DATA
   -- */

SELECT COUNT(*) AS raw_rows FROM layoffs;
SELECT TOP 50 * FROM layoffs;
GO


/* -- 
   STEP 1: STAGING TABLE
   -- */

DROP TABLE IF EXISTS layoffs_staging;
GO

SELECT * INTO layoffs_staging
FROM layoffs;
GO                             -- 4618 rows affected


SELECT COUNT(*) AS staging_rows FROM layoffs_staging;
GO


/* --
   STEP 2: REMOVE DUPLICATES
   no unique ID, so duplicates are found with ROW_NUMBER()
   -- */

-- 2a. Find the duplicates
WITH duplicate_cte AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, [date], stage, country,
                            funds_raised
               ORDER BY (SELECT NULL)
           ) AS rn
    FROM layoffs_staging
)
SELECT *
FROM duplicate_cte
WHERE rn > 1;
GO                  -- 2 duplicates were found.

-- 2b. Delete them
WITH duplicate_cte AS (
    SELECT ROW_NUMBER() OVER (
               PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, [date], stage, country,
                            funds_raised
               ORDER BY (SELECT NULL)
           ) AS rn
    FROM layoffs_staging
)
DELETE FROM duplicate_cte
WHERE rn > 1;
GO            -- 2 rows were affected.

SELECT COUNT(*) AS rows_after_dedupe FROM layoffs_staging;
GO           -- 4616 rows were found after dedupe


/* --
   STEP 3: STANDARDIZE THE DATA
   -- */

-- 3a. Trim spaces and turn blanks / the text 'NULL' into real NULLs
UPDATE layoffs_staging
SET company             = NULLIF(NULLIF(TRIM(company), ''), 'NULL'),
    location            = NULLIF(NULLIF(TRIM(location), ''), 'NULL'),
    industry            = NULLIF(NULLIF(TRIM(industry), ''), 'NULL'),
    stage               = NULLIF(NULLIF(TRIM(stage), ''), 'NULL'),
    country             = NULLIF(NULLIF(TRIM(country), ''), 'NULL'),
    percentage_laid_off = NULLIF(NULLIF(TRIM(percentage_laid_off), ''), 'NULL'),
    funds_raised        = NULLIF(NULLIF(TRIM(funds_raised), ''), 'NULL'),
    [date]              = NULLIF(NULLIF(TRIM([date]), ''), 'NULL'),
    date_added          = NULLIF(NULLIF(TRIM(date_added), ''), 'NULL');
GO

-- 3b. Industry: look for variants of the same thing (e.g. Crypto, CryptoCurrency)
SELECT DISTINCT industry FROM layoffs_staging ORDER BY industry;
GO

UPDATE layoffs_staging
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';
GO

-- 3c. Country: fix trailing punctuation (e.g. 'United States.')
SELECT DISTINCT country FROM layoffs_staging ORDER BY country;
GO

UPDATE layoffs_staging
SET country = 'United States'
WHERE country LIKE 'United States%';
GO

-- 3d. Stage and location: check for inconsistencies
SELECT DISTINCT stage    FROM layoffs_staging ORDER BY stage;
SELECT DISTINCT location FROM layoffs_staging ORDER BY location;
GO

-- 3e. Dates: convert text (m/d/yyyy) to a real DATE.
--     Style 101 = mm/dd/yyyy. Check the conversion first.
SELECT [date], TRY_CONVERT(date, [date], 101) AS converted
FROM layoffs_staging
WHERE [date] IS NOT NULL;
GO

-- Any rows where the text is not NULL but could not be converted? (should be empty)
SELECT [date]
FROM layoffs_staging
WHERE [date] IS NOT NULL
  AND TRY_CONVERT(date, [date], 101) IS NULL;
GO          -- empty result

-- Rewrite as ISO text (yyyy-mm-dd), then change the column type
UPDATE layoffs_staging
SET [date]     = CONVERT(varchar(10), TRY_CONVERT(date, [date], 101), 23),
    date_added = CONVERT(varchar(10), TRY_CONVERT(date, date_added, 101), 23);
GO                 -- 4616 row affected

ALTER TABLE layoffs_staging ALTER COLUMN [date]     DATE NULL;
ALTER TABLE layoffs_staging ALTER COLUMN date_added DATE NULL;
GO

-- 3f. Numbers: check that everything converts before changing the type
SELECT percentage_laid_off
FROM layoffs_staging
WHERE percentage_laid_off IS NOT NULL
  AND TRY_CONVERT(decimal(6,4), percentage_laid_off) IS NULL;   -- should be empty

SELECT funds_raised
FROM layoffs_staging
WHERE funds_raised IS NOT NULL
  AND TRY_CONVERT(decimal(12,2), funds_raised) IS NULL;         -- should be empty
GO

ALTER TABLE layoffs_staging ALTER COLUMN percentage_laid_off DECIMAL(6,4)  NULL;
ALTER TABLE layoffs_staging ALTER COLUMN funds_raised        DECIMAL(12,2) NULL;
ALTER TABLE layoffs_staging ALTER COLUMN total_laid_off      INT           NULL;
GO

-- Confirm the new data types
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'layoffs_staging';
GO             -- column name and data type confirmed.


/* --
   STEP 4: HANDLE NULLS
   -- */

-- 4a. Companies with a missing industry
SELECT * FROM layoffs_staging
WHERE industry IS NULL;
GO            -- Two companies were found with missing industry.

-- 4b. Fill missing industries from other rows of the same company + location
SELECT t1.company, t1.industry AS missing, t2.industry AS known
FROM layoffs_staging t1
JOIN layoffs_staging t2
  ON t1.company = t2.company
 AND t1.location = t2.location
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;
GO

UPDATE t1
SET t1.industry = t2.industry
FROM layoffs_staging t1
JOIN layoffs_staging t2
  ON t1.company = t2.company
 AND t1.location = t2.location
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;
GO

-- 4c. Anything still NULL cannot be filled reliably, so it stays NULL
SELECT * FROM layoffs_staging
WHERE industry IS NULL;
GO          -- 2 rows filled


/* --
   STEP 5: REMOVE UNUSABLE ROWS
   Rows with no layoff numbers at all cannot be analysed.
  -- */

SELECT * FROM layoffs_staging
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;
GO             -- 748 rows were found

DELETE FROM layoffs_staging
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;
GO


/* --
   STEP 6: VALIDATE THE CLEANED DATA
   -- */

SELECT COUNT(*) AS clean_rows FROM layoffs_staging;
GO             -- 3868 clean rows

-- Remaining duplicates (should return no rows)
SELECT company, location, [date], total_laid_off, COUNT(*) AS n
FROM layoffs_staging
GROUP BY company, location, [date], total_laid_off,
         percentage_laid_off, stage, country, funds_raised
HAVING COUNT(*) > 1;
GO

-- Date range
SELECT MIN([date]) AS first_date, MAX([date]) AS last_date
FROM layoffs_staging;
GO             -- 2020-03-11 first_date, 2026-09-30 last date.

-- NULLs remaining per column
SELECT
    SUM(CASE WHEN industry            IS NULL THEN 1 ELSE 0 END) AS null_industry,
    SUM(CASE WHEN total_laid_off      IS NULL THEN 1 ELSE 0 END) AS null_total_laid_off,
    SUM(CASE WHEN percentage_laid_off IS NULL THEN 1 ELSE 0 END) AS null_percentage,
    SUM(CASE WHEN [date]              IS NULL THEN 1 ELSE 0 END) AS null_date,
    SUM(CASE WHEN stage               IS NULL THEN 1 ELSE 0 END) AS null_stage,
    SUM(CASE WHEN funds_raised        IS NULL THEN 1 ELSE 0 END) AS null_funds
FROM layoffs_staging;
GO

SELECT TOP 50 * FROM layoffs_staging;
GO


/* --
   STEP 7: EXPLORATORY DATA ANALYSIS (EDA)
  -- */

-- 7.1 Biggest single layoff events
SELECT TOP 10 company, total_laid_off, percentage_laid_off, [date]
FROM layoffs_staging
WHERE total_laid_off IS NOT NULL
ORDER BY total_laid_off DESC;
GO           -- Intel had the highest single layoff events.

-- 7.2 Companies that laid off 100% of staff, ranked by funding raised
SELECT TOP 10 company, industry, funds_raised, total_laid_off
FROM layoffs_staging
WHERE percentage_laid_off = 1
ORDER BY funds_raised DESC;
GO             -- Britishvolt had the highest funds_raised

-- 7.3 Total layoffs by company
SELECT TOP 10 company, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging
GROUP BY company
HAVING SUM(total_laid_off) IS NOT NULL
ORDER BY total_laid_off DESC;
GO                -- Amazon had the highest total_laid_off

-- 7.4 Total layoffs by industry
SELECT industry, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging
GROUP BY industry
HAVING SUM(total_laid_off) IS NOT NULL
ORDER BY total_laid_off DESC;
GO             -- Other had the highest total_laid_off

-- 7.5 Total layoffs by country
SELECT country, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging
GROUP BY country
HAVING SUM(total_laid_off) IS NOT NULL
ORDER BY total_laid_off DESC;
GO                -- United States had the highest total_laid_off
-- 7.6 Total layoffs by year
SELECT YEAR([date]) AS yr, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging
WHERE [date] IS NOT NULL
GROUP BY YEAR([date])
ORDER BY yr;
GO                 -- year 2023 had the highest toal_laid_off

-- 7.7 Total layoffs by company stage
SELECT stage, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging
GROUP BY stage
HAVING SUM(total_laid_off) IS NOT NULL
ORDER BY total_laid_off DESC;
GO              -- Post-IPO had the highest total_laid_off

-- 7.8 Monthly layoffs with a rolling total
WITH monthly AS (
    SELECT CONVERT(varchar(7), [date], 120) AS [month],
           SUM(total_laid_off)              AS total_laid_off
    FROM layoffs_staging
    WHERE [date] IS NOT NULL
    GROUP BY CONVERT(varchar(7), [date], 120)
)
SELECT [month],
       total_laid_off,
       SUM(total_laid_off) OVER (ORDER BY [month]) AS rolling_total
FROM monthly
ORDER BY [month];
GO               -- 2026-08 had the highest rolling_total.

-- 7.9 Top 5 companies by layoffs in each year
WITH company_year AS (
    SELECT company, YEAR([date]) AS yr, SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging
    WHERE [date] IS NOT NULL
    GROUP BY company, YEAR([date])
),
ranked AS (
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY yr ORDER BY total_laid_off DESC) AS ranking
    FROM company_year
    WHERE total_laid_off IS NOT NULL
)
SELECT *
FROM ranked
WHERE ranking <= 5
ORDER BY yr, ranking;
GO

-- 7.10 Top 3 industries by layoffs in each year
WITH industry_year AS (
    SELECT industry, YEAR([date]) AS yr, SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging
    WHERE [date] IS NOT NULL AND industry IS NOT NULL
    GROUP BY industry, YEAR([date])
),
ranked AS (
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY yr ORDER BY total_laid_off DESC) AS ranking
    FROM industry_year
    WHERE total_laid_off IS NOT NULL
)
SELECT *
FROM ranked
WHERE ranking <= 3
ORDER BY yr, ranking;
GO
