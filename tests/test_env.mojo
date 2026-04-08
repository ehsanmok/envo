"""Tests for envo.env -- getenv and getenv_or."""

from std.testing import assert_equal, assert_true, assert_false
from envo.env import getenv, getenv_or


def test_getenv_known_var() raises:
    # PATH is always set on POSIX systems
    var val = getenv("PATH")
    assert_true(val.__bool__(), "PATH must be set")
    assert_true(len(val.value()) > 0, "PATH must be non-empty")


def test_getenv_missing_var() raises:
    var val = getenv("__ENVO_DEFINITELY_NOT_SET_XYZ__")
    assert_false(val.__bool__(), "unset var must return None")


def test_getenv_or_present() raises:
    # HOME is set on POSIX systems
    var val = getenv_or("HOME", "/fallback")
    assert_true(val != "/fallback", "HOME must override fallback")


def test_getenv_or_absent() raises:
    var val = getenv_or("__ENVO_DEFINITELY_NOT_SET_ABC__", "default_val")
    assert_equal(val, "default_val")


def test_getenv_or_empty_default() raises:
    var val = getenv_or("__ENVO_DEFINITELY_NOT_SET_DEF__", "")
    assert_equal(val, "")


def main() raises:
    test_getenv_known_var()
    test_getenv_missing_var()
    test_getenv_or_present()
    test_getenv_or_absent()
    test_getenv_or_empty_default()
    print("All env tests passed.")
