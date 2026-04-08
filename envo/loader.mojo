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
        def __init__(out self):
            self.host = "localhost"
            self.port = 8080
            self.debug = False

    # Load from file; env PORT=9090 overrides port; --host 0.0.0.0 overrides host
    var cfg = load_config[ServerConfig]("config.toml")
    var cfg2 = load_config[ServerConfig]("config.toml", args=argv())
"""

from std.ffi import external_call
from std.reflection import (
    struct_field_count,
    struct_field_names,
    struct_field_types,
    get_type_name,
)
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
        A populated instance of ``T``.

    Raises:
        Error: If the file cannot be read, the TOML is malformed, or a
            CLI flag is unknown or missing its value.
    """
    var toml_str = _read_file(toml_path)
    var cfg = from_toml[T](toml_str)
    cfg = _apply_env_overrides(cfg^)
    if args:
        cfg = _apply_cli_overrides(cfg^, args.value())
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
    var result = String()
    with open(path, "r") as f:
        result = f.read()
    return result^


@always_inline
fn _to_env_name(field: String) -> String:
    """Convert a struct field name to its corresponding env var name.

    Applies ``str.upper()`` only; underscores are preserved.
    Example: ``db_host`` -> ``DB_HOST``, ``port`` -> ``PORT``.

    Args:
        field: Struct field name.

    Returns:
        Uppercase env var name.
    """
    return field.upper()


def _apply_env_overrides[T: Morphable](owned cfg: T) raises -> T:
    """Override fields in ``cfg`` with matching environment variables.

    Iterates over every field of ``T`` at compile time.  For each field
    whose uppercased name exists as an env var, the env var value is
    parsed and written into ``cfg`` using an ``UnsafePointer`` cast -- the
    same pattern used by ``morph.cli.parse_args``.

    Supported field types: ``String``, ``Int``, ``Int64``, ``Bool``,
    ``Float64``, ``Float32``, ``Optional[String]``, ``Optional[Int]``,
    ``Optional[Float64]``, ``Optional[Bool]``.

    Parameters:
        T: A ``Morphable`` struct type.

    Args:
        cfg: Existing config (moved in), typically populated from TOML.

    Returns:
        A new struct with env var values applied where found.

    Raises:
        Error: If an env var value cannot be converted to the field's type
            (e.g., ``PORT=abc`` for an ``Int`` field).
    """
    comptime count = struct_field_count[T]()
    comptime names = struct_field_names[T]()
    comptime types = struct_field_types[T]()

    comptime
    for idx in range(count):
        comptime field_name = names[idx]
        comptime field_type = types[idx]
        comptime type_name = get_type_name[field_type]()

        var env_name = _to_env_name(String(field_name))
        var env_val = getenv(env_name)
        if env_val:
            var raw = env_val.value()
            ref field = trait_downcast[_Base](__struct_field_ref(idx, cfg))
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

    return cfg^


def _apply_cli_overrides[T: Morphable](
    owned cfg: T, args: List[String]
) raises -> T:
    """Override fields in ``cfg`` with explicitly provided CLI flags.

    Parses ``--field-name value`` pairs (same conventions as
    ``morph.cli.parse_args``) but starts from the existing ``cfg`` rather
    than a zero-initialised struct, so only provided flags are overridden.

    Underscore-to-hyphen conversion: ``db_host`` matches ``--db-host``.
    Bool fields are flags: ``--debug`` sets the field to ``True``.

    Supported field types: ``String``, ``Int``, ``Int64``, ``Bool``,
    ``Float64``, ``Float32``, ``Optional[String]``, ``Optional[Int]``,
    ``Optional[Float64]``, ``Optional[Bool]``, ``List[String]``,
    ``List[Int]``.

    Parameters:
        T: A ``Morphable`` struct type.

    Args:
        cfg: Config populated from TOML + env (moved in).
        args: CLI argument list without the program name.

    Returns:
        ``cfg`` with all provided flags applied.

    Raises:
        Error: If an unknown flag is encountered or a value is missing.
    """
    comptime count = struct_field_count[T]()
    comptime names = struct_field_names[T]()
    comptime types = struct_field_types[T]()

    var i = 0
    while i < len(args):
        var arg = args[i]
        var is_long = arg.startswith("--")
        var is_short = not is_long and arg.startswith("-") and len(arg) == 2

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
            comptime type_name = get_type_name[field_type]()

            var cli_name = String(field_name).replace("_", "-")
            var fn_str = String(field_name)
            var short_name = chr(Int(fn_str.as_bytes()[0]))
            if flag == cli_name or (is_short and flag == short_name):
                matched = True
                ref field = trait_downcast[_Base](
                    __struct_field_ref(idx, cfg)
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
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    ptr.destroy_pointee()
                    ptr.bitcast[Int]().init_pointee_move(atol(args[i]))
                elif type_name == OPT_INT_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    ptr.destroy_pointee()
                    ptr.bitcast[Optional[Int]]().init_pointee_move(
                        atol(args[i])
                    )
                elif type_name == INT64_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    ptr.destroy_pointee()
                    ptr.bitcast[Int64]().init_pointee_move(
                        Int64(atol(args[i]))
                    )
                elif type_name == FLOAT64_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    ptr.destroy_pointee()
                    ptr.bitcast[Float64]().init_pointee_move(atof(args[i]))
                elif type_name == OPT_FLOAT64_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    ptr.destroy_pointee()
                    ptr.bitcast[Optional[Float64]]().init_pointee_move(
                        atof(args[i])
                    )
                elif type_name == STRING_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    ptr.destroy_pointee()
                    ptr.bitcast[String]().init_pointee_move(args[i])
                elif type_name == OPT_STRING_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    ptr.destroy_pointee()
                    ptr.bitcast[Optional[String]]().init_pointee_move(
                        args[i]
                    )
                elif type_name == LIST_STRING_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    var parts = _split_comma(args[i])
                    ptr.destroy_pointee()
                    ptr.bitcast[List[String]]().init_pointee_move(parts^)
                elif type_name == LIST_INT_NAME:
                    i += 1
                    if i >= len(args):
                        raise Error("Missing value for --" + cli_name)
                    var parts = _split_comma(args[i])
                    var int_list = List[Int]()
                    for pi in range(len(parts)):
                        int_list.append(atol(parts[pi]))
                    ptr.destroy_pointee()
                    ptr.bitcast[List[Int]]().init_pointee_move(int_list^)

        if not matched:
            raise Error("Unknown flag: --" + flag)

        i += 1

    return cfg^


@always_inline
fn _split_comma(s: String) -> List[String]:
    """Split ``s`` on commas and return trimmed parts.

    Args:
        s: Comma-separated string (e.g., ``"a,b,c"``).

    Returns:
        List of trimmed substrings.
    """
    var result = List[String]()
    var start = 0
    for i in range(len(s)):
        if s[i] == ",":
            result.append(s[start:i].strip())
            start = i + 1
    result.append(s[start:].strip())
    return result^
