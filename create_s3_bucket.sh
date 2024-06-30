#!env bash

BUCKET_NAME=iot-fleetwise-demo-$( cat /dev/urandom | env LC_ALL=C tr -dc 'a-z0-9' | fold -w 8 | head -n 1 )
SERVICE_PRINCIPAL="iotfleetwise.amazonaws.com"
REGION=us-east-1
BUCKET_REGION=$REGION
SKIP_S3_POLICY=false

echo "Checking if S3 bucket exists..."

    BUCKET_LIST=$( aws s3 ls )
    if grep -q "$BUCKET_NAME" <<< "$BUCKET_LIST"; then
        echo "S3 bucket already exists"
    else
        echo "Creating S3 bucket..."
        aws s3 mb s3://$BUCKET_NAME --region $REGION
    fi
    if [ ${SKIP_S3_POLICY} == false ]; then
        echo "Adding S3 bucket policy..."
        cat << EOF > s3-bucket-policy.json
{
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "${SERVICE_PRINCIPAL}"
            },
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "${SERVICE_PRINCIPAL}"
            },
            "Action": ["s3:GetObject", "s3:PutObject"],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        }
    ]
}
EOF
        aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://s3-bucket-policy.json
    else
        echo "Skipping S3 bucket policy. Since bucket already existed it needs to be manually configured."
    fi
    echo "Getting S3 bucket region..."
    BUCKET_REGION=`aws s3api get-bucket-location --bucket ${BUCKET_NAME} | jq -r .LocationConstraint`
    if [ -z "${BUCKET_REGION}" ] || [ "${BUCKET_REGION}" == "null" ]; then
        BUCKET_REGION="us-east-1"
    fi
    echo ${BUCKET_REGION}
    if [ "${BUCKET_REGION}" != "${REGION}" ]; then
        echo "Error: S3 bucket ${BUCKET_NAME} is not in region ${REGION}. Cross-region not yet supported."
        exit -1
    fi
    echo "Checking bucket ACLs are disabled..."
    if ! OWNERSHIP_CONTROLS=`aws s3api get-bucket-ownership-controls --bucket ${BUCKET_NAME} 2> /dev/null` \
        || [ "`echo ${OWNERSHIP_CONTROLS} | jq -r '.OwnershipControls.Rules[0].ObjectOwnership'`" != "BucketOwnerEnforced" ]; then
        echo "Error: ACLs are enabled for bucket ${BUCKET_NAME}. Disable them at https://s3.console.aws.amazon.com/s3/bucket/${BUCKET_NAME}/property/oo/edit"
        exit -1
    fi

