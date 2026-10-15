#!/usr/bin/env python3
"""Unit tests for classify-install-command.py. Run: python3 hooks/lib/classify-install-command.test.py

Pass -v to print one PASS/FAIL line per check (used to falsify the suite against stub classifiers).
Set CLASSIFY_INSTALL_COMMAND_UNDER_TEST=<file> to load a different module (the always-allow and
always-deny stubs of the falsification step); unset, the real classifier beside this file is loaded.

Dependency-free (no pytest), as classify-pr-command.test.py is. The expected intents below are
written out by hand and never derived from the classifier or from is_exact_version, so the suite
is an independent baseline for both.
"""

import importlib.util
import os
import re
import subprocess
import sys

MARKER_SELF = os.path.abspath(__file__)
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

_HERE = os.path.dirname(os.path.abspath(__file__))
_MODULE_ENV = "CLASSIFY_INSTALL_COMMAND_UNDER_TEST"
CARD_PATH = os.path.join(MARKER_ROOT, "docs", "features", "dependency-vetting-guard.md")
sys.path.insert(0, _HERE)


def _load_module():
    path = os.environ.get(_MODULE_ENV) or os.path.join(_HERE, "classify-install-command.py")
    try:
        spec = importlib.util.spec_from_file_location("classify_install_command", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except (FileNotFoundError, ImportError) as exc:
        print("FAIL -- cannot load the classifier under test ({}): {}".format(path, exc))
        sys.exit(1)


_MOD = _load_module()
classify = _MOD.classify

# ---------------------------------------------------------------------------------------------
# Expected-intent builders. `pinned` is always written out by hand.
# ---------------------------------------------------------------------------------------------


def _intent(eco, name, version, tool, pinned, runner=None, source="registry", exempt=None, via=False):
    return {"ecosystem": eco, "name": name, "version": version, "pinned": pinned, "tool": tool,
            "runner": runner, "form": "run" if runner else "add", "source": source, "exempt": exempt,
            "via_package_option": via}


def npm(name, version, pinned, tool="npm", runner=None, via=False):
    return _intent("npm", name, version, tool, pinned, runner, via=via)


def pypi(name, version, pinned, tool="pip", runner=None):
    return _intent("pypi", name, version, tool, pinned, runner)


def crate(name, version, pinned):
    return _intent("crates.io", name, version, "cargo", pinned)


def gomod(name, version, pinned):
    return _intent("go", name, version, "go", pinned)


def gem(name, version, pinned):
    return _intent("rubygems", name, version, "gem", pinned)


def brew(name):
    return _intent("homebrew", name, None, "brew", False)


def other(eco, name, tool, runner=None):
    return _intent(eco, name, None, tool, False, runner, "other")


def reqfile(name, tool):
    return _intent("pypi", name, None, tool, False, source="requirements-file")


def exempt(intents, value):
    """The same intents, each carrying the segment's VET_EXEMPT value."""
    return [dict(i, exempt=value) for i in intents]


_CHECKS = []  # (name, thunk -> (ok, detail))


def add_check(name, thunk):
    _CHECKS.append((name, thunk))


def add_cases(group, cases):
    """cases: (command, expected_intents, why)."""
    for command, want, why in cases:
        def thunk(command=command, want=want, why=why):
            got = classify(command)
            return got == want, "{}\n       want {!r}\n       got  {!r}".format(why, want, got)
        add_check("{}: {!r}".format(group, command), thunk)


def none_of(group, commands, why):
    add_cases(group, [(c, [], why) for c in commands])


# ---------------------------------------------------------------------------------------------
# The install-forms table, row by row
# ---------------------------------------------------------------------------------------------
NPM_INSTALL_WORDS = ["install", "add", "i", "in", "ins", "inst", "insta", "instal", "isnt", "isnta",
                     "isntal", "isntall", "install-test", "it"]

add_cases("npm row", [(("npm {} zod@3.23.8".format(w)), [npm("zod", "3.23.8", True)],
                       "npm install alias {!r}".format(w)) for w in NPM_INSTALL_WORDS])
add_cases("npm row", [
    ("npm install zod", [npm("zod", None, False)], "no version"),
    ("npm i @scope/pkg@1.0.0", [npm("@scope/pkg", "1.0.0", True)], "scope kept"),
    ("npm i @scope/pkg", [npm("@scope/pkg", None, False)], "scope kept, no version"),
    ("npm install -g zod@3.23.8", [npm("zod", "3.23.8", True)], "boolean flag"),
    ("npm install zod@3.23.8 --save-dev", [npm("zod", "3.23.8", True)], "flag after the package"),
    ("npm --prefix app install zod@3.23.8", [npm("zod", "3.23.8", True)], "valued flag before the subcommand"),
    ("npm install --registry https://r.example.com zod@3.23.8", [npm("zod", "3.23.8", True)],
     "a valued flag's value is not a package"),
    ("npm install 'zod@3.23.8'", [npm("zod", "3.23.8", True)], "quoted"),
    ("npm install foo@npm:bar@1.0.0", [npm("bar", "1.0.0", True)], "alias resolves to the real package"),
    ("npm install foo@npm:bar", [npm("bar", None, False)], "alias, no version"),
    ("npm install foo@npm:@s/bar@2.0.0", [npm("@s/bar", "2.0.0", True)], "alias to a scoped package"),
    ("npm exec cowsay@1.6.0 hi", [npm("cowsay", "1.6.0", True, runner="npm exec")], "npm exec row"),
    ("npm x cowsay@1.6.0", [npm("cowsay", "1.6.0", True, runner="npm x")], "npm x row"),
])

NODE_MANAGER_LINES = [
    ("pnpm add zod@3.23.8", "pnpm"), ("pnpm install zod@3.23.8", "pnpm"), ("pnpm i zod@3.23.8", "pnpm"),
    ("pn add zod@3.23.8", "pn"), ("pn install zod@3.23.8", "pn"), ("pnpm --filter web add zod@3.23.8", "pnpm"),
    ("yarn add zod@3.23.8", "yarn"), ("yarn install zod@3.23.8", "yarn"), ("yarnpkg add zod@3.23.8", "yarnpkg"),
    ("bun add zod@3.23.8", "bun"), ("bun install zod@3.23.8", "bun"), ("bun i zod@3.23.8", "bun"),
]
add_cases("pnpm/yarn/bun row", [(c, [npm("zod", "3.23.8", True, tool=t)], "manager install form")
                                for c, t in NODE_MANAGER_LINES])
add_cases("pnpm/yarn/bun row", [
    ("pnpm add zod", [npm("zod", None, False, tool="pnpm")], "unpinned"),
    ("yarn add -D zod@3.23.8", [npm("zod", "3.23.8", True, tool="yarn")], "dev flag"),
])

COREPACK_LINES = [
    ("corepack pnpm add left-pad@1.3.0", [npm("left-pad", "1.3.0", True, tool="pnpm")]),
    ("corepack pnpm@9.0.0 add left-pad@1.3.0", [npm("left-pad", "1.3.0", True, tool="pnpm")]),
    ("corepack yarn add left-pad", [npm("left-pad", None, False, tool="yarn")]),
    ("corepack npm install left-pad@1.3.0", [npm("left-pad", "1.3.0", True)]),
    ("corepack pnpm dlx cowsay@1.6.0", [npm("cowsay", "1.6.0", True, tool="pnpm", runner="pnpm dlx")]),
    ("corepack pnpm install", []),
    ("corepack enable", []),
    ("corepack --version", []),
]
add_cases("corepack row", [(c, w, "read as the manager it runs, @version stripped") for c, w in COREPACK_LINES])

add_cases("npx row", [
    ("npx cowsay@1.6.0 hi", [npm("cowsay", "1.6.0", True, "npx", "npx")], "first non-flag arg"),
    ("npx cowsay hi", [npm("cowsay", None, False, "npx", "npx")], "unpinned; the args after it are not packages"),
    ("npx -y cowsay@1.6.0 hi", [npm("cowsay", "1.6.0", True, "npx", "npx")], "boolean flag first"),
    ("npx --yes --no-install cowsay@1.6.0", [npm("cowsay", "1.6.0", True, "npx", "npx")], "two boolean flags"),
    ("npx @scope/tool@2.0.0", [npm("@scope/tool", "2.0.0", True, "npx", "npx")], "scoped"),
    ("npx --package=a@1.0.0 --package b@2.0.0 -p c@3.0.0 cmd",
     [npm("a", "1.0.0", True, "npx", "npx", via=True), npm("b", "2.0.0", True, "npx", "npx", via=True),
      npm("c", "3.0.0", True, "npx", "npx", via=True), npm("cmd", None, False, "npx", "npx")],
     "every -p/--package value is an intent (via_package_option), and so is the first non-flag arg"),
    ("npx -p cowsay cowsay hi",
     [npm("cowsay", None, False, "npx", "npx", via=True), npm("cowsay", None, False, "npx", "npx")],
     "scenario 'npx -p names an install'; the -p value AND the positional (via_package_option only on the first)"),
    ("npx -p cowsay@1.6.0 cowsay",
     [npm("cowsay", "1.6.0", True, "npx", "npx", via=True), npm("cowsay", None, False, "npx", "npx")],
     "Mark kept this refused: the bare command word is a second, unpinned intent"),
    ("npx --package cowsay@1.6.0 cowsay",
     [npm("cowsay", "1.6.0", True, "npx", "npx", via=True), npm("cowsay", None, False, "npx", "npx")],
     "--package <v> separate value"),
    ("npx -pcowsay@1.6.0 cowsay",
     [npm("cowsay", "1.6.0", True, "npx", "npx", via=True), npm("cowsay", None, False, "npx", "npx")],
     "attached short value"),
    ("npx cowsay@1.6.0 -p other@2.0.0", [npm("cowsay", "1.6.0", True, "npx", "npx")],
     "-p after the package belongs to the command being run"),
    ("pnpm dlx -p a@1.0.0 cmd@2.0.0",
     [npm("a", "1.0.0", True, "pnpm", "pnpm dlx", via=True), npm("cmd", "2.0.0", True, "pnpm", "pnpm dlx")],
     "pnpm dlx -p"),
    ("npm exec --package=a@1.0.0 -- cmd",
     [npm("a", "1.0.0", True, "npm", "npm exec", via=True), npm("cmd", None, False, "npm", "npm exec")],
     "npm exec --package="),
    ("yarn dlx --package a@1.0.0 cmd",
     [npm("a", "1.0.0", True, "yarn", "yarn dlx", via=True), npm("cmd", None, False, "yarn", "yarn dlx")],
     "yarn dlx --package"),
    ("uvx -p 3.12 ruff==0.6.0 check", [pypi("ruff", "0.6.0", True, "uvx", "uvx")],
     "uvx -p is --python, not a package option: no intent, via_package_option false"),
    ("uvx --python 3.12 ruff check", [pypi("ruff", None, False, "uvx", "uvx")], "uvx --python"),
    ("npx -- cowsay@1.6.0", [npm("cowsay", "1.6.0", True, "npx", "npx")], "after -- the next token is the package"),
    ("npx github:user/repo", [other("npm", "github:user/repo", "npx", "npx")], "a git source"),
    ("npx NPX-NOT-A-FLAG@1.0.0", [npm("NPX-NOT-A-FLAG", "1.0.0", True, "npx", "npx")], "name spelling kept"),
])

PIP_TOOL_PREFIXES = [("pip", "pip"), ("pip3", "pip3"), ("python -m pip", "python"),
                     ("python3 -m pip", "python3"), ("python3 -u -m pip", "python3"), ("uv pip", "uv")]
add_cases("pip row", [("{} install requests==2.32.3".format(p), [pypi("requests", "2.32.3", True, tool=t)],
                       "pip install form via {}".format(p)) for p, t in PIP_TOOL_PREFIXES])
add_cases("pip row", [
    ("pip install requests[security]==2.32.3", [pypi("requests", "2.32.3", True)], "extra dropped from the name"),
    ("pip install requests", [pypi("requests", None, False)], "no version"),
    ("pip install --upgrade requests==2.32.3", [pypi("requests", "2.32.3", True)], "flag before"),
    ("pip install -i https://pypi.example/simple requests==2.32.3", [pypi("requests", "2.32.3", True)],
     "valued flag"),
    ("pip install --index-url=https://pypi.example/simple requests==2.32.3", [pypi("requests", "2.32.3", True)],
     "valued flag, = spelling"),
    ("pip install 'requests==2.32.3; python_version<\"3.9\"'", [pypi("requests", "2.32.3", True)],
     "environment marker dropped"),
    ("pip install 'requests == 2.32.3'", [pypi("requests", "2.32.3", True)], "spaces around =="),
    ("pip install 'torch==2.1.0+cu118'", [pypi("torch", "2.1.0+cu118", True)], "local label is exact"),
    ("pip install -r requirements.txt", [reqfile("requirements.txt", "pip")], "-r is a requirements-file source, not parsed"),
    ("pip install --requirement reqs.txt", [reqfile("reqs.txt", "pip")], "long form"),
    ("pip install --requirement=reqs.txt", [reqfile("reqs.txt", "pip")], "long form, ="),
    ("pip install -rreqs.txt", [reqfile("reqs.txt", "pip")], "attached short form"),
    ("pip install -r reqs.txt requests==2.32.3",
     [reqfile("reqs.txt", "pip"), pypi("requests", "2.32.3", True)], "-r and a package, in order"),
    ("uv pip install -r reqs.txt", [reqfile("reqs.txt", "uv")], "uv pip -r"),
    ("python -m pip install -r reqs.txt", [reqfile("reqs.txt", "python")], "python -m pip -r"),
])

add_cases("uv/poetry row", [
    ("uv add requests==2.32.3", [pypi("requests", "2.32.3", True, tool="uv")], "uv add"),
    ("uv add requests", [pypi("requests", None, False, tool="uv")], "uv add, unpinned"),
    ("uv add --dev pytest==8.0.0", [pypi("pytest", "8.0.0", True, tool="uv")], "uv add --dev"),
    ("uv add --group lint ruff==0.6.0", [pypi("ruff", "0.6.0", True, tool="uv")], "a valued flag"),
    ("uv add -r reqs.txt", [reqfile("reqs.txt", "uv")], "uv add -r"),
    ("poetry add requests@2.32.3", [pypi("requests", "2.32.3", True, tool="poetry")], "poetry name@version"),
    ("poetry add requests==2.32.3", [pypi("requests", "2.32.3", True, tool="poetry")], "poetry accepts =="),
    ("poetry add requests", [pypi("requests", None, False, tool="poetry")], "poetry, unpinned"),
    ("poetry add --group dev pytest@8.0.0", [pypi("pytest", "8.0.0", True, tool="poetry")], "poetry --group"),
])

add_cases("uvx row", [
    ("uv tool install ruff==0.6.0", [pypi("ruff", "0.6.0", True, tool="uv")], "uv tool install is a plain install"),
    ("pipx install black==24.1.0", [pypi("black", "24.1.0", True, tool="pipx")], "pipx install is a plain install"),
    ("pipx install black", [pypi("black", None, False, tool="pipx")], "pipx install, unpinned"),
])

CARGO_CASES = [
    ("cargo add serde@=1.0.210", [crate("serde", "1.0.210", True)], "= -> exact, as Cargo reads it"),
    ("cargo add serde@1.0.210", [crate("serde", "^1.0.210", False)], "bare version is a caret requirement"),
    ("cargo add serde", [crate("serde", None, False)], "no version"),
    ("cargo add serde@~1.0", [crate("serde", "~1.0", False)], "other operator kept"),
    ("cargo add 'serde@>=1.0'", [crate("serde", ">=1.0", False)], "other operator kept"),
    ("cargo add serde@=1.0.210 --features derive", [crate("serde", "1.0.210", True)], "valued flag"),
    ("cargo add serde@=1.0.210 tokio@=1.40.0 -F full",
     [crate("serde", "1.0.210", True), crate("tokio", "1.40.0", True)], "two crates, -F value skipped"),
    ("cargo install ripgrep@14.1.0", [crate("ripgrep", "14.1.0", True)], "install name@version is exact"),
    ("cargo install ripgrep@=14.1.0", [crate("ripgrep", "14.1.0", True)], "install name@=version"),
    ("cargo install ripgrep --version 14.1.0", [crate("ripgrep", "14.1.0", True)], "--version"),
    ("cargo install ripgrep --version =14.1.0", [crate("ripgrep", "14.1.0", True)], "--version =x"),
    ("cargo install ripgrep --version=14.1.0", [crate("ripgrep", "14.1.0", True)], "--version=x"),
    ("cargo install ripgrep --version '^14'", [crate("ripgrep", "^14", False)], "operator kept"),
    ("cargo install ripgrep@^14.1", [crate("ripgrep", "^14.1", False)], "operator kept"),
    ("cargo install ripgrep", [crate("ripgrep", None, False)], "no version"),
    ("cargo install --locked ripgrep@14.1.0", [crate("ripgrep", "14.1.0", True)], "boolean flag"),
    ("cargo +nightly install ripgrep@14.1.0", [crate("ripgrep", "14.1.0", True)], "toolchain selector"),
    ("cargo install --git https://github.com/u/r", [other("crates.io", "https://github.com/u/r", "cargo")],
     "git source with no crate name"),
    ("cargo add foo --path ../foo", [other("crates.io", "foo", "cargo")], "path source"),
    ("cargo add foo --git https://github.com/u/foo", [other("crates.io", "foo", "cargo")], "git source"),
]
add_cases("cargo row", CARGO_CASES)

add_cases("go row", [
    ("go get golang.org/x/text@v0.3.8", [gomod("golang.org/x/text", "v0.3.8", True)], "module path keeps its slashes"),
    ("go install golang.org/x/tools/cmd/goimports@v0.20.0",
     [gomod("golang.org/x/tools/cmd/goimports", "v0.20.0", True)], "go install"),
    ("go get example.com/m@latest", [gomod("example.com/m", "latest", False)], "@latest is not exact"),
    ("go get example.com/m", [gomod("example.com/m", None, False)], "no version"),
    ("go get -u example.com/m@v1.0.0", [gomod("example.com/m", "v1.0.0", True)], "boolean flag"),
    ("go install -tags foo example.com/m@v1.0.0", [gomod("example.com/m", "v1.0.0", True)], "valued flag"),
    ("go get ./...", [other("go", "./...", "go")], "local path"),
])

add_cases("gem row", [
    ("gem install rails --version 7.1.3", [gem("rails", "7.1.3", True)], "--version is the version spelling"),
    ("gem install rails -v 7.1.3", [gem("rails", "7.1.3", True)], "-v"),
    ("gem install rails --version=7.1.3", [gem("rails", "7.1.3", True)], "--version="),
    ("gem install -v 7.1.3 rails", [gem("rails", "7.1.3", True)], "flag first"),
    ("gem install rails:7.1.3", [gem("rails", "7.1.3", True)], "name:version"),
    ("gem install rails", [gem("rails", None, False)], "no version"),
    ("gem install rails -v '~> 7.0'", [gem("rails", "~> 7.0", False)], "pessimistic constraint"),
    ("gem install rails -v '>= 7'", [gem("rails", ">= 7", False)], "range"),
    ("gem install rails -- --with-opt-dir=/x", [gem("rails", None, False)], "build args after -- are not gems"),
    ("gem install ./foo.gem", [other("rubygems", "./foo.gem", "gem")], "local gem file"),
])

add_cases("brew row", [
    ("brew install jq", [brew("jq")], "no pin (D8)"),
    ("brew reinstall jq", [brew("jq")], "reinstall"),
    ("brew install --cask firefox", [brew("firefox")], "flag"),
    ("brew install jq yq", [brew("jq"), brew("yq")], "every formula"),
    ("brew install user/tap/formula", [brew("user/tap/formula")], "tap form"),
    ("brew install node@20", [brew("node@20")], "versioned formula name kept as written"),
    ("brew install ./foo.rb", [other("homebrew", "./foo.rb", "brew")], "local formula file"),
    ("brew install https://example.com/foo.rb", [other("homebrew", "https://example.com/foo.rb", "brew")], "URL"),
])

# ---------------------------------------------------------------------------------------------
# Not installs, always allowed
# ---------------------------------------------------------------------------------------------
none_of("not an install", [
    "npm ci", "npm install", "npm i", "npm install -g", "npm install --save-dev", "npm install --prefix app",
    "pnpm install", "pnpm i", "yarn", "yarn install", "yarn add", "bun install", "bun add", "bun install --frozen-lockfile",
    "pip install -e .", "pip install .", "pip install -e . --no-deps", "pip install --upgrade", "pip install",
    "uv pip install -e .", "uv add", "poetry add",
    "cargo build", "cargo install", "cargo add", "go build ./...", "go mod download", "go version", "go get",
    "gem install", "brew install", "brew update",
    "npm run build", "npm update", "npm uninstall zod", "pip uninstall requests", "pip list", "pip freeze",
    "git status", "ls -la", "echo hello",
], "reinstalls a lockfile/manifest, or runs something that is not an install form")

HELP_ARGS = ["--help", "-h", "--version", "-v", "-V"]
HELP_TOOLS = ["npm", "pnpm", "yarn", "bun", "pip", "pip3", "uv", "poetry", "cargo", "go", "gem", "brew",
              "pipx", "corepack", "npx", "pnpx", "pnx", "bunx", "uvx"]
none_of("not an install", ["{} {}".format(t, a) for t in HELP_TOOLS for a in HELP_ARGS],
        "a lone --help/--version/-v/-V after the tool name")
none_of("not an install", ["python -m pip --version", "uv tool run --help", "npm exec --help", "bun x --version"],
        "the help exemption through a multi-word tool")

add_cases("help is not exempt after a package", [
    ("npx pip --version", [npm("pip", None, False, "npx", "npx")],
     "the runner fetches pip before --version reaches it (card lines 313-316)"),
    ("npx cowsay@1.6.0 --help", [npm("cowsay", "1.6.0", True, "npx", "npx")], "a flag after a runner's package"),
    ("pnpm dlx tsc -v", [npm("tsc", None, False, "pnpm", "pnpm dlx")], "-v after a pnpm dlx package"),
    ("uvx ruff --version", [pypi("ruff", None, False, "uvx", "uvx")], "--version after a uvx package"),
    ("gem install rails --version 7.1.3", [gem("rails", "7.1.3", True)], "--version inside an install is its version"),
])

# ---------------------------------------------------------------------------------------------
# Wrappers, chaining, spelling of the tool name
# ---------------------------------------------------------------------------------------------
Z = [npm("zod", "3.23.8", True)]
add_cases("wrappers", [
    ("env FOO=1 sudo npm i zod@3.23.8", Z, "the card's wrapped-install scenario"),
    ("sudo npm i zod@3.23.8", Z, "sudo"),
    ("sudo -E npm i zod@3.23.8", Z, "sudo boolean flag"),
    ("sudo -u root npm i zod@3.23.8", Z, "sudo valued flag"),
    ("sudo FOO=1 npm i zod@3.23.8", Z, "sudo assignment"),
    ("env npm i zod@3.23.8", Z, "bare env"),
    ("env -i FOO=1 npm i zod@3.23.8", Z, "env -i and an assignment"),
    ("env -u HOME npm i zod@3.23.8", Z, "env -u NAME"),
    ("timeout 30 npm i zod@3.23.8", Z, "timeout <n>"),
    ("timeout -k 5 30 npm i zod@3.23.8", Z, "timeout -k <n> <n>"),
    ("timeout --foreground 30s npm i zod@3.23.8", Z, "timeout flag then a duration"),
    ("nice npm i zod@3.23.8", Z, "bare nice"),
    ("nice -n 5 npm i zod@3.23.8", Z, "nice -n <n>"),
    ("nice -5 npm i zod@3.23.8", Z, "nice -<n>"),
    ("sudo nice -n 5 timeout 30 env FOO=1 npm i zod@3.23.8", Z, "wrappers stack"),
    ("rtk npm i zod@3.23.8", Z, "shell_segments wrapper"),
    ("time npm i zod@3.23.8", Z, "shell_segments wrapper"),
    ("env time sudo npm i zod@3.23.8", Z, "a shell_segments wrapper after env"),
    ("FOO=1 npm i zod@3.23.8", Z, "leading assignment"),
    ("/usr/local/bin/npm i zod@3.23.8", Z, "absolute path"),
    ("node_modules/.bin/npm install zod@3.23.8", Z, "the project's own npm is still npm (card line 332)"),
    ("NPM i zod@3.23.8", Z, "upper case folds"),
    ("node_modules/.bin/NPM install zod@3.23.8", Z, "path and case together"),
    ("env FOO=1 sudo npx cowsay@1.6.0", [npm("cowsay", "1.6.0", True, "npx", "npx")], "wrapped runner"),
    ("sudo pip install requests==2.32.3", [pypi("requests", "2.32.3", True)], "wrapped pip"),
    ("env", [], "env alone"),
    ("sudo", [], "sudo alone"),
    ("timeout 30", [], "timeout with no command"),
    ("env FOO=1", [], "env with only assignments"),
])

add_cases("chaining", [
    ("cd app && npm install left-pad@1.3.0", [npm("left-pad", "1.3.0", True)], "&&"),
    ("cd app; npm install left-pad@1.3.0", [npm("left-pad", "1.3.0", True)], ";"),
    ("false || npm install left-pad@1.3.0", [npm("left-pad", "1.3.0", True)], "||"),
    ("echo y | npm install left-pad@1.3.0", [npm("left-pad", "1.3.0", True)], "pipe"),
    ("cd app\nnpm install left-pad@1.3.0", [npm("left-pad", "1.3.0", True)], "newline"),
    ("cd app && \\\nnpm install left-pad@1.3.0", [npm("left-pad", "1.3.0", True)], "continuation"),
    ("(cd app && npm install left-pad@1.3.0)", [npm("left-pad", "1.3.0", True)], "subshell"),
    ("{ npm install left-pad@1.3.0; }", [npm("left-pad", "1.3.0", True)], "brace group"),
    ("npm install left-pad@1.3.0 && npm test", [npm("left-pad", "1.3.0", True)], "install first"),
    ("npm install left-pad@1.3.0 2>&1 | tail -3", [npm("left-pad", "1.3.0", True)], "redirect and pipe"),
    ("npm i a@1.0.0 && pip install b==2.0 && cargo add c@=3.0.0",
     [npm("a", "1.0.0", True), pypi("b", "2.0", True), crate("c", "3.0.0", True)],
     "every segment's intents, in order"),
    ("npm ci && npm install zod@3.23.8", Z, "a non-install segment does not hide the next"),
    ("npm install zod@3.23.8; npm install zod", [npm("zod", "3.23.8", True), npm("zod", None, False)],
     "the same package twice is two intents"),
    ("echo npm install zod", [], "an argument, not a command"),
    ('git commit -m "npm install zod"', [], "commit message"),
    ("echo 'npm i zod' && ls", [], "quoted text"),
])

# Accepted-open shapes (card "Known gaps"): pinned so closing one is a deliberate edit.
none_of("known gap", [
    'bash -c "npm i left-pad"', 'sh -c "pip install requests"', 'eval "npm i left-pad"',
    'echo "$(npm i left-pad)"', "npx -c 'npm i left-pad'", "./install.sh",
], "the lexer keeps the body as one token / the install is not on the command line")
add_cases("known gap", [
    ("uvx --from httpie==3.2.0 http", [pypi("http", None, False, "uvx", "uvx")],
     "--from names the downloaded package; the guard vets the command instead (card lines 905-907)"),
])

# ---------------------------------------------------------------------------------------------
# VET_EXEMPT: the owning segment's own assignment, exact name, plain-word value only
# ---------------------------------------------------------------------------------------------
A1 = [npm("a", "1.0.0", True)]
add_cases("exempt", [
    ("VET_EXEMPT=offline-mirror npm install zod@3.23.8", exempt(Z, "offline-mirror"), "the card's scenario"),
    ("VET_EXEMPT=x npm install zod", exempt([npm("zod", None, False)], "x"),
     "reported on an unpinned intent too; the hook denies it at step 1"),
    ("VET_EXEMPT=a.b_c,d:e/f-g npm i zod@3.23.8", exempt(Z, "a.b_c,d:e/f-g"), "every allowlisted character class"),
    ("VET_EXEMPT=x1 npm i zod@3.23.8", exempt(Z, "x1"), "digits"),
    ("VET_EXEMPT='x' npm i zod@3.23.8", exempt(Z, "x"), "the lexer removes cleanly balanced quotes"),
    ("VET_EXEMPT='a;b' npm install zod@3.23.8", Z, "the card's metacharacter scenario: ignored"),
    ("VET_EXEMPT=a;b npm install zod@3.23.8", [],
     "an unquoted ; ends the segment: the next one starts with the command word b, not npm"),
    ('VET_EXEMPT="two words" npm i zod@3.23.8', Z, "a space is outside the allowlist"),
    ("VET_EXEMPT='a b' npm i zod@3.23.8", Z, "a space is outside the allowlist"),
    ("VET_EXEMPT= npm i zod@3.23.8", Z, "empty value is absent"),
    ("VET_EXEMPT=$HOME npm i zod@3.23.8", Z, "$ is outside the allowlist"),
    ("VET_EXEMPT='a$b' npm i zod@3.23.8", Z, "quoted $ is outside the allowlist"),
    ("VET_EXEMPT='a`b' npm i zod@3.23.8", Z, "backtick"),
    ("VET_EXEMPT='a|b' npm i zod@3.23.8", Z, "pipe"),
    ("VET_EXEMPT='a&b' npm i zod@3.23.8", Z, "ampersand"),
    ("VET_EXEMPT='a>b' npm i zod@3.23.8", Z, "redirect character"),
    ("VET_EXEMPT='a*b' npm i zod@3.23.8", Z, "glob"),
    ("VET_EXEMPT='a\\\\b' npm i zod@3.23.8", Z, "backslash"),
    ("VET_EXEMPT=\"a'b\" npm i zod@3.23.8", Z, "embedded quote"),
    ("VET_EXEMPT=caf\u00e9 npm i zod@3.23.8", Z, "non-ASCII letter"),
    ("VET_EXEMPT=\uff11 npm i zod@3.23.8", Z, "non-ASCII digit"),
    ("vet_exempt=x npm i zod@3.23.8", Z, "the name is exact: case matters"),
    ("MY_VET_EXEMPT=x npm i zod@3.23.8", Z, "a longer name that ends in the name"),
    ("VET_EXEMPT_X=x npm i zod@3.23.8", Z, "a longer name that starts with the name"),
    ("JUDGE_EXEMPT=x npm i zod@3.23.8", Z, "another guard's exemption"),
    ("MERGE_EXEMPT=x npm i zod@3.23.8", Z, "another guard's exemption"),
    ("VET_EXEMPT=x true && npm i a@1.0.0", A1, "the card's rule: it belongs to the segment that carries it"),
    ("VET_EXEMPT=x true; npm i a@1.0.0", A1, "; ends the segment"),
    ("VET_EXEMPT=x true || npm i a@1.0.0", A1, "|| ends the segment"),
    ("VET_EXEMPT=x true | npm i a@1.0.0", A1, "a pipe ends the segment"),
    ("VET_EXEMPT=x cd app && npm i a@1.0.0", A1, "a non-install segment's exemption is not borrowed"),
    ("npm i a@1.0.0 && VET_EXEMPT=y pip install b==2.0",
     A1 + exempt([pypi("b", "2.0", True)], "y"), "only the second segment carries it"),
    ("VET_EXEMPT=y npm i a@1.0.0 && pip install b==2.0", exempt(A1, "y") + [pypi("b", "2.0", True)],
     "only the first segment carries it"),
    ("VET_EXEMPT=x npm i a@1.0.0 b@2.0.0", exempt([npm("a", "1.0.0", True), npm("b", "2.0.0", True)], "x"),
     "every package of the owning segment"),
    ("VET_EXEMPT=x npx cowsay@1.6.0", exempt([npm("cowsay", "1.6.0", True, "npx", "npx")], "x"), "a runner"),
    ("VET_EXEMPT=x npx npm@12.0.1 install a", exempt([npm("npm", "12.0.1", True, "npx", "npx")], "x"),
     "the card's runner-of-a-manager scenario: reported, and step 0 still refuses it"),
    ("VET_EXEMPT=x pip install -r reqs.txt", exempt([reqfile("reqs.txt", "pip")], "x"), "a requirements file"),
    ("VET_EXEMPT=x npm install ./local", exempt([other("npm", "./local", "npm")], "x"), "source other"),
    ("VET_EXEMPT=x FOO=1 npm i zod@3.23.8", exempt(Z, "x"), "two assignments"),
    ("FOO=1 VET_EXEMPT=x npm i zod@3.23.8", exempt(Z, "x"), "the exemption second"),
    ("VET_EXEMPT=x VET_EXEMPT=y npm i zod@3.23.8", exempt(Z, "y"), "bash applies the last assignment"),
    ("VET_EXEMPT=x sudo npm i zod@3.23.8", exempt(Z, "x"), "before a wrapper this classifier strips"),
    ("time VET_EXEMPT=x npm i zod@3.23.8", exempt(Z, "x"), "after a shell_segments wrapper"),
    ("env VET_EXEMPT=x npm i zod@3.23.8", Z,
     "set by env, not by the segment's own prefix: not read (fail toward not exempting)"),
    ("sudo VET_EXEMPT=x npm i zod@3.23.8", Z, "set by sudo, not by the segment's own prefix: not read"),
    ("VET_EXEMPT=x corepack pnpm add left-pad@1.3.0", exempt([npm("left-pad", "1.3.0", True, "pnpm")], "x"),
     "through corepack"),
    ("npm i zod@3.23.8", Z, "absent"),
])
_SHAPE_COMMANDS = ["npm i a@1.0.0", "pip install -r r.txt", "npx -p a@1.0.0 b", "brew install jq",
                   "cargo add c@=1.0.0", "go get m.example/x@v1.0.0", "gem install g -v 1.0.0"]
add_check("shape: every intent of every ecosystem has exactly the 10 contract keys", lambda: (
    all(len(classify(c)) >= 1 for c in _SHAPE_COMMANDS)
    and all(sorted(i) == sorted(["ecosystem", "name", "version", "pinned", "tool", "runner", "form", "source",
                                 "exempt", "via_package_option"])
            for c in _SHAPE_COMMANDS for i in classify(c)),
    "an intent has the contract's fields and no others"))

# ---------------------------------------------------------------------------------------------
# Unpinned spellings, per ecosystem
# ---------------------------------------------------------------------------------------------
for _v in ["^3.23.8", "~3.23.8", "latest", "next", "3", "3.23", "*", "x", "3.x", ">=3", "v3.23.8",
           "3.23.8/../evil", "01.2.3"]:
    add_cases("unpinned npm", [("npm install 'zod@{}'".format(_v), [npm("zod", _v, False)],
                                "spelling {!r} is not exact".format(_v))])
add_cases("unpinned pypi", [
    ("pip install 'requests>=2'", [pypi("requests", ">=2", False)], ">="),
    ("pip install 'requests~=2.0'", [pypi("requests", "~=2.0", False)], "~="),
    ("pip install 'requests<3'", [pypi("requests", "<3", False)], "<"),
    ("pip install 'requests!=2.0'", [pypi("requests", "!=2.0", False)], "!="),
    ("pip install 'requests>=2,<3'", [pypi("requests", ">=2,<3", False)], "two bounds"),
    ("pip install 'requests==2.*'", [pypi("requests", "2.*", False)], "wildcard"),
    ("pip install 'requests===2.32.3'", [pypi("requests", "===2.32.3", False)], "arbitrary equality is not ==="),
    ("pip install 'requests==2.32.3/../evil'", [pypi("requests", "2.32.3/../evil", False)],
     "a malformed value is unpinned, so no path is built from it (scenario)"),
    ("pip install requests", [pypi("requests", None, False)], "absent"),
    ("poetry add 'requests@^2.0'", [pypi("requests", "^2.0", False, tool="poetry")], "poetry caret"),
    ("poetry add 'requests@~2.0'", [pypi("requests", "~2.0", False, tool="poetry")], "poetry tilde"),
])
add_cases("unpinned go/gem/cargo", [
    ("go get example.com/m@v1", [gomod("example.com/m", "v1", False)], "go: major only"),
    ("go get example.com/m@master", [gomod("example.com/m", "master", False)], "go: a branch"),
    ("gem install rails -v '>= 1'", [gem("rails", ">= 1", False)], "gem: range"),
    ("gem install rails -v 1.x", [gem("rails", "1.x", False)], "gem: 1.x"),
    ("cargo add serde@1.0.210", [crate("serde", "^1.0.210", False)], "cargo add: bare is caret"),
    ("cargo add serde@*", [crate("serde", "*", False)], "cargo add: *"),
])

# ---------------------------------------------------------------------------------------------
# Multi-package commands: every package is returned
# ---------------------------------------------------------------------------------------------
add_cases("multi-package", [
    ("npm install zod@3.23.8 left-pad@1.3.0", [npm("zod", "3.23.8", True), npm("left-pad", "1.3.0", True)],
     "the card's multi-package scenario"),
    ("npm install zod@3.23.8 left-pad", [npm("zod", "3.23.8", True), npm("left-pad", None, False)],
     "an unpinned package later in the command is still returned"),
    ("npm install left-pad zod@3.23.8", [npm("left-pad", None, False), npm("zod", "3.23.8", True)],
     "an unpinned package first"),
    ("npm install a@1.0.0 b@2.0.0 c@3.0.0 d",
     [npm("a", "1.0.0", True), npm("b", "2.0.0", True), npm("c", "3.0.0", True), npm("d", None, False)], "four"),
    ("pip install requests==2.32.3 flask==3.0.0", [pypi("requests", "2.32.3", True), pypi("flask", "3.0.0", True)],
     "pip"),
    ("cargo add serde@=1.0.210 tokio", [crate("serde", "1.0.210", True), crate("tokio", None, False)], "cargo"),
    ("go get a.example/m@v1.0.0 b.example/m@v2.0.0", [gomod("a.example/m", "v1.0.0", True),
                                                     gomod("b.example/m", "v2.0.0", True)], "go"),
    ("npm install zod@3.23.8 ./local-pkg", [npm("zod", "3.23.8", True), other("npm", "./local-pkg", "npm")],
     "registry and non-registry mixed"),
])

# ---------------------------------------------------------------------------------------------
# source: other
# ---------------------------------------------------------------------------------------------
NPM_OTHER = ["./local-pkg", "../sibling", "/abs/pkg", "github:user/repo", "gitlab:user/repo",
             "bitbucket:user/repo", "gist:abc123", "git:github.com/u/r", "git@github.com:u/r.git", "user/repo",
             "user/repo#semver:^1.0.0", "file:../foo", "link:../foo",
             "workspace:*", "git+https://github.com/u/r.git", "git+ssh://git@github.com/u/r.git",
             "https://example.com/p.tgz", "http://example.com/p.tgz", "./pkg.tgz", "pkg.tar.gz", "~/pkg"]
add_cases("source other", [("npm install {}".format(v), [other("npm", v, "npm")], "npm: {}".format(v))
                           for v in NPM_OTHER])
add_cases("source other", [
    ("npm install github:user/repo", [other("npm", "github:user/repo", "npm")], "the card's scenario"),
    ("npm install foo@file:../foo", [other("npm", "foo@file:../foo", "npm")], "name@file:"),
    ("npm install foo@workspace:*", [other("npm", "foo@workspace:*", "npm")], "name@workspace:"),
    ("npm install foo@github:user/repo", [other("npm", "foo@github:user/repo", "npm")], "name@github:"),
    ("npm install foo@https://example.com/p.tgz", [other("npm", "foo@https://example.com/p.tgz", "npm")],
     "name@URL"),
    ("pnpm add ./local-pkg", [other("npm", "./local-pkg", "pnpm")], "pnpm path"),
    ("yarn add file:../foo", [other("npm", "file:../foo", "yarn")], "yarn file:"),
    ("bun add github:user/repo", [other("npm", "github:user/repo", "bun")], "bun git"),
    ("pip install ./local", [other("pypi", "./local", "pip")], "pip path"),
    ("pip install git+https://github.com/u/r.git", [other("pypi", "git+https://github.com/u/r.git", "pip")],
     "pip git"),
    ("pip install https://example.com/p-1.0-py3-none-any.whl",
     [other("pypi", "https://example.com/p-1.0-py3-none-any.whl", "pip")], "pip URL"),
    ("pip install pkg-1.0-py3-none-any.whl", [other("pypi", "pkg-1.0-py3-none-any.whl", "pip")], "pip wheel"),
    ("pip install -e ./pkg", [other("pypi", "./pkg", "pip")], "editable local path"),
    ("pip install -e git+https://github.com/u/r.git#egg=r",
     [other("pypi", "git+https://github.com/u/r.git#egg=r", "pip")], "editable git"),
    ("pip install 'pkg @ https://example.com/p.zip'", [other("pypi", "pkg @ https://example.com/p.zip", "pip")],
     "PEP 508 direct reference"),
    ("uv add ./local", [other("pypi", "./local", "uv")], "uv path"),
    ("poetry add ../local", [other("pypi", "../local", "poetry")], "poetry path"),
    ("npx ./local-tool", [other("npm", "./local-tool", "npx", "npx")], "a runner given a path"),
    ("uvx ./local-tool", [other("pypi", "./local-tool", "uvx", "uvx")], "uvx given a path"),
])

# A git URL, git-host shorthand or local path is `source: other` wherever it sits (card, "Not from a
# registry"): after `name@`, after `npm:` in an alias, and as a pip argument containing `/`.
SHORTHAND_VERSIONS = ["user/repo", "user/repo#semver:^1.0.0", "my-org/my.repo_2", "user/repo#abc123"]
for _v in SHORTHAND_VERSIONS:
    add_cases("source other after name@", [
        ("npm install foo@{}".format(_v), [other("npm", "foo@" + _v, "npm")], "npm"),
        ("npm i @scope/foo@{}".format(_v), [other("npm", "@scope/foo@" + _v, "npm")], "scoped name"),
        ("pnpm add foo@{}".format(_v), [other("npm", "foo@" + _v, "pnpm")], "pnpm add"),
        ("pnpm install foo@{}".format(_v), [other("npm", "foo@" + _v, "pnpm")], "pnpm install"),
        ("yarn add foo@{}".format(_v), [other("npm", "foo@" + _v, "yarn")], "yarn add"),
        ("bun add foo@{}".format(_v), [other("npm", "foo@" + _v, "bun")], "bun add"),
        ("bun install foo@{}".format(_v), [other("npm", "foo@" + _v, "bun")], "bun install"),
        ("npx foo@{} hi".format(_v), [other("npm", "foo@" + _v, "npx", "npx")], "npx"),
        ("pnpm dlx foo@{} hi".format(_v), [other("npm", "foo@" + _v, "pnpm", "pnpm dlx")], "pnpm dlx"),
        ("npm exec foo@{} -- hi".format(_v), [other("npm", "foo@" + _v, "npm", "npm exec")], "npm exec"),
    ])
add_cases("source other after name@", [
    ("npx -p foo@user/repo cmd",
     [_intent("npm", "foo@user/repo", None, "npx", False, "npx", "other", via=True), npm("cmd", None, False, "npx", "npx")],
     "-p value is source other and still marked via_package_option"),
    ("npm install zod@3.23.8 foo@user/repo", [npm("zod", "3.23.8", True), other("npm", "foo@user/repo", "npm")],
     "mixed: the registry package is unaffected"),
])
add_cases("source other after npm:", [
    ("npm install foo@npm:user/repo", [other("npm", "user/repo", "npm")], "alias to a shorthand"),
    ("npm install foo@npm:user/repo#semver:^1.0.0", [other("npm", "user/repo#semver:^1.0.0", "npm")],
     "alias to a shorthand with a ref"),
    ("npm install foo@npm:bar@user/repo", [other("npm", "bar@user/repo", "npm")], "alias, shorthand after name@"),
    ("npm install foo@npm:@s/bar@user/repo", [other("npm", "@s/bar@user/repo", "npm")], "scoped alias target"),
    ("npm install foo@npm:github:user/repo", [other("npm", "github:user/repo", "npm")], "alias to github:"),
    ("pnpm add foo@npm:user/repo", [other("npm", "user/repo", "pnpm")], "alias under pnpm"),
])
add_cases("not a shorthand after name@", [
    ("npm install 'zod@3.23.8/../evil'", [npm("zod", "3.23.8/../evil", False)],
     "a malformed version is unpinned (card line 245), not a source"),
    ("npm install 'zod@1.0/x'", [npm("zod", "1.0/x", False)], "dots are not allowed in a GitHub user"),
    ("npm install 'zod@../x'", [other("npm", "zod@../x", "npm")], "a ../ path is a local path"),
    ("npm install 'zod@a/b/c'", [npm("zod", "a/b/c", False)], "three parts are not user/repo"),
    ("npm install zod@next", [npm("zod", "next", False)], "a dist-tag is unpinned, not a source"),
])
add_cases("source other: pip argument with /", [
    ("pip install user/repo", [other("pypi", "user/repo", "pip")], "bare user/repo"),
    ("pip install sub/dir", [other("pypi", "sub/dir", "pip")], "relative directory"),
    ("pip3 install sub/dir", [other("pypi", "sub/dir", "pip3")], "pip3"),
    ("python3 -m pip install sub/dir", [other("pypi", "sub/dir", "python3")], "python -m pip"),
    ("uv pip install sub/dir", [other("pypi", "sub/dir", "uv")], "uv pip"),
    ("pip install ./pkg", [other("pypi", "./pkg", "pip")], "dot-slash"),
    ("pip install a/b/c", [other("pypi", "a/b/c", "pip")], "several levels"),
    ("pip install a/b==1.0", [other("pypi", "a/b==1.0", "pip")], "the slash is in the name part"),
    ("pip install -e sub/dir", [other("pypi", "sub/dir", "pip")], "editable directory"),
    ("pip install requests==2.32.3 sub/dir", [pypi("requests", "2.32.3", True), other("pypi", "sub/dir", "pip")],
     "mixed: the registry package is unaffected"),
    ("uv add sub/dir", [other("pypi", "sub/dir", "uv")], "uv add"),
    ("poetry add sub/dir", [other("pypi", "sub/dir", "poetry")], "poetry add"),
    ("pip install 'requests==2.32.3/../evil'", [pypi("requests", "2.32.3/../evil", False)],
     "a malformed VERSION stays unpinned (card scenario, MSG_UNPINNED), the slash is not in the name"),
    ("pip install 'requests>=2/x'", [pypi("requests", ">=2/x", False)], "same, other operator"),
])
add_cases("go and homebrew slashes are not sources", [
    ("go get golang.org/x/text@v0.14.0", [gomod("golang.org/x/text", "v0.14.0", True)],
     "a Go module path has slashes and is a registry intent"),
    ("go get github.com/user/repo@v1.2.3", [gomod("github.com/user/repo", "v1.2.3", True)],
     "a Go module hosted on github is still a Go module"),
    ("go install golang.org/x/tools/cmd/goimports@v0.20.0",
     [gomod("golang.org/x/tools/cmd/goimports", "v0.20.0", True)], "go install"),
    ("brew install user/tap/formula", [brew("user/tap/formula")], "a tap formula is a registry intent"),
    ("brew install homebrew/core/jq", [brew("homebrew/core/jq")], "a tap formula, core"),
])

# ---------------------------------------------------------------------------------------------
# Every runner: each member of RUNNERS names a package and returns form: run
# ---------------------------------------------------------------------------------------------
# runner -> (command template, ecosystem, tool, pinned package spelling, its name, version)
RUNNER_FORMS = {
    "npx": ("npx {p} hi", "npx", "npm"), "pnpx": ("pnpx {p} hi", "pnpx", "npm"),
    "pnx": ("pnx {p} hi", "pnx", "npm"), "bunx": ("bunx {p} hi", "bunx", "npm"),
    "bun x": ("bun x {p} hi", "bun", "npm"), "npm exec": ("npm exec {p} -- hi", "npm", "npm"),
    "npm x": ("npm x {p} -- hi", "npm", "npm"), "pnpm dlx": ("pnpm dlx {p} hi", "pnpm", "npm"),
    "pn dlx": ("pn dlx {p} hi", "pn", "npm"), "yarn dlx": ("yarn dlx {p} hi", "yarn", "npm"),
    "yarnpkg dlx": ("yarnpkg dlx {p} hi", "yarnpkg", "npm"),
    "uvx": ("uvx {p} check", "uvx", "pypi"), "uv tool run": ("uv tool run {p} check", "uv", "pypi"),
    "pipx run": ("pipx run {p} --help", "pipx", "pypi"),
}


def _spelling(eco, name, version):
    if version is None:
        return name
    return "{}@{}".format(name, version) if eco == "npm" else "{}=={}".format(name, version)


for _runner, (_tmpl, _tool, _eco) in sorted(RUNNER_FORMS.items()):
    for _name, _ver, _pin in ([("cowsay", "1.6.0", True), ("cowsay", None, False)]
                              + ([("@sc/tool", "2.0.0", True)] if _eco == "npm" else [])
                              + [("npm" if _eco == "npm" else "pip", "12.0.1", True)]):
        _want = [_intent(_eco, _name, _ver, _tool, _pin, runner=_runner)]
        add_cases("runner {}".format(_runner), [(_tmpl.format(p=_spelling(_eco, _name, _ver)), _want,
                   "form run, pinned set by the version spelling; a package manager is still an intent")])
    add_cases("runner {}".format(_runner), [
        ("{} --help".format(_runner), [], "a lone --help names no package"),
        ("{} --version".format(_runner), [], "a lone --version names no package"),
    ])
    add_cases("runner {}".format(_runner), [
        ("sudo " + _tmpl.format(p=_spelling(_eco, "cowsay", "1.6.0")),
         [_intent(_eco, "cowsay", "1.6.0", _tool, True, runner=_runner)], "wrapped runner"),
        ("cd x && " + _tmpl.format(p=_spelling(_eco, "cowsay", "1.6.0")),
         [_intent(_eco, "cowsay", "1.6.0", _tool, True, runner=_runner)], "chained runner"),
    ])


def _check_runner_forms_cover_runners():
    want, got = set(_MOD.RUNNERS), set(RUNNER_FORMS)
    return want == got, "RUNNERS has {} members; this suite exercises {}; only in RUNNERS: {}; only here: {}".format(
        len(want), len(got), sorted(want - got), sorted(got - want))


add_check("runner coverage: this suite exercises exactly the members of RUNNERS", _check_runner_forms_cover_runners)
add_check("runner coverage: RUNNERS has 14 distinct members", lambda: (
    len(_MOD.RUNNERS) == 14 and len(set(_MOD.RUNNERS)) == 14, "RUNNERS = {!r}".format(_MOD.RUNNERS)))
add_cases("runner of a package manager", [
    ("npx npm@12.0.1 install left-pad", [npm("npm", "12.0.1", True, "npx", "npx")],
     "a pinned intent for npm, which step 0 then refuses"),
    ("npx npm install left-pad@1.3.0", [npm("npm", None, False, "npx", "npx")], "unpinned npm via npx"),
    ("npx NPM install left-pad@1.3.0", [npm("NPM", None, False, "npx", "npx")], "name spelling kept"),
    ("pnpm dlx yarn@1.22.22 add left-pad", [npm("yarn", "1.22.22", True, "pnpm", "pnpm dlx")], "pnpm dlx yarn"),
    ("uvx pip==24.2 install requests", [pypi("pip", "24.2", True, "uvx", "uvx")], "uvx pip"),
    ("npx corepack pnpm add left-pad", [npm("corepack", None, False, "npx", "npx")], "npx corepack"),
    ("npm exec npm@12.0.1 install left-pad", [npm("npm", "12.0.1", True, "npm", "npm exec")], "npm exec npm"),
    ("pnx npm@12.0.1 install left-pad", [npm("npm", "12.0.1", True, "pnx", "pnx")], "pnx npm"),
])

# ---------------------------------------------------------------------------------------------
# is_exact_version: every accepted example and every refused value, per pattern
# ---------------------------------------------------------------------------------------------
REFUSED_BY_ALL = ["2.32.3/../evil", "^1.0.0", "1.x", "latest", "~1.2.3", "*", ">=1.0", "=1.2.3", "1.2.3/..", "..",
                  "1.0.0-a..b", "1.0.0+..", "1.0.0-..", "v1.0.0-..", "３.２３.８", "3.23.8\n",
                  "", " 3.23.8", "3.23.8 "]
PATTERNS = {
    "npm": (["3.23.8", "1.0.0-rc.1", "1.0.0+build.5"], ["01.2.3", "1.02.3", "v1.2.3", "1.2", "1.2.3.4"]),
    "crates.io": (["3.23.8", "1.0.0-rc.1", "1.0.0+build.5"], ["01.2.3", "1.02.3", "v1.2.3", "1.2", "1.2.3.4"]),
    "pypi": (["2.32.3", "1.0rc1", "2.1.0+cu118", "2.1.0+CU118"], []),
    "go": (["v0.3.8", "v1.2.3-pre.1", "v2.0.0+incompatible"], ["v01.2.3", "v1.02.3", "1.2.3", "v1.2"]),
    "rubygems": (["7.1.3", "1.0.0.pre", "13.0"], ["01.2.3", "1.02.3", "1", "v1.2.3"]),
}


def _call(fn, *args):
    try:
        return fn(*args), ""
    except Exception as exc:  # a missing function must read as a failed check, not abort the run
        return None, "{}: {}".format(type(exc).__name__, exc)


for _eco, (_ok_values, _extra_refused) in PATTERNS.items():
    for _value in _ok_values:
        def thunk(eco=_eco, value=_value):
            got, err = _call(_MOD.is_exact_version, eco, value)
            return got is True, "is_exact_version({!r}, {!r}) = {!r} {}".format(eco, value, got, err)
        add_check("is_exact_version {} accepts {!r}".format(_eco, _value), thunk)
    for _value in REFUSED_BY_ALL + _extra_refused:
        def thunk(eco=_eco, value=_value):
            got, err = _call(_MOD.is_exact_version, eco, value)
            return got is False, "is_exact_version({!r}, {!r}) = {!r} {}".format(eco, value, got, err)
        add_check("is_exact_version {} refuses {!r}".format(_eco, _value), thunk)
add_check("is_exact_version: the classifier uses the one definition in vetting_record", lambda: (
    getattr(_MOD, "is_exact_version", None) is not None
    and _MOD.is_exact_version is __import__("vetting_record").is_exact_version,
    "classify-install-command must import is_exact_version, not redefine it"))

# The same values through the command line, which is where `pinned` is actually produced. A value
# with a newline cannot be typed on one line (the lexer turns it into ';'), so those stay above.
_CLI_SPELLINGS = [
    ("npm", lambda v: "npm install 'zod@{}'".format(v)),
    ("crates.io", lambda v: "cargo install 'serde@{}'".format(v)),
    ("pypi", lambda v: "pip install 'requests=={}'".format(v)),
    ("go", lambda v: "go get 'example.com/m@{}'".format(v)),
    ("rubygems", lambda v: "gem install rails -v '{}'".format(v)),
]
for _eco, _build in _CLI_SPELLINGS:
    _accepted, _extra = PATTERNS[_eco]
    for _value in _accepted:
        def thunk(eco=_eco, value=_value, build=_build):
            got = classify(build(value))
            return len(got) == 1 and got[0]["pinned"] is True and got[0]["version"] == value, repr(got)
        add_check("pinned via command line {} accepts {!r}".format(_eco, _value), thunk)
    for _value in [v for v in REFUSED_BY_ALL + _extra if "\n" not in v and v not in ("", "=1.2.3")
                   and v == v.strip()]:  # pip and cargo read a padded specifier as the bare one
        def thunk(eco=_eco, value=_value, build=_build):
            got = classify(build(value))
            return len(got) >= 1 and all(i["pinned"] is False for i in got), repr(got)
        add_check("pinned via command line {} refuses {!r}".format(_eco, _value), thunk)
add_cases("pinned from a null version", [
    ("npm install zod", [npm("zod", None, False)], "null is never pinned"),
    ("brew install jq", [brew("jq")], "homebrew is never pinned"),
])

# ---------------------------------------------------------------------------------------------
# The cannot-read case, and the INSTALL_TOOL_WORDS helpers the hook shares
# ---------------------------------------------------------------------------------------------
UNREADABLE_WITH_TOOL = [
    "echo it's; npm i zod@3.23.8", "echo it's; NPM I zod@3.23.8", "cat <<EOF\nit's here\nEOF\nnpm i zod@3.23.8",
    "echo it's && bunx cowsay@1.6.0", "echo it's; Pip install requests==2.32.3", "echo it's; /usr/bin/NPM i x",
    "echo it's; cargo add serde", "echo it's; python3 -m pip install x", "echo it's; brew install jq",
    "echo it's; uvx ruff", "echo it's; YARNPKG add x", "echo it's; Go get x",
]
UNREADABLE_NO_TOOL = ["echo it's fine", "echo it's; ls -la", "cat <<EOF\nit's\nEOF",
                      "echo it's; echo hello"]
for _cmd in UNREADABLE_WITH_TOOL + UNREADABLE_NO_TOOL:
    add_check("cannot read: classify returns [] for {!r}".format(_cmd), lambda c=_cmd: (
        classify(c) == [], "an unreadable command yields no intents"))
for _cmd in UNREADABLE_WITH_TOOL:
    add_check("cannot read: is_unreadable and mentions_install_tool for {!r}".format(_cmd), lambda c=_cmd: (
        _call(_MOD.is_unreadable, c)[0] is True and _call(_MOD.mentions_install_tool, c)[0] is True,
        "non-blank, unlexable, names a tool -> the hook asks"))
for _cmd in UNREADABLE_NO_TOOL:
    add_check("cannot read: is_unreadable without a tool word for {!r}".format(_cmd), lambda c=_cmd: (
        _call(_MOD.is_unreadable, c)[0] is True and _call(_MOD.mentions_install_tool, c)[0] is False,
        "non-blank, unlexable, no tool word -> the hook allows and logs"))
for _cmd in ["", "   ", "\n", "npm i zod@3.23.8", "ls -la", "echo hi"]:
    add_check("cannot read: is_unreadable is False for readable {!r}".format(_cmd), lambda c=_cmd: (
        _call(_MOD.is_unreadable, c)[0] is False, "blank and lexable commands are not 'cannot read'"))

TOOL_WORD_HITS = ["npm i x", "NPM i x", "Npm", "echo foo; npm", "(npm)", "'npm'", "x=npm", "a;npm;b", "pip3 install",
                  "python3 -m pip", "uvx", "yarnpkg", "pn", "bun", "go get x", "GO get x", "path/npm i"]
TOOL_WORD_MISSES = ["foo-npm", "npm-run-all", "npm.js", "_npm", "anpm", "npmx", "my.npm", "pip-compile", "pipe",
                    "bunny", "gopher", "cargoship", "gemstone", "brewery", "uvxx", "pnpmx", "x-pn", "pn.js", "npm_",
                    "", "echo hello world"]
for _text in TOOL_WORD_HITS:
    add_check("tool word: whole word in {!r}".format(_text), lambda t=_text: (
        _call(_MOD.mentions_install_tool, t)[0] is True, "a whole word, any case"))
for _text in TOOL_WORD_MISSES:
    add_check("tool word: not a whole word in {!r}".format(_text), lambda t=_text: (
        _call(_MOD.mentions_install_tool, t)[0] is False, "a neighbour [A-Za-z0-9_.-] makes it part of a longer word"))

EXPECTED_TOOL_WORDS = ["npm", "npx", "pnpm", "pn", "pnpx", "pnx", "yarn", "yarnpkg", "corepack", "bun", "bunx", "pip",
                       "pip3", "python", "python3", "uv", "uvx", "poetry", "pipx", "cargo", "go", "gem", "brew"]
add_check("INSTALL_TOOL_WORDS is exactly the card's list (card lines 496-497)", lambda: (
    sorted(_MOD.INSTALL_TOOL_WORDS) == sorted(EXPECTED_TOOL_WORDS) and len(set(_MOD.INSTALL_TOOL_WORDS)) == len(
        _MOD.INSTALL_TOOL_WORDS),
    "got {!r}".format(tuple(_MOD.INSTALL_TOOL_WORDS))))
add_check("RUNNERS is exactly the card's list (card lines 298-299)", lambda: (
    sorted(_MOD.RUNNERS) == sorted(["npx", "pnpx", "pnx", "bunx", "bun x", "npm exec", "npm x", "pnpm dlx", "pn dlx",
                                    "yarn dlx", "yarnpkg dlx", "uvx", "uv tool run", "pipx run"]),
    "got {!r}".format(tuple(_MOD.RUNNERS))))

# ---------------------------------------------------------------------------------------------
# The sync tests. DECISION: these parse the card's install-forms table itself, not a copy -- a copy
# would be a second list that can drift from the first, which is what the sync test exists to
# catch. The parse fails loudly (a failed check naming what it could not find) rather than passing
# vacuously, and pins the row count so a new table row forces this parser to be revisited.
# ---------------------------------------------------------------------------------------------
TABLE_HEADER = "| Tool | Install forms | Exact-version spelling |"
TABLE_ROW_COUNT = 11


def _card_table_rows():
    if not os.path.isfile(CARD_PATH):
        raise AssertionError("cannot find the card at {}".format(CARD_PATH))
    with open(CARD_PATH, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    starts = [i for i, line in enumerate(lines) if line.strip() == TABLE_HEADER]
    if len(starts) != 1:
        raise AssertionError("expected exactly one {!r} header in the card, found {}".format(TABLE_HEADER, len(starts)))
    rows = []
    for line in lines[starts[0] + 2:]:
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 3:
            raise AssertionError("install-forms row does not have 3 cells: {!r}".format(line[:80]))
        rows.append(cells)
    if len(rows) != TABLE_ROW_COUNT:
        raise AssertionError("install-forms table has {} rows, this parser knows {}; revisit the parser".format(
            len(rows), TABLE_ROW_COUNT))
    return rows


def _row(rows, prefix):
    found = [r for r in rows if r[0].startswith(prefix)]
    if len(found) != 1:
        raise AssertionError("expected exactly one install-forms row starting {!r}, found {}".format(prefix, len(found)))
    return found[0]


def _backticked(text):
    return re.findall(r"`([^`]+)`", text)


def _card_runners():
    """The runner forms the table names (card line 300-302): npm exec/x; the npx row; the 'runners' list in
    the pnpm/yarn/bun row; uvx, uv tool run and pipx run in the uvx row."""
    rows = _card_table_rows()
    found = set()
    npm_tail = _row(rows, "npm")[1].rsplit(";", 1)[1]
    names = _backticked(npm_tail)
    if names != ["exec", "x"]:
        raise AssertionError("expected `exec`/`x` after the last ';' of the npm row, got {!r}".format(names))
    found.update("npm " + n for n in names)
    if _row(rows, "npx")[0] != "npx":
        raise AssertionError("the npx row's first cell is not exactly 'npx'")
    found.add("npx")
    managers = _row(rows, "pnpm, yarn, bun")[1]
    if "runners " not in managers:
        raise AssertionError("no 'runners' list in the pnpm/yarn/bun row")
    found.update(_backticked(managers.split("runners ", 1)[1]))
    uvx_cell = _row(rows, "uvx")[0]
    items = [uvx_cell.split(",")[0].strip()] + _backticked(uvx_cell)
    runners = [i for i in items if i == "uvx" or i.endswith(" run")]
    if sorted(runners) != ["pipx run", "uv tool run", "uvx"]:
        raise AssertionError("expected uvx, uv tool run, pipx run in the uvx row, got {!r}".format(runners))
    found.update(runners)
    return found


def _card_programs():
    """Every program name the table names: the first word of each Tool-cell item (backticked or not),
    plus the first word of each runner form."""
    rows = _card_table_rows()
    found = set()
    for cells in rows:
        col1 = cells[0]
        spans = _backticked(col1)
        found.update(s.split()[0] for s in spans)
        bare = re.sub(r"`[^`]*`", "", col1)
        for piece in bare.split(","):
            match = re.match(r"\s*([a-z][a-z0-9]*)", piece)
            if match:
                found.add(match.group(1))
    found.update(r.split()[0] for r in _card_runners())
    found.discard("and")
    return found


def _check_runners_card_subset():
    _assert_card_parse_is_not_vacuous()
    card, mod = _card_runners(), set(_MOD.RUNNERS)
    return card <= mod, "in the card table but not in RUNNERS: {}".format(sorted(card - mod))


def _check_runners_mod_subset():
    _assert_card_parse_is_not_vacuous()
    card, mod = _card_runners(), set(_MOD.RUNNERS)
    return bool(mod) and mod <= card, "in RUNNERS but not in the card table: {}".format(sorted(mod - card))


def _check_tool_words_cover_table():
    _assert_card_parse_is_not_vacuous()
    card, words = _card_programs(), set(_MOD.INSTALL_TOOL_WORDS)
    return card <= words, "named in the install-forms table but not in INSTALL_TOOL_WORDS: {}".format(
        sorted(card - words))


def _assert_card_parse_is_not_vacuous():
    """Run first by every sync check, so a parser that quietly finds nothing fails them instead of
    letting an empty-set comparison pass."""
    programs, runners = _card_programs(), _card_runners()
    need = {"npm", "npx", "pnpm", "pn", "pnpx", "pnx", "yarn", "yarnpkg", "corepack", "bun", "bunx", "pip", "pip3",
            "python", "uv", "uvx", "poetry", "pipx", "cargo", "go", "gem", "brew"}
    if not (need <= programs and len(runners) == 14):
        raise AssertionError("card parse looks wrong: programs {} runners {}".format(sorted(programs), sorted(runners)))


add_check("sync: every runner in the card table is in RUNNERS", _check_runners_card_subset)
add_check("sync: every member of RUNNERS is a runner form in the card table", _check_runners_mod_subset)
add_check("sync: every program in the install-forms table is in INSTALL_TOOL_WORDS", _check_tool_words_cover_table)


# ---------------------------------------------------------------------------------------------
def main():
    verbose = "-v" in sys.argv[1:]
    passed = failed = 0
    for name, thunk in _CHECKS:
        try:
            ok, detail = thunk()
        except Exception as exc:  # an exception is a failed check, with its reason; never a silent skip
            ok, detail = False, "raised {}: {}".format(type(exc).__name__, exc)
        if ok:
            passed += 1
            if verbose:
                print("PASS " + name)
        else:
            failed += 1
            print("FAIL " + name + ("\n       " + detail if detail and not verbose else ""))
    print("\nclassify-install-command unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
