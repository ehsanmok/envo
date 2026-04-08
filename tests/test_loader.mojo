"""Tests for envo.loader -- load_config with layered precedence."""

from std.testing import assert_equal, assert_true, assert_false
from std.ffi import external_call
from envo.loader import load_config, _read_file


# ---------------------------------------------------------------------------
# Test struct fixtures
# ---------------------------------------------------------------------------


@fieldwise_init
struct ServerConfig(Defaultable, Movable):
    var host: String
    var port: Int
    var debug: Bool
    var max_conns: Int
    var db_url: String

    def __init__(out self):
        self.host = "localhost"
        self.port = 8080
        self.debug = False
        self.max_conns = 10
        self.db_url = ""


@fieldwise_init
struct MinimalConfig(Defaultable, Movable):
    var name: String
    var count: Int

    def __init__(out self):
        self.name = ""
        self.count = 0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _setenv(name: String, value: String) -> Int:
    """Set an env var for test isolation (POSIX setenv)."""
    return external_call["setenv", Int](name.unsafe_ptr(), value.unsafe_ptr(), 1)


def _unsetenv(name: String) -> Int:
    """Unset an env var after a test."""
    return external_call["unsetenv", Int](name.unsafe_ptr())


# ---------------------------------------------------------------------------
# _read_file tests
# ---------------------------------------------------------------------------


def test_read_file_contents() raises:
    var content = _read_file("tests/fixtures/server.toml")
    assert_true(len(content) > 0, "_read_file must return non-empty string")
    assert_true(
        "host" in content, "_read_file must contain 'host'"
    )


def test_read_file_missing() raises:
    var raised = False
    try:
        _ = _read_file("tests/fixtures/nonexistent.toml")
    except:
        raised = True
    assert_true(raised, "reading missing file must raise")


# ---------------------------------------------------------------------------
# TOML base loading
# ---------------------------------------------------------------------------


def test_load_toml_base() raises:
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    assert_equal(cfg.host, "localhost")
    assert_equal(cfg.port, 8080)
    assert_false(cfg.debug, "debug must be false from TOML")
    assert_equal(cfg.max_conns, 100)
    assert_equal(cfg.db_url, "postgres://localhost/mydb")


# ---------------------------------------------------------------------------
# Env var override tests
# ---------------------------------------------------------------------------


def test_env_overrides_string_field() raises:
    _ = _setenv("HOST", "0.0.0.0")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("HOST")
    assert_equal(cfg.host, "0.0.0.0")


def test_env_overrides_int_field() raises:
    _ = _setenv("PORT", "9090")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("PORT")
    assert_equal(cfg.port, 9090)


def test_env_overrides_bool_field_true() raises:
    _ = _setenv("DEBUG", "true")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("DEBUG")
    assert_true(cfg.debug, "DEBUG=true must set debug to True")


def test_env_overrides_bool_field_1() raises:
    _ = _setenv("DEBUG", "1")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("DEBUG")
    assert_true(cfg.debug, "DEBUG=1 must set debug to True")


def test_env_overrides_bool_field_false() raises:
    _ = _setenv("DEBUG", "false")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("DEBUG")
    assert_false(cfg.debug, "DEBUG=false must keep debug False")


def test_env_overrides_multiple_fields() raises:
    _ = _setenv("HOST", "db.internal")
    _ = _setenv("PORT", "5432")
    _ = _setenv("MAX_CONNS", "50")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("HOST")
    _ = _unsetenv("PORT")
    _ = _unsetenv("MAX_CONNS")
    assert_equal(cfg.host, "db.internal")
    assert_equal(cfg.port, 5432)
    assert_equal(cfg.max_conns, 50)


def test_env_does_not_affect_unset_fields() raises:
    # Only PORT is set; other fields must keep TOML values
    _ = _setenv("PORT", "9999")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("PORT")
    assert_equal(cfg.port, 9999)
    assert_equal(cfg.host, "localhost")
    assert_equal(cfg.max_conns, 100)


# ---------------------------------------------------------------------------
# CLI override tests
# ---------------------------------------------------------------------------


def test_cli_overrides_string_field() raises:
    var args = List[String]()
    args.append("--host")
    args.append("api.example.com")
    var cfg = load_config[ServerConfig](
        "tests/fixtures/server.toml", args=args.copy()
    )
    assert_equal(cfg.host, "api.example.com")
    assert_equal(cfg.port, 8080)  # unchanged from TOML


def test_cli_overrides_int_field() raises:
    var args = List[String]()
    args.append("--port")
    args.append("7070")
    var cfg = load_config[ServerConfig](
        "tests/fixtures/server.toml", args=args.copy()
    )
    assert_equal(cfg.port, 7070)


def test_cli_overrides_bool_flag() raises:
    var args = List[String]()
    args.append("--debug")
    var cfg = load_config[ServerConfig](
        "tests/fixtures/server.toml", args=args.copy()
    )
    assert_true(cfg.debug, "--debug flag must enable debug")


def test_cli_overrides_multiple_fields() raises:
    var args = List[String]()
    args.append("--host")
    args.append("prod.example.com")
    args.append("--port")
    args.append("443")
    args.append("--debug")
    var cfg = load_config[ServerConfig](
        "tests/fixtures/server.toml", args=args.copy()
    )
    assert_equal(cfg.host, "prod.example.com")
    assert_equal(cfg.port, 443)
    assert_true(cfg.debug, "debug must be enabled via CLI")


def test_cli_unknown_flag_raises() raises:
    var args = List[String]()
    args.append("--nonexistent-flag")
    var raised = False
    try:
        _ = load_config[ServerConfig](
            "tests/fixtures/server.toml", args=args.copy()
        )
    except:
        raised = True
    assert_true(raised, "unknown CLI flag must raise")


# ---------------------------------------------------------------------------
# Precedence tests
# ---------------------------------------------------------------------------


def test_env_beats_toml() raises:
    # TOML has port=8080; env sets PORT=9000; result must be 9000
    _ = _setenv("PORT", "9000")
    var cfg = load_config[ServerConfig]("tests/fixtures/server.toml")
    _ = _unsetenv("PORT")
    assert_equal(cfg.port, 9000)


def test_cli_beats_env() raises:
    # Env sets PORT=9000; CLI sets --port 7777; result must be 7777
    _ = _setenv("PORT", "9000")
    var args = List[String]()
    args.append("--port")
    args.append("7777")
    var cfg = load_config[ServerConfig](
        "tests/fixtures/server.toml", args=args.copy()
    )
    _ = _unsetenv("PORT")
    assert_equal(cfg.port, 7777)


def test_cli_beats_toml_env_unchanged() raises:
    # TOML host=localhost; env HOST=env.host; CLI --host cli.host -> cli.host
    _ = _setenv("HOST", "env.host")
    var args = List[String]()
    args.append("--host")
    args.append("cli.host")
    var cfg = load_config[ServerConfig](
        "tests/fixtures/server.toml", args=args.copy()
    )
    _ = _unsetenv("HOST")
    assert_equal(cfg.host, "cli.host")


# ---------------------------------------------------------------------------
# Minimal struct tests
# ---------------------------------------------------------------------------


def test_minimal_config_toml() raises:
    var toml = "name = \"Alice\"\ncount = 42\n"
    with open("/tmp/envo_test_minimal.toml", "w") as f:
        f.write(toml)
    var cfg = load_config[MinimalConfig]("/tmp/envo_test_minimal.toml")
    assert_equal(cfg.name, "Alice")
    assert_equal(cfg.count, 42)


def test_minimal_config_env_override() raises:
    var toml = "name = \"Alice\"\ncount = 42\n"
    with open("/tmp/envo_test_minimal2.toml", "w") as f:
        f.write(toml)
    _ = _setenv("NAME", "Bob")
    _ = _setenv("COUNT", "99")
    var cfg = load_config[MinimalConfig]("/tmp/envo_test_minimal2.toml")
    _ = _unsetenv("NAME")
    _ = _unsetenv("COUNT")
    assert_equal(cfg.name, "Bob")
    assert_equal(cfg.count, 99)


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------


def main() raises:
    test_read_file_contents()
    test_read_file_missing()
    test_load_toml_base()
    test_env_overrides_string_field()
    test_env_overrides_int_field()
    test_env_overrides_bool_field_true()
    test_env_overrides_bool_field_1()
    test_env_overrides_bool_field_false()
    test_env_overrides_multiple_fields()
    test_env_does_not_affect_unset_fields()
    test_cli_overrides_string_field()
    test_cli_overrides_int_field()
    test_cli_overrides_bool_flag()
    test_cli_overrides_multiple_fields()
    test_cli_unknown_flag_raises()
    test_env_beats_toml()
    test_cli_beats_env()
    test_cli_beats_toml_env_unchanged()
    test_minimal_config_toml()
    test_minimal_config_env_override()
    print("All loader tests passed.")
