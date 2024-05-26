#!zsh -xe


REGION="us-east-1"
TIMESTAMP=`date +%s`
VEHICLE_NAME="v_tesla3"
DECODER_NAME="dec_vcan0_tesla3"
MODEL_MANIFEST_NAME="vm_tesla3" # Vehicle model name
SIGNAL_CATALOG_NAME="sigs_tesla3" 

export AWS_PAGER="" 

echo "Vehicle name: ${VEHICLE_NAME}"

echo "Getting AWS account ID..."
ACCOUNT_ID=`aws sts get-caller-identity | jq -r .Account`
echo ${ACCOUNT_ID}

# Cleanup
aws iotfleetwise delete-vehicle --vehicle-name $VEHICLE_NAME
aws iotfleetwise delete-decoder-manifest --name $DECODER_NAME
aws iotfleetwise delete-model-manifest --name $MODEL_MANIFEST_NAME
aws iotfleetwise delete-signal-catalog --name $SIGNAL_CATALOG_NAME --region $REGION

# Create signal catalog
SIGNAL_CATALOG_ARN=`aws iotfleetwise create-signal-catalog --name $SIGNAL_CATALOG_NAME --region $REGION | jq -r .arn`
aws iotfleetwise update-signal-catalog --name $SIGNAL_CATALOG_NAME  --cli-input-json file://signal_catalog.json --region $REGION

# Create vehicle model
MODEL_MANIFEST_ARN=`aws iotfleetwise create-model-manifest  --name $MODEL_MANIFEST_NAME \
    --signal-catalog-arn $SIGNAL_CATALOG_ARN \
    --status ACTIVE \
    --nodes '["Vehicle"]' | jq -r .arn` # include all VSS signals

# Create decoder
aws iotfleetwise create-decoder-manifest --name $DECODER_NAME \
    --status ACTIVE \
    --model-manifest-arn $MODEL_MANIFEST_ARN \
    --cli-input-json file://decoder_manifest.json

# activate the model
#aws iotfleetwise update-model-manifest --status ACTIVE --name $MODEL_MANIFEST_NAME --region $REGION
