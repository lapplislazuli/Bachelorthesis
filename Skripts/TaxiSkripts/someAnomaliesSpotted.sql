/****** Skript für SelectTopNRows-Befehl aus SSMS ******/
USE Taxi2Bachelor
GO

SELECT TOP (1000) Vendor, passenger_count, count(*) as trips
  FROM [Taxi2Bachelor].[dbo].[richYellowData]
  Group by Vendor, passenger_count
  Order by passenger_count desc

  SELECT TOP (20) *
  FROM [Taxi2Bachelor].[dbo].[richYellowData]
  Where passenger_count=0

  SELECT Top(20) * from richYellowData
  -- split by date and location
  Select count(*) as irrfahrten, pickup_zone, Convert(DATE,pickup_datetime) as date_,  sum(total_amount) as irrgeld
  From richYellowData
  Where pickup_zone = dropoff_zone
  Group by Convert(DATE,pickup_datetime),pickup_zone;

  -- Group only by date
   Select Convert(DATE,pickup_datetime) as date_,count(*) as irrfahrten,  sum(total_amount) as irrgeld, avg(total_amount) as avg_irrgeld, avg(Datediff(Minute,pickup_datetime,dropoff_datetime)) as avg_timeBetween
  From richYellowData
  Where pickup_zone = dropoff_zone
  Group by Convert(DATE,pickup_datetime);

  GO

  DATEDIFF(MINUTE,pickup_datetime,dropoff_datetime)
  -- show me some
  SELECT TOP (20) DATEDIFF(MINUTE,pickup_datetime,dropoff_datetime) as wartezeit, pickup_zone, total_amount, tip_amount
  From richYellowData
  Where pickup_zone = dropoff_zone