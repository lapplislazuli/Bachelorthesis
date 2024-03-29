--=============================================
-- Mein NN Ger�st f�r Taschengeld
--==============================================
USE Taxi2Bachelor;
GO

-- =============================================
-- Create Procedure to Create and Train NN
-- Takes Trainingsize as Parameter
-- Safes a model with timestamp in ModelTable
-- =============================================

DROP PROCEDURE IF EXISTS [dbo].[TrainTipBigNN];
GO
CREATE PROCEDURE [dbo].[TrainTipBigNN] 
@TrainingSize BigInt	
AS
BEGIN
	declare @inputCmd nvarchar(max)
	set @inputCmd = CONCAT( N'Select Top(',@TrainingSize,N') 
		tip_amount,total_amount,RatecodeID,trip_distance, 
		DATEDIFF(MINUTE,pickup_datetime,dropoff_datetime) as duration_in_minutes,
		WetBulbTemp,DryBulbTemp,RelativeHumidity,passenger_count,Windspeed,extra,
		mta_tax,PULocationID,DOLocationID,fare_amount 
		from [dbo].[yellowSample];')
	SET NOCOUNT ON;
	-- Construct the RML script.
	declare @cmd nvarchar(max)
	set @cmd = N'
		library(MicrosoftML)
		library(dplyr)

		netDefinition <- ("
			input Data auto;
			hidden Mystery [100] sigmoid from Data all;
			hidden Magic [100] sigmoid from Mystery all;
			output Result [1] linear from Magic all;
		")
		
		dat_all <- InputData;
		
		LocationLevels <- as.factor(c(1:255));	
		dat_all$PULocationID <- factor(dat_all$PULocationID, levels=LocationLevels);
		dat_all$DOLocationID <- factor(dat_all$DOLocationID, levels=LocationLevels);
		
		dat_all$RatecodeID <- factor(dat_all$RatecodeID, levels=(as.factor(c(1:5))));
		

		sizeAll <- length(InputData$total_amount);

		sample_train <- base::sample(nrow(dat_all), 
									 size = (sizeAll*0.9))

		sample_test  <- base::sample((1:nrow(dat_all))[-sample_train], 
									 size = (sizeAll*0.1))

		dat_train <- dat_all %>% 
		  slice(sample_train) 

		dat_test <- dat_all %>% 
		  slice(sample_test)
		form <- tip_amount ~+total_amount+RatecodeID+trip_distance+duration_in_minutes+WetBulbTemp+DryBulbTemp+RelativeHumidity+passenger_count+Windspeed+extra+mta_tax+PULocationID+DOLocationID+fare_amount;

		model <- rxNeuralNet(formula=form, data = dat_train,              
						   type            = "regression",
						   netDefinition   = netDefinition,
						   numIterations = 100,
						   normalize       = "yes",
						   verbose         = 0,
						   postTransformCache = "Disk");
		trained_model <- data.frame(payload = as.raw(serialize(model, connection=NULL)));
	'

	create table #m (model varbinary(max));
	insert into #m
	execute sp_execute_external_script
	  @language = N'R'
	, @script = @cmd
	, @input_data_1 = @inputcmd 
    , @input_data_1_name=N'InputData'
	, @output_data_1_name = N'trained_model ';
	 
	insert into Models (timest,model,model_name)
	select CURRENT_TIMESTAMP as timest, model, 'NNtipModelBig' as name from #m;  
	drop table #m
END

GO
EXEC TrainTipBigNN @TrainingSize=1000000;
GO

-- =============================================
-- Procedure to use the NN
-- =============================================
DROP PROCEDURE IF EXISTS [dbo].[PredictTipAmountNN]
GO
CREATE PROCEDURE [dbo].[PredictTipAmountNN]
@ModelName nvarchar(50)
AS
BEGIN	
	SET NOCOUNT ON;
	DECLARE @dbModel varbinary(max) = (SELECT TOP (1) Model FROM Models WHERE [model_name] = @ModelName ORDER BY timest DESC);
	declare @inputCmd nvarchar(max)
	set @inputCmd = N'Select TOP (10000) NEWID() as id,tip_amount,total_amount,RatecodeID,trip_distance,DATEDIFF(MINUTE,pickup_datetime,dropoff_datetime) as duration_in_minutes,WetBulbTemp,DryBulbTemp,RelativeHumidity,passenger_count,Windspeed,extra,mta_tax,PULocationID,DOLocationID,fare_amount from yellowTest;';
	DECLARE @predictScript nvarchar(max);
	set @predictScript = N'
	   library("MicrosoftML")
	   print(summary(TestData));
       model_un <- unserialize(as.raw(nb_model));

	   dat_all <- data.frame(TestData);
	   LocationLevels <- as.factor(c(1:255));	
		dat_all$PULocationID <- factor(dat_all$PULocationID, levels=LocationLevels);
		dat_all$DOLocationID <- factor(dat_all$DOLocationID, levels=LocationLevels);
		
		dat_all$RatecodeID <- factor(dat_all$RatecodeID, levels=(as.factor(c(1:5))));
		

	   #score the model
	   prediction <- rxPredict(model= model_un, data = dat_all, verbose = 1);
	   prediction <- round(prediction,2);
	   sum <- cbind(dat_all, prediction);
	   OutputDataSet <- data.frame(sum)
	   '
	  -- Execute the RML script (train & score).
	execute sp_execute_external_script
	  @language = N'R'
	, @script = @predictScript
	, @input_data_1 = @inputCmd
	, @input_data_1_name = N'TestData'
	, @params = N'@nb_model varbinary(max)'
	, @nb_model = @dbModel
	WITH RESULT SETS ((
	[ID] uniqueidentifier, 
	[real_tip_amount] float,
	[total_amount] float, 
	[RatecodeID] smallint,
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
	[predicted_tip_amount] float)) 
END
GO


-- =============================================
-- Predict NN and Store Data in temporary Result-table
-- =============================================

DROP TABLE IF EXISTS #Results;
GO
Create Table #Results (
[ID] uniqueidentifier PRIMARY KEY NOT NULL, 
	[real_tip_amount] float,
	[total_amount] float, 
	[RatecodeID] smallint,
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
	[predicted_tip_amount] float
);
GO
Insert into #Results 
Exec [PredictTipAmountNN] @Modelname = "NNTipModelBig";

---------------------------
-- Show me the Test Results
---------------------------
GO
DECLARE @realMean float;
SET @realMean = (SELECT AVG(real_tip_amount) FROM #Results);

SELECT
	(SUM(POWER(real_tip_amount - @realMean,2))) AS RSS,
	(SUM(POWER((real_tip_amount - predicted_tip_amount),2))) AS TSS,
	1- ((SUM(POWER((real_tip_amount - predicted_tip_amount),2)))/(SUM(POWER(real_tip_amount - @realMean,2)))) as RQuadrat,
	sum(abs(real_tip_amount-predicted_tip_amount)) as miss_in_Dollar,
	sum(predicted_tip_amount) as predicted_total_tip, 
	sum(real_tip_amount) as real_tip
FROM #Results;

SELECT Top (100) abs(real_tip_amount-predicted_tip_amount) as miss_in_Dollar, predicted_tip_amount as estTip, real_tip_amount as realTip from #Results;
GO
DROP TABLE IF EXISTS #Results;
GO