# Local Prime service

This standard-library Python service provides the local substitute for the
network-facing Prime flows. It listens only on loopback; it does not accept a
LAN host address.

Start it from the repository root in PowerShell:

```powershell
python script\local_service\local_server.py
```

The default endpoint is `http://127.0.0.1:8765/api/v1`. The Godot Prime
Network page retains the native notice, occupied-save selection with OK/BACK footers, waiting
dialog, and server-time synchronization before opening the four native online
entries. Time synchronization attempts to launch the server on first use and
does not create an account or mutate saves. Authenticated actions subsequently
register a random local account and reuse it. A process launched by the game is
stopped when the game exits. Its generated password is saved in Godot's
`user://` configuration;
the service stores only a salted PBKDF2 hash. Service data defaults to
`%LOCALAPPDATA%\BattleMonster\local-service\service.json`. Use `--data-dir`
to select another local data directory or `--port` to select another port.
For a game launched from a development environment, the same settings can be
overridden with `BATTLEMONSTER_LOCAL_SERVICE_PORT` and
`BATTLEMONSTER_LOCAL_SERVICE_DATA_DIR`; the game passes those values to its
child service and uses the matching loopback endpoint.

## Routes

All routes except health, capabilities, time, registration and login require the `Authorization: Bearer`
token returned by registration or login.

| Route | Behavior |
|---|---|
| `GET /health`, `GET /capabilities` | Readiness and explicit simulation limits |
| `GET /time` | Unix time for the native connection handshake; no authentication or state mutation |
| `POST /auth/register`, `POST /auth/login`, `POST /auth/logout` | Local accounts; no phone or SMS verification |
| `GET/PUT /profile` | Local display name and profile |
| `GET /saves`, `GET/PUT/DELETE /saves/{0,1}` | Per-account copies of the two game slots |
| `GET/POST /mail`, `POST /mail/{id}` | Local inbox, gift messages, and claim state |
| `GET/POST /friends`, `DELETE /friends/{username}` | Username-based local friend list, capped at ten |
| `GET /battles/records`, `POST /battles/records` | Local result history |
| `GET/POST /battles/matches`, `GET/POST /battles/matches/{id}` | Local match lobby and participant-reported result records |
| `GET /ranking` | Ranking view over local recorded wins/losses |
| `GET/POST /market`, `DELETE /market/{id}`, `POST /market/{id}:buy` | Local monster listings and purchase delivery by inbox |
| `GET/PUT /island`, `GET /islands`, `GET /islands/{username}`, `POST /islands/{username}/like`, `GET /island/visits` | Local island snapshots, visits, likes, and visit history |
| `GET /cash`, `POST /cash/test-credit` | Simulated local balance and explicitly confirmed test credits |
| `POST /cash/purchase` | Always rejects real-money purchases |

JSON errors have `error` and `message` fields. The service caps request bodies
at 1 MiB and uses atomic replacement for persisted state.

Run the API and Godot client tests with:

```powershell
python -m unittest discover -s script\local_service -p "test_*.py" -v
godot --headless --path game --script res://tests/local_service_client_test.gd
godot --headless --path game --script res://tests/local_service_autostart_test.gd
```

## Compatibility boundary

These are local protocol substitutes, not a reconstruction of the defunct
original server. The game connects only to loopback. Account credentials,
saves, mailbox, rankings, friends, matches, listings, islands, and the
simulated balance are isolated to the local data directory. No real payment,
SMS, or external network request is performed.

Market listings use simulated Cash only: purchases require an explicitly
credited test balance, debit the buyer, credit the seller, and deliver the
listing as an inbox payload. They do not update a game save or perform real
payments.

The native battle engine is not an authoritative server simulation: a local
match stores participant-reported results, and the ranking view reflects
recorded wins/losses rather than claiming the original ranking formula.
Likewise, island snapshots and gifts are user-supplied local payloads; the
original inventory/economy rules are not inferred by this service.
