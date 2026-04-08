"""Environment variable access via libc FFI.

Wraps the POSIX ``getenv(3)`` C function to provide safe, idiomatic
Mojo access to environment variables.

Example:

    from envo.env import getenv, getenv_or

    var home = getenv("HOME")      # Optional[String]
    var port = getenv_or("PORT", "8080")  # String
"""

from std.ffi import external_call


@always_inline
fn getenv(name: String) -> Optional[String]:
    """Return the value of environment variable ``name``, or ``None``.

    Calls libc ``getenv(3)``. The returned pointer is valid for the
    lifetime of the process environment; this function immediately copies
    the value into an owned ``String``.

    Args:
        name: The environment variable name (case-sensitive, NUL-terminated
            by ``unsafe_cstr_ptr``).

    Returns:
        ``Some(value)`` if the variable is set, ``None`` otherwise.
    """
    var ptr = external_call["getenv", UnsafePointer[UInt8]](
        name.unsafe_cstr_ptr()
    )
    if not ptr:
        return None
    return String(ptr=ptr, length=_cstrlen(ptr))


@always_inline
fn getenv_or(name: String, default: String) -> String:
    """Return the value of environment variable ``name``, or ``default``.

    Args:
        name: The environment variable name.
        default: The fallback value when the variable is not set.

    Returns:
        The variable's value, or ``default`` if unset.
    """
    var val = getenv(name)
    if val:
        return val.value()
    return default


@always_inline
fn _cstrlen(ptr: UnsafePointer[UInt8]) -> Int:
    """Return the byte length of a NUL-terminated C string.

    Args:
        ptr: Pointer to the start of the C string.

    Returns:
        Number of bytes before the NUL terminator.
    """
    var i = 0
    while ptr[i] != 0:
        i += 1
    return i
