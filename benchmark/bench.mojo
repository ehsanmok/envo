"""Throughput benchmarks for envo -- config loading operations."""

from std.benchmark import Bench, BenchConfig, BenchId, Bencher, keep
from std.ffi import external_call
from envo import load_config, getenv, getenv_or


@fieldwise_init
struct BenchConfig_(Defaultable, Movable):
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


def _setenv(name: String, value: String) -> Int:
    return external_call["setenv", Int](
        name.unsafe_ptr(), value.unsafe_ptr(), 1
    )


def _unsetenv(name: String) -> Int:
    return external_call["unsetenv", Int](name.unsafe_ptr())


def bench_getenv(mut bencher: Bencher) capturing raises:
    @always_inline
    @parameter
    def call() raises:
        var v = getenv("PATH")
        keep(v.__bool__())

    bencher.iter[call]()


def bench_getenv_or(mut bencher: Bencher) capturing raises:
    @always_inline
    @parameter
    def call() raises:
        var v = getenv_or("__ENVO_BENCH_MISSING__", "default")
        keep(v.byte_length())

    bencher.iter[call]()


def bench_load_config_toml_only(mut bencher: Bencher) capturing raises:
    @always_inline
    @parameter
    def call() raises:
        var cfg = load_config[BenchConfig_]("/tmp/envo_bench.toml")
        keep(cfg.port)

    bencher.iter[call]()


def bench_load_config_with_env(mut bencher: Bencher) capturing raises:
    _ = _setenv("PORT", "9090")

    @always_inline
    @parameter
    def call() raises:
        var cfg = load_config[BenchConfig_]("/tmp/envo_bench.toml")
        keep(cfg.port)

    bencher.iter[call]()
    _ = _unsetenv("PORT")


def bench_load_config_with_cli(mut bencher: Bencher) capturing raises:
    # ponytail: build args fresh per call rather than capturing+copying a
    # shared outer List[String] -- the latter crashes inside Bencher.iter's
    # hot loop (reproduced in isolation outside the harness it does not).
    @always_inline
    @parameter
    def call() raises:
        var args = List[String]()
        args.append("--port")
        args.append("7777")
        var cfg = load_config[BenchConfig_]("/tmp/envo_bench.toml", args=args^)
        keep(cfg.port)

    bencher.iter[call]()


def main() raises:
    # Write a benchmark TOML fixture
    var toml = (
        'host = "localhost"\nport = 8080\ndebug = false\nmax_conns ='
        ' 100\ndb_url = "postgres://localhost/mydb"\n'
    )
    with open("/tmp/envo_bench.toml", "w") as f:
        f.write(toml)

    var config = BenchConfig(max_iters=100_000)
    var bench = Bench(config^)

    bench.bench_function[bench_getenv](BenchId("getenv (PATH)"))
    bench.bench_function[bench_getenv_or](
        BenchId("getenv_or (missing -> default)")
    )
    bench.bench_function[bench_load_config_toml_only](
        BenchId("load_config (TOML only)")
    )
    bench.bench_function[bench_load_config_with_env](
        BenchId("load_config (TOML + env override)")
    )
    bench.bench_function[bench_load_config_with_cli](
        BenchId("load_config (TOML + env + CLI override)")
    )

    bench.dump_report()
