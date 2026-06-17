/* Data cleaning using SQL (MySQL version)
Skills used: CREATE TABLE ... AS SELECT, GROUP BY, ORDER BY, REPLACE, CASE, window functions,
CTEs, removing duplicates, inadequate and unnecessary data.

Porting notes (BigQuery -> MySQL):
- Original script ran in BigQuery Standard SQL against a `project.dataset.table` hierarchy.
  Here it targets a single MySQL database, selected with USE below; all `project.dataset.`
  prefixes are dropped.
- BigQuery's `CREATE OR REPLACE TABLE x AS SELECT ... FROM x` (rewriting a table from itself in
  one statement) has no MySQL equivalent. Every self-referencing step below is rewritten as:
  build into a `_tmp` table -> drop the original -> rename `_tmp` into place.
- INT64 -> SIGNED, FLOAT64 -> DECIMAL(15,6), STRING -> CHAR (MySQL CAST target types).
- A couple of steps in the original appear to have been done via the BigQuery console
  (e.g. `re_us4` is used before it's ever created in-script). Those are made explicit as SQL
  here and flagged inline, so this version runs top-to-bottom without gaps. */

USE real_estate_us;

----------------------------------------------------------------------------------

/* First look at the dataset */

SELECT *
FROM re_us
LIMIT 1000;


/* Remove duplicates and create a new table */

DROP TABLE IF EXISTS re_us1;
CREATE TABLE re_us1 AS
SELECT DISTINCT *
FROM re_us;

/* The dataset has decreased by almost 9 times */



/* Change datatypes and names in the 'bed', 'bath', 'zip_code' columns
   (self-referencing rebuild: re_us1 -> re_us1) */

DROP TABLE IF EXISTS re_us1_tmp;
CREATE TABLE re_us1_tmp AS
SELECT
    status,
    price,
    CAST(bed AS SIGNED) AS bedrooms,
    CAST(bath AS SIGNED) AS bathrooms,
    acre_lot,
    full_address,
    street,
    city,
    state,
    CAST(zip_code AS CHAR) AS zipcode,
    house_size,
    sold_date
FROM re_us1;

DROP TABLE re_us1;
RENAME TABLE re_us1_tmp TO re_us1;



/* Check distinct values in the status column and quantity */

SELECT
    status,
    COUNT(status)
FROM re_us1
GROUP BY status;



/* Check sold_date column with status 'ready_to_build' */

SELECT *
FROM re_us1
WHERE status = 'ready_to_build'
  AND sold_date IS NOT NULL;

/* The Status column has two distinct values, the majority of which are "for_sale" (113512).
There is no 'sold date' for any of the rows with "ready_to_build" (277 rows). Later, we will exclude
'ready_to_build' rows from our analysis, because they are now actually existing buildings. */



/* Check bed column */

SELECT
    bedrooms,
    COUNT(bedrooms) AS count_bed
FROM re_us
GROUP BY bedrooms
ORDER BY count_bed DESC;


SELECT *
FROM re_us1
WHERE bedrooms > 11;


SELECT *
FROM re_us1
WHERE bedrooms IS NULL;

/* Here are some rows with an enormously high quantity of bedrooms; for example, 123 is the maximum
value. However, a portion of the rows do not have a null sold_date. There aren't many rows like this.
We will leave it as is. 17516 with null values in this column */



/* Check the other columns */

SELECT
    bathrooms,
    COUNT(bathrooms) AS count_bath
FROM re_us1
GROUP BY bathrooms
ORDER BY count_bath DESC;

SELECT *
FROM re_us1
WHERE bathrooms > 12;

SELECT *
FROM re_us1
WHERE bathrooms IS NULL;

/* 16297 null values in the bathrooms column. Enormously high values (more than 11) in the bathroom
column in 210 rows. There are more bathrooms than bedrooms in these rows. Maybe it's a mistake. But we
don't know exactly; it's not the goal of our analysis right now. And it will not skew the results;
we will leave it as it is. */


SELECT *
FROM re_us1
WHERE state IS NULL;


SELECT
    state,
    COUNT(state) AS counts
FROM re_us1
GROUP BY state
ORDER BY counts DESC;


/* There are no null values in the "state" column.
Virginia (7), Georgia (5), South Carolina, Tennessee, Wyoming, and West Virginia (1) have a low
quantity of rows. We will exclude them from our analysis. */


SELECT *
FROM re_us1
WHERE sold_date IS NULL;

/* There are 54092 null values in the "sold_date" column. These rows cannot be used for time-series
analysis. So, let's create two tables: one for analysis by time periods and prediction, and another
for the basic exploration. */



/* Remove the states of Virginia, Georgia, South Carolina, Tennessee, Wyoming, and West Virginia;
'ready_to_build' status. Drop the status, full_address, and zipcode columns.
(self-referencing rebuild: re_us1 -> re_us1)
[Note: BigQuery's original comment "I use CREATE OR DROP TABLE because DML is not available in the
BigQuery Sandbox" doesn't apply in MySQL, where UPDATE/DELETE are available - the temp+rename
pattern is used here purely to mirror the original transformation logic.] */

DROP TABLE IF EXISTS re_us1_tmp;
CREATE TABLE re_us1_tmp AS
SELECT
    state,
    city,
    street,
    price,
    bedrooms,
    bathrooms,
    acre_lot,
    house_size,
    sold_date
FROM re_us1
WHERE status != 'ready_to_build'
  AND state != 'Virginia'
  AND state != 'Georgia'
  AND state != 'South Carolina'
  AND state != 'Tennessee'
  AND state != 'Wyoming'
  AND state != 'West Virginia';

DROP TABLE re_us1;
RENAME TABLE re_us1_tmp TO re_us1;



/* Inspect city column */

SELECT
    city,
    COUNT(city) AS counts,
    state
FROM re_us1
GROUP BY city, state
ORDER BY counts DESC;


SELECT
    city,
    COUNT(city) AS counts,
    state
FROM re_us1
WHERE city LIKE 'N%' AND state = 'New York'
GROUP BY city, state
ORDER BY counts DESC;



/* There are different spellings of New York (New York City, Ny, Nyc). Let's fix it */

SELECT
    city,
    COUNT(city) AS counts,
    REPLACE(REPLACE(REPLACE(city, 'New York City', 'New York'), 'Nyc', 'New York'), 'Ny', 'New York') AS ny,
    state
FROM re_us1
WHERE city LIKE 'N%' AND state = 'New York'
GROUP BY city, state
ORDER BY counts DESC;


/* (self-referencing rebuild: re_us1 -> re_us1) */

DROP TABLE IF EXISTS re_us1_tmp;
CREATE TABLE re_us1_tmp AS
SELECT
    state,
    REPLACE(REPLACE(REPLACE(city, 'New York City', 'New York'), 'Nyc', 'New York'), 'Ny', 'New York') AS city,
    street,
    price,
    bedrooms,
    bathrooms,
    acre_lot,
    house_size,
    sold_date
FROM re_us1;

DROP TABLE re_us1;
RENAME TABLE re_us1_tmp TO re_us1;



/* Fixing 23 null values in the "city" column and add extract year from 'sold_date'.
Checking null and suspiciously low values (51 rows) in 'price' column and removing them */

SELECT *
FROM re_us1
WHERE city IS NULL;


SELECT *
FROM re_us2
WHERE price IS NULL;


SELECT *
FROM re_us2
WHERE price < 5000;


DROP TABLE IF EXISTS re_us2;
CREATE TABLE re_us2 AS
SELECT
    state,
    CASE
        WHEN street IN ('163 Union and Mt Wash Ea','155-A La Vallee Nb','123 Catherines Hope Eb', '21 N Grapetree Eb', '42 43 Shoys Ea', '8-B Teagues Bay Eb', '242 Union and Mt Wash Ea', '96 Hard Labor Pr') AND city IS NULL
            THEN 'Christiansted'
        WHEN street IN ('4 Prosperity Nb', '20 River Pr', '17 Prosperity Nb', '94V I Corp Lands Pr', '14 Diamond Pr', '192 La Vallee Nb') AND city IS NULL
            THEN 'Frederiksted'
        WHEN street IN ('240 St John Qu') AND city IS NULL THEN 'Saint John'
        WHEN street IN ('230 S Stevens Ave') AND city IS NULL THEN 'South Amboy'
        WHEN street IN ('0 Block 32 Quinton Alloway Quinton Rd Lot 11 01') AND city IS NULL THEN 'Quinton'
        WHEN street = '641 State Route 82' AND city IS NULL THEN 'Hopewell Junction'
        WHEN street = '32 Devereux Dr' AND city IS NULL THEN 'Manchester Township'
        WHEN street = '9-11 Putnam Park Rd' AND city IS NULL THEN 'Bethel'
        WHEN street = '68 Avondale St' AND city IS NULL THEN 'Valley Stream'
        WHEN street = '824-26 Berckman St' AND city IS NULL THEN 'Plainfield'
        WHEN street = '689 Luis M Marin Blvd Unit 1009' AND city IS NULL THEN 'Jersey City'
        ELSE city
    END AS city,
    street,
    price,
    bedrooms,
    bathrooms,
    acre_lot,
    house_size,
    sold_date,
    EXTRACT(YEAR FROM sold_date) AS year
FROM re_us1
WHERE price > 5000;



/* Create house_size_m2 and hectare_lot columns.
Replace incorrect highest value, update new highest value according to realtor.com data.
Change info about property with address 421 W 250th St.
(self-referencing rebuild: re_us2 -> re_us2; original comment about DML not being available in the
BigQuery Sandbox doesn't apply here, kept only to preserve the original transformation logic) */

SELECT *
FROM re_us2
ORDER BY price DESC;


DROP TABLE IF EXISTS re_us2_tmp;
CREATE TABLE re_us2_tmp AS
SELECT
    state,
    CASE
        WHEN street = '421 W 250th St' AND city = 'New York' THEN 'Bronx'
        ELSE city
    END AS city,
    street,
    CASE
        WHEN street = '952 E 223 St Units 4858 & 66' AND price = 875000000 THEN 850000
        WHEN street = '432 Park Ave Unit Penthouse' AND price = 169000000 THEN 180000000
        WHEN street = '421 W 250th St' AND price = 120000000 THEN 8750000
        ELSE price
    END AS price,
    CASE
        WHEN street = '421 W 250th St' AND bedrooms = 123 THEN 8
        ELSE bedrooms
    END AS bedrooms,
    CASE
        WHEN street = '421 W 250th St' AND bathrooms = 123 THEN 10
        ELSE bathrooms
    END AS bathrooms,
    acre_lot,
    acre_lot * 0.404686 AS hectare_lot,
    CASE
        WHEN street = '421 W 250th St' AND house_size IS NULL THEN 11135
        ELSE house_size
    END AS house_size,
    house_size / 10.7639 AS house_size_m2,
    CASE
        WHEN street = '421 W 250th St' AND sold_date = '2012-06-29' THEN NULL
        ELSE sold_date
    END AS sold_date
FROM re_us2
ORDER BY price DESC;

DROP TABLE re_us2;
RENAME TABLE re_us2_tmp TO re_us2;



/* Here are some more duplicates with slightly different street column values but the same other
columns. We need to solve this.
[Note: the original script references `re_us4` here without ever creating it - most likely a copy
or export made via the BigQuery console. That step is made explicit below so this script runs without
gaps; `re_us2` itself is left untouched, since it's still needed later for `re_us_sold`.] */

DROP TABLE IF EXISTS re_us4;
CREATE TABLE re_us4 AS
SELECT * FROM re_us2;


SELECT DISTINCT
    state,
    city,
    price,
    bedrooms,
    bathrooms,
    acre_lot,
    house_size,
    sold_date
FROM re_us2
ORDER BY price DESC;

/* There are 111016 distinct rows excluding the street column */


/* Check the duplicate rows to decide how to treat them. */

SELECT
    a.*
FROM re_us4 a
JOIN (
    SELECT
        state,
        city,
        price,
        IFNULL(bedrooms, 0) AS bedrooms,
        IFNULL(bathrooms, 0) AS bathrooms,
        IFNULL(acre_lot, 0) AS acre_lot,
        IFNULL(house_size, 0) AS house_size,
        COUNT(*) AS cnt
    FROM re_us4
    GROUP BY state, city, price, bedrooms, bathrooms, acre_lot, house_size
    HAVING COUNT(*) > 1
) b
    ON a.state = b.state
   AND a.city = b.city
   AND a.price = b.price
   AND a.bedrooms = b.bedrooms
   AND a.bathrooms = b.bathrooms
   AND a.acre_lot = b.acre_lot
   AND a.house_size = b.house_size
ORDER BY a.price;

/* With a few exceptions, we can tell from the web information about duplicate row addresses that the
majority of them are the same property. We can remove these duplicates. But it's necessary to check
rows where bedrooms, bathrooms, acre_lot, house_size are nulls to see if they are the same. */


/* Create a table with the changed datatypes and replaced null values. */

DROP TABLE IF EXISTS re_us5;
CREATE TABLE re_us5 AS
SELECT
    state,
    city,
    street,
    CAST(price AS SIGNED) AS price,
    IFNULL(bedrooms, 0) AS bedrooms,
    IFNULL(bathrooms, 0) AS bathrooms,
    IFNULL(CAST(acre_lot AS CHAR), '0') AS acre_lot,
    IFNULL(CAST(house_size AS CHAR), '0') AS house_size,
    IFNULL(CAST(sold_date AS CHAR), '0') AS sold_date
FROM re_us4;


SELECT *
FROM (
    SELECT
        t.*,
        ROW_NUMBER() OVER (
            PARTITION BY state, city, price, bedrooms, bathrooms, acre_lot, house_size, sold_date
            ORDER BY price DESC
        ) AS rn
    FROM re_us5 t
) cte
WHERE rn > 1
  AND bedrooms = 0
  AND bathrooms = 0
  AND acre_lot = '0'
  AND house_size = '0';

/* 33 rows with null in bedrooms, bathrooms, acre_lot, house_size columns at the same time.
Part of them are different plots of land, and another part are duplicate properties.
We can remove duplicates here. */


DROP TABLE IF EXISTS re_us_noduplicates;
CREATE TABLE re_us_noduplicates AS
SELECT *
FROM (
    SELECT
        t.*,
        ROW_NUMBER() OVER (
            PARTITION BY state, city, price, bedrooms, bathrooms, acre_lot, house_size, sold_date
            ORDER BY price DESC
        ) AS rn
    FROM re_us5 t
) cte
WHERE rn = 1
ORDER BY price DESC;


/* Also, we need to separate plots of land from property for our analysis.
(self-referencing rebuild: re_us_noduplicates -> re_us_noduplicates, adding a row id) */

DROP TABLE IF EXISTS re_us_noduplicates_tmp;
CREATE TABLE re_us_noduplicates_tmp AS
SELECT
    ROW_NUMBER() OVER (ORDER BY price DESC) AS id,
    state,
    city,
    street,
    price,
    bedrooms,
    bathrooms,
    acre_lot,
    house_size,
    sold_date
FROM re_us_noduplicates;

DROP TABLE re_us_noduplicates;
RENAME TABLE re_us_noduplicates_tmp TO re_us_noduplicates;


/* (self-referencing rebuild: re_us_noduplicates -> re_us_noduplicates, dropping ambiguous rows) */

DROP TABLE IF EXISTS re_us_noduplicates_tmp;
CREATE TABLE re_us_noduplicates_tmp AS
SELECT *
FROM re_us_noduplicates
WHERE id NOT IN (
    SELECT id FROM re_us_noduplicates
    WHERE bedrooms = 0 AND bathrooms = 0 AND acre_lot != '0' AND house_size = '0'
)
ORDER BY price DESC;

DROP TABLE re_us_noduplicates;
RENAME TABLE re_us_noduplicates_tmp TO re_us_noduplicates;


/* Check columns with nulls in bedrooms, bathrooms, acre_lot, house_size columns */

SELECT *
FROM (
    SELECT
        t.*,
        ROW_NUMBER() OVER (
            PARTITION BY state, city, price, bedrooms, bathrooms, acre_lot, house_size, sold_date
            ORDER BY price DESC
        ) AS rn
    FROM re_us5 t
) cte
WHERE bedrooms = 0 AND bathrooms = 0 AND acre_lot = '0' AND house_size = '0'
ORDER BY price DESC;

/* There are 552 such rows. Most of them are properties. Maybe all this information was just skipped
while entering data. Leave these rows in our property data. */


/* Change datatypes, add columns */

SELECT
    state,
    city,
    street,
    price,
    bedrooms,
    bathrooms,
    CAST(CASE WHEN acre_lot = 0 THEN NULL ELSE acre_lot END AS DECIMAL(15,6)) AS acre_lot,
    CAST(CASE WHEN house_size = 0 THEN NULL ELSE house_size END AS DECIMAL(15,6)) AS house_size,
    CAST(CASE WHEN sold_date = '0' THEN NULL ELSE sold_date END AS DATE) AS sold_date
FROM re_us5;


/* [Note: the original script here goes straight from the preview SELECT above into a self-referencing
`CREATE OR REPLACE TABLE re_us_property AS SELECT ... FROM re_us_property`, which implies the preview
was actually materialized into `re_us_property` first (likely via the BigQuery console). That
materialization step is made explicit below.] */

DROP TABLE IF EXISTS re_us_property;
CREATE TABLE re_us_property AS
SELECT
    state,
    city,
    street,
    price,
    bedrooms,
    bathrooms,
    CAST(CASE WHEN acre_lot = 0 THEN NULL ELSE acre_lot END AS DECIMAL(15,6)) AS acre_lot,
    CAST(CASE WHEN house_size = 0 THEN NULL ELSE house_size END AS DECIMAL(15,6)) AS house_size,
    CAST(CASE WHEN sold_date = '0' THEN NULL ELSE sold_date END AS DATE) AS sold_date
FROM re_us5;


/* (self-referencing rebuild: re_us_property -> re_us_property, adding hectare/m2 conversions and year) */

DROP TABLE IF EXISTS re_us_property_tmp;
CREATE TABLE re_us_property_tmp AS
SELECT
    state,
    city,
    street,
    price,
    bedrooms,
    bathrooms,
    acre_lot,
    acre_lot * 0.404686 AS hectare_lot,
    house_size,
    house_size / 10.7639 AS house_size_m2,
    sold_date,
    EXTRACT(YEAR FROM sold_date) AS year
FROM re_us_property;

DROP TABLE re_us_property;
RENAME TABLE re_us_property_tmp TO re_us_property;


/* Create second table only with not null values in the 'sold_date' column */

DROP TABLE IF EXISTS re_us_sold;
CREATE TABLE re_us_sold AS
SELECT *
FROM re_us2
WHERE sold_date IS NOT NULL;


/* Create a table with plots of land.
But we need to do more exploration of this data to be sure that this table contains actual
information about plots. */

DROP TABLE IF EXISTS re_us_plots;
CREATE TABLE re_us_plots AS
SELECT
    state,
    city,
    street,
    price,
    CAST(acre_lot AS DECIMAL(15,6)) AS acre_lot,
    sold_date
FROM re_us5
WHERE bedrooms = 0 AND bathrooms = 0 AND acre_lot != '0' AND house_size = '0'
ORDER BY price DESC;
