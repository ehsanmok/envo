"""Typed config loading from env vars, TOML, and CLI for Mojo.

`envo` composes `morph`'s TOML and CLI parsing with a single libc
`getenv(3)` FFI call to give you layered, typed configuration with zero
boilerplate.

## Precedence (highest to lowest)

```
CLI args   --port 9090          highest
env vars   PORT=9090
TOML file  port = 8080          lowest
```

## Core API

```mojo
from envo import load_config, getenv, getenv_or

@fieldwise_init
struct ServerConfig(Defaultable, Movable):
    var host: String
    var port: Int
    var debug: Bool
    def __init__(out self):
        self.host = "localhost"
        self.port = 8080
        self.debug = False

# Load from file; PORT env var overrides port; --host overrides host
var cfg = load_config[ServerConfig]("config.toml")
var cfg2 = load_config[ServerConfig]("config.toml", args=argv())

# Low-level env var access
var home = getenv("HOME")        # Optional[String]
var port = getenv_or("PORT", "8080")  # String
```

## Field name mapping

| Struct field | Env var   | CLI flag      |
|------------- |---------- |-------------- |
| `host`       | `HOST`    | `--host`      |
| `db_url`     | `DB_URL`  | `--db-url`    |
| `max_conns`  | `MAX_CONNS` | `--max-conns` |

For API reference see <https://ehsanmok.github.io/envo>.
"""

from envo.loader import load_config
from envo.env import getenv, getenv_or
