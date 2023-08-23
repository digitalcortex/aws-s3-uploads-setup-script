#!/bin/bash
AWS_BUCKET=""
AWS_REGION=""
DOMAIN=""
ACM_CERTIFICATE_ARN=""

aws s3api create-bucket --bucket $AWS_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
echo "Created bucket with name=${AWS_BUCKET} in ${AWS_REGION} region"

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
AWS_CF_CONFIG_ALIAS_ITEMS=$([ -z "$DOMAIN" ] && echo "{\"Quantity\":0}" || echo "{\"Quantity\":1,\"Items\":[\"${DOMAIN}\"]}")
AWS_CF_CONFIG_CACHE_POLICY_ID="658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed policy "CachingOptimized"
AWS_CF_CONFIG_USES_DEFAULT_CERTIFICATE=$([ -z "$DOMAIN" ] && echo "true" || echo "false,")
AWS_CF_CONFIG_ACM_CERTIFICATE_ARN=$([ -z "$DOMAIN" ] && echo "" || echo "\"ACMCertificateArn\":\"${ACM_CERTIFICATE_ARN}\",")
AWS_CF_CONFIG_SSL_SUPPORT_METHOD=$([ -z "$DOMAIN" ] && echo "" || echo "\"SSLSupportMethod\":\"sni-only\",")
AWS_CF_CONFIG_MIN_SSL_VERSION=$([ -z "$DOMAIN" ] && echo "" || echo "\"MinimumProtocolVersion\":\"TLSv1.2_2018\"")
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
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
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