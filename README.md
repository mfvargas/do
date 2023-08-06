# Manejo de recursos en Digital Ocean (DO)

## create-droplet-dns-record.sh

Instalador del portal de ALA
```shell
./create-droplet-dns-record.sh \
  instalador.geocademia.org \
  nyc1 \
  ubuntu-18-04-x64 \
  s-1vcpu-1gb \
  36105160 \
  "ala,instalador,geoacademia" \
  "~/.ssh/crbio" \
  instalador \
  geoacademia.org
```

Servidor de datos del portal de ALA
```shell
./create-droplet-dns-record.sh \
  datos.geocademia.org \
  nyc1 \
  ubuntu-18-04-x64 \
  s-8vcpu-16gb \
  36105160 \
  "ala,datos,geoacademia" \
  "~/.ssh/crbio" \
  datos \
  geoacademia.org
```
