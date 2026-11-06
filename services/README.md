# The application — "Voting App"

Three small services and two data stores. The code comes from Docker's open source [example-voting-app](https://github.com/dockersamples/example-voting-app) (Apache 2.0, see `LICENSE`). Your job is **not** to change the application. Your job is to build it, ship it and run it on AWS.

```
 browser --vote--> [ vote ]  --push-->  [ Redis ]  --pop-->  [ worker ] --insert--> [ Postgres ]
 (Python/Flask)                (a queue)              (.NET)                      (the votes)
                                                                                      |
 browser <--live--  [ result ] <----------------------- select count(*) --------------+
                    (Node.js, socket.io)
```

| Service | Language | Port | Talks to | Health check |
|---|---|---|---|---|
| `vote` | Python (Flask + gunicorn) | 80 | Redis | `GET /healthz` |
| `result` | Node.js | 80 | Postgres | `GET /healthz` |
| `worker` | .NET 7 | none (no web server) | Redis and Postgres | none |

`worker` has no port and no health check: it only reads from the queue and writes to the database. A load balancer cannot check it.

## Configuration (environment variables)

| Variable | Used by | Default | Meaning |
|---|---|---|---|
| `REDIS_HOST` | vote, worker | `redis` | Redis address |
| `REDIS_PORT` | vote | `6379` | Redis port |
| `DB_HOST` | result, worker | `db` | Postgres address |
| `DB_PORT` | result, worker | `5432` | Postgres port |
| `DB_USER` | result, worker | `postgres` | Database user |
| `DB_PASSWORD` | result, worker | `postgres` | Database password |
| `DB_NAME` | result, worker | `postgres` | Database name |
| `DB_SSL` | result, worker | `false` | `true` = connect to Postgres over TLS |
| `OPTION_A`, `OPTION_B` | vote | `ביבי`, `אייזנקוט` | The two choices on the page |

> **RDS Postgres 15 and newer refuses connections without TLS** (`rds.force_ssl`). On AWS the services must run with `DB_SSL=true`. Without it you see `no pg_hba.conf entry ... no encryption` in the logs.

## What was changed from the original (and why)

The original code has the hostnames **written in the code** (`redis`, `db`) and a fixed password. That works in docker compose, where the container names are the hostnames. On AWS the addresses are the ElastiCache and RDS endpoints, so the code had to read them from the environment.

| File | Change |
|---|---|
| `vote/app.py` | Redis host and port from `REDIS_HOST` / `REDIS_PORT`. New `GET /healthz` that does not depend on Redis |
| `result/server.js` | Database settings from `DB_*`, optional TLS with `DB_SSL`. New `GET /healthz`. Added the missing `require('path')`. The log now prints the connection error |
| `worker/Program.cs` | Redis and database settings from the environment, optional TLS with `DB_SSL` |
| `*/.dockerignore` | Added, so local build files do not enter the image |

Everything else (Dockerfiles, views, dependencies) is unchanged.

## Run it on your machine (optional, to understand it)

```bash
docker network create vote-net
docker run -d --name redis --network vote-net redis:7-alpine
docker run -d --name db --network vote-net -e POSTGRES_PASSWORD=postgres postgres:16
docker build -t vote ./vote && docker run -d --name vote --network vote-net -e REDIS_HOST=redis -p 8080:80 vote
docker build -t result ./result && docker run -d --name result --network vote-net -e DB_HOST=db -p 8081:80 result
docker build -t worker ./worker && docker run -d --name worker --network vote-net -e REDIS_HOST=redis -e DB_HOST=db worker
```

Open `http://localhost:8080` (vote) and `http://localhost:8081` (result).

Cleanup: `docker rm -f redis db vote result worker && docker network rm vote-net`.
