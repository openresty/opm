Name
====

opm - Official package management system for OpenResty

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
* [Description](#description)
* [Usage](#usage)
* [Author Workflow](#author-workflow)
* [File dist.ini](#file-distini)
* [File .opmrc](#file-opmrc)
* [Prerequisites](#prerequisites)
    * [For opm](#for-opm)
* [TODO](#todo)
* [Author](#author)
* [Copyright and License](#copyright-and-license)

Status
======

This is still under early active development and it is not complete nor fully usable yet.

Check back often ;)

Synopsis
========

For library users:

```bash
# show usage
opm --help

# account is a github account (either a github user or a github org);
# lua-resty-foo is the library name under that github account.
opm get some_account/lua-resty-foo

# show the details of the installed package specified by name.
opm info lua-resty-foo

# show all the installed packages.
opm list

# upgrade package lua-resty-foo to the latest version.
opm upgrade lua-resty-foo

# update all the installed packages to their latest version.
opm update

# uninstall the newly installed package
opm remove lua-resty-foo
```

All the commands can follow the `--cwd` option to work in the current working
directory (under ./resty/modules/) instead of the system-wide location.

```bash
# install into ./resty_modules/ instead of the system-wide location:
opm --cwd get foo/lua-resty-bar

# check the locally installed packages under ./resty_modules/
opm --cwd list

# remove the locally installed packages under ./resty_modules/
opm --cwd remove lua-resty-bar
```

For library authors:

```bash
cd /path/to/lua-resty-foo/

opm build

# optional:
#     cd lua-resty-foo-VERSION/ && opm server-build

# you may need to edit the ~/.opmrc file to set up your github
# personal access tokens. the first run of "opm upload" will create
# a boilerplate ~/.opmrc file for you.
opm upload
```

Description
===========

`opm` is the official OpenResty package management system kinda similar to
Perl's CPAN.

We provide both the `opm` client-side command-line utility and
the server-side application for the central package repository in this
GitHub code repository.

The `opm` command-line utility can be used by OpenResty users to download
packages published on the central `opm` server (i.e., `opm.openresty.org`).
It can also be used to package and upload the OpenResty package to the server
for package authors and maintainers. You can find the source of `opm` under
the `bin/` directory. It is currently implemented as a standalone Perl script.

The server side web application is built upon OpenResty and written in Lua.
You can find the server code under the `web/` directory.

Unlike many other package management systems like `cpan`, `luarocks`, `npm`,
or `pip`, `opm` adopts a package naming discipline similar to `github`, that
is, every package name should be qualified by a publisher ID, as in
`agentzh/lua-resty-foo` where `agentzh` is the publisher ID while `lua-resty-foo`
is the package name itself. This naming requirement voids the temptation of
occupying good package names and also allows multiple same-name libraries to
coexist in the same central server repository. It is up to the user to decide
which library to install (or even install multiple forks of the same library
in different projects of hers). For simplicity, we simply map the GitHub
user IDs and organization IDs to the publisher IDs for `opm`. For this reason,
we use the GitHub personal access tokens (or oauth tokens) to authenticate
our package publishers. This also eliminates the sign-up process for `opm`
package authors altogether.

`opm` currently only supports pure Lua libraries but we will add support for
Lua libraries in pure C or with some C components very soon. The vision is
to also add support for redistributing 3rd-party NGINX C modules as dynamic
NGINX modules via `opm` in the future. The OpenResty world consists of various
different kinds of "modules" after all.

We also have plans to allow the user to install LuaRocks packages via `opm`
through the special user ID `luarocks`. Although it poses a risk of installing
an OpenResty-agnostic Lua module which may block the NGINX worker processes
horribly on network I/O. But as the developers of `opm`, we always like choices,
especially choices given to our users.

[Back to TOC](#table-of-contents)

Usage
=====

```
opm [options] command package...

Options:
    -h
    --help              Print this help.

    --cwd               Install into the current working directory under ./resty_modules/
                        instead of the system-wide OpenResty installation tree contaning
                        this tool.

Commands:
    build               Build from the current working directory a package tarball ready
                        for uploading to the server.

    info PACKAGE...     Output the detailed information (or meta data) about the specified
                        packages.  Short package names like "lua-resty-lock" are acceptable.

    get PACKAGE...      Fetch and install the specified packages. Fully qualified package
                        names like "openresty/lua-resty-lock" are required. One can also
                        specify a version constraint like "=0.05" and ">=0.01".

    list                List all the installed packages. Both the package names and versions
                        are displayed.

    remove PACKAGE...   Remove (or uninstall) the specified packages. Short package names
                        like "lua-resty-lock" are acceptable.

    server-build        Build a final package tarball ready for distribution on the server.
                        This command is usually used by the server to verify the uploaded
                        package tarball.

    update              Update all the installed packages to their latest version from
                        the server.

    upgrade PACKAGE...  Upgrade the packages specified by names to the latest version from
                        the server. Short package names like "lua-resty-lock" are acceptable.

    upload              Upload the package tarball to the server. This command always invokes
                        the build command automatically right before uploading.

```

[Back to TOC](#table-of-contents)

Author Workflow
===============

The package author should put a meta-data file named `dist.ini` on the top-level of the Lua library source tree.
This file is used by the `opm build` command to build and package up your library into a tarball file which can be
later uploaded to the central package server via the `opm upload` command.

One example `dist.ini` file looks like below for OpenResty's
[lua-resty-core](https://github.com/openresty/lua-resty-core) library:

```ini
name=lua-resty-core
abstract=New FFI-based Lua API for the ngx_lua module
author=Yichun "agentzh" Zhang (agentzh)
is_original=yes
license=2bsd
lib_dir=lib
doc_dir=lib
repo_link=https://github.com/openresty/lua-resty-core
main_module=lib/resty/core/base.lua
requires = luajit, openresty = 1.11.2.1, openresty/lua-resty-lrucache
```

As we can see, the `dist.ini` file is using the popular [INI file format](https://en.wikipedia.org/wiki/INI_file).
Most of the fields in this example should be self-explanatory. For detailed documentation for the fields available
in `dist.ini`, please check out the [File dist.ini](#file-dist-ini) section.

The `opm build` command also reads and extracts information from the configuration file `.opmrc` under the current
system user's home directory (i.e., with the file path `~/.opmrc`). If the file does not exist, `opm build` will
automatically generates a boilerplate file in that path. One sample `~/.opmrc` file looks like this.

```ini
# your github account name (either your github user name or github organization that you owns)
github_account=agentzh

# you can generate a github personal access token from the web UI: https://github.com/settings/tokens
# IMPORTANT! you are required to assign the scopes "user:email" and "read:org" to your github token.
# you should NOT assign any other scopes to your token due to security considerations.
github_token=0123456789abcdef0123456789abcdef01234567

# the opm central server for uploading openresty packages.
upload_server_link=https://opm.openresty.org/api/pkg/upload
download_server_link=https://opm.openresty.org/api/pkg/fetch
```

Basically, the `opm build` command just needs the `github_account` setting from this file. Other fields are needed
by the `opm upload` command that tries to upload the packaged tarball onto the remote package server. You can either
use your own GitHub login name (which is `agentzh` in this example), or a GitHub organization name that you owns
(i.e., having the `admin` permission to it).

After `opm build` successfully generates a `.tar.gz` file under the current working directory, the author can use
the `opm upload` command to upload that file to the remote server. To ensure consistency, `opm upload` automatically
runs `opm build` itself right before attempting the uploading operation. The central package server (`opm.openresty.org`
in this case) calls the GitHub API behind the scene to validate the author's identify. Thus the author needs to
provide his GitHub personal access token in her `~/.opmrc` file. Only the `user:email` and `read:org` permissions
(or `scopes` in the GitHub terms) need to be assigned to this access token.

[Back to TOC](#table-of-contents)

File dist.ini
=============

TODO

[Back to TOC](#table-of-contents)

File .opmrc
===========

TODO

[Back to TOC](#table-of-contents)

Prerequisites
=============

For opm
-------

You just need `perl`, `tar`, and `curl` to run the `opm` tool. Ensure that your perl is not
too old (should be at least `5.10.1`), and your curl supports SNI.

[Back to TOC](#table-of-contents)

TODO
====

* Add rate limiting to the GitHub API on the package server.
* Add automatic email notification for the package processing results on the package server.
* When the package names provided to `opm get` do not have a publisher ID prefix, we should prompt with a list
of fully qualified package names that match the package short names.
* Add `opm doctor` command to check if there is any inconsistency in the current opm package installation tree.
* Add `opm search <pattern>` command to search package names with a user-supplied pattern.
* Add `opm files <package>` command to list all the files in the specified package.
* Add `opm whatprovides <package>` command to find out which package the specified file belongs to.
* Add plugin mechanisms to `opm build` (similar to Perl's Dist::Zilla packaging framework).
* Add a web site for opm.openresty.org (similar to search.cpan.org).
* Add support for Lua C modules and LuaJIT FFI modules with standalone C libraries.
* Add (limited) support for LuaRocks via the special namespace `luarocks`, for example,

```bash
opm get luarocks/foo
```

[Back to TOC](#table-of-contents)

Author
======

Yichun Zhang (agentzh) <agentzh@gmail.com>, CloudFlare Inc.

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2016, by Yichun "agentzh" Zhang (章亦春) <agentzh@gmail.com>, CloudFlare Inc.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

