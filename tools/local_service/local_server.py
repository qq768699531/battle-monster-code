#!/usr/bin/env python3
"""Loopback-only local service for the reconstructed Prime online features."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit


MAX_BODY = 1_048_576
MAX_NAME = 24
MAX_PASSWORD = 128
PBKDF2_ROUNDS = 180_000
API_PREFIX = "/api/v1"


class ServiceError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code


def _now() -> int:
    return int(time.time())


def _valid_name(value: Any) -> bool:
    return isinstance(value, str) and 1 <= len(value) <= MAX_NAME and \
        all(char.isalnum() or char in "_-" for char in value)


def _positive_int(value: Any, label: str, maximum: int = 2_000_000_000) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0 or value > maximum:
        raise ServiceError(400, "invalid_input", f"{label} must be a positive integer.")
    return value


def _object(value: Any, label: str = "request") -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ServiceError(400, "invalid_input", f"{label} must be an object.")
    return value


class LocalService:
    """Persistent account-scoped data and explicit local simulation capabilities."""

    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.path = self.data_dir / "service.json"
        self.lock = threading.RLock()
        self.tokens: dict[str, str] = {}
        self.state = self._load()

    def _load(self) -> dict[str, Any]:
        if not self.path.exists():
            return {"version": 1, "users": {}, "listings": [], "matches": []}
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise RuntimeError(f"Cannot load local service data: {error}") from error
        if not isinstance(data, dict) or data.get("version") != 1 or \
                not isinstance(data.get("users"), dict) or \
                not isinstance(data.get("listings"), list) or \
                not isinstance(data.get("matches"), list):
            raise RuntimeError("Local service data has an unsupported or invalid structure.")
        return data

    def _persist(self) -> None:
        temporary = self.path.with_suffix(".pending")
        encoded = json.dumps(self.state, ensure_ascii=False, separators=(",", ":"))
        with temporary.open("w", encoding="utf-8", newline="\n") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, self.path)

    @staticmethod
    def _password_record(password: str, salt: bytes | None = None) -> dict[str, str]:
        salt = salt or secrets.token_bytes(16)
        digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ROUNDS)
        return {"salt": salt.hex(), "digest": digest.hex()}

    @staticmethod
    def _password_matches(password: str, record: dict[str, str]) -> bool:
        try:
            salt = bytes.fromhex(record["salt"])
            expected = bytes.fromhex(record["digest"])
        except (KeyError, ValueError):
            return False
        actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ROUNDS)
        return hmac.compare_digest(actual, expected)

    def _new_user(self, username: str, password: str) -> dict[str, Any]:
        if not _valid_name(username):
            raise ServiceError(400, "invalid_username", "Use 1-24 letters, numbers, '_' or '-'.")
        if not isinstance(password, str) or not 8 <= len(password) <= MAX_PASSWORD:
            raise ServiceError(400, "invalid_password", "Password must contain 8-128 characters.")
        if username.casefold() in {key.casefold() for key in self.state["users"]}:
            raise ServiceError(409, "name_taken", "This local username is already registered.")
        user = {
            "username": username,
            "password": self._password_record(password),
            "created_at": _now(),
            "profile": {"display_name": username, "bio": ""},
            "saves": {},
            "mail": [],
            "friends": [],
            "battle": {"rating": 1000, "wins": 0, "losses": 0, "draws": 0, "log": []},
            "island": {"snapshot": None, "likes": 0, "visits": 0, "visited": [],
                       "liked_by": []},
            "cash": {"balance": 0, "ledger": []},
        }
        self.state["users"][username] = user
        self._persist()
        return user

    def _issue_token(self, username: str) -> str:
        token = secrets.token_urlsafe(32)
        self.tokens[token] = username
        return token

    def authenticate(self, token: str | None) -> str:
        if not token:
            raise ServiceError(401, "unauthorized", "Sign in to a local account first.")
        username = self.tokens.get(token)
        if username is None or username not in self.state["users"]:
            raise ServiceError(401, "unauthorized", "The local session is no longer valid.")
        return username

    def _user(self, username: str) -> dict[str, Any]:
        return self.state["users"][username]

    def request(self, method: str, path: str, body: Any, token: str | None) -> tuple[int, dict[str, Any]]:
        body = _object(body) if body is not None else {}
        route = path.removeprefix(API_PREFIX).rstrip("/") or "/"
        with self.lock:
            if route == "/health" and method == "GET":
                return 200, {"ok": True, "service": "battlemonster-local", "version": 1}
            if route == "/time" and method == "GET":
                return 200, {"server_time": _now()}
            if route == "/capabilities" and method == "GET":
                return 200, {
                    "authentication": "local-password",
                    "sms": "disabled",
                    "payment": "simulated-only",
                    "features": ["profile", "saves", "mail", "battle-records",
                                 "battle-lobbies", "friends", "ranking", "market",
                                 "island", "cash-simulation"],
                }
            if route == "/auth/register" and method == "POST":
                user = self._new_user(body.get("username"), body.get("password"))
                session = self._issue_token(user["username"])
                return 201, {"token": session, "user": self._public_user(user)}
            if route == "/auth/login" and method == "POST":
                username, password = body.get("username"), body.get("password")
                if not isinstance(username, str) or not isinstance(password, str):
                    raise ServiceError(400, "invalid_input", "username and password are required.")
                user = next((value for key, value in self.state["users"].items()
                             if key.casefold() == username.casefold()), None)
                if user is None or not self._password_matches(password, user["password"]):
                    raise ServiceError(401, "invalid_credentials", "Username or password is incorrect.")
                return 200, {"token": self._issue_token(user["username"]),
                             "user": self._public_user(user)}

            username = self.authenticate(token)
            user = self._user(username)

            if route == "/auth/logout" and method == "POST":
                self.tokens.pop(token or "", None)
                return 200, {"ok": True}
            if route == "/profile" and method == "GET":
                return 200, {"profile": user["profile"], "username": username}
            if route == "/profile" and method == "PUT":
                display = body.get("display_name", username)
                bio = body.get("bio", "")
                if not isinstance(display, str) or not 1 <= len(display) <= 32 or \
                        not isinstance(bio, str) or len(bio) > 160:
                    raise ServiceError(400, "invalid_input", "Invalid profile fields.")
                user["profile"] = {"display_name": display, "bio": bio}
                self._persist()
                return 200, {"profile": user["profile"]}

            if route == "/saves" and method == "GET":
                return 200, {"slots": sorted(int(slot) for slot in user["saves"])}
            parts = route.strip("/").split("/")
            if len(parts) == 2 and parts[0] == "saves":
                slot = self._slot(parts[1])
                if method == "GET":
                    if str(slot) not in user["saves"]:
                        raise ServiceError(404, "save_missing", "No uploaded save exists in this slot.")
                    return 200, {"slot": slot, "save": user["saves"][str(slot)]}
                if method == "PUT":
                    save = body.get("save")
                    if not isinstance(save, dict) or len(json.dumps(save)) > 512_000:
                        raise ServiceError(400, "invalid_save", "Save must be an object under 512 KB.")
                    user["saves"][str(slot)] = {"updated_at": _now(), "data": save}
                    self._persist()
                    return 200, {"slot": slot, "saved": True}
                if method == "DELETE":
                    removed = user["saves"].pop(str(slot), None) is not None
                    self._persist()
                    return 200, {"slot": slot, "deleted": removed}

            if route == "/mail" and method == "GET":
                return 200, {"messages": user["mail"]}
            if route == "/mail" and method == "POST":
                recipient = body.get("recipient")
                message = body.get("message", "")
                if not isinstance(recipient, str) or recipient not in self.state["users"] or \
                        not isinstance(message, str) or len(message) > 240:
                    raise ServiceError(400, "invalid_mail", "A local recipient and message (max 240 chars) are required.")
                if recipient == username:
                    raise ServiceError(400, "invalid_mail", "You cannot send a gift to yourself.")
                mail = {"id": secrets.token_hex(8), "from": username, "message": message,
                        "created_at": _now(), "claimed": False, "gift": body.get("gift")}
                if mail["gift"] is not None and not isinstance(mail["gift"], dict):
                    raise ServiceError(400, "invalid_mail", "gift must be an object.")
                self._user(recipient)["mail"].append(mail)
                self._persist()
                return 201, {"message": mail}
            if len(parts) == 2 and parts[0] == "mail" and method == "POST":
                message = next((entry for entry in user["mail"] if entry["id"] == parts[1]), None)
                if message is None:
                    raise ServiceError(404, "mail_missing", "Message not found.")
                message["claimed"] = True
                self._persist()
                return 200, {"message": message}

            if route == "/battles/records" and method == "GET":
                ranking = sorted(
                    self.state["users"].values(),
                    key=lambda entry: (-entry["battle"]["wins"], entry["battle"]["losses"],
                                       entry["username"].casefold()))
                rank = next(index + 1 for index, entry in enumerate(ranking)
                            if entry["username"] == username)
                return 200, {"rating": user["battle"]["rating"], "wins": user["battle"]["wins"],
                             "losses": user["battle"]["losses"], "draws": user["battle"]["draws"],
                             "rank": rank, "log": user["battle"]["log"],
                             "ranking_basis": "local-recorded-wins-losses"}
            if route == "/battles/records" and method == "POST":
                # The server records only a result explicitly supplied by the game client.
                result = body.get("result")
                if result not in ["win", "loss", "draw"]:
                    raise ServiceError(400, "invalid_result", "result must be win, loss, or draw.")
                self._record_battle(user, result, str(body.get("mode", "local"))[:24])
                self._persist()
                return 201, {"record": user["battle"]}
            if route == "/battles/matches" and method == "POST":
                mode = body.get("mode")
                if mode not in ["quick", "ranked", "friendly", "challenge"]:
                    raise ServiceError(400, "invalid_mode", "Unsupported local battle mode.")
                opponent = body.get("opponent")
                if mode in ["friendly", "challenge"]:
                    if not isinstance(opponent, str) or opponent == username or \
                            opponent not in self.state["users"]:
                        raise ServiceError(404, "opponent_missing", "A different local account is required.")
                else:
                    opponents = [name for name in self.state["users"] if name != username]
                    opponent = sorted(opponents, key=str.casefold)[0] if opponents else None
                match = {
                    "id": secrets.token_hex(8), "mode": mode, "players": [username, opponent]
                    if opponent else [username],
                    "status": "ready" if opponent else "waiting",
                    "created_at": _now(), "results": {},
                }
                self.state["matches"].append(match)
                self._persist()
                return 201, {"match": match, "simulation": True}
            if route == "/battles/matches" and method == "GET":
                return 200, {"matches": [match for match in self.state["matches"]
                                         if username in match["players"]]}
            if len(parts) == 3 and parts[0] == "battles" and parts[1] == "matches":
                match = next((entry for entry in self.state["matches"]
                              if entry["id"] == parts[2]), None)
                if match is None or username not in match["players"]:
                    raise ServiceError(404, "match_missing", "Local match not found.")
                if method == "GET":
                    return 200, {"match": match, "simulation": True}
                if method == "POST":
                    result = body.get("result")
                    if result not in ["win", "loss", "draw"]:
                        raise ServiceError(400, "invalid_result", "result must be win, loss, or draw.")
                    if username in match["results"]:
                        raise ServiceError(409, "result_submitted", "A result was already submitted.")
                    match["results"][username] = result
                    self._record_battle(user, result, match["mode"])
                    if len(match["players"]) == len(match["results"]):
                        match["status"] = "complete"
                    self._persist()
                    return 200, {"match": match, "simulation": True}
            if route == "/ranking" and method == "GET":
                ranking = sorted(
                    ({"username": entry["username"],
                      "display_name": entry["profile"]["display_name"],
                      "rating": entry["battle"]["rating"],
                      "wins": entry["battle"]["wins"],
                      "losses": entry["battle"]["losses"]}
                     for entry in self.state["users"].values()),
                    key=lambda entry: (-entry["wins"], entry["losses"],
                                       entry["username"].casefold()))
                return 200, {"entries": ranking}

            if route == "/friends" and method == "GET":
                return 200, {"friends": user["friends"]}
            if route == "/friends" and method == "POST":
                friend = body.get("username")
                if not isinstance(friend, str) or friend not in self.state["users"] or friend == username:
                    raise ServiceError(404, "friend_missing", "A different local account is required.")
                if friend in user["friends"]:
                    raise ServiceError(409, "friend_exists", "This local account is already on the list.")
                if len(user["friends"]) >= 10:
                    raise ServiceError(409, "friend_limit", "The local friend list is limited to 10 accounts.")
                user["friends"].append(friend)
                self._persist()
                return 201, {"friends": user["friends"]}
            if len(parts) == 2 and parts[0] == "friends" and method == "DELETE":
                friend = unquote(parts[1])
                if friend not in user["friends"]:
                    raise ServiceError(404, "friend_missing", "Friend not found.")
                user["friends"].remove(friend)
                self._persist()
                return 200, {"friends": user["friends"]}

            if route == "/market" and method == "GET":
                return 200, {"listings": [item for item in self.state["listings"]
                                          if item["status"] == "active" and
                                          item["seller"] != username]}
            if route == "/market" and method == "POST":
                monster = body.get("monster")
                if not isinstance(monster, dict) or len(json.dumps(monster)) > 16_384:
                    raise ServiceError(400, "invalid_listing", "monster must be an object under 16 KB.")
                price = _positive_int(body.get("price"), "price", 1_000_000)
                listing = {"id": secrets.token_hex(8), "seller": username, "monster": monster,
                           "price": price, "status": "active", "created_at": _now()}
                self.state["listings"].append(listing)
                self._persist()
                return 201, {"listing": listing}
            if len(parts) == 2 and parts[0] == "market":
                buying = method == "POST" and parts[1].endswith(":buy")
                listing_id = parts[1][:-4] if buying else parts[1]
                listing = next((item for item in self.state["listings"]
                                if item["id"] == listing_id), None)
                if listing is None:
                    raise ServiceError(404, "listing_missing", "Market listing not found.")
                if method == "DELETE":
                    if listing["seller"] != username:
                        raise ServiceError(403, "not_owner", "Only the seller can cancel this listing.")
                    if listing["status"] != "active":
                        raise ServiceError(409, "listing_closed", "This listing is no longer active.")
                    listing["status"] = "cancelled"
                    self._persist()
                    return 200, {"listing": listing}
                if buying:
                    if listing["seller"] == username:
                        raise ServiceError(400, "self_purchase", "You cannot buy your own listing.")
                    if listing["status"] != "active":
                        raise ServiceError(409, "listing_closed", "This listing is no longer active.")
                    if user["cash"]["balance"] < listing["price"]:
                        raise ServiceError(409, "insufficient_funds",
                                           "The local account does not have enough simulated Cash.")
                    listing["status"] = "sold"
                    listing["buyer"] = username
                    listing["sold_at"] = _now()
                    seller = self._user(listing["seller"])
                    user["cash"]["balance"] -= listing["price"]
                    user["cash"]["ledger"].append({"kind": "market-purchase",
                        "amount": -listing["price"], "listing": listing_id, "created_at": _now()})
                    seller["cash"]["balance"] += listing["price"]
                    seller["cash"]["ledger"].append({"kind": "market-sale",
                        "amount": listing["price"], "listing": listing_id, "created_at": _now()})
                    user["mail"].append({"id": secrets.token_hex(8), "from": "local-market",
                        "message": "A purchased monster is ready for local delivery.",
                        "gift": {"monster": listing["monster"]}, "claimed": False, "created_at": _now()})
                    self._persist()
                    return 200, {"listing": listing}

            if route == "/island" and method == "GET":
                return 200, {"snapshot": user["island"]["snapshot"],
                             "likes": user["island"]["likes"],
                             "visits": user["island"]["visits"]}
            if route == "/island" and method == "PUT":
                snapshot = body.get("snapshot")
                if snapshot is not None and (not isinstance(snapshot, dict) or
                                             len(json.dumps(snapshot)) > 128_000):
                    raise ServiceError(400, "invalid_island", "snapshot must be an object under 128 KB.")
                user["island"]["snapshot"] = snapshot
                self._persist()
                return 200, {"saved": True}
            if route == "/islands" and method == "GET":
                return 200, {"islands": [self._island_summary(name, entry)
                                         for name, entry in self.state["users"].items()
                                         if name != username and entry["island"]["snapshot"] is not None]}
            if len(parts) == 2 and parts[0] == "islands" and method == "GET":
                owner = unquote(parts[1])
                target = self.state["users"].get(owner)
                if target is None or target["island"]["snapshot"] is None:
                    raise ServiceError(404, "island_missing", "Island not found.")
                target["island"]["visits"] += 1
                target["island"]["visited"].append({"username": username, "at": _now()})
                target["island"]["visited"] = target["island"]["visited"][-100:]
                self._persist()
                return 200, {"island": self._island_summary(owner, target),
                             "snapshot": target["island"]["snapshot"]}
            if len(parts) == 3 and parts[0] == "islands" and parts[2] == "like" and method == "POST":
                owner = unquote(parts[1])
                if owner == username:
                    raise ServiceError(400, "self_like", "You cannot like your own island.")
                target = self.state["users"].get(owner)
                if target is None or target["island"]["snapshot"] is None:
                    raise ServiceError(404, "island_missing", "Island not found.")
                liked_by = target["island"].setdefault("liked_by", [])
                if username in liked_by:
                    raise ServiceError(409, "already_liked", "You already liked this local island.")
                liked_by.append(username)
                target["island"]["likes"] += 1
                self._persist()
                return 200, {"likes": target["island"]["likes"]}
            if route == "/island/visits" and method == "GET":
                return 200, {"visits": user["island"]["visited"]}

            if route == "/cash" and method == "GET":
                return 200, {"balance": user["cash"]["balance"], "ledger": user["cash"]["ledger"],
                             "payment": "simulated-only"}
            if route == "/cash/test-credit" and method == "POST":
                if not body.get("confirm_simulation") is True:
                    raise ServiceError(400, "confirmation_required", "Confirm this is a simulated test credit.")
                amount = _positive_int(body.get("amount"), "amount", 100_000)
                user["cash"]["balance"] += amount
                user["cash"]["ledger"].append({"kind": "simulated-credit", "amount": amount,
                                               "created_at": _now()})
                self._persist()
                return 201, {"balance": user["cash"]["balance"], "simulated": True}
            if route == "/cash/purchase" and method == "POST":
                raise ServiceError(501, "payment_disabled",
                                   "Real-money and Cash purchases are disabled in this local service.")

        raise ServiceError(404, "not_found", "Route not found.")

    @staticmethod
    def _slot(value: str) -> int:
        try:
            slot = int(value)
        except ValueError as error:
            raise ServiceError(400, "invalid_slot", "Slot must be 0 or 1.") from error
        if slot not in [0, 1]:
            raise ServiceError(400, "invalid_slot", "Slot must be 0 or 1.")
        return slot

    @staticmethod
    def _public_user(user: dict[str, Any]) -> dict[str, Any]:
        return {"username": user["username"], "profile": user["profile"]}

    @staticmethod
    def _island_summary(username: str, user: dict[str, Any]) -> dict[str, Any]:
        return {"username": username, "display_name": user["profile"]["display_name"],
                "likes": user["island"]["likes"], "visits": user["island"]["visits"]}

    @staticmethod
    def _record_battle(user: dict[str, Any], result: str, mode: str) -> None:
        battle = user["battle"]
        if result == "win":
            battle["wins"] += 1
        elif result == "loss":
            battle["losses"] += 1
        else:
            battle["draws"] += 1
        battle["log"].append({"result": result, "mode": mode, "at": _now()})
        battle["log"] = battle["log"][-100:]


class LocalServiceServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], service: LocalService):
        super().__init__(address, RequestHandler)
        self.service = service


class RequestHandler(BaseHTTPRequestHandler):
    server: LocalServiceServer
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *args: Any) -> None:
        if os.environ.get("BATTLEMONSTER_SERVICE_LOG"):
            super().log_message(_format, *args)

    def _send(self, status: int, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(encoded)

    def _handle(self) -> None:
        try:
            parsed = urlsplit(self.path)
            if parsed.path != "/api/v1/health" and not parsed.path.startswith(API_PREFIX + "/"):
                raise ServiceError(404, "not_found", "Route not found.")
            if parsed.path.startswith(API_PREFIX + "/") and ".." in parsed.path:
                raise ServiceError(400, "invalid_path", "Invalid API path.")
            body: Any = {}
            if self.command in ["POST", "PUT", "PATCH"]:
                length_text = self.headers.get("Content-Length", "")
                if not length_text.isdigit():
                    raise ServiceError(411, "length_required", "Content-Length is required.")
                length = int(length_text)
                if length > MAX_BODY:
                    raise ServiceError(413, "body_too_large", "Request body exceeds 1 MB.")
                raw = self.rfile.read(length)
                try:
                    body = json.loads(raw.decode("utf-8")) if raw else {}
                except (UnicodeError, json.JSONDecodeError) as error:
                    raise ServiceError(400, "invalid_json", "Request body must be valid UTF-8 JSON.") from error
            auth = self.headers.get("Authorization", "")
            token = auth[7:] if auth.startswith("Bearer ") else None
            status, response = self.server.service.request(
                self.command, parsed.path, body, token)
            self._send(status, response)
        except ServiceError as error:
            self._send(error.status, {"error": error.code, "message": str(error)})
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as error:
            self._send(500, {"error": "internal_error", "message": "Local service request failed."})
            if os.environ.get("BATTLEMONSTER_SERVICE_LOG"):
                raise error

    do_GET = _handle
    do_POST = _handle
    do_PUT = _handle
    do_DELETE = _handle


def main() -> None:
    default_data_dir = Path(os.environ.get("LOCALAPPDATA", Path.home() / ".local" / "share")) \
        / "BattleMonster" / "local-service"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1",
                        help="must be a loopback address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--data-dir", type=Path, default=default_data_dir)
    args = parser.parse_args()
    if args.host not in ["127.0.0.1", "::1", "localhost"]:
        parser.error("this service is loopback-only; use 127.0.0.1 or ::1")
    if not 0 <= args.port <= 65535:
        parser.error("port must be in range 0-65535")
    service = LocalService(args.data_dir)
    server = LocalServiceServer((args.host, args.port), service)
    print(f"BattleMonster local service listening at http://{args.host}:{server.server_port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
