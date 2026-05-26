select * from customers;
SET SQL_SAFE_UPDATES = 0;
---------------------------------------------- Romoving Outlier --------------------------------------------------------------------------
WITH ordered AS (SELECT CustomerID, age,
        NTILE(4) OVER (ORDER BY age) AS quartile FROM customers),
quartiles AS (
    SELECT MAX(CASE WHEN quartile = 1 THEN age END) AS Q1,
           MAX(CASE WHEN quartile = 3 THEN age END) AS Q3
           FROM ordered)
DELETE FROM customers
WHERE age > (SELECT Q3 + 1.5 * (Q3 - Q1) FROM quartiles);

SELECT * 
FROM sales_transaction
WHERE price > (SELECT AVG(price) + 3 * STD(price) FROM sales_transaction)
   OR price < (SELECT AVG(price) - 3 * STD(price) FROM sales_transaction);
   
   DELETE 
FROM sales_transaction
WHERE price > (SELECT * FROM (SELECT AVG(price) + 3 * STD(price) FROM sales_transaction) t)
   OR price < (SELECT * FROM (SELECT AVG(price) - 3 * STD(price) FROM sales_transaction) t);
   
------------ List all products along with their category and price, ordered by price from highest to lowest------------------------------------
select s.productID, p.category, p.price 
from product_inventory as p
join sales_transaction as s on p.ProductID = s.ProductID 
group by s.productID, p.category, p.price 
order by p.Category, p.price desc;
--------------------------------- count the customers location wise ----------------------------------------------------------------------
select case
           when location = '' then 'Not Available' 
           else location 
       end as location, 
       count(*) as total_customer 
from customers 
group by location 
order by count(*) desc;

--------------------------------- Total StockQuantity and QuantityPurchased by Category wise ---------------------------------------------

SELECT p.Category,
       ROUND((COUNT(DISTINCT s.CustomerID) / SUM(COUNT(DISTINCT s.CustomerID)) OVER()) * 100, 2) AS percentage_of_customers,
       ROUND((COUNT(DISTINCT s.ProductID) / SUM(COUNT(DISTINCT s.ProductID)) OVER()) * 100, 2) AS percentage_of_product,
       ROUND((AVG(s.Price) / SUM(AVG(s.Price)) OVER()) * 100, 2) AS average_price_percentage,
       ROUND((SUM(p.StockLevel) / SUM(SUM(p.StockLevel)) OVER()) * 100, 2) AS stock_percentage,
       ROUND((SUM(s.QuantityPurchased) / SUM(SUM(s.QuantityPurchased)) OVER()) * 100, 2) AS sell_percentage,
       ROUND((SUM(s.QuantityPurchased * s.Price) / SUM(SUM(s.QuantityPurchased * s.Price)) OVER()) * 100, 2) AS revenue_as_percentage
FROM product_inventory AS p
JOIN sales_transaction AS s ON p.ProductID = s.ProductID
GROUP BY p.Category;
------------------------------------------ deal with date column -------------------------------------------------------------------------
alter table customers
add column Joindate_new date;

update customers
set joindate = str_to_date(joindate, '%d/%m/%y');

alter table customers 
drop column Joindate_new;

select year(joindate) as Year, 
       count(*) as number_of_customers 
from customers
where year(joindate) != 2023 
group by year(joindate);

----------------------------------------- Average Price in Each Category -----------------------------------------------------------------
select category, round(avg(price), 2) as Average_price from product_inventory group by Category;

----------------------------------- List of all products where StockLevel is below 50 ----------------------------------------------------
select productid, category,stocklevel from product_inventory where stocklevel < 50 order by ProductID asc;

------------------------------------------ CustomerID and transaction count --------------------------------------------------------------
select CustomerID, count(*) as transaction_count from sales_transaction group by CustomerID order by count(*) desc;

----------------------------------------- Total revenue generated per product ------------------------------------------------------------
select ProductID, sum(QuantityPurchased) as Total_Quantity, 
round(sum(price * quantitypurchased), 1) as Revenue from sales_transaction 
group by ProductID order by sum(price * quantitypurchased) desc;

------------------------------------------- Top 2 customers Every month in every year ----------------------------------------------------
update sales_transaction
set transactiondate = str_to_date(transactiondate, '%d/%m/%y');
SELECT *
FROM (
    SELECT
        MONTHNAME(TransactionDate)              AS MonthName,
        YEAR(TransactionDate)                   AS Year,
        CustomerID,
        Round(SUM(QuantityPurchased * Price), 2)          AS Revenue,
        RANK() OVER (
            PARTITION BY 
                MONTHNAME(TransactionDate),
                YEAR(TransactionDate)
            ORDER BY 
                SUM(QuantityPurchased * Price) DESC
        )                                       AS Month_Rank
    FROM sales_transaction
    GROUP BY
        MONTHNAME(TransactionDate),
        YEAR(TransactionDate),
        CustomerID
    ORDER BY
        MONTHNAME(TransactionDate),
        SUM(QuantityPurchased * Price) DESC
) t
WHERE t.Month_Rank < 3;

------------------------------------------------------ Inventory Risk Analysis -----------------------------------------------------------
select 
      t.ProductID, t.Category, t.Stocklevel, t.Total_Sell_Quantity,
      round((t.stocklevel/t.total_sell_quantity*100), 2) as Stock_Fulfillment_Pct,
      round(t.total_sell_quantity/365, 2) as Daily_Sell_Velocity,
      round(t.stocklevel/(t.total_sell_quantity/365), 2) as Days_Of_Stock_Left,
      case
          when t.stocklevel = 0 then 'Out Of Sock'
          WHEN t.stocklevel/t.total_sell_quantity < 0.10 then 'Critical Risk'
          when t.stocklevel/t.total_sell_quantity < 0.20 then 'High Risk'
          when t.stocklevel/t.total_sell_quantity < 0.35 then 'Watch'
          else 'Stable' end as Risk_Level
		   from   (select 
               p.productid, p.Category, p.stocklevel, 
               sum(s.QuantityPurchased) as total_sell_quantity 
               from product_inventory as p
			   join sales_transaction as s on p.ProductID = s.productid
			   group by  p.productid, p.stocklevel, p.Category order by p.productid asc) t
               where  round((t.stocklevel/t.total_sell_quantity*100), 2) < 100
               order by Stock_Fulfillment_Pct asc;

------------------------------------- Month over Month (MoM) Revenue Growth Analysis -----------------------------------------------------
SELECT
    MONTHNAME(transactiondate)  AS month_name,
    MONTH(transactiondate)      AS month_num,
    SUM(revenue)                AS current_revenue,

    CASE
        WHEN (SUM(revenue) - LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate))) IS NULL
        THEN 0
        ELSE (SUM(revenue) - LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)))
    END AS revenue_change,

    CASE
        WHEN LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)) IS NULL
        THEN 0
        ELSE LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate))
    END AS previous_revenue,

    CASE
        WHEN ROUND(
                (SUM(revenue) - LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)))
                / LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)) * 100, 2
             ) IS NULL
        THEN 0
        ELSE ROUND(
                (SUM(revenue) - LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)))
                / LAG(SUM(revenue)) OVER (ORDER BY MONTH(transactiondate)) * 100, 2
             )
    END AS pct_growth

FROM sales_transaction
GROUP BY
    MONTHNAME(transactiondate),
    MONTH(transactiondate);

-------------------------------------- top 5 customer of every location ------------------------------------------------------------------ 
select case when Location = '' then 'Not Available' else location end as Location, CustomerID, Revenue, Top_customer
from (   
select c.Location, s.customerid, sum(s.revenue) as Revenue, 
dense_rank() over(partition by c.location order by sum(s.revenue) desc) as top_customer
from sales_transaction as s
join customers as c on s.CustomerID = c.CustomerID
group by c.location, s.customerid) as t 
where Top_customer < 6
order by Location asc;

------------------------------------ Revenue breakdown by Location → Gender → Grand Total ------------------------------------------------
select case
          when Location = '' then 'Not Available' else Location end as Location,
          Gender, Total_Customers, Total_Transaction 
          from 
				(select c.Location as Location, c.Gender as Gender, count(distinct(s.customerid)) as Total_Customers, 
				count(distinct(s.TransactionID)) as Total_Transaction
				from sales_transaction as s join customers as c on c.CustomerID = s.CustomerID
				group by  c.Location, c.Gender) as t
			    order by Location asc;

------------------------------------------- Pct vise contribution in particuler category  ------------------------------------------------
SELECT 
    Category,
    ProductName,
    Price,
    Revenue,
    ROUND((Revenue / SUM(Revenue) OVER ()) * 100, 2) AS Pct_contribution
FROM (
    SELECT 
        p.Category    AS Category,
        p.ProductName AS ProductName,
        s.Price       AS Price,
        SUM(s.Revenue) AS Revenue
    FROM product_inventory  AS p
    JOIN sales_transaction  AS s ON p.ProductID = s.ProductID
    WHERE Category = 'Beauty & Health'
    GROUP BY 
        p.Category,
        p.ProductName,
        s.Price
) t
ORDER BY Pct_contribution DESC;
                 
--------------------------------------------------  RFM MODEL  --------------------------------------------------------------------------                 
WITH Max_date AS (
    SELECT 
        MAX(transactiondate) AS ref_date 
    FROM sales_transaction
),
rfm AS (
    SELECT 
        CustomerID,
        DATEDIFF((SELECT ref_date FROM Max_date), MAX(TransactionDate)) AS Recency,
        COUNT(CustomerID)                                                AS Frequency,
        SUM(Revenue)                                                     AS Monetary
    FROM sales_transaction
    GROUP BY CustomerID
),
rfm_score AS (
    SELECT 
        CustomerID,
        Recency,
        Frequency,
        Monetary,
        NTILE(5) OVER (ORDER BY Recency   DESC) AS R_Score,
        NTILE(5) OVER (ORDER BY Frequency ASC)  AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary  ASC)  AS M_Score
    FROM rfm
),

rfm_segment AS (
    SELECT 
        CustomerID,
        Recency,
        Frequency,
        Monetary,
        R_Score,
        F_Score,
        M_Score,
        CONCAT(R_Score, F_Score, M_Score) AS rfm_combined,
        CASE
            WHEN R_Score = 5  AND F_Score = 5  AND M_Score = 5  THEN 'Good Customer'
            WHEN R_Score >= 4 AND F_Score >= 4                  THEN 'Loyal Customer'
            WHEN R_Score >= 4 AND F_Score <= 2                  THEN 'New Customer'
            WHEN R_Score <= 2 AND F_Score >= 4                  THEN 'At Risk'
            WHEN R_Score <= 3 AND F_Score >= 3 AND M_Score >= 3 THEN 'Potential Loyalist'
            WHEN R_Score <= 2 AND M_Score >= 4                  THEN 'Can Not Lose Them'
            WHEN R_Score <= 2 AND F_Score <= 2 AND M_Score <= 2 THEN 'Lost'
            ELSE 'Needs Attention'
        END AS Segment
    FROM rfm_score
)

SELECT 
    CustomerID,
    Recency,
    Frequency,
    Monetary,
    R_Score,
    F_Score,
    M_Score,
    Segment,
    sum(Monetary) over(partition by Segment) as Total_Revenue
FROM rfm_segment
ORDER BY rfm_combined DESC; 

---------------------------------------- Customer Cohort Retention Analysis --------------------------------------------------------------
WITH cohort AS (
    SELECT
        CustomerID,
        DATE_FORMAT(MIN(TransactionDate), '%Y-%m-01') AS cohort_month
    FROM sales_transaction
    GROUP BY CustomerID
),

active AS (
    SELECT
        c.CustomerID,
        c.cohort_month,
        DATE_FORMAT(s.transactiondate, '%y-%m-01')                AS active_month,
        TIMESTAMPDIFF(
            month,
            c.cohort_month,
            DATE_FORMAT(s.transactiondate, '%y-%m-01')
        )                                                          AS month_number
    FROM cohort AS c
    JOIN sales_transaction AS s 
        ON c.CustomerID = s.CustomerID
),

cohort_2 AS (
    SELECT
        cohort_month,
        month_number,
        COUNT(DISTINCT customerid)                                 AS active_customer
    FROM active
    GROUP BY cohort_month, month_number
),

cohort_size AS (
    SELECT
        cohort_month,
        month_number,
        active_customer,
        FIRST_VALUE(active_customer) OVER (
            PARTITION BY cohort_month
            ORDER BY month_number
        )                                                          AS cohort_size,
        ROUND(
            active_customer / FIRST_VALUE(active_customer) OVER (
                PARTITION BY cohort_month
                ORDER BY month_number
            ) * 100, 2
        )                                                          AS retention_pct
    FROM cohort_2
)

SELECT * 
FROM cohort_size
ORDER BY cohort_month, month_number;

------------------------------------------- Final Executive Dashboard -------------------------------------------------------------------------
with total_customer as (
    select count(distinct(customerid)) as total_customer 
    from sales_transaction),

total_revenue as (
    select round(sum(revenue), 2) as Total_sales 
    from sales_transaction),

top_category as (
    select p.Category as Category  
    from product_inventory as p 
    join sales_transaction as s on p.ProductID = s.ProductID 
    group by p.Category 
    order by sum(revenue) desc limit 1),

top_category_revenue as (
    select sum(revenue) as Top_Category_Revenue 
    from product_inventory as p 
    join sales_transaction as s on p.ProductID = s.ProductID 
    group by p.Category 
    order by sum(revenue) desc limit 1),

top_location as (
    select c.location as Location 
    from customers as c 
    join sales_transaction as s on c.customerid = s.CustomerID 
    group by c.location 
    order by sum(s.revenue) desc limit 1),

best_selling_product as (
    select p.ProductName as Best_Selling_Product 
    from product_inventory as p 
    join sales_transaction as s on p.productid = s.productid 
    group by p.ProductName 
    order by sum(quantitypurchased) desc limit 1),

repeat_customers AS (
    SELECT COUNT(DISTINCT CASE
                WHEN txn_count > 1
                THEN CustomerID END) AS repeat_customer_count, 
           COUNT(DISTINCT CustomerID) AS buying_customers,
           ROUND(
                COUNT(DISTINCT CASE
                    WHEN txn_count > 1
                    THEN CustomerID END) * 100.0
                / COUNT(DISTINCT CustomerID)
            , 2) AS repeat_customer_pct
    FROM (SELECT CustomerID,
                 COUNT(TransactionID) AS txn_count
          FROM sales_transaction
          GROUP BY CustomerID) customer_txns)

select tc.Total_Customer, tr.Total_sales, c.Category, cr.Top_Category_Revenue, 
       tl.Location, bp.Best_Selling_Product, rc.Repeat_Customer_Count, 
       rc.Buying_Customers, rc.Repeat_Customer_Pct 
from total_customer tc
join total_revenue tr on 1=1
join top_category c on 1=1
join top_category_revenue cr on 1=1 
join top_location tl on 1=1
join best_selling_product bp on 1=1
join repeat_customers rc on 1=1;           



         







 













			   



