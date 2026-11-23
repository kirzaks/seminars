# MISP tehniskās mācības

## MISP uzstādīšana

Skripts `misp-init.sh` veic šādas darbības:

- Pārbauda `docker` instalāciju un ja tādas nav, piedāvā uzinstalēt
- Lejupielādē `misp-docker` [repozitoriju](https://github.com/misp/misp-docker)
- Iestada noklusējuma vērtības:
```
ADMIN_EMAIL=admin@misp.lab
ADMIN_ORG=Jenots
ADMIN_PASSWORD=parole
BASE_URL=https://misp.lab
```

- izveido **servera** un **lietotāja** sertifikātus

- lietotāja sertifikāta parole - `parole`

## Konfigurācija

Tā kā domēns `misp.lab` ir iekšējais, lai izmantotu šo domēna vārdu ir nepieciešams rediģēt `hosts` failu.

## Īsā instrukcija

```bash
git clone https://github.com/kirzaks/seminars
cd seminars
chmod +x misp-ini.sh
sudo ./misp-init.sh

cd misp-docker
sudo docker compose up
```

sertifikātu imports

**Chrome** piemērs:

chrome://certificate-manager/localcerts/usercerts
Trusted Certificates -> rootCA.crt

chrome://certificate-manager/clientcerts
import user1.p12

Var atvērt lapu:
https://misp.lab

Lietotājvārds:
admin@misp.lab
Parole:
parole
