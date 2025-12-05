# Run Quay

## A super simple way to get a basic Quay instance running with object storage.

To start everything:

    $ git clone https://github.com/BilLDett/runquay.git
    $ ./start.sh

To stop everything:

    $ ./stop.sh

The only thing you need installed are [podman](podman.io) and `openssl`.

Quay requires a few components to run:

* Postgres database
* Redis cache
* Object Storage (we're using [garage](https://garagehq.deuxfleurs.fr/))

The stop.sh script will leave all of your data intact, so it's safe to re-run start.sh on an existing environment.

A minimal Quay configuration is provided in `config/config_template.yaml`, feel free to adapt it as you see fit. Just avoid updating `config/config.yaml` directly since we use the template to inject the `garage` keys into the storage config.




