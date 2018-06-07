-----------------------------------------------------------
-- My First Attempts for R with Taxi Data 
-- Goal: Estimate whether a tip will be given (yes or no, no amount)
-- Does not Include Testing (Different file)
-----------------------------------------------------------

Use Taxi2Bachelor
GO

--------------------------
-- Creating Model (Data needs to be given)
--------------------------

DROP PROCEDURE IF EXISTS generate_Big_logit_model;
GO
CREATE PROCEDURE generate_Big_logit_model
AS
BEGIN
    EXEC sp_execute_external_script
    @language = N'R'
    , @script = N'
		form <- tipped ~ duration_in_minutes+total_amount+RatecodeID+trip_type+trip_distance+WetBulbTemp+DryBulbTemp+RelativeHumidity+passenger_count+Windspeed+extra+mta_tax+PULocationID+DOLocationID+fare_amount;
		logitmodel <- rxLogit(formula = form, data = TaxiData) ; 
        trained_model <- data.frame(payload = as.raw(serialize(logitmodel, connection=NULL)));
		'
    , @input_data_1 = N'Select tipped,duration_in_minutes, total_amount,trip_type,RatecodeID,trip_distance,WetBulbTemp,DryBulbTemp,RelativeHumidity,passenger_count,Windspeed,extra,mta_tax,PULocationID,DOLocationID,fare_amount  from greenBigTipSample;' 
    , @input_data_1_name = N'TaxiData'
    , @output_data_1_name = N'trained_model'
    WITH RESULT SETS ((model varbinary(max)));
END;
GO

-- Run only once because you primary identifier
INSERT INTO tip_models (model)
EXEC generate_Big_logit_model;
GO
UPDATE tip_models
SET model_name = ('rxBigLogit ' + format(getdate(), 'yyyy.MM.HH.mm', 'en-gb'))
WHERE model_name = 'default model';
GO

--------------------------------
-- Use the Model
-- Put the Data in a temporary table
--------------------------------

DROP PROCEDURE IF EXISTS use_my_Big_tip_model
GO
CREATE PROCEDURE use_my_Big_tip_model
AS
BEGIN
	DECLARE @tipmodel varbinary(max) = (SELECT TOP(1) model FROM tip_models WHERE model_name LIKE 'rxBigLogit%' Order by model_name desc);
	EXEC sp_execute_external_script
		@language = N'R'
		, @script = N'
				current_model <- unserialize(as.raw(tipmodel)); #unfolds the model from binary
				new <- data.frame(greenTipTest); # Curls my new Data
				predicted.tip <- rxPredict(current_model, new);
				OutputDataSet <- cbind(new,predicted.tip);
				'
		, @input_data_1 = N' SELECT id,real_tipped,total_amount,duration_in_minutes,trip_type,RatecodeID,trip_distance,WetBulbTemp,DryBulbTemp,RelativeHumidity,passenger_count,Windspeed,extra,mta_tax,PULocationID,DOLocationID,fare_amount FROM greenBigTipTest ' 
		, @input_data_1_name = N'greenTipTest'
		, @params = N'@tipmodel varbinary(max)' 
		, @tipmodel = @tipmodel
	WITH RESULT SETS ((
		[ID] uniqueidentifier,
		[real_tipped] bit, 
		[total_amount] float,
		[duration_in_minutes] int, 
		[trip_type] smallint, 
		[RatecodeID] smallint,
		[trip_distance] float, 
		[WetBulbTemp] real,
		[DryBulbTemp] real,
		[RelativeHumidity] smallint,
		[passenger_count] smallint,
		[Windspeed] smallint,
		[extra] real,
		[mta_tax] real,
		[PULocationID] smallint,
		[DOLocationID] smallint,
		[fare_amount] real, 
		[estimated_tip] float ))
END
GO
EXEC use_my_Big_tip_model;

DROP TABLE IF EXISTS #tmpTipTestData;
CREATE TABLE #tmpTipTestData(
	ID uniqueidentifier not null primary key,
	real_tipped bit,
	total_amount float,
	duration_in_minutes int,
	RatecodeID  smallint,
	trip_type smallint,
	trip_distance float,
	[WetBulbTemp] real,
	[DryBulbTemp] real,
	[RelativeHumidity] smallint,
	[passenger_count] smallint,
	[Windspeed] smallint,
	[extra] real,
	[mta_tax] real,
	[PULocationID] smallint,
	[DOLocationID] smallint,
	[fare_amount] real, 
	estimated_tip  float	
)

INSERT INTO #tmpTipTestData
EXEC use_my_Big_tip_model;
GO

--------------------------
-- Test the Model
--------------------------

SELECT ID, real_tipped, ROUND(estimated_tip,0) as predicted_tip, estimated_tip as estimated_chance FROM #tmpTipTestData;

SELECT sum(abs(real_tipped - ROUND(estimated_tip,0))) as total_misses from #tmpTipTestData;