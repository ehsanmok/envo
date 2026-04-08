"""Throughput benchmarks for envo -- config loading operations."""

from std.benchmark import Bench, BenchConfig, BenchId, Bencher, keep
from std.ffi import external_call
from envo import load_config, getenv, getenv_or
from envo.loader import _read_file, _apply_env_overrides, _apply_cli_overrides


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


fn _setenv(name: String, value: String) -> Int:
    return external_call["setenv", Int](
        name.unsafe_cstr_ptr(), value.unsafe_cstr_ptr(), 1
    )


fn _unsetenv(name: String) -> Int:
    return external_call["unsetenv", Int](name.unsafe_cstr_ptr())


@parameter
fn bench_getenv(mut bencher: Bencher) raises:
    @always_inline
    @parameter
    fn call() raises:
        var v = getenv("PATH")
        keep(v.__bool__())

    bencher.iter[call]()


@parameter
fn bench_getenv_or(mut bencher: Bencher) raises:
    @always_inline
    @parameter
    fn call() raises:
        var v = getenv_or("__ENVO_BENCH_MISSING__", "default")
        keep(len(v))

    bencher.iter[call]()


@parameter
fn bench_load_config_toml_only(mut bencher: Bencher) raises:
    @always_inline
    @parameter
    fn call() raises:
        var cfg = load_config[BenchConfig_]("/tmp/envo_bench.toml")
        keep(cfg.port)

    bencher.iter[call]()


@parameter
fn bench_load_config_with_env(mut bencher: Bencher) raises:
    _ = _setenv("PORT", "9090")

    @always_inline
    @parameter
    fn call() raises:
        var cfg = load_config[BenchConfig_]("/tmp/envo_bench.toml")
        keep(cfg.port)

    bencher.iter[call]()
    _ = _unsetenv("PORT")


@parameter
fn bench_load_config_with_cli(mut bencher: Bencher) raises:
    var args = List[String]()
    args.append("--port")
    args.append("7777")

    @always_inline
    @parameter
    fn call() raises:
        var cfg = load_config[BenchConfig_](
            "/tmp/envo_bench.toml", args=args
        )
        keep(cfg.port)

    bencher.iter[call]()


def main() raises:
    # Write a benchmark TOML fixture
    var toml = (
        'host = "localhost"\nport = 8080\ndebug = false\nmax_conns = 100\ndb_url'
        ' = "postgres://localhost/mydb"\n'
    )
    with open("/tmp/envo_bench.toml", "w") as f:
        f.write(toml)

    var config = BenchConfig(max_iters=100_000)
    var bench = Bench(config)

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
