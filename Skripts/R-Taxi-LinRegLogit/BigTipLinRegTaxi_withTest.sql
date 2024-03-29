-----------------------------------------------------------
-- Goal: Simple Linear Regression for tip
-- Does include test and summary
-----------------------------------------------------------
USE Taxi2Bachelor
GO

--------------------------------
-- Creating Model (Data needs to be given)
--------------------------------

DROP PROCEDURE IF EXISTS generate_linear_tipModel;
GO
CREATE PROCEDURE generate_linear_tipModel
AS
BEGIN
	CREATE TABLE #m (model varbinary(max));
	INSERT INTO #m
    EXEC sp_execute_external_script
    @language = N'R'
    , @script = N'
		form <- tip_amount ~ total_amount+RatecodeID+trip_type+trip_distance+duration_in_minutes+WetBulbTemp+DryBulbTemp+RelativeHumidity+passenger_count+Windspeed+extra+mta_tax+PULocationID+DOLocationID+fare_amount;
		lrModel <- rxLinMod(formula = form, data = TaxiData);
        trained_model <- data.frame(payload = as.raw(serialize(lrModel, connection=NULL)));'
    , @input_data_1 = N'Select tip_amount,total_amount,RatecodeID,trip_type,trip_distance,duration_in_minutes,WetBulbTemp,DryBulbTemp,RelativeHumidity,passenger_count,Windspeed,extra,mta_tax,PULocationID,DOLocationID,fare_amount from greenBigTipAmountSample;' 
    , @input_data_1_name = N'TaxiData' 
    , @output_data_1_name = N'trained_model';

	INSERT INTO Models (timest,model,model_name)
	SELECT CURRENT_TIMESTAMP AS timest, model, 'LinRegTip' AS name FROM #m;  
	DROP TABLE #m
END;
GO

EXEC generate_linear_tipModel;
GO
--------------------------------
-- Use Model
--------------------------------

DROP PROCEDURE IF EXISTS use_my_tipAmount_model;
GO
CREATE PROCEDURE use_my_tipAmount_model
AS
BEGIN
	DECLARE @tipmodel varbinary(max) = (SELECT Top(1) model FROM Models WHERE model_name='LinRegTip' ORDER BY timest desc);
	EXEC sp_execute_external_script
		@language = N'R'
		, @script = N'
				current_model <- unserialize(as.raw(tipmodel)); #unfolds the model from binary
				new <- data.frame(greenBigTipAmountTest); # Curls my new Data
				predicted.amount <- round(rxPredict(current_model, new),2);
				OutputDataSet <- cbind(new, predicted.amount); #Combine resources and amount for smarter output
				'
		, @input_data_1 = N'Select id,real_tip_amount,total_amount,RatecodeID,trip_type,trip_distance,duration_in_minutes,WetBulbTemp,DryBulbTemp,RelativeHumidity,passenger_count,Windspeed,extra,mta_tax,PULocationID,DOLocationID,fare_amount from greenBigTipAmountTest;'
		, @input_data_1_name = N'greenBigTipAmountTest'
		, @params = N'@tipmodel varbinary(max)'
		, @tipmodel = @tipmodel 
	WITH RESULT SETS ((
	[ID] uniqueidentifier, 
	[real_tip_amount] float,
	[real_amount] float, 
	[RatecodeID] smallint,
	[trip_type] smallint,
	[trip_distance] float,
	[duration_in_minutes] float,
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
	[predicted_amount] float)) 
END;
GO

DROP TABLE IF EXISTS #Results
CREATE TABLE #Results(
	ID uniqueidentifier not null primary key,
	[real_tip_amount] float,
	[real_amount] float,
	RatecodeID  smallint,
	trip_type smallint,
	trip_distance float,
	[duration_in_minutes] float,
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
	predicted_amount  float	
)

INSERT INTO #Results
EXEC use_my_tipAmount_model;
GO

---------------------------
-- Show me the Test Results
---------------------------

SELECT TOP(50) ID,(real_tip_amount-predicted_amount) as miss_in_Dollar, (1-(real_tip_amount/predicted_amount)) as accuracy, real_tip_amount, predicted_amount FROM #Results;
SELECT avg(abs((1-(real_amount/predicted_amount)))) as avg_accuracy From #Results;
SELECT sum(abs(real_tip_amount-predicted_amount)) as total_miss_in_Dollar, sum(real_tip_amount) as total_real_tip_amount, sum(predicted_amount) as total_predicted_tip_amount FROM #Results;
