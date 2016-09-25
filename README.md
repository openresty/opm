Name
====

opm - Official package management system for OpenResty

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
* [Description](#description)
* [Prerequisites](#prerequisites)
    * [For opm](#for-opm)
* [TODO](#todo)
* [Author](#author)
* [Copyright and License](#copyright-and-license)

Status
======

This is still under early active development and it is not complete nor usable yet.

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

Prerequisites
=============

For opm
-------

You just need `perl`, `tar`, and `curl` to run the `opm` tool. Ensure that your perl is not
too old (should be at least `5.10.1`), and your curl supports SNI.

[Back to TOC](#table-of-contents)

TODO
====

* Add `opm search <pattern>` command.
* Add `opm files <package>` command.
* Add `opm whatprovides <package>` command.
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

