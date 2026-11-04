#!/usr/bin/env python3
# Copyright 2026 Cisco Systems, Inc. and its affiliates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

"""Helpers for locating external CLI tool executables."""

import os
import shutil
import sys


def find_tool(name):
    """Resolve a CLI tool executable to a runnable path.

    Checks the directory containing sys.executable first, so tools installed
    in the same virtualenv are found even when the venv is NOT activated
    (e.g. start.bat invoking .venv\\Scripts\\python.exe directly on Windows,
    which leaves .venv\\Scripts off the child process PATH). Falls back to a
    PATH lookup, then to the bare name so subprocess raises the familiar
    FileNotFoundError if the tool is truly missing.
    """
    exe_dir = os.path.dirname(os.path.abspath(sys.executable))
    exe_name = name + (".exe" if os.name == "nt" else "")
    local = os.path.join(exe_dir, exe_name)
    if os.path.isfile(local):
        return local
    resolved = shutil.which(name)
    return resolved if resolved else name


def tool_env():
    """Return a child-process environment that forces UTF-8 mode.

    On a CJK Windows locale (e.g. GBK) Python defaults ``open()`` to the
    locale codec, which makes semgrep crash on UTF-8 rule/config/source
    files with ``UnicodeDecodeError``. ``PYTHONUTF8=1`` makes every child
    Python process default to UTF-8 regardless of locale.

    The returned mapping is a copy; ``os.environ`` is left untouched.
    """
    env = dict(os.environ)
    env["PYTHONUTF8"] = "1"
    return env
