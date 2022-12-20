## Environment

Copy the `example.env` file to `.env` and modify the values if needed:

```shell
cp example.env .env
```

## Serve

```shell
docker compose up -d dev
```

## Build static files

```shell
docker compose run --rm builder
```
