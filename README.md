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
    * [name](#name)
    * [abstract](#abstract)
    * [author](#author)
    * [license](#license)
    * [requires](#requires)
    * [repo_link](#repo_link)
    * [is_original](#is_original)
    * [lib_dir](#lib_dir)
    * [main_module](#main_module)
    * [doc_dir](#doc_dir)
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

# search package names and abstracts with the user pattern "lock".
opm search lock

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
or `pip`. Our `opm` adopts a package naming discipline similar to `github`, that
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

`opm` has built-in support for the `restydoc` tool, that is, the documentation
of the packages installed via `opm` is already indexed by `restydoc` and can
be viewed directly on the terminal with the `restydoc` tool.

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

    search PATTERN      Search on the server for packages matching the user pattern in their
                        names or abstracts.

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
# distribution config for opm packaging
name = lua-resty-core
abstract = New FFI-based Lua API for the ngx_lua module
author = Yichun "agentzh" Zhang (agentzh)
is_original = yes
license = 2bsd
lib_dir = lib
doc_dir = lib
repo_link = https://github.com/openresty/lua-resty-core
main_module = lib/resty/core/base.lua
requires = luajit, openresty = 1.11.2.1, openresty/lua-resty-lrucache >= 0.04
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

# the opm central servers for uploading openresty packages.
upload_server=https://opm.openresty.org
download_server=https://opm.openresty.org
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

The `dist.ini` file specifies the meta data of a package and is used by `opm build`
to generate a tarball that is ready to upload to the remote pacakge server. This
file should sit at the top of the library or module source tree.

This file uses the [INI file format](https://en.wikipedia.org/wiki/INI_file). It
contains the following keys (or properties) in the default top-level section:

[Back to TOC](#table-of-contents)

name
----

Specifies the name of the package (excluding version numbers). For example,

```ini
name = lua-resty-limit-traffic
```

The name can only contain letters, digits, and dashes (`-`).

This key is mandatory.

[Back to TOC](#table-of-contents)

abstract
--------

Abstract for the current package.

```ini
abstract = New FFI-based Lua API for the ngx_lua module
```

This key is mandatory.

[Back to TOC](#table-of-contents)

author
------

Specifies one or more authors of the libraries. For instance,

```ini
author = Yichun Zhang (agentzh)
```

The names of multiple authors should
be separated by a comma, with optional surrounding spaces.

```ini
author = Yichun Zhang (agentzh), Dejiang Zhu
```

This key is mandatory.

[Back to TOC](#table-of-contents)

license
-------

Specifies the license for the library. For example,

```ini
license = 3bsd
```

This assigns the 3-clause BSD license to the current package.

Special IDs for common code licenses are required. For now, the following IDs are supported:

* `2bsd`

BSD 2-Clause "Simplified" or "FreeBSD" license
* `3bsd`

BSD 3-Clause "New" or "Revised" license
* `apache2`

Apache License 2.0
* `artistic`

Artistic License
* `artistic2`

Artistic License 2.0
* `cddl`

Common Development and Distribution License
* `eclipse`

Eclipse Public License
* `gpl`

GNU General Public License (GPL)
* `gpl2`

GNU General Public License (GPL) version 2
* `gpl3`

GNU General Public License (GPL) version 3
* `lgpl`

GNU Library or "Lesser" General Public License (LGPL)
* `mit`

MIT license
* `mozilla2`

Mozilla Public License 2.0
* `proprietary`

Proprietary
* `public`

Public Domain

If you do need an open source license not listed above, please let us know.

It is also possible to specify multiple licenses at the same time, as in

```ini
license = gpl2, artistic2
```

This specifies dual licenses: GPLv2 and Artistic 2.0.

To upload the package to the official opm package server, you must at least specify
an open source license here.

This key is mandatory.

[Back to TOC](#table-of-contents)

requires
--------

Specifies the runtime dependencies of this package.

Multiple dependencies are separated by commas, with optional surrounding spaces. As in

```ini
requires = foo/lua-resty-bar, baz/lua-resty-blah
```

You can also specify version number requirements, as in

```ini
requires = foo/lua-resty-bar >= 0.3.5
```

The version comparison operators supported are `>=`, `=`, and `>`. Their
semantics is self-explanatory.

You can also specify the following special dependency names:

* `luajit`
* `nginx`
* `openresty`
* `ngx_http_lua`

Below is such an example:

```ini
requires = luajit >= 2.1.0, nginx >= 1.11.2, ngx_http_lua = 0.10.6
```

This key is optional.

[Back to TOC](#table-of-contents)

repo_link
---------

The URL of the code repository (usually on GitHub). For example,

```ini
repo_link = https://github.com/openresty/lua-resty-core
```

If the repository is on GitHub, then `opm build` ensures that the name
specified in the `github_account` in your `~/.opmrc` file *does* match
the account in your GitHub repository URL. Otherwise `opm build` reports
an error.

This key is mandatory.

[Back to TOC](#table-of-contents)

is_original
-----------

Takes the value `yes` or `no` to specify whether this package is an original work
(that is, not a fork of another package of somebody else).

This key is mandatory.

[Back to TOC](#table-of-contents)

lib_dir
-------

Specifies the root directory of the library files (`.lua` files, for example).

Default to `lib`.

This key is optional.

[Back to TOC](#table-of-contents)

main_module
-----------

This key specifies the PATH of the "main module" file of the current package.
The `opm build` command reads the "main module" file to extract the version number
of the current package, for example.

When this key is not specified, then `opm build` will try to find the main module
file automatically (which might be wrong though).

This key is optional.

[Back to TOC](#table-of-contents)

doc_dir
-------

Specifies the root directory of the documentation files. Default to `lib`.

`opm build` always tries to collect the documentation files in either the Markdown (`.md` or `.markdown`)
or the POD (`.pod`) format.

Regardless of the value of this `doc_dir` key, `opm build` always tries to collect
the following files in the current working directory (which should be the root of
the current package):

* `README.md`, `README.markdown`, or `README.pod`
* `COPYING`
* `COPYRIGHT`
* `Changes.md`, `Changes.markdown`, or `Changes.pod`

This key is optional.

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
* Add `opm doctor` command to check if there is any inconsistency in the current opm package installation tree.
* Add `opm files <package>` command to list all the files in the specified package.
* Add `opm whatprovides <package>` command to find out which package the specified file belongs to.
* Add plugin mechanisms to `opm build` (similar to Perl's Dist::Zilla packaging framework).
* Add a web site for opm.openresty.org (similar to search.cpan.org).
* Add support for Lua C modules and LuaJIT FFI modules with standalone C libraries.
* Add (limited) support for LuaRocks via the special name space `luarocks`, for example,

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

