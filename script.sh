#!/bin/bash
AWS_BUCKET="$(printenv AWS_BUCKET)"
AWS_REGION="$(printenv AWS_REGION)"
CF_DOMAIN="$(printenv CF_DOMAIN)"
ACM_CERTIFICATE_ARN="$(printenv ACM_CERTIFICATE_ARN)"
SIGNER_KEY_PATH="$(printenv SIGNER_KEY_PATH)"

echo "Setting a new S3 storage for file uploads with Cloudfront for your web application..."
# User input if variables are empty
if [ "$AWS_BUCKET" = "" ]; then read -p 'Enter S3 bucket name: ' AWS_BUCKET; else echo "S3 bucket \"${AWS_BUCKET}\""; fi
if [ "$AWS_BUCKET" = "" ]; then echo "No bucket provided. Exiting"; fi

if [ "$AWS_REGION" = "" ]; then read -p 'Enter AWS region (leave blank for "us-east-1"): ' AWS_REGION; else echo "AWS region \"${AWS_BUCKET}\""; fi
if [ "$AWS_REGION" = "" ]; then echo "AWS region \"us-east-1\""; AWS_REGION="us-east-1"; fi

if [ "$CF_DOMAIN" != "null" ]; then
    if [ "$CF_DOMAIN" = "" ]; then
        read -p 'Enter your domain for serving files (leave blank for no domain): ' CF_DOMAIN
    else
        echo "Domain \"${AWS_BUCKET}\""
    fi
else 
    CF_DOMAIN=""
fi
if [ "$CF_DOMAIN" = "" ]; then
    echo "Using only default Cloudfront domain";
else
    if [ "$ACM_CERTIFICATE_ARN" = "" ]; then
        echo "Error: ACM_CERTIFICATE_ARN env variable is empty. Custom domain requires an issued ACM certificate for SSL connection"
        exit 1;
    fi
fi
if [ "$SIGNER_KEY_PATH" = "" ]; then
    read -p 'Enter signer key path (leave blank for no signer): ' SIGNER_KEY_PATH
fi
exit 0;

# Create an S3 bucket where we will store all files uploaded to our web app
aws s3api create-bucket --bucket $AWS_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
echo "Created bucket with name=${AWS_BUCKET} in ${AWS_REGION} region"

# Upload a Cloudfront signer public key
if [ ! -z "$SIGNER_KEY_PATH" ]; then # Read file only if the path is provided
    AWS_CF_SIGNER_PUBLIC_KEY=$(sed 's/$/\\n/' ${SIGNER_KEY_PATH} | tr -d '\n')
fi
echo "Uploading the signer's public key: ${AWS_CF_SIGNER_PUBLIC_KEY}"
AWS_CF_SIGNER_PUBLIC_KEY_CONFIG=$(cat <<EOF
{ "Name": "${AWS_BUCKET}", "EncodedKey": "${AWS_CF_SIGNER_PUBLIC_KEY}", "Comment": "${AWS_BUCKET}", "CallerReference": "${RANDOM}" }
EOF
)
if [ ! -z "$SIGNER_KEY_PATH" ]; then # Create public key only if it exists
    AWS_CF_SIGNER_PUBLIC_KEY_ID=$(aws cloudfront create-public-key --public-key-config "${AWS_CF_SIGNER_PUBLIC_KEY_CONFIG}" | jq -r '.PublicKey.Id')
    if [ "$AWS_CF_SIGNER_PUBLIC_KEY_ID" = "" ]; then
        echo "Error: failed to create a Cloudfront public key"
        exit 1;
    fi
    echo "Created Cloudfront public key with ID=${AWS_CF_SIGNER_PUBLIC_KEY_ID}"
fi

# Create a Cloudfront key group using the provided public key
AWS_CF_SIGNER_KEY_GROUP_CONFIG=$(cat <<EOF
{ "Name": "${AWS_BUCKET}", "Items": ["${AWS_CF_SIGNER_PUBLIC_KEY_ID}"], "Comment": "${AWS_BUCKET}" }
EOF
)
if [ ! -z "$SIGNER_KEY_PATH" ]; then # Create key group only if signer key is provided
    AWS_CF_SIGNER_KEY_GROUP_ID=$(aws cloudfront create-key-group --key-group-config "${AWS_CF_SIGNER_KEY_GROUP_CONFIG}" | jq -r '.KeyGroup.Id')
    if [ "$AWS_CF_SIGNER_KEY_GROUP_ID" = "" ]; then
        echo "Error: failed to create a Cloudfront key group"
        exit 1;
    fi
    echo "Created Cloudfront key group with ID=${AWS_CF_SIGNER_KEY_GROUP_ID}"
fi

# Create an Origin Access Control for the Cloudfront distribution
AWS_CF_OAC_CONFIG=$(cat <<EOF
{
    "Name": "${AWS_BUCKET}",
    "Description": "${AWS_BUCKET}",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
}
EOF
)
AWS_CF_OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config "${AWS_CF_OAC_CONFIG}" | jq -r '.OriginAccessControl.Id')
if [ "$AWS_CF_OAC_ID" = "" ]; then
    echo "Error: failed to create an Origin Access Control"
    exit 1;
fi
echo "Created Origin Access Control with ID=${AWS_CF_OAC_ID}"

# Create a Cloudfront distribution for the bucket
AWS_CF_CONFIG_ALIAS_ITEMS=$([ -z "$CF_DOMAIN" ] && echo "{\"Quantity\":0}" || echo "{\"Quantity\":1,\"Items\":[\"${DOMAIN}\"]}")
AWS_CF_CONFIG_CACHE_POLICY_ID="658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed policy "CachingOptimized"
AWS_CF_CONFIG_USES_DEFAULT_CERTIFICATE=$([ -z "$CF_DOMAIN" ] && echo "true" || echo "false,")
AWS_CF_CONFIG_ACM_CERTIFICATE_ARN=$([ -z "$CF_DOMAIN" ] && echo "" || echo "\"ACMCertificateArn\":\"${ACM_CERTIFICATE_ARN}\",")
AWS_CF_CONFIG_SSL_SUPPORT_METHOD=$([ -z "$CF_DOMAIN" ] && echo "" || echo "\"SSLSupportMethod\":\"sni-only\",")
AWS_CF_CONFIG_MIN_SSL_VERSION=$([ -z "$CF_DOMAIN" ] && echo "" || echo "\"MinimumProtocolVersion\":\"TLSv1.2_2018\"")
AWS_CF_CONFIG_TRUSTED_SIGNERS=$([ -z "$AWS_CF_SIGNER_KEY_GROUP_ID" ] && echo "{\"Enabled\":false,\"Quantity\":0}" || echo "{\"Enabled\":true,\"Quantity\":1,\"Items\":[\"$AWS_CF_SIGNER_KEY_GROUP_ID\"]}")
AWS_CF_CONFIG=$(cat <<EOF
{
    "Comment": "${AWS_BUCKET}",
    "CacheBehaviors": {
        "Quantity": 0
    },
    "Origins": {
        "Items": [
            {
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "Id": "S3-origin",
                "DomainName": "${AWS_BUCKET}.s3.${AWS_REGION}.amazonaws.com",
                "OriginAccessControlId": "${AWS_CF_OAC_ID}"
            }
        ],
        "Quantity": 1
    },
    "DefaultRootObject": "",
    "PriceClass": "PriceClass_All",
    "Enabled": false,
    "DefaultCacheBehavior": {
        "TrustedSigners": ${AWS_CF_CONFIG_TRUSTED_SIGNERS},
        "TargetOriginId": "S3-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "CachePolicyId": "${AWS_CF_CONFIG_CACHE_POLICY_ID}",
        "SmoothStreaming": false,
        "Compress": true,
        "AllowedMethods": {
            "Items": [
                "GET",
                "HEAD"
            ],
            "Quantity": 2
        }
    },
    "CallerReference": "${RANDOM}",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": ${AWS_CF_CONFIG_USES_DEFAULT_CERTIFICATE}
        ${AWS_CF_CONFIG_ACM_CERTIFICATE_ARN}
        ${AWS_CF_CONFIG_SSL_SUPPORT_METHOD}
        ${AWS_CF_CONFIG_MIN_SSL_VERSION}
    },
    "HttpVersion": "http2and3",
    "CustomErrorResponses": {
        "Quantity": 0
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    },
    "Aliases": ${AWS_CF_CONFIG_ALIAS_ITEMS}
}
EOF
)
AWS_CF_ARN=$(aws cloudfront create-distribution --distribution-config "${AWS_CF_CONFIG}" | jq -r '.Distribution.ARN')
if [ "$AWS_CF_ARN" = "" ]; then
    echo "Error: failed to create a Cloudfront distribution"
    exit 1;
fi
echo "Created Cloudfront distribution with ARN=${AWS_CF_ARN}"

# Update bucket policy to include a new Cloudfront distribution
AWS_BUCKET_POLICY_CONFIG=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipalReadOnly",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${AWS_BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "${AWS_CF_ARN}"
                }
            }
        }
    ]
}
EOF
)
aws s3api put-bucket-policy --bucket ${AWS_BUCKET} --policy "${AWS_BUCKET_POLICY_CONFIG}" && echo "Updated bucket policy to allow Cloudfront distribution access the bucket"