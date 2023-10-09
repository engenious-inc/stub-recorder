#! /bin/bash

DOMAIN="localhost"

# Create root CA & Private key

openssl req -x509 \
            -sha256 -days 356 \
            -nodes \
            -newkey rsa:2048 \
            -subj "/CN=${DOMAIN}/C=US/L=San Fransisco" \
            -keyout rootCA.key -out rootCA.crt 

# Generate Private key 

openssl genrsa -out ${DOMAIN}.key.pem 2048

# Create csf conf

cat > /tmp/csr.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = US
ST = California
L = San Fransisco
O = Apple
OU = Apple QA
CN = ${DOMAIN}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${DOMAIN}
DNS.2 = www.${DOMAIN}
IP.1 = 127.0.0.1
IP.2 = 127.0.0.1

EOF

# create CSR request using private key

openssl req -new -key ${DOMAIN}.key.pem -out /tmp/${DOMAIN}.csr -config /tmp/csr.conf

# Create a external config file for the certificate

cat > /tmp/cert.conf <<EOF

authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}

EOF

# Create SSl with self signed CA valid for 1 year

openssl x509 -req \
    -in /tmp/${DOMAIN}.csr \
    -CA rootCA.crt -CAkey rootCA.key \
    -CAcreateserial -out ${DOMAIN}.crt \
    -days 365 \
    -sha256 -extfile /tmp/cert.conf
    
echo
echo "You must double-click on the rootCA.crt file to add the Certificate Authority to your keychain so that the certificate will be trusted"
echo

