#!/bin/bash

CA_NAME="MispLab Root CA"
SERVER_NAME="misp.lab"

CA_DAYS=3650
SERVER_DAYS=365

# Dockera lietas
# ===============================

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR]: Run script with root (sudo)." >&2
    exit 1
fi


if docker compose version >/dev/null 2>&1; then
    echo "[+] Docker compose OK"
else
    echo "[ERROR] Docker compose is not installed. Please check install manual"
    echo "https://docs.docker.com/engine/install/"
    echo ""
    read -p  "...or install now. Would you like to install docker now? (Y/n):  " answ

    if [[ -z "$answ" || "$answ" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1)
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
    else
        echo "Cancelled."
        exit 0
    fi

fi

if command -v git >/dev/null 2>&1; then
    echo "[+] Git OK"
else
    echo "[ERROR] Git is not installed."
    exit 1
fi

git clone https://github.com/misp/misp-docker

cp misp-docker/template.env misp-docker/.env

sed -i 's/start_period: 60s/start_period: 300s/g' misp-docker/docker-compose.yml

sed -i '\|etc/nginx/certs:ro"|a\
      - "./05-user.sh:/docker-entrypoint.d/05-user.sh"\
      - "./99-after.sh:/docker-entrypoint.d/99-after.sh"' misp-docker/docker-compose.yml

sed -i \
    -e 's|^ADMIN_EMAIL=.*|ADMIN_EMAIL=admin@misp.lab|' \
    -e 's|^ADMIN_ORG=.*|ADMIN_ORG=Jenots|' \
    -e 's|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=parole|' \
    -e 's|^BASE_URL=.*|BASE_URL=https://misp.lab|' \
    misp-docker/.env

mkdir -p misp-docker/ssl
chmod 755 misp-docker/ssl
chown root:root misp-docker/ssl

# ============================================================

echo "[+] root CA"

mkdir -p ca

cat > rootCA.ext <<'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = LV
O = MispLab
CN = MispLab Root CA

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF


openssl genrsa \
    -out ca/rootCA.key \
    4096


openssl req -x509 -new \
    -key ca/rootCA.key \
    -sha256 \
    -days "${CA_DAYS}" \
    -out ca/rootCA.crt \
    -config rootCA.ext \
    -extensions v3_ca


echo "[+] server SSL"

# ====================================================

mkdir -p server

cat > "${SERVER_NAME}.ext" <<EOF
[v3_server]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SERVER_NAME}
EOF


openssl genrsa \
    -out server/"${SERVER_NAME}.key" \
    4096

openssl req -new \
    -key server/"${SERVER_NAME}.key" \
    -out "${SERVER_NAME}.csr" \
    -subj "/C=LV/O=MispLab/CN=${SERVER_NAME}"


openssl x509 -req \
    -in "${SERVER_NAME}.csr" \
    -CA ca/rootCA.crt \
    -CAkey ca/rootCA.key \
    -CAcreateserial \
    -out server/"${SERVER_NAME}.crt" \
    -days "${SERVER_DAYS}" \
    -sha256 \
    -extfile "${SERVER_NAME}.ext" \
    -extensions v3_server



echo "[+] Check"

openssl verify \
    -CAfile ca/rootCA.crt \
    -purpose sslserver \
    -verify_hostname "${SERVER_NAME}" \
    server/"${SERVER_NAME}.crt"


echo -e "=========\n"

openssl x509 \
    -in server/"${SERVER_NAME}.crt" \
    -noout \
    -subject \
    -issuer \
    -dates \
    -ext subjectAltName


rm -v rootCA.ext ${SERVER_NAME}.csr ${SERVER_NAME}.ext ca/rootCA.srl

# Pielagots MISP mācībām.
mv server/${SERVER_NAME}.key server/key.pem
mv server/${SERVER_NAME}.crt server/cert.pem

# ===========================================

mkdir -p user

openssl genrsa -out user/user1.key 4096
openssl req -new \
    -key user/user1.key \
    -out user1.csr \
    -subj "/C=LV/O=MispLab/CN=lietotajs1"
cat > user1.ext <<'EOF'
[v3_client]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF
openssl x509 -req \
    -in user1.csr \
    -CA ca/rootCA.crt \
    -CAkey ca/rootCA.key \
    -CAcreateserial \
    -out user/user1.crt \
    -days 365 \
    -sha256 \
    -extfile user1.ext \
    -extensions v3_client

openssl pkcs12 -export \
    -out user/user1.p12 \
    -inkey user/user1.key \
    -in user/user1.crt \
    -certfile ca/rootCA.crt \
    -passout pass:parole \
    -name "MISP Lietotajs"

rm -v user1.csr user1.ext ca/rootCA.srl
cp ca/rootCA.crt user/
tar -zcvf user.tar.gz user/


# ============= Permīcijas =========================
cp server/key.pem misp-docker/ssl/key.pem
cp server/cert.pem misp-docker/ssl/cert.pem
cp ca/rootCA.crt misp-docker/ssl/rootCA.crt


chgrp 101 misp-docker/ssl/key.pem misp-docker/ssl/cert.pem misp-docker/ssl/rootCA.crt
chmod 640 misp-docker/ssl/key.pem misp-docker/ssl/cert.pem misp-docker/ssl/rootCA.crt


# skriptu faili


cat <<'EOF_MAIN' > misp-docker/05-user.sh
#!/usr/bin/env sh
# -*- coding: utf-8 -*-

set -eu


SSL_CONF="${NGINX_INCLUDE_DIR}/user.conf"

if [ ! -f "/etc/nginx/certs/rootCA.crt" ]; then
    echo "ERROR: No rootCA.crt in SSL folder." >&2

    exit 0
fi

ca="/etc/nginx/certs/rootCA.crt"
if [ ! -r $ca ]; then
    echo "ERROR: $ca exists but is not readable by uid $(id -u) / gid $(id -g)." >&2
    echo "ERROR: Fix the permissions on the host, e.g. 'chgrp $(id -g) ssl/$(basename "$ca") && chmod 640 ssl/$(basename "$ca")'." >&2
    exit 1
fi

cat >> "$SSL_CONF" <<EOF
    ssl_client_certificate /etc/nginx/certs/rootCA.crt;
    ssl_verify_client on;
EOF

EOF_MAIN

cat <<EOF_MAIN > misp-docker/99-after.sh
#!/usr/bin/env sh
# -*- coding: utf-8 -*-

set -eu

sed -i '/include \/etc\/nginx\/conf.d\/include\/ssl.conf;/a\    include /etc/nginx/conf.d/include/user.conf;' /etc/nginx/conf.d/misp.conf
EOF_MAIN

chown root:root misp-docker/99-after.sh misp-docker/05-user.sh
chmod +x misp-docker/99-after.sh misp-docker/05-user.sh


cd misp-docker
docker compose pull
