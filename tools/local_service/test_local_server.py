import http.client
import json
import tempfile
import threading
import time
import unittest
from pathlib import Path
from local_server import LocalService, LocalServiceServer


class LocalServiceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.service = LocalService(Path(cls.temporary.name))
        cls.server = LocalServiceServer(("127.0.0.1", 0), cls.service)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)
        cls.temporary.cleanup()

    def request(self, method, path, body=None, token=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        headers = {}
        encoded = None
        if body is not None:
            encoded = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = "Bearer " + token
        connection.request(method, "/api/v1" + path, encoded, headers)
        response = connection.getresponse()
        result = json.loads(response.read())
        status = response.status
        connection.close()
        return status, result

    def register(self, username):
        status, response = self.request("POST", "/auth/register",
                                        {"username": username, "password": "safe-test-pass"})
        self.assertEqual(status, 201)
        return response["token"]

    def test_health_and_capabilities_are_explicit_about_disabled_real_services(self):
        self.assertEqual(self.request("GET", "/health")[0], 200)
        _, capabilities = self.request("GET", "/capabilities")
        self.assertEqual(capabilities["sms"], "disabled")
        self.assertEqual(capabilities["payment"], "simulated-only")
        self.assertIn("battle-lobbies", capabilities["features"])
        self.assertIn("friends", capabilities["features"])

    def test_native_time_request_requires_no_account_and_does_not_mutate_state(self):
        snapshot = json.dumps(self.service.state, sort_keys=True)
        status, response = self.request("GET", "/time")
        self.assertEqual(status, 200)
        self.assertIsInstance(response["server_time"], int)
        self.assertLessEqual(abs(response["server_time"] - int(time.time())), 2)
        self.assertEqual(json.dumps(self.service.state, sort_keys=True), snapshot)

    def test_authentication_and_accounts_are_isolated(self):
        alice = self.register("alice")
        bob = self.register("bob")
        self.assertEqual(self.request("GET", "/profile")[0], 401)
        self.assertEqual(self.request("GET", "/profile", token=bob)[1]["username"], "bob")
        self.assertEqual(self.request("PUT", "/saves/0", {"save": {"secret": 1}},
                                      token=alice)[0], 200)
        self.assertEqual(self.request("GET", "/saves/0", token=bob)[0], 404)
        self.assertEqual(self.request("POST", "/auth/login",
                                      {"username": "alice", "password": "wrong"})[0], 401)
        self.assertEqual(self.request("POST", "/auth/register",
                                      {"username": "ALICE", "password": "safe-test-pass"})[0], 409)

    def test_save_slots_validate_range_and_survive_service_restart(self):
        token = self.register("saver")
        self.assertEqual(self.request("PUT", "/saves/2", {"save": {}}, token)[0], 400)
        self.assertEqual(self.request("PUT", "/saves/0", {"save": {"version": 1}}, token)[0], 200)
        replacement = LocalService(Path(self.temporary.name))
        login_status, login = replacement.request("POST", "/auth/login", {
            "username": "saver", "password": "safe-test-pass",
        }, None)
        self.assertEqual(login_status, 200)
        _, result = replacement.request("GET", "/saves/0", {}, login["token"])
        self.assertEqual(result["save"]["data"], {"version": 1})

    def test_mail_is_private_and_claimable(self):
        sender, recipient = self.register("sender"), self.register("recipient")
        _, sent = self.request("POST", "/mail", {
            "recipient": "recipient", "message": "A test gift",
            "gift": {"monster": {"species": 2}},
        }, sender)
        mail_id = sent["message"]["id"]
        self.assertEqual(self.request("POST", f"/mail/{mail_id}", token=recipient)[0], 200)
        self.assertEqual(self.request("GET", "/mail", token=recipient)[1]["messages"][0]["claimed"], True)
        self.assertEqual(self.request("POST", f"/mail/{mail_id}", token=sender)[0], 404)

    def test_market_ownership_purchase_and_mail_delivery(self):
        seller, buyer = self.register("seller"), self.register("buyer")
        _, created = self.request("POST", "/market",
                                  {"monster": {"species": 4}, "price": 25}, seller)
        listing_id = created["listing"]["id"]
        self.assertEqual(self.request("DELETE", f"/market/{listing_id}", token=buyer)[0], 403)
        status, rejected = self.request("POST", f"/market/{listing_id}:buy", token=buyer)
        self.assertEqual(status, 409)
        self.assertEqual(rejected["error"], "insufficient_funds")
        self.assertEqual(self.request("GET", "/market", token=buyer)[1]["listings"][0]["status"],
                         "active")
        self.assertEqual(self.request("GET", "/cash", token=buyer)[1]["balance"], 0)
        self.assertEqual(self.request("GET", "/cash", token=seller)[1]["balance"], 0)
        self.assertEqual(self.request("POST", "/cash/test-credit", {
            "amount": 25, "confirm_simulation": True,
        }, buyer)[0], 201)
        self.assertEqual(self.request("POST", f"/market/{listing_id}:buy", token=buyer)[0], 200)
        self.assertEqual(self.request("GET", "/cash", token=seller)[1]["balance"], 25)
        self.assertEqual(self.request("GET", "/cash", token=buyer)[1]["balance"], 0)
        self.assertEqual(self.request("GET", "/cash", token=buyer)[1]["ledger"][1]["kind"],
                         "market-purchase")
        self.assertEqual(self.request("GET", "/mail", token=buyer)[1]["messages"][0]["gift"],
                         {"monster": {"species": 4}})
        self.assertEqual(self.request("POST", f"/market/{listing_id}:buy", token=buyer)[0], 409)

    def test_island_visits_and_likes_are_scoped_and_persisted(self):
        island_owner, visitor = self.register("islander"), self.register("visitor")
        self.assertEqual(self.request("PUT", "/island", {"snapshot": {"map": "local"}}, island_owner)[0], 200)
        self.assertEqual(self.request("GET", "/islands", token=visitor)[1]["islands"][0]["username"],
                         "islander")
        _, visit = self.request("GET", "/islands/islander", token=visitor)
        self.assertEqual(visit["snapshot"], {"map": "local"})
        self.assertEqual(self.request("POST", "/islands/islander/like", token=visitor)[1]["likes"], 1)
        self.assertEqual(self.request("POST", "/islands/islander/like", token=visitor)[0], 409)
        self.assertEqual(self.request("POST", "/islands/islander/like", token=island_owner)[0], 400)
        self.assertEqual(self.request("GET", "/island/visits", token=island_owner)[1]["visits"][0]["username"],
                         "visitor")

    def test_rankings_battle_records_and_cash_simulation_safety(self):
        token = self.register("fighter")
        self.assertEqual(self.request("POST", "/battles/records",
                                      {"result": "win", "mode": "ranked"}, token)[0], 201)
        _, records = self.request("GET", "/battles/records", token=token)
        self.assertEqual(records["wins"], 1)
        self.assertEqual(records["ranking_basis"], "local-recorded-wins-losses")
        _, ranking = self.request("GET", "/ranking", token=token)
        fighter_rank = next(index + 1 for index, entry in enumerate(ranking["entries"])
                            if entry["username"] == "fighter")
        self.assertEqual(records["rank"], fighter_rank)
        self.assertEqual(self.request("POST", "/cash/purchase",
                                      {"amount": 5}, token)[0], 501)
        self.assertEqual(self.request("POST", "/cash/test-credit",
                                      {"amount": 50}, token)[0], 400)
        _, credit = self.request("POST", "/cash/test-credit", {
            "amount": 50, "confirm_simulation": True,
        }, token)
        self.assertTrue(credit["simulated"])
        self.assertEqual(self.request("GET", "/cash", token=token)[1]["balance"], 50)

    def test_local_friends_and_match_records(self):
        alice, bob = self.register("alice-battle"), self.register("bob-battle")
        status, friends = self.request("POST", "/friends", {"username": "bob-battle"}, alice)
        self.assertEqual(status, 201)
        self.assertEqual(friends["friends"], ["bob-battle"])
        self.assertEqual(self.request("POST", "/friends",
                                      {"username": "bob-battle"}, alice)[0], 409)
        status, created = self.request("POST", "/battles/matches", {
            "mode": "friendly", "opponent": "bob-battle",
        }, alice)
        self.assertEqual(status, 201)
        match_id = created["match"]["id"]
        self.assertTrue(created["simulation"])
        self.assertEqual(self.request("POST", f"/battles/matches/{match_id}",
                                      {"result": "win"}, alice)[0], 200)
        self.assertEqual(self.request("POST", f"/battles/matches/{match_id}",
                                      {"result": "loss"}, bob)[0], 200)
        self.assertEqual(self.request("GET", f"/battles/matches/{match_id}", token=bob)[1]
                         ["match"]["status"], "complete")

    def test_invalid_json_and_large_payload_are_rejected(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        connection.request("POST", "/api/v1/auth/register", b"{bad",
                           {"Content-Length": "4", "Content-Type": "application/json"})
        response = connection.getresponse()
        self.assertEqual(response.status, 400)
        response.read()
        connection.close()
        self.assertEqual(self.request("POST", "/auth/register",
                                      {"username": "bad/name", "password": "safe-test-pass"})[0], 400)


if __name__ == "__main__":
    unittest.main()
