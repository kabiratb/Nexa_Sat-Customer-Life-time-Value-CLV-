-- Create a table in the schema
Create Table "Nexa_Sat".nexa_sat(
		Customer_id VARCHAR(50),
		gender      VARCHAR(10),
		Partner     VARCHAR(5),
		Dependents	VARCHAR(5),
		Senior_Citizen 	INT,
		Call_Duration FLOAT,
		Data_Usage	  FLOAT,
		Plan_Type	VARCHAR(20),
		Plan_Level  VARCHAR(20),
		Monthly_Bill_Amount FLOAT,
		Tenure_Months    INT,
		Multiple_Lines	VARCHAR(5),
		Tech_Support    VARCHAR(5),
		Churn 	INT);

--I have to set the path for queries
Set search_path To "Nexa_Sat";

--confirm current schema
Select current_schema();

-- View My Data table
Select *
From nexa_sat;

--Data Cleaning, Check For Duplicates
Select customer_id, gender, partner, dependents, 
       senior_citizen, call_duration, data_usage, plan_type, 
       plan_level, monthly_bill_amount, tenure_months, 
       multiple_lines, tech_support, churn
From nexa_sat
Group by customer_id, gender, partner, dependents, 
         senior_citizen, call_duration, data_usage, plan_type, 
         plan_level, monthly_bill_amount, tenure_months, 
         multiple_lines, tech_support, churn

Having Count(*) > 1; to filter out rows that are duplicates

--Check for null values
Select *
From nexa_sat
Where customer_id IS Null
OR gender IS Null
OR partner IS Null
OR dependents IS Null
OR senior_citizen IS Null
OR call_duration IS Null
OR data_usage IS Null
OR plan_type IS Null
OR plan_level IS Null
OR monthly_bill_amount IS null
OR tenure_months IS Null
OR multiple_lines IS Null
OR tech_support IS Null
OR churn IS Null;

--EDA
--Number of Users
SELECT count(customer_id) AS current_users
FROM nexa_sat
WHERE churn = 0;

--total users by level
Select plan_level, COUNT(customer_id) as Total_users
From nexa_sat
Group By 1; --1 is the first selected column plan_level

--Total Revenue
Select ROUND(Sum(monthly_bill_amount::numeric),2) AS "Total Revenue"
From nexa_sat;


--Revenue By Each Plan level
Select plan_level, ROUND(Sum(monthly_bill_amount::numeric),2) AS "Revenue_By_Level"
From nexa_sat
Group By 1
Order By 2 desc; -- 2 as the second called column

--Gender base contribution
Select gender, plan_level, ROUND(SUM(monthly_bill_amount::INT),2) AS "Revenure Cont"
FROM nexa_sat
GROUP BY 1, 2
ORDER BY 1 desc;

--churn count by plan type and plan level
Select plan_level,
       plan_type,
	   COUNT(*) AS "Total Customers",
	   SUM(churn) AS "Churn_Count"
From nexa_sat
Group BY 1, 2   --- plan_level, plan_type
Order BY 1;

--Avg tenure by plan level
SELECT plan_level, ROUND(AVG(tenure_months),2) AS avg_tenure
FROM nexa_sat
GROUP By 1;




--MARketing Segments
--Create table of existing users only
CREATE TABLE existing_users AS 
Select *
From nexa_sat
Where churn = 0;

--View New Table
Select *
From existing_users;

--Calculate ARPU for existing users
SELECT ROUND(AVG(monthly_bill_amount::INT),2) as "ARPU"
FROM existing_users;

--Calculate CLV and add column 
ALTER TABLE existing_users
ADD COLUMN clv FLOAT;

UPDATE existing_users
SET clv = monthly_bill_amount * tenure_months;

--View NEW CLV column
SELECT customer_id, clv
FROM existing_users;

--CLV Score
--monthly_bill = 40%, tenure = 30%, call_duration = 10%, data_usage = 10%, Premium = 10%
ALTER TABLE existing_users
ADD COLUMN clv_score numeric(10,2);

UPDATE existing_users
SET clv_score = 
			(0.4 * monthly_bill_amount) +
			(0.3 * tenure_months) +
			(0.1 * call_duration) +
			(0.1 * data_usage) +
			(0.1 * CASE When plan_level = 'premium'
			            Then 1 Else 0
						END);
						
--View new CLv Score Column
SELECT customer_id, clv_score
FROM existing_users
ORDER BY 2 desc;

--Group users into egment based  on clv_scores
ALTER TABLE existing_users
ADD COLUMN clv_segments varchar;

UPDATE existing_users
SET clv_segments = 
		   CASE WHEN clv_score > (SELECT percentile_cont(0.85)
								 Within Group (Order By clv_score)
								 From existing_users) Then 'High Value'
				WHEN clv_score >(SELECT percentile_cont(0.50)
								 WITHIN Group (ORDER BY clv_score)
								 FROM existing_users) THEN 'Moderate Value'
				WHEN clv_score >=(SELECT percentile_cont(0.25)
								 WITHIN GROUP (ORDER BY clv_score)
								 FROM existing_users) THEN 'Low Value'
				ELSE 'Churn RIsk'
				END;
--View Segment
SELECT customer_id, clv, clv_score, clv_segments
FROM existing_users

--ANALYZING THE SEGMENTS
--Avg Bill And tenure per segment
Select clv_segments,
		ROUND(AVG(monthly_bill_amount::INT),2) AS avg_monthly_charges,
		ROUND(AVG(tenure_months::INT),2) AS avg_tenure
FROM existing_users
GROUP BY 1;


--tech support and multiple lines count
SELECT clv_segments,
		ROUND(AVG(CASE WHEN tech_support = 'Yes' 
		               THEN 1 ELSE 0 
		          END),2) AS tech_support_pct, --percentage
		ROUND(AVG(CASE WHEN multiple_lines = 'Yes' 
				       THEN 1 ELSE 0 
				  END),2) AS multiple_line_pct
FROM existing_users
GROUP BY 1;


SELECT clv_segments, count(tech_support), count(multiple_lines)
FROM existing_users
GROUP BY 1

--revenue per segment
SELECT clv_segments, COUNT(customer_id) AS "No Of Customer",
		CAST(SUM(monthly_bill_amount * tenure_months) AS NUMERIC(10,2)) AS "Total Revenue"
FROM existing_users
GROUP BY 1;

--CRoss Selling AND UP Selling
--cross selling tech support to our citizen
SELECT customer_id
FROM existing_users
WHERE senior_citizen = 1 --senior citizens
AND dependents = 'No' --no children or tech savy helpers
AND tech_support = 'No' --does that don't have this service
AND (clv_segments = 'Churn Risk' OR clv_segments = 'Low Value');
								 
Select customer_id, clv_segments, tech_support, dependents
FROM existing_users;

--Cross selling of multiple lines for partners and dependents
SELECT customer_id
FROM existing_users
WHERE multiple_lines = 'No'
AND (dependents = 'Yes' OR partner = 'Yes')
AND plan_level = 'Basic';


--Up selling: premium discount for basic user with churn risk
SELECT customer_id
FROM existing_users
WHERE clv_segments = 'Churn RIsk'
AND plan_level = 'Basic';

--up Selling: Basic to Premium for longer lock in period and high ARPU
SELECT plan_level, ROUND(AVG(monthly_bill_amount::INT),2) AS AVG_Bill, ROUND(AVG(tenure_months),2) AS AVG_tenure
FROM existing_users
WHERE clv_segments = 'High Value'
OR clv_segments = 'Moderate Value'
Group By 1;


--Select customers
SELECT customer_id, monthly_bill_amount
FROM existing_users
WHERE plan_level = 'Basic'
AND (clv_segments = 'High Value' OR clv_segments = 'Moderate Value')
AND monthly_bill_amount >150
ORDER By 2 desc;


--Create Stored PROCEDURES
--Senior citizen who will be offered tech support
Drop Function tech_support_snr_citizens()  --TO DROP The function as and recreate as it run error when i try to view

CREATE FUNCTION tech_support_snr_citizens()
RETURNS TABLE (customer_id varchar(50))
AS $$
BEGIN 
	RETURN QUERY
	SELECT eu.customer_id
	FROM existing_users eu
	WHERE eu.senior_citizen = 1 --senior citizens
	AND eu.dependents = 'No' -- no children or tech savy helpers
	AND eu.tech_support = 'No' --do not already have this service
	AND (eu.clv_segments = 'Churn Risk' OR eu.clv_segments = 'Low Value');
END;
$$ LANGUAGE plpgsql;


--AT RISK CUSTOMER TO BE OFFERED PREMIUM DISCOUNT
CREATE FUNCTION churn_risk_discount()
RETURNS TABLE (customer_id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id
    FROM existing_users eu
    WHERE eu.clv_segments = 'Churn RIsk'
    AND eu.plan_level = 'Basic';
END;
$$ LANGUAGE plpgsql;


--High Usage customer who will Should be offered premium upgrade

CREATE FUNCTION high_usage_basic()
RETURNS TABLE (customer_id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id
	FROM existing_users eu
	WHERE eu.plan_level = 'Basic'
	AND (eu.clv_segments = 'High Value' OR eu.clv_segments = 'Moderate Value')
	AND eu.monthly_bill_amount > 150;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION high_usage_basic(); -- there was an error with the column nt match so i drop the function remove monthly bill and recreate

--VIEW PROCEDURE
--Churn risk discount
SELECT *
FROM churn_risk_discount();

--High Usage Back
SELECT *
FROM high_usage_basic();

--Tech Support Snr Citizen
SELECT *
FROM tech_support_snr_citizens();

								 


						



