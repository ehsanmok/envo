"""envo usage examples -- layered typed config loading."""

from envo import load_config, getenv, getenv_or


# ---------------------------------------------------------------------------
# Config struct definition
# ---------------------------------------------------------------------------


@fieldwise_init
struct ServerConfig(Defaultable, Movable, Writable):
    """Server configuration loaded from TOML, env vars, and CLI."""

    var host: String
    var port: Int
    var debug: Bool
    var max_conns: Int
    var db_url: String

    def __init__(out self):
        self.host = "localhost"
        self.port = 8080
        self.debug = False
        self.max_conns = 100
        self.db_url = "postgres://localhost/mydb"

    def write_to[W: Writer](self, mut writer: W):
        writer.write(
            "ServerConfig { host=",
            self.host,
            ", port=",
            self.port,
            ", debug=",
            self.debug,
            ", max_conns=",
            self.max_conns,
            ", db_url=",
            self.db_url,
            " }",
        )


def main() raises:
    # --- 1. Raw env var access -------------------------------------------
    print("=== Raw env var access ===")
    var home = getenv("HOME")
    if home:
        print("HOME =", home.value())
    else:
        print("HOME not set")

    var port_str = getenv_or("PORT", "8080")
    print("PORT (or default) =", port_str)

    # --- 2. Load from TOML (base) ----------------------------------------
    print("\n=== Load from TOML file ===")
    var toml_content = """host = "db.internal"
port = 5432
debug = false
max_conns = 50
db_url = "postgres://db.internal/prod"
"""
    with open("/tmp/envo_example.toml", "w") as f:
        f.write(toml_content)

    var cfg = load_config[ServerConfig]("/tmp/envo_example.toml")
    print("From TOML:", cfg)

    # --- 3. Env var overrides (simulated by CLI args instead, since we  ---
    #        cannot reliably setenv in examples without FFI imports)       ---
    print("\n=== CLI argument overrides ===")
    var args = List[String]()
    args.append("--host")
    args.append("api.prod.example.com")
    args.append("--port")
    args.append("443")
    args.append("--debug")

    var cfg2 = load_config[ServerConfig]("/tmp/envo_example.toml", args=args)
    print("After CLI overrides:", cfg2)

    # --- 4. Precedence summary -------------------------------------------
    print(
        "\nPrecedence (highest to lowest): CLI > env vars > TOML file > struct"
        " defaults"
    )
