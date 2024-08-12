----Author: Sraddha Bhattacharjee
----Notes: I have executed both solutions in PostgreSQL
----------------------------------------------------------------------------------------------------------------------------------------------

----- Question 1 (from PDF)


-- Step 1: Identify the first order date for each customer

-----I created a Common Table Expression (CTE) named FirstOrderDate.
-----I selected customer_number and the earliest orderdate for each customer by grouping the data by customer_number.
-----This gives the first order date for every customer.

WITH FirstOrderDate AS (
    SELECT
        customer_number,
        MIN(orderdate) AS first_order_date
    FROM sales
    GROUP BY customer_number
),
-- Step 2: Classify each order as new or returning

-----I created another CTE named CustomerClassification.
-----I joined the sales table with the FirstOrderDate CTE on customer_number.
-----Then, I extracted the year from both the order date and the first order date.
-----Following this, I classified the order as 'New' if the order year matches the year of the first order, otherwise classify it as 'Returning'.
	
CustomerClassification AS (
    SELECT
        s.customer_number,
        EXTRACT(YEAR FROM s.orderdate) AS order_year,
        CASE
            WHEN EXTRACT(YEAR FROM s.orderdate) = EXTRACT(YEAR FROM f.first_order_date) THEN 'New'
            ELSE 'Returning'
        END AS customer_type
    FROM sales s
    JOIN FirstOrderDate f ON s.customer_number = f.customer_number
),
-- Step 3: Count the number of new and returning customers per year

----I created a CTE named YearlyCustomerCount.
----I grouped by order_year and customer_type and counted the distinct customer_number for each combination.
-----This provides the count of new and returning customers for each year.
	
YearlyCustomerCount AS (
    SELECT
        order_year AS year,
        customer_type AS customer_type,
        COUNT(DISTINCT customer_number) AS customer_count
    FROM CustomerClassification
    GROUP BY order_year, customer_type
),
-- Step 4: Calculate the total number of customers per year

----I created another CTE named TotalCustomersPerYear.
----I aggregated the counts from YearlyCustomerCount by year, summing up the customer_count for each year.
----This gives the total customer count for each year.
	
TotalCustomersPerYear AS (
    SELECT
        year,
        SUM(customer_count) AS total_customers
    FROM YearlyCustomerCount
    GROUP BY year
),
-- Step 5: Calculate the portion of new and returning customers

----I created a CTE named Portions.
----I joined YearlyCustomerCount with TotalCustomersPerYear on year.
----Then, I calculated the portion by dividing the count of each type of customer by the total number of customers for that year.
----I used ::FLOAT to ensure that division results in a floating-point number.
	
Portions AS (
    SELECT
        ycc.year,
        ycc.customer_type,
        ycc.customer_count::FLOAT / tcp.total_customers AS portion
    FROM YearlyCustomerCount ycc
    JOIN TotalCustomersPerYear tcp ON ycc.year = tcp.year
)
-- Step 6: Pivot the result to the desired format

---Using the Portions CTE, I applied conditional aggregation (CASE WHEN) to compute the sums for new and returning customers separately.
----I Calculated the total portion by summing the portions for new and returning customers.
----I used the COALESCE function to handle cases where no data is present for a given category and ensure proper handling of nulls.
----Then, I grouped by year and ordered by year to produce the final result in chronological order.
	
SELECT
    year,
    COALESCE(SUM(CASE WHEN customer_type = 'New' THEN portion END), 0) AS new,
    COALESCE(SUM(CASE WHEN customer_type = 'Returning' THEN portion END), 0) AS returning,
    COALESCE(SUM(CASE WHEN customer_type = 'New' THEN portion END), 0) + 
    COALESCE(SUM(CASE WHEN customer_type = 'Returning' THEN portion END), 0) AS total
FROM Portions
GROUP BY year
ORDER BY year;

----------------------------------------------------------------------------------------

----- Outlier Sales (as mentioned in the email)

-----I used PERCENTILE_CONT(0.25) to calculate the value below which 25% of the data falls, giving Q1.
-----I used PERCENTILE_CONT(0.75) to calculate the value below which 75% of the data falls, giving Q3.
-----I used GROUP BY "sku_id" to ensure that quartiles are calculated for each sku_id individually.

WITH quartiles AS (
    SELECT "sku_id",
           PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY "QuantityOrdered") AS Q1,
           PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY "QuantityOrdered") AS Q3
    FROM sales
    GROUP BY "sku_id"
),
---I joined the sales table with the quartiles table to get Q1 and Q3 for each sku_id.
---I computed IQR as Q3 - Q1, which measures the spread of the middle 50% of the data.
iqr_calculated AS (
    SELECT s."sku_id",
           s."orderdate",
           s."QuantityOrdered",
           q.Q1,
           q.Q3,
           (q.Q3 - q.Q1) AS IQR
    FROM sales s
    JOIN quartiles q ON s."sku_id" = q."sku_id"
),
---Now, I have written a CASE statement to classify each record as an outlier (1) or not (0).
----An outlier is defined as a data point that falls below (Q1 - 1.5 * IQR) or above (Q3 + 1.5 * IQR)
----Empirically, using 1.5 times the IQR captures about 99.5% of the data in a normal distribution. This means values beyond this range are rare and can be considered potential outliers.
outlier_check AS (
    SELECT "sku_id",
           CASE
               WHEN "QuantityOrdered" < (Q1 - 1.5 * IQR) OR "QuantityOrdered" > (Q3 + 1.5 * IQR)
               THEN 1
               ELSE 0
           END AS IsOutlier
    FROM iqr_calculated
)
----I have used MAX(IsOutlier) to check if there is at least one outlier for each sku_id.
----If IsOutlier is 1 for any record, MAX(IsOutlier) will be 1, indicating that the SKU has outliers.
SELECT "sku_id",
       MAX(IsOutlier) AS OutlierSales
FROM outlier_check
GROUP BY "sku_id";


----------------------------------------------------------------------------------------

---- Question 2 (from PDF)


-- Step 1: Create a table to hold the filtered data

---I created a table sales_filtered that excludes outliers in terms of QuantityOrdered using the Interquartile Range (IQR) method.

----a)To Calculate Quartiles:

----I created quartiles CTE which calculates the first quartile (Q1) and the third quartile (Q3) for each sku_id. The quartiles are used to understand the spread of QuantityOrdered.

----b)To Calculate IQR:

---I created iqr_calculated CTE which calculates the IQR by subtracting Q1 from Q3 for each sku_id. It also includes the raw data alongside quartile information.

----c)To Filter Outliers:

----I create the filtered_data CTE which filters out the rows where QuantityOrdered falls outside the range defined by Q1 - 1.5 * IQR to Q3 + 1.5 * IQR. This helps in removing extreme outliers from the dataset.
---- Empirically, using 1.5 times the IQR captures about 99.5% of the data in a normal distribution. This means values beyond this range are rare and can be considered potential outliers.

CREATE TABLE sales_filtered AS
WITH quartiles AS (
    SELECT "sku_id",
           PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY "QuantityOrdered") AS Q1,
           PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY "QuantityOrdered") AS Q3
    FROM sales
    GROUP BY "sku_id"
),
iqr_calculated AS (
    SELECT s."sku_id",
           s."orderdate",
           s."QuantityOrdered",
           q.Q1,
           q.Q3,
           (q.Q3 - q.Q1) AS IQR
    FROM sales s
    JOIN quartiles q ON s."sku_id" = q."sku_id"
),
filtered_data AS (
    SELECT s."sku_id",
           s."orderdate",
           s."QuantityOrdered"
    FROM iqr_calculated s
    WHERE s."QuantityOrdered" >= (s.Q1 - 1.5 * s.IQR)
      AND s."QuantityOrdered" <= (s.Q3 + 1.5 * s.IQR)
)
SELECT *
FROM filtered_data;

-- Step 2: Calculate average demand per year

---The average_demand table calculates the average quantity ordered (avg_quantity) for each combination of order_year and sku_id.
----I used EXTRACT(YEAR FROM "orderdate") to group the data by year.

CREATE TABLE average_demand AS
SELECT EXTRACT(YEAR FROM "orderdate") AS order_year,
       "sku_id",
       AVG("QuantityOrdered") AS avg_quantity
FROM sales_filtered
GROUP BY order_year, "sku_id";

-- Step 3: Predict next year's demand using linear regression or single-year value

----a)Linear Regression Calculation:

----I created sku_regression CTE to calculate the slope and intercept of a linear regression line that fits the average quantity ordered over several years for each sku_id.
----I did this using the REGR_SLOPE and REGR_INTERCEPT functions, which are built-in functions of PostgreSQL.

----b)Predict Next Year's Quantity:

----I created predicted_values CTE to compute the next year’s predicted quantity. 
----If only one year of data is available, it simply uses that year’s quantity. If more years' data is available, it uses the linear regression equation to predict the quantity for the next year.

----c)Final Selection:

----The predicted_demand table contains the predicted quantities for each sku_id for the next year.

CREATE TABLE predicted_demand AS
WITH sku_regression AS (
    SELECT
        "sku_id",
        -- Calculate slope and intercept for linear regression
        REGR_SLOPE(avg_quantity, order_year) AS slope,
        REGR_INTERCEPT(avg_quantity, order_year) AS intercept,
        MAX(order_year) AS max_year,
        COUNT(order_year) AS year_count
    FROM average_demand
    GROUP BY "sku_id"
),
predicted_values AS (
    SELECT
        sr."sku_id",
        CASE
            WHEN sr.year_count = 1 THEN MAX(ad.avg_quantity)  -- Use the single year's quantity if only one year of data
            ELSE (sr.slope * (sr.max_year + 1) + sr.intercept) -- Otherwise, use linear regression prediction
        END AS quantity
    FROM sku_regression sr
    LEFT JOIN average_demand ad
    ON sr."sku_id" = ad."sku_id"
    AND ad.order_year = sr.max_year
    GROUP BY sr."sku_id", sr.slope, sr.intercept, sr.max_year, sr.year_count
)
-- Final selection to create the predicted_demand table
SELECT *
FROM predicted_values;

-- Step 4: Create a new table with modified predicted_quantity values

---As an additional step I created predicted_demand_adjusted table which adjusts the predicted quantities:

---a) Sets values between 0 and 1 to 1.
---b)Sets non-positive values to 0.
---c) Leaves other values unchanged.

----The Linear Regression model predicts whether demand for a particular sku_id will increase or decrease.
----However, when the sales for a sku_id keeps reducing over the years, the model forecasts negative values for the quantity column, suggesting a demand drop below zero for the following year. 
----To address this, I adjusted the predictions by setting the quantities to zero or one when they are close to zero (as mentioned above), ensuring that the forecasted stock levels remain practical and feasible.


CREATE TABLE predicted_demand_adjusted AS
SELECT 
    sku_id,
    CASE
        WHEN quantity > 0 AND quantity < 1 THEN 1
        WHEN quantity <= 0 THEN 0
        ELSE quantity
    END AS quantity
FROM predicted_demand;

---The final output is the predicted_demand table which is selected to review the adjusted predicted quantities.
SELECT * from predicted_demand;





