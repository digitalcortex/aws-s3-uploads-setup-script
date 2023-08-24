#!/bin/bash

read -p 'Enter file name: ' NAME
mkdir -p signer-key
cd signer-key
openssl genrsa -out ${NAME}.pem 2048
openssl rsa -pubout -in ${NAME}.pem -out ${NAME}_pub.pem