"""Read-only public deployment probes; never authenticate, invoke chat, or emit keys."""
import datetime
import hashlib
import json
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def probe(url, kind):
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=20) as response:
            body = response.read(2_000_001)
            result = {"url": url, "status": response.status,
                      "content_type": response.headers.get("Content-Type"),
                      "body_sha256": hashlib.sha256(body).hexdigest()}
            if len(body) > 2_000_000:
                result["outcome"] = "body_limit_exceeded"
                return result
            data = json.loads(body)
            if kind == "firebase_init":
                result["public_project_id"] = data.get("projectId")
                result["public_auth_domain"] = data.get("authDomain")
            elif kind == "health":
                result["health"] = {key: data[key] for key in
                                    ("status", "version", "model_loaded") if key in data}
            else:
                result["openapi"] = data.get("openapi")
                result["title"] = data.get("info", {}).get("title")
                result["version"] = data.get("info", {}).get("version")
                result["operations"] = {
                    path: {verb: {"operation_id": op.get("operationId"),
                                  "security": op.get("security", data.get("security", [])),
                                  "response_media": {code: sorted(reply.get("content", {}))
                                                     for code, reply in op.get("responses", {}).items()}}
                           for verb, op in methods.items() if verb in ("get", "post")}
                    for path, methods in data.get("paths", {}).items()}
                # Public schema only. No runtime request/response, auth headers, or credentials.
                result["schemas"] = data.get("components", {}).get("schemas", {})
            return result
    except urllib.error.HTTPError as error:
        return {"url": url, "status": error.code, "outcome": "http_error_no_body_recorded"}
    except Exception as error:
        return {"url": url, "outcome": "unverified", "error_type": type(error).__name__}


def main():
    values = {}
    for line in Path(".env.local").read_text(encoding="utf-8-sig").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("\"").strip("'")
    project = values.get("NEXT_PUBLIC_FIREBASE_PROJECT_ID", "")
    base = values.get("NEXT_PUBLIC_KOI_API_BASE", "").rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != "https" or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Public backend URL is not safe for a read-only probe")
    if not project or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in project):
        raise ValueError("Invalid public project ID")
    result = {"observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "Unauthenticated GET only; no chat POST, Firebase account creation, writes or deployment",
              "local_public_configuration": {key: values.get(key) for key in
                  ("NEXT_PUBLIC_FIREBASE_PROJECT_ID", "NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN",
                   "NEXT_PUBLIC_KOI_API_BASE", "NEXT_PUBLIC_KOI_LOCAL_TEST_ANON")},
              "probes": [probe(base + "/health", "health"),
                         probe(base + "/openapi.json", "openapi"),
                         probe("https://" + project + ".web.app/__/firebase/init.json", "firebase_init")]}
    target = Path("review/web-0.5/deployment-evidence.json")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"saved": str(target), "probes": [
        {key: value for key, value in item.items() if key != "schemas"} for item in result["probes"]]}, indent=2))


if __name__ == "__main__":
    main()
