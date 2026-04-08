"""Environment variable access via the Mojo standard library.

Wraps ``std.os.getenv`` to provide ``Optional[String]`` semantics: an
unset (or empty) variable returns ``None``, which lets callers distinguish
"no override" from an explicit value.

Example:

    from envo.env import getenv, getenv_or

    var home = getenv("HOME")              # Optional[String]
    var port = getenv_or("PORT", "8080")  # String
"""

from std.os import getenv as _os_getenv


def getenv(name: String) -> Optional[String]:
    """Return the value of environment variable ``name``, or ``None``.

    An unset variable and a variable explicitly set to the empty string
    are both treated as absent (return ``None``).  This is the correct
    semantic for config-layer overrides: an empty env var should not
    override a non-empty TOML value.

    Args:
        name: The environment variable name (case-sensitive).

    Returns:
        ``Some(value)`` if the variable is set to a non-empty string,
        ``None`` otherwise.
    """
    var val = _os_getenv(name)
    if val == "":
        return None
    return val


def getenv_or(name: String, default: String) -> String:
    """Return the value of environment variable ``name``, or ``default``.

    Args:
        name: The environment variable name.
        default: The fallback value when the variable is unset or empty.

    Returns:
        The variable's value, or ``default`` if unset/empty.
    """
    var val = getenv(name)
    if val:
        return val.value()
    return default
