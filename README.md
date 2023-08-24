# Setup S3 storage for file uploads in seconds
**script.sh** creates everything needed for storing web app uploads and making them available via Cloudfront:
- S3 bucket with policy allowing Cloudfront to access the contents
- Cloudfront distribution for serving files from S3 bucket
- Origin Access Control for connecting Cloudfront distribution with an S3 bucket
- Cloudfront signer public key and key group for protecting private files with signed URLs

**request-certificate.sh** creates an SSL certificate issued by Amazon. Needs manual DNS validation

**generate-signer.sh** creates a key that you can use to sign Cloudfront URLs for providing access to protected private files

*Ensure you have a AWS CLI configured with your credentials before running "script.sh" and "request-certificate.sh".*

## How to use
### Step 1. Allow execution on Linux & Mac OS:
First time setup command:
```
chmod +x script.sh && chmod +x request-certificate.sh && chmod +x generate-signer.sh
```
### Step 2. Generate signer keys for protecting uploads that require authentication for access (optional)
```
generate-signer.sh
```
The script will ask for the name of the file where to put the generated key. You'll find the key in the "signer-key" folder.

Example output:
```
generate-signer.sh
Enter file name: test
writing RSA key
```
Script saves the public key to "signer-key/test_pub.pem" and the private key to "signer-key/test.pem". Use private key on a backend to create signed URLs for letting authenticated users view the protected files

### Step 3. Create an SSL certificate when using custom domain for accessing your uploads (optional)
You may skip this step if you are not planning to connect your Cloudfront distribution to your own domain and just use default domain name provided by Amazon.

However if you're interested in serving your uploads with URL looking like this "https://cdn.mycustomdomain.com/*" then do following:
```
request-certificate.sh
```
The script will ask for the domain name that you want to create your SSL certificate for. Keep the default "us-east-1" region in the script because Cloudfront will only allow certificates generated in "us-east-1" region even if your S3 bucket is in another region.

Example output:
```
request-certificate.sh
Enter domain: cdn.mycustomdomain.com
{
    "CertificateArn": "arn:aws:acm:us-east-1:********:certificate/*******-****-****-****-************"
}
```
Visit your Amazon console and copy the validation DNS settings to your domain settings. Wait for Amazon to issue an SSL certificate for your domain and save the CertificateARN, you'll need it later.

### Step 4. Create bucket and Cloudfront distribution
Set env variables and run the script.sh

List of all env variables with example values:
```
// Name of the bucket to create
AWS_BUCKET="test"

// Region where bucket will store the data
AWS_REGION="us-east-1" 

// Custom domain. If not needed, set it to "null" without quotes
CF_DOMAIN="cdn.mycustomdomain.com"

// ARN of a verified SSL certificate that you created during step 3. Needed only when you set CF_DOMAIN 
ACM_CERTIFICATE_ARN="arn:aws:acm:us-east-1:********:certificate/*******-****-****-****-************"

// Public key of a signer. If you want to make all files public, set it to "null" without quotes
SIGNER_PUBLIC_KEY_PATH="signer-key/test_pub.pem"

// If you provided SIGNER_PUBLIC_KEY_PATH variable during setup, the script will create two Cloudfront cache behaviours: "\*" for protecting private files that require signed URL and "public/\*" for keeping files that don't need any protection.
```
The script will request user input for missing env variables.

Example without custom domain and with private files:
```
AWS_BUCKET=test-53825985928 AWS_REGION=eu-west-2 CF_DOMAIN=null SIGNER_PUBLIC_KEY_PATH=signer-key/test_pub.pem ./script.sh
```

Example without custom domain and with all files publicly available:
```
AWS_BUCKET=test-53825985928 AWS_REGION=eu-west-2 CF_DOMAIN=null SIGNER_PUBLIC_KEY_PATH=null ./script.sh
```

Example with custom domain and with private files:
```
AWS_BUCKET=test-53825985928 AWS_REGION=eu-west-2 CF_DOMAIN=cdn.mycustomdomain.com ACM_CERTIFICATE_ARN=arn:aws:acm:us-east-1:********:certificate/*******-****-****-****-************ SIGNER_PUBLIC_KEY_PATH=signer-key/test_pub.pem ./script.sh
```