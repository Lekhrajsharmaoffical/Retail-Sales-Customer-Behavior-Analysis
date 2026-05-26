 Data Cleaning Outlier Removal — Customers (IQR Method)
WITH ordered AS (
    SELECT CustomerID, age,
           NTILE(4) OVER (ORDER BY age) AS quartile
    FROM customers
),
quartiles AS (
    SELECT MAX(CASE WHEN quartile = 1 THEN age END) AS Q1,
           MAX(CASE WHEN quartile = 3 THEN age END) AS Q3
    FROM ordered
)
DELETE FROM customers
WHERE age > (SELECT Q3 + 1.5 * (Q3 - Q1) FROM quartiles);
---- Outlier Removal — Transactions (3-STD Method).
DELETE FROM sales_transaction
WHERE price > (SELECT * FROM (SELECT AVG(price) + 3 * STD(price) FROM sales_transaction) t)
   OR price < (SELECT * FROM (SELECT AVG(price) - 3 * STD(price) FROM sales_transaction) t);
---------Date Standardisation
UPDATE customers        SET joindate        = STR_TO_DATE(joindate,        '%d/%m/%y');
UPDATE sales_transaction SET transactiondate = STR_TO_DATE(transactiondate, '%d/%m/%y');
-------- Analysis Sections
1. Category Performance
SELECT p.Category,
       ROUND((SUM(s.QuantityPurchased * s.Price) / SUM(SUM(s.QuantityPurchased * s.Price)) OVER()) * 100, 2) AS revenue_as_percentage
FROM product_inventory AS p
JOIN sales_transaction AS s ON p.ProductID = s.ProductID
GROUP BY p.Category;
2. Customer Distribution — Location & Gender
SELECT CASE WHEN location = '' THEN 'Not Available' ELSE location END AS location,
       COUNT(*) AS total_customer
FROM customers
GROUP BY location
ORDER BY COUNT(*) DESC;
3. New Customer Acquisition by Year
SELECT YEAR(joindate) AS Year, COUNT(*) AS number_of_customers
FROM customers
WHERE YEAR(joindate) != 2023
GROUP BY YEAR(joindate);
4. Product & Revenue Rankings
SELECT ProductID, SUM(QuantityPurchased) AS Total_Quantity,
       ROUND(SUM(price * quantitypurchased), 1) AS Revenue
FROM sales_transaction
GROUP BY ProductID
ORDER BY Revenue DESC;
5. Inventory Risk Analysis
SELECT t.ProductID, t.Category, t.StockLevel,
       ROUND(t.StockLevel / t.Total_Sell_Quantity * 100, 2)     AS Stock_Fulfillment_Pct,
       ROUND(t.Total_Sell_Quantity / 365, 2)                     AS Daily_Sell_Velocity,
       ROUND(t.StockLevel / (t.Total_Sell_Quantity / 365), 2)    AS Days_Of_Stock_Left,
       CASE
           WHEN t.StockLevel = 0                                    THEN 'Out Of Stock'
           WHEN t.StockLevel / t.Total_Sell_Quantity < 0.10         THEN 'Critical Risk'
           WHEN t.StockLevel / t.Total_Sell_Quantity < 0.20         THEN 'High Risk'
           WHEN t.StockLevel / t.Total_Sell_Quantity < 0.35         THEN 'Watch'
           ELSE 'Stable'
       END AS Risk_Level
FROM (...) t
WHERE ROUND(t.StockLevel / t.Total_Sell_Quantity * 100, 2) < 100
ORDER BY Stock_Fulfillment_Pct ASC;
6. Month-over-Month (MoM) Revenue Growth
SELECT MONTHNAME(transactiondate) AS month_name,
       SUM(revenue) AS current_revenue,
       LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)) AS previous_revenue,
       ROUND((SUM(revenue) - LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)))
             / LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)) * 100, 2) AS pct_growth
FROM sales_transaction
GROUP BY MONTHNAME(transactiondate), MONTH(transactiondate);
7. Top 2 Customers Every Month
SELECT * FROM (
    SELECT MONTHNAME(TransactionDate) AS MonthName, YEAR(TransactionDate) AS Year,
           CustomerID,
           ROUND(SUM(QuantityPurchased * Price), 2) AS Revenue,
           RANK() OVER (
               PARTITION BY MONTHNAME(TransactionDate), YEAR(TransactionDate)
               ORDER BY SUM(QuantityPurchased * Price) DESC
           ) AS Month_Rank
    FROM sales_transaction
    GROUP BY MONTHNAME(TransactionDate), YEAR(TransactionDate), CustomerID
) t
WHERE Month_Rank < 3;
8. Top 5 Customers per Location & Revenue by Location → Gender
SELECT Location, CustomerID, Revenue, Top_customer
FROM (
    SELECT c.Location, s.CustomerID, SUM(s.revenue) AS Revenue,
           DENSE_RANK() OVER (PARTITION BY c.location ORDER BY SUM(s.revenue) DESC) AS Top_customer
    FROM sales_transaction AS s
    JOIN customers AS c ON s.CustomerID = c.CustomerID
    GROUP BY c.location, s.customerid
) AS t
WHERE Top_customer < 6;
9. Product Contribution within a Category (Beauty & Health)
SELECT Category, ProductName, Price, Revenue,
       ROUND((Revenue / SUM(Revenue) OVER()) * 100, 2) AS Pct_contribution
FROM (
    SELECT p.Category, p.ProductName, s.Price, SUM(s.Revenue) AS Revenue
    FROM product_inventory AS p
    JOIN sales_transaction AS s ON p.ProductID = s.ProductID
    WHERE Category = 'Beauty & Health'
    GROUP BY p.Category, p.ProductName, s.Price
) t
ORDER BY Pct_contribution DESC;
10. RFM Customer Segmentation Model
WITH Max_date AS (SELECT MAX(transactiondate) AS ref_date FROM sales_transaction),
rfm AS (
    SELECT CustomerID,
           DATEDIFF((SELECT ref_date FROM Max_date), MAX(TransactionDate)) AS Recency,
           COUNT(CustomerID)                                                AS Frequency,
           SUM(Revenue)                                                     AS Monetary
    FROM sales_transaction GROUP BY CustomerID
),
rfm_score AS (
    SELECT CustomerID, Recency, Frequency, Monetary,
           NTILE(5) OVER (ORDER BY Recency   DESC) AS R_Score,
           NTILE(5) OVER (ORDER BY Frequency ASC)  AS F_Score,
           NTILE(5) OVER (ORDER BY Monetary  ASC)  AS M_Score
    FROM rfm
),
rfm_segment AS (
    SELECT *, CONCAT(R_Score, F_Score, M_Score) AS rfm_combined,
           CASE
               WHEN R_Score = 5  AND F_Score = 5  AND M_Score = 5  THEN 'Good Customer'
               WHEN R_Score >= 4 AND F_Score >= 4                  THEN 'Loyal Customer'
               ...
           END AS Segment
    FROM rfm_score
)
SELECT CustomerID, Segment,
       SUM(Monetary) OVER (PARTITION BY Segment) AS Total_Revenue
FROM rfm_segment;
11. Customer Cohort Retention Analysis
WITH cohort AS (
    SELECT CustomerID,
           DATE_FORMAT(MIN(TransactionDate), '%Y-%m-01') AS cohort_month
    FROM sales_transaction GROUP BY CustomerID
),
active AS (
    SELECT c.CustomerID, c.cohort_month,
           TIMESTAMPDIFF(month, c.cohort_month,
               DATE_FORMAT(s.transactiondate, '%y-%m-01')) AS month_number
    FROM cohort AS c JOIN sales_transaction AS s ON c.CustomerID = s.CustomerID
),
cohort_2 AS (
    SELECT cohort_month, month_number, COUNT(DISTINCT customerid) AS active_customer
    FROM active GROUP BY cohort_month, month_number
),
cohort_size AS (
    SELECT cohort_month, month_number, active_customer,
           FIRST_VALUE(active_customer) OVER (PARTITION BY cohort_month ORDER BY month_number) AS cohort_size,
           ROUND(active_customer / FIRST_VALUE(active_customer) OVER (PARTITION BY cohort_month ORDER BY month_number) * 100, 2) AS retention_pct
    FROM cohort_2
)
SELECT * FROM cohort_size ORDER BY cohort_month, month_number;
12. Executive Dashboard (8-CTE Summary)
WITH total_customer AS (...),
     total_revenue AS (...),
     top_category AS (...),
     top_category_revenue AS (...),
     top_location AS (...),
     best_selling_product AS (...),
     repeat_customers AS (...)
SELECT * FROM total_customer
JOIN total_revenue        ON 1=1
JOIN top_category         ON 1=1
JOIN top_category_revenue ON 1=1
JOIN top_location         ON 1=1
JOIN best_selling_product ON 1=1
JOIN repeat_customers     ON 1=1;

🔑 Key Business Findings

📉 Revenue declined 13.3% from Jan ($103,730) to Jul ($89,972) 2023 — driven by flat acquisition (334 → 331 new customers/year since 2020)
⚠️ 271 customers (27%) are At Risk, Lost, or Can't Lose Them — holding $147,766 in at-risk revenue
🏆 Home & Kitchen leads with $217,756 revenue (31.24%); Beauty & Health underperforms with 50 SKUs but only 20.65% revenue share
📦 1 product is out of stock, 2 in High Risk, and 14 below 50 units with no visible reorder system
🔁 95.85% repeat purchase rate — strong retention but masks the acquisition gap
🌍 West region outperforms East by $38,992 despite only 47 more customers


