#!/bin/bash
read -p 'Enter domain: ' DOMAIN
aws acm request-certificate --domain-name ${DOMAIN} --region=us-east-1 --validation-method DNS