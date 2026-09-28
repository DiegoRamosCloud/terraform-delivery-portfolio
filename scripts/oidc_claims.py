"""Print only diagnostic claims, never the JWT or the request bearer token."""
import base64
import json
import os
import urllib.parse
import urllib.request


def main():
    url = urllib.parse.urlsplit(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"])
    query = urllib.parse.parse_qsl(url.query)
    query.append(("audience", "sts.amazonaws.com"))
    request = urllib.request.Request(
        urllib.parse.urlunsplit(url._replace(query=urllib.parse.urlencode(query))),
        headers={"Authorization": f"Bearer {os.environ['ACTIONS_ID_TOKEN_REQUEST_TOKEN']}"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.load(response)["value"]
    encoded = token.split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    print(json.dumps({key: claims.get(key) for key in
                      ["sub", "aud", "repository", "repository_id", "repository_owner_id", "ref", "environment"]}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        raise SystemExit("Could not inspect OIDC claims; check id-token permission and environment.") from None
