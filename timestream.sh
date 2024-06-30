#!env bash

VEHICLE_NAME=""
TIMESTREAM_DB_NAME="IoTFleetWiseDB"
TIMESTREAM_TABLE_NAME="VehicleDataTable"
SERVICE_ROLE="IoTFleetWiseServiceRole"
SERVICE_ROLE_POLICY_ARN=""
SERVICE_PRINCIPAL="iotfleetwise.amazonaws.com"
REGION=us-east-1
ACCOUNT_ID=`aws sts get-caller-identity --query "Account" --output text`


echo "Creating Timestream database..."
aws timestream-write create-database \
    --region ${REGION} \
    --database-name ${TIMESTREAM_DB_NAME} | jq -r .Database.Arn

echo "Creating Timestream table..."
TIMESTREAM_TABLE_ARN=$( aws timestream-write create-table \
    --region ${REGION} \
    --database-name ${TIMESTREAM_DB_NAME} \
    --table-name ${TIMESTREAM_TABLE_NAME} \
    --retention-properties "{\"MemoryStoreRetentionPeriodInHours\":2, \
        \"MagneticStoreRetentionPeriodInDays\":2}" | jq -r .Table.Arn )

echo "Creating service role..."
SERVICE_ROLE_TRUST_POLICY=$(cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
            "$SERVICE_PRINCIPAL"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
SERVICE_ROLE_ARN=`aws iam create-role \
    --role-name "${SERVICE_ROLE}" \
    --assume-role-policy-document "${SERVICE_ROLE_TRUST_POLICY}" | jq -r .Role.Arn`
echo ${SERVICE_ROLE_ARN}

echo "Waiting for role to be created..."
aws iam wait role-exists \
    --role-name "${SERVICE_ROLE}"

echo "Creating service role policy..."
SERVICE_ROLE_POLICY=$(cat <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "timestreamIngestion",
            "Effect": "Allow",
            "Action": [
                "timestream:WriteRecords",
                "timestream:Select",
                "timestream:DescribeTable"
            ]
        },
        {
            "Sid": "timestreamDescribeEndpoint",
            "Effect": "Allow",
            "Action": [
                "timestream:DescribeEndpoints"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
SERVICE_ROLE_POLICY=`echo "${SERVICE_ROLE_POLICY}" \
    | jq ".Statement[0].Resource=\"arn:aws:timestream:${REGION}:${ACCOUNT_ID}:database/${TIMESTREAM_DB_NAME}/*\""`
SERVICE_ROLE_POLICY_ARN=`aws iam create-policy \
    --policy-name ${SERVICE_ROLE}-policy \
    --policy-document "${SERVICE_ROLE_POLICY}" | jq -r .Policy.Arn`
echo ${SERVICE_ROLE_POLICY_ARN}

echo "Waiting for policy to be created..."
aws iam wait policy-exists \
    --policy-arn "${SERVICE_ROLE_POLICY_ARN}"

echo "Attaching policy to service role..."
aws iam attach-role-policy \
    --policy-arn ${SERVICE_ROLE_POLICY_ARN} \
    --role-name "${SERVICE_ROLE}"


