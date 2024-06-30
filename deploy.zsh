#!zsh -xe


REGION="us-east-1"
TIMESTAMP=`date +%s`
BUCKET_NAME="iot-fleetwise-demo-emylvsv5"

# set up base name, like make of the car
MODEL_NAME="tesla3"

# set up names for the resources
VEHICLE_NAME="vhcl-${MODEL_NAME}"
DECODER_NAME="dcdr-vcan0-${MODEL_NAME}"
MODEL_MANIFEST_NAME="vm-${MODEL_NAME}"
SIGNAL_CATALOG_NAME="sigs-${MODEL_NAME}"
CAMPAIGN_BASE_NAME="cmpgn-${MODEL_NAME}"
CAMPAIGN_NAMES=(${CAMPAIGN_BASE_NAME}-to-s3 ${CAMPAIGN_BASE_NAME}-to-ts)

export AWS_PAGER="" 

echo "Vehicle name: ${VEHICLE_NAME}"

# Cleanup
for CAMPAIGN_NAME in "${CAMPAIGN_NAMES[@]}"; do
  aws iotfleetwise delete-campaign --name $CAMPAIGN_NAME --region $REGION
done
aws iotfleetwise delete-vehicle --vehicle-name $VEHICLE_NAME --region $REGION
aws iotfleetwise delete-decoder-manifest --name $DECODER_NAME --region $REGION
aws iotfleetwise delete-model-manifest --name $MODEL_MANIFEST_NAME --region $REGION
aws iotfleetwise delete-signal-catalog --name $SIGNAL_CATALOG_NAME --region $REGION

# Create signal catalog
SIGNAL_CATALOG_ARN=`aws iotfleetwise create-signal-catalog --name $SIGNAL_CATALOG_NAME --region $REGION | jq -r .arn`
aws iotfleetwise update-signal-catalog --name $SIGNAL_CATALOG_NAME  --cli-input-json file://signal_catalog.json --region $REGION

# Create vehicle model
MODEL_MANIFEST_ARN=`aws iotfleetwise create-model-manifest  --name $MODEL_MANIFEST_NAME \
    --signal-catalog-arn $SIGNAL_CATALOG_ARN \
    --nodes '["Vehicle"]' | jq -r .arn` # include all VSS signals

# Create decoder
DECODER_MANIFEST_ARN=`aws iotfleetwise create-decoder-manifest --name $DECODER_NAME \
    --model-manifest-arn $MODEL_MANIFEST_ARN \
    --cli-input-json file://decoder_manifest.json | jq -r .arn`

# activate the model
aws iotfleetwise update-model-manifest --status ACTIVE --name $MODEL_MANIFEST_NAME --region $REGION
aws iotfleetwise update-decoder-manifest --status ACTIVE --name $DECODER_NAME --region $REGION

# Create vehicle
VEHICLE_ARN=`aws iotfleetwise create-vehicle --decoder-manifest-arn $DECODER_MANIFEST_ARN \
    --association-behavior ValidateIotThingExists --model-manifest-arn $MODEL_MANIFEST_ARN \
    --vehicle-name $VEHICLE_NAME --region $REGION | jq -r .arn`

# Set up a campaign 
# TODO: Update the campaign.json file with the correct signal names and make the S3 bucket configurable

for CAMPAIGN_NAME in "${CAMPAIGN_NAMES[@]}"; do
  sed -i.bak "/\"bucketArn\"/c\\
    \"bucketArn\": \"arn:aws:s3:::$BUCKET_NAME\",
    " ${CAMPAIGN_NAME}.json
  aws iotfleetwise create-campaign --name $CAMPAIGN_NAME --cli-input-json file://${CAMPAIGN_NAME}.json \
      --signal-catalog-arn $SIGNAL_CATALOG_ARN --target-arn $VEHICLE_ARN --region $REGION

  echo "Waiting for campaign to become ready for approval..."
  while true; do
      sleep 5
      CAMPAIGN_STATUS=`aws iotfleetwise get-campaign \
          --region ${REGION} \
          --name ${CAMPAIGN_NAME}`
      if [[ $(echo "${CAMPAIGN_STATUS}" | jq -r '.status') == "WAITING_FOR_APPROVAL" ]]; then
          break
      fi
  done
  aws iotfleetwise update-campaign --action APPROVE --region $REGION --name $CAMPAIGN_NAME
done
