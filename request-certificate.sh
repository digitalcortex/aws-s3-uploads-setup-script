#!/bin/bash
DOMAIN=cdn.baripay.am

aws acm request-certificate --domain-name ${DOMAIN} --region=us-east-1 --validation-method DNS