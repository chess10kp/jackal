"""Stored-credential env hydration and logout (merged with auth_env.jac)."""

import os;
import json;
import tempfile;
import shutil;


def _with_agent_dir(creds: dict[str, any]) -> str {
    tmp_dir = tempfile.mkdtemp(prefix="jackal-auth-env-");
    fh = open(os.path.join(tmp_dir, "auth.json"), "w");
    fh.write(json.dumps(creds));
    fh.close();
    return tmp_dir;
}


test "hydrate exports stored keys and logout clears only those" {
    key_env = _key_env("openrouter");
    assert key_env;
    saved_dir = os.environ.get("JACKAL_AGENT_DIR");
    saved_key = os.environ.pop(key_env, None);
    tmp_dir = _with_agent_dir({"openrouter": {"type": "api_key", "key": "sk-test"}});
    os.environ["JACKAL_AGENT_DIR"] = tmp_dir;
    try {
        assert "openrouter" in hydrate_auth_environment();
        assert os.environ.get(key_env) == "sk-test";
        assert stored_providers() == ["openrouter"];
        assert logout_provider("openrouter") == "logged out of openrouter";
        assert key_env not in os.environ;
        assert stored_providers() == [];
        assert logout_provider("openrouter").startswith("no stored credential");
        assert logout_provider("not-a-provider").startswith("unknown provider");
        # A shell-exported key is never cleared by logout.
        os.environ[key_env] = "from-shell";
        assert "still set" in logout_provider("openrouter");
        assert os.environ.get(key_env) == "from-shell";
    } finally {
        os.environ.pop(key_env, None);
        if saved_key is not None { os.environ[key_env] = saved_key; }
        if saved_dir is None { os.environ.pop("JACKAL_AGENT_DIR", None); }
        else { os.environ["JACKAL_AGENT_DIR"] = saved_dir; }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
