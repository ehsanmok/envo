# envo

[![CI](https://github.com/ehsanmok/envo/actions/workflows/ci.yml/badge.svg)](https://github.com/ehsanmok/envo/actions)
[![Docs](https://github.com/ehsanmok/envo/actions/workflows/docs.yaml/badge.svg)](https://ehsanmok.github.io/envo)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Typed config loading from env vars, TOML, and CLI for Mojo.

`envo` composes [`morph`](https://github.com/ehsanmok/morph)'s TOML and
CLI parsing with a single libc `getenv(3)` FFI call to give you layered,
typed configuration with zero boilerplate.

## Precedence

```
CLI args   --port 9090      (highest)
env vars   PORT=9090
TOML file  port = 8080      (lowest)
```

## Quick Start

```mojo
from envo import load_config

@fieldwise_init
struct ServerConfig(Defaultable, Movable):
    var host: String
    var port: Int
    var debug: Bool
    def __init__(out self):
        self.host = "localhost"
        self.port = 8080
        self.debug = False

var cfg = load_config[ServerConfig]("config.toml")
# PORT=9090 in environment -> cfg.port == 9090
# --debug on CLI -> cfg.debug == True
```

With explicit CLI args:

```mojo
var cfg = load_config[ServerConfig]("config.toml", args=argv())
```

Low-level env var access:

```mojo
from envo import getenv, getenv_or

var home = getenv("HOME")             # Optional[String]
var port = getenv_or("PORT", "8080") # String
```

## Installation

```toml
# pixi.toml
[dependencies]
envo = { git = "https://github.com/ehsanmok/envo.git", tag = "v0.1.0" }
```

For the latest development version:

```toml
[dependencies]
envo = { git = "https://github.com/ehsanmok/envo.git", branch = "main" }
```

## Field name mapping

| Struct field | Env var    | CLI flag      |
|------------- |----------- |-------------- |
| `host`       | `HOST`     | `--host`      |
| `db_url`     | `DB_URL`   | `--db-url`    |
| `max_conns`  | `MAX_CONNS`| `--max-conns` |

## Supported field types

`String`, `Int`, `Int64`, `Bool`, `Float64`, `Float32`,
`Optional[String]`, `Optional[Int]`, `Optional[Float64]`, `Optional[Bool]`,
`List[String]`, `List[Int]`

Full API reference: [ehsanmok.github.io/envo](https://ehsanmok.github.io/envo)

## Development

```bash
pixi run tests     # run all tests
pixi run example   # run example
pixi run bench     # run benchmarks
pixi run -e dev docs  # build and open docs
```

## License

[MIT](LICENSE)
