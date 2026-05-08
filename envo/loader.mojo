"""Layered config loading: TOML file, env vars, and CLI arguments.

Loads a struct ``T`` by merging three sources in increasing priority order:

1. **TOML file** (lowest) -- ``from_toml[T](path)`` via morph.
2. **Environment variables** -- field ``my_field`` maps to env var ``MY_FIELD``.
3. **CLI arguments** (highest) -- ``--my-field value`` flags via morph.

Example:

    from envo.loader import load_config

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
            self.max_conns = 100
            self.db_url = ""

    # Load from file; env PORT=9090 overrides port; --host 0.0.0.0 overrides host
    var cfg = load_config[ServerConfig]("config.toml")
    var cfg2 = load_config[ServerConfig]("config.toml", args=argv())
"""

from std.builtin.rebind import trait_downcast
from morph.reflect import (
    _Base,
    Morphable,
    INT_NAME,
    INT64_NAME,
    BOOL_NAME,
    STRING_NAME,
    FLOAT64_NAME,
    FLOAT32_NAME,
    OPT_INT_NAME,
    OPT_STRING_NAME,
    OPT_FLOAT64_NAME,
    OPT_BOOL_NAME,
    LIST_INT_NAME,
    LIST_STRING_NAME,
    LIST_FLOAT64_NAME,
    LIST_BOOL_NAME,
)
from morph.toml import from_toml
from envo.env import getenv


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def load_config[
    T: Morphable
](toml_path: String, args: Optional[List[String]] = None) raises -> T:
    """Load config struct ``T`` from a TOML file with optional overrides.

    Merges three sources with increasing priority:

    1. TOML file at ``toml_path`` (base values).
    2. Environment variables matching ``FIELD_NAME`` (uppercase field names).
    3. CLI args ``--field-name value`` in ``args``, if provided.

    Parameters:
        T: A ``Morphable`` (``Defaultable & Movable``) struct type.

    Args:
        toml_path: Path to the TOML config file.
        args: Optional CLI argument list (without the program name).

    Returns:
        A populated instance of ``T`` with all layers applied.

    Raises:
        Error: If the file cannot be read, the TOML is malformed, or a
            CLI flag is unknown or missing its value.
    """
    var toml_str = _read_file(toml_path)
    var cfg = from_toml[T](toml_str)

    # --- Layer 2: environment variables ----------------------------------
    comptime count = reflect[T]().field_count()
    comptime names = reflect[T]().field_names()
    comptime types = reflect[T]().field_types()

    comptime
    for idx in range(count):
        comptime field_name = names[idx]
        comptime field_type = types[idx]
        comptime type_name = reflect[field_type]().name()

        var env_name = String(field_name).upper()
        var env_val = getenv(env_name)
        if env_val:
            var raw = env_val.value()
            ref field = trait_downcast[_Base](reflect[T]().field_ref[idx](cfg))
            var ptr = UnsafePointer(to=field)

            comptime
            if type_name == STRING_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[String]().init_pointee_move(raw)
            elif type_name == INT_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[Int]().init_pointee_move(atol(raw))
            elif type_name == INT64_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[Int64]().init_pointee_move(Int64(atol(raw)))
            elif type_name == FLOAT64_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[Float64]().init_pointee_move(atof(raw))
            elif type_name == FLOAT32_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[Float32]().init_pointee_move(Float32(atof(raw)))
            elif type_name == BOOL_NAME:
                var bval = raw.lower() == "true" or raw == "1"
                ptr.destroy_pointee()
                ptr.bitcast[Bool]().init_pointee_move(bval)
            elif type_name == OPT_STRING_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[Optional[String]]().init_pointee_move(raw)
            elif type_name == OPT_INT_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[Optional[Int]]().init_pointee_move(atol(raw))
            elif type_name == OPT_FLOAT64_NAME:
                ptr.destroy_pointee()
                ptr.bitcast[Optional[Float64]]().init_pointee_move(atof(raw))
            elif type_name == OPT_BOOL_NAME:
                var bval = raw.lower() == "true" or raw == "1"
                ptr.destroy_pointee()
                ptr.bitcast[Optional[Bool]]().init_pointee_move(bval)

    # --- Layer 3: CLI arguments ------------------------------------------
    if args:
        var cli_args = args.value().copy()
        var i = 0
        while i < len(cli_args):
            var arg = cli_args[i]
            var is_long = arg.startswith("--")
            var is_short = (
                not is_long and arg.startswith("-") and len(arg) == 2
            )

            if not is_long and not is_short:
                raise Error("Expected --flag or -x, got: " + arg)

            var flag: String
            if is_long:
                flag = String(arg.removeprefix("--"))
            else:
                flag = String(arg.removeprefix("-"))

            var matched = False

            comptime
            for idx in range(count):
                comptime field_name = names[idx]
                comptime field_type = types[idx]
                comptime type_name = reflect[field_type]().name()

                var cli_name = String(field_name).replace("_", "-")
                var fn_bytes = String(field_name).as_bytes()
                var short_name = chr(Int(fn_bytes[0]))
                if flag == cli_name or (is_short and flag == short_name):
                    matched = True
                    ref field = trait_downcast[_Base](
                        reflect[T]().field_ref[idx](cfg)
                    )
                    var ptr = UnsafePointer(to=field)

                    comptime
                    if type_name == BOOL_NAME:
                        ptr.destroy_pointee()
                        ptr.bitcast[Bool]().init_pointee_move(True)
                    elif type_name == OPT_BOOL_NAME:
                        ptr.destroy_pointee()
                        ptr.bitcast[Optional[Bool]]().init_pointee_move(True)
                    elif type_name == INT_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        var val = atol(cli_args[i])
                        ptr.destroy_pointee()
                        ptr.bitcast[Int]().init_pointee_move(val)
                    elif type_name == OPT_INT_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        var val = atol(cli_args[i])
                        ptr.destroy_pointee()
                        ptr.bitcast[Optional[Int]]().init_pointee_move(val)
                    elif type_name == INT64_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        var val = Int64(atol(cli_args[i]))
                        ptr.destroy_pointee()
                        ptr.bitcast[Int64]().init_pointee_move(val)
                    elif type_name == FLOAT64_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        var val = atof(cli_args[i])
                        ptr.destroy_pointee()
                        ptr.bitcast[Float64]().init_pointee_move(val)
                    elif type_name == OPT_FLOAT64_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        var val = atof(cli_args[i])
                        ptr.destroy_pointee()
                        ptr.bitcast[Optional[Float64]]().init_pointee_move(val)
                    elif type_name == STRING_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        ptr.destroy_pointee()
                        ptr.bitcast[String]().init_pointee_move(cli_args[i])
                    elif type_name == OPT_STRING_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        ptr.destroy_pointee()
                        ptr.bitcast[Optional[String]]().init_pointee_move(
                            cli_args[i]
                        )
                    elif type_name == LIST_STRING_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        var slices = cli_args[i].split(",")
                        var str_list = List[String]()
                        for si in range(len(slices)):
                            str_list.append(String(slices[si]))
                        ptr.destroy_pointee()
                        ptr.bitcast[List[String]]().init_pointee_move(
                            str_list^
                        )
                    elif type_name == LIST_INT_NAME:
                        i += 1
                        if i >= len(cli_args):
                            raise Error("Missing value for --" + cli_name)
                        var slices = cli_args[i].split(",")
                        var int_list = List[Int]()
                        for si in range(len(slices)):
                            int_list.append(atol(String(slices[si])))
                        ptr.destroy_pointee()
                        ptr.bitcast[List[Int]]().init_pointee_move(int_list^)

            if not matched:
                raise Error("Unknown flag: --" + flag)

            i += 1

    return cfg^


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _read_file(path: String) raises -> String:
    """Read an entire file and return its contents as a ``String``.

    Args:
        path: File system path to read.

    Returns:
        UTF-8 file contents.

    Raises:
        Error: If the file does not exist or cannot be read.
    """
    with open(path, "r") as f:
        return f.read()
