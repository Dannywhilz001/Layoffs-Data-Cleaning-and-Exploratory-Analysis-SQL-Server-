I took a raw, messy layoffs dataset from Kaggle, cleaned it entirely in SQL Server, and then analysed it to see which companies, industries, and countries were hit hardest.

## Dataset

- **Source:** Layoffs dataset on Kaggle
- **Size:** 4,618 rows, 11 columns
- **Columns:** company, location, total_laid_off, date, percentage_laid_off, industry, source, stage, funds_raised, country, date_added

## Tools

- SQL Server
- SQL Server Management Studio

## Cleaning Process

I never edited the raw table. Everything was done on a staging copy (`layoffs_staging`).

| Step | What I did | Result |
|---|---|---|
| Duplicates | Numbered identical rows with `ROW_NUMBER(2)` and deleted the extras | 2 duplicate rows removed |
| Standardizing text | Trimmed spaces, turned blanks and the text "NULL" into real NULLs, merged industry variants (for example Crypto), and fixed country names.
| Dates | Converted text dates (m/d/yyyy) to a real `DATE` type using `TRY_CONVERT` | Date range: 2020-03-11 to 2026-09-30 |
| Numbers | Converted `percentage_laid_off`, `funds_raised`, and `total_laid_off` from text to numeric types | |
| Missing industries | Filled them in from other rows of the same company and location | 2 rows had no industry before filling, and both were filled |
| Unusable rows | Removed rows with neither a layoff count nor a percentage | 748 rows removed |

**Rows: 4,618 raw, 4,616 after removing duplicates, 3,868 after cleaning.**

## Analysis

Questions I answered with SQL:

1. What were the biggest single layoff events?
2. Which companies laid off 100% of their staff, and how much funding had they raised?
3. Which companies, industries, and countries had the most layoffs in total?
4. How did layoffs change by year and by month, including a rolling total?
5. Which companies and industries ranked highest in each year?

## Key Findings
- **Intel** had the largest single layoff event in the dataset.
- **Amazon** had the most layoffs in total across all of its events.
- The **United States** accounted for the most layoffs of any country.
- **2023** was the year with the most layoffs.
- **Post-IPO** companies had the most layoffs of any funding stage.
- **Britishvolt** laid off 100% of its staff and had raised more funding than any other company that did.
- The **"Other"** category had the highest layoff total by industry. Because it is a catch-all label, the named industries below it are the more useful ones to compare.

## Challenges I Ran Into

- **Import types:** the import wizard guessed the wrong data types, so I imported the dates and percentages as text and converted them myself during cleaning.
- **Date conversion:** I checked with `TRY_CONVERT` that every date converted properly before changing the column type.
- **Rolling total error:** the `FORMAT()` function returns a very wide text type, which stopped the rolling `SUM() OVER (ORDER BY ...)` from running. Switching to `CONVERT(varchar(7), [date], 120)` fixed it.
- **CTE scope:** a CTE only exists inside the one statement that defines it, so the `WITH` part and the `SELECT` that uses it have to run together.

## Limitations

- Duplicates were removed before the text was standardized, so rows that differ only by spacing or spelling (for example "Crypto" and "CryptoCurrency") would not have been caught as duplicates.
- 748 rows had neither a layoff count nor a percentage and were removed, which is about 16% of the data after de-duplication. The results describe layoffs where a number was reported.
- Rankings use `SUM` over reported values only, so layoffs that were never reported are not counted.

## Files

- `layoffs_clean_eda_sqlserver.sql`: the full cleaning and analysis script
- `README.md`: this file

## About Me

**Oladotun Olawale**, aspiring Business / Data Analyst anywhere in Nigeria

- [LinkedIn](https://www.linkedin.com/in/oladotun-olawale)
- [Email](oladotunolawale29@yahoo.com)
