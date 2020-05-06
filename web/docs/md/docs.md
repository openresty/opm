Name
====

opm - OpenResty Package Manager

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
* [Description](#description)
* [Usage](#usage)
    * [Global Installation](#global-installation)
    * [Local Installation](#local-installation)
* [HTTP Proxy Support](#http-proxy-support)
* [Author Workflow](#author-workflow)
* [File dist.ini](#file-distini)
    * [name](#name)
    * [abstract](#abstract)
    * [version](#version)
    * [author](#author)
    * [license](#license)
    * [requires](#requires)
    * [repo_link](#repo_link)
    * [is_original](#is_original)
    * [lib_dir](#lib_dir)
    * [exclude_files](#exclude_files)
    * [main_module](#main_module)
    * [doc_dir](#doc_dir)
* [File .opmrc](#file-opmrc)
    * [github_account](#github_account)
    * [github_token](#github_token)
    * [upload_server](#upload_server)
    * [download_server](#download_server)
* [Version Number Handling](#version-number-handling)
* [Installation](#installation)
    * [For opm](#for-opm)
* [Security Considerations](#security-considerations)
* [Credit](#credit)
* [TODO](#todo)
* [Author](#author)
* [Copyright and License](#copyright-and-license)

Status
======

Experimental.

Synopsis
========

For library users:

```bash
# show usage
opm --help

# search package names and abstracts with the user pattern "lock".
opm search lock

# search package names and abstracts with multiple patterns "lru" and "cache".
opm search lru cache

# install a package named lua-resty-foo under the name of some_author
opm get some_author/lua-resty-foo

# get a list of lua-resty-foo packages under all authors.
opm get lua-resty-foo

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

# cleaning up the leftovers of the opm build command.
opm clean dist
```

Description
===========

`opm` is the official OpenResty package manager, similar to
Perl's CPAN and NodeJS's npm in rationale.

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
through the special user ID `luarocks`. It poses a risk of installing
an OpenResty-agnostic Lua module which blocks the NGINX worker processes
horribly on network I/O, nevertheless, as the developers of `opm`, we always like choices,
especially those given to our users.

[Back to TOC](#table-of-contents)

Usage
=====

```
opm [options] command package...

Options:
    -h
    --help              Print this help.


    --install-dir=PATH  Install into the specified PATH directory instead of the system-wide
                        OpenResty installation tree containing this tool.

    --cwd               Install into the current working directory under ./resty_modules/
                        instead of the system-wide OpenResty installation tree containing
                        this tool.

Commands:
    build               Build from the current working directory a package tarball ready
                        for uploading to the server.

    clean ARGUMENT...   Do clean-up work. Currently the valid argument is "dist", which
                        cleans up the temporary files and directories created by the "build"
                        command.

    info PACKAGE...     Output the detailed information (or meta data) about the specified
                        packages.  Short package names like "lua-resty-lock" are acceptable.

    get PACKAGE...      Fetch and install the specified packages. Fully qualified package
                        names like "openresty/lua-resty-lock" are required. One can also
                        specify a version constraint like "=0.05" and ">=0.01".

    list                List all the installed packages. Both the package names and versions
                        are displayed.

    remove PACKAGE...   Remove (or uninstall) the specified packages. Short package names
                        like "lua-resty-lock" are acceptable.

    search QUERY...     Search on the server for packages matching the user queries in their
                        names or abstracts. Multiple queries can be specified and they must
                        fulfilled at the same time.

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

Global Installation
-------------------

To globally install opm packages, just use the `sudo opm get foo/bar` command.

[Back to TOC](#table-of-contents)

Local Installation
------------------

When you use `--cwd` option to install packages to the `./resty_modules/` directory, then you should
put the following lines to your `nginx.conf`, inside the `http {}` block:

```nginx
lua_package_path "$prefix/resty_modules/lualib/?.lua;;";
lua_package_cpath "$prefix/resty_modules/lualib/?.so;;";
```

Do NOT change `$prefix` to a hard-coded absolute path yourself! OpenResty will automatically resolve the
special `$prefix` variable in the directive values at startup. The `$prefix` value will be resolved
to the server prefix, which will later be specified via the `-p` option of the `openresty` command
line.

And then you should start your OpenResty application from the current working directory like this:

```bash
openresty -p $PWD/
```

assuming you have the following OpenResty application directory layout in the current directory:

```
logs/
conf/
conf/nginx.conf
resty_modules/
```

Alternatively, if you just want to use the `resty` command line utility with the opm modules installed
into the `./resty_modules` directory, then you should just use the `-I ./resty_modules/lualib` option, as in

```bash
resty -I ./resty_modules/lualib -e 'require "foo.bar".go()'
```

[Back to TOC](#table-of-contents)

HTTP Proxy Support
==================

HTTP proxies are supported via the `http_proxy` and `https_proxy` system environment variables, as in

```
http_proxy [protocol://]<host>[:port]
      Sets the proxy server to use for HTTP.

https_proxy [protocol://]<host>[:port]
      Sets the proxy server to use for HTTPS.
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
requires = luajit, openresty/lua-resty-lrucache >= 0.04
```

As we can see, the `dist.ini` file is using the popular [INI file format](https://en.wikipedia.org/wiki/INI_file).
Most of the fields in this example should be self-explanatory. For detailed documentation for the fields available
in `dist.ini`, please check out the [File dist.ini](#file-distini) section.

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
to generate a tarball that is ready to upload to the remote package server. This
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

You can use UTF-8 characters in this field value. Invalid UTF-8 sequences, however,
will lead to errors in `opm build` or `opm server-build` commands.

This key is mandatory.

[Back to TOC](#table-of-contents)

version
-------

Version number for the current package.

If this key is specified, then the version number specified here will be automatically compared with
the version number extracted from the "main module" file (see the [main_module](#main_module) key for more
details).

Example:

```ini
version = 1.0.2
```

See also the [Version Number Handling](#version-number-handling) section for more details on package
version numbers.

This key is optional.

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

You can use UTF-8 characters in this field value. Invalid UTF-8 sequences, however,
will lead to errors in `opm build` or `opm server-build` commands.

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
* `ccby`

Creative Commons Attribution 4.0 International Public License
* `ccbysa`

Creative Commons Attribution-ShareAlike 4.0 International Public License
* `ccbynd`

Creative Commons Attribution-NoDerivatives 4.0 International Public License
* `ccbync`

Creative Commons Attribution-NonCommercial 4.0 International Public License
* `ccbyncsa`

Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License
* `ccbyncnd`

Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International Public License
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

All the dependency constraints specified in this key must be met at the same time when
the `opm get` or `opm build` command is run.

You can also specify version number requirements, as in

```ini
requires = foo/lua-resty-bar >= 0.3.5
```

The version comparison operators supported are `>=`, `=`, and `>`. Their
semantics is self-explanatory.

You can also specify the following special dependency names:

* `luajit`

Requires the LuaJIT component in the package user's OpenResty installation (and also the package uploader's). When
version number constraints are specified, the version number of the LuaJIT will also be checked.
* `nginx`

Requires the NGINX component in the package user's OpenResty installation (and also the package uploader's). When
version number constraints are specified, the version number of the NGINX core will also be checked.
* `openresty`

This dependency only makes sense when there is an associated version number constraint specified.
The version number of the package user's (and also uploader's) OpenResty installation must meet the version
constraint here.
* `ngx_http_lua`

Requires the ngx_http_lua_module component in the package user's OpenResty installation (and also the package uploader's).
When version number constraints are specified, the version of the installed ngx_http_lua_module will also be checked.

Below is such an example:

```ini
requires = luajit >= 2.1.0, nginx >= 1.11.2, ngx_http_lua = 0.10.6
```

or you can just specify a single `openresty` version constraint to cover them all in the example above:

```ini
requires = openresty >= 1.11.2.1
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

You must not use absolute directory paths or paths containing `..` as the value.

Default to `lib`.

This key is optional.

[Back to TOC](#table-of-contents)

exclude_files
-------------

Specifies patterns for files to be excluded during packaging via `opm bulid`.
Unix shell wildcards like `*` and `?` are supported.

Multiple patterns should be separated by commas, with optional surrounding spaces.

```ini
exclude_files=foo*.lua, bar/baz/*/*.lua, lint_config.lua
```

[Back to TOC](#table-of-contents)

main_module
-----------

This key specifies the PATH of the "main module" file of the current package.
The `opm build` command reads the "main module" file to extract the version number
of the current package, for example.

`opm build` uses simple regular expressions to find Lua code patterns like below:

```lua
_VERSION = '1.0.2'
```

```lua
version = "0.5"
```

```lua
version = 0.08
```

When this key is not specified, then `opm build` will try to find the main module
file automatically (which might be wrong though).

You must not use absolute file paths or paths containing `..` as the value.

This key is optional.

[Back to TOC](#table-of-contents)

doc_dir
-------

Specifies the root directory of the documentation files. Default to `lib`.

You must not use absolute directory paths or paths containing `..` as the value.

`opm build` always tries to collect the documentation files in either the Markdown (`.md` or `.markdown`)
or the POD (`.pod`) format.

Regardless of the value of this `doc_dir` key, `opm build` always tries to collect
the following files in the current working directory (which should be the root of
the current package):

* `README.md`, `README.markdown`, or `README.pod`
* `COPYING`
* `COPYRIGHT`
* `Changes.md`, `Changes.markdown`, or `Changes.pod`

You can use UTF-8 characters in these documentation files. Other multi-byte character
encodings must be avoided.

This key is optional.

[Back to TOC](#table-of-contents)

File .opmrc
===========

The `.opmrc` file under the current system user's home directory configures various important settings
for the current system user. Only library
authors should care about this file since commands like `opm get`, `opm search`, or `opm list` do
not need this file at all.

Like [file dist-ini](#file-distini), this file is also in the [INI file format](https://en.wikipedia.org/wiki/INI_file).
When this file is absent, the first run of the `opm build` or `opm upload` commands will automatically generate
a boilerplate file for you to fill out later yourself.

This file recognizes the following keys:

[Back to TOC](#table-of-contents)

github_account
--------------

Specifies your GitHub account name, either your GitHub user login name or
github organization that you owns.

For example, the document writer's GitHub login name is `agentzh` while he
also owns the GitHub organization `openresty`. So he can choose to upload
his packages either under the `agentzh` or `openresty` with the same GitHub
access token (defined via the [github_token](#github_token) key) by configuring
this `github_account` key.

This key is required.

[Back to TOC](#table-of-contents)

github_token
------------

Specifies your GitHub personal access token used for package uploads.

You can generate a GitHub personal access token from the GitHub [web UI](https://github.com/settings/tokens).

While you are generating your token on GitHub's web site, it is crucial to assign the right permissions (or `scopes`
in GitHub's terminology) to your token. The `opm` tool chain requires that the token must contain the `user:email`
scope. Optionally, you can also assign the `read:org` scope at the same time, which is required if you want to
upload your OpenResty packages under an organization name that you owns.

The GitHub personal access tokens are like passwords, so be very careful when handling it. Never share it with
the rest of the world otherwise anybody can upload packages to the OPM package server under *your* name.

Due to security considerations, the package server also rejects GitHub personal access tokens that are too permissive
(that is, having more scopes than needed). The package server caches a sorted hash of your tokens in its own database,
so that the server does not have to query GitHub upon subsequent uploads. Because the tokens are hashed, the package
server can only verifies that your token is correct but cannot recover your original token just from the database.

This key is required.

[Back to TOC](#table-of-contents)

upload_server
-------------

Specifies the OPM server for uploading packages. Defaults to `https://opm.openresty.org`. It is strongly recommended
to use `https` (which is the default) for communication privacy.

The official OPM package server is `https://opm.openresty.org`. You could, however, point this key to your own or
any 3rd-party servers (then you are at your own risk).

This key can have a different value than [download_server](#download_server).

[Back to TOC](#table-of-contents)

download_server
---------------

Specifies the OPM server for downloading packages. Defaults to `https://opm.openresty.org`. It is strongly recommended
to use `https` (which is the default) for communication privacy.

The official OPM package server is `https://opm.openresty.org`. You could, however, point this key to your own or
any 3rd-party servers (then you are at your own risk).

This key can have a different value than [upload_server](#upload_server).

[Back to TOC](#table-of-contents)

Version Number Handling
=======================

OPM requires all package version numbers to only consist of digits, dots, alphabetic letters, and underscores.
Only the digits part are mandatory.

OPM treats all version numbers as one or more integers separated by dots (`.`) or any other non-digit characters.
Version number comparisons are performed by comparing each integer part in the order of their appearance.
For example, the following version number comparisons hold true:

```
12 > 10
1.0.3 > 1.0.2
1.1.0 > 1.0.9
0.10.0 > 0.9.2
```

There can be some surprises when your version numbers look like decimal numbers, as in

```
0.1 < 0.02
```

This is because `0.1` is parsed as the integer pair `{0, 1}`, while `0.02` is parsed as
`{0, 2}`, so the latter is greater than the former.
To avoid such pitfalls, always specify the decimal part of the equal length, that is,
writing `0.1` as `0.10`, which is of the same length as `0.02`.

OPM does not support special releases like "release candidates" (RC) or "developer releases" yet.
But we may add such support in the future. For forward-compatibility, the package author
should avoid version numbers with suffixes like `_2` or `rc1`.

[Back to TOC](#table-of-contents)

Installation
============

For opm
-------

[OpenResty releases](https://openresty.org/en/download.html) since `1.11.2.2` already include and
install `opm` by default. So usually you do *not* need to install `opm` yourself.

It worth noting that if you are using the official OpenResty
[prebuilt linux packages](https://openresty.org/en/linux-packages.html), you should install the
[openresty-opm](https://openresty.org/en/rpm-packages.html#openresty-opm) package since the
[openresty](https://openresty.org/en/rpm-packages.html#openresty) binary package itself does not
contain `opm`.

If you really want to update to the latest version of
`opm` in the code repository, then just copy the file `bin/opm` in the repository over to
`<openresty-prefix>/bin/` where `<openresty-prefix>` is the value of the `--prefix` option of
`./configure` while you are building your OpenResty (defaults to `/usr/local/openresty/`).

```bash
# <openresty-prefix> defaults to `/usr/local/openresty/`
# unless you override it when building OpenResty yourself.
sudo cp bin/opm <openresty-prefix>/bin/
```

If you are using an older version of OpenResty that does *not* include `opm` by default, then
you should also create the following directories:

```bash
cd <openresty-prefix>
sudo mkdir -p site/lualib site/manifest site/pod
```

Note that at least OpenResty 1.11.2.1 is needed for `opm` to work properly.

To run the `opm` tool, you just need `perl`, `tar`, and `curl` to run the `opm` tool. Ensure
that your perl is not too old (should be at least `5.10.1`), and your curl supports `SNI`.

[Back to TOC](#table-of-contents)

Security Considerations
=======================

The `opm` client tool always uses HTTPS to talk to the package server, [opm.openresty.org](https://opm.openresty.org/),
by default. Both for package uploading and package downloading, as well as other web service queries for meta data.
Although it is possible for the user to manually switch to the HTTP protocol
by editing the `download_server` and/or `upload_server` keys in her own `~/.opmrc` file.
The `opm` client tool also always verifies the SSL certificates of the remote OPM package server (via `curl` right now).

Similarly, the OPM package server always uses TLS to talk to remote services provided by GitHub and Mailgun.
These remote sites' SSL certificates are also always verified on the server side. This cannot be turned off by the user.

The OPM package server uses PostgreSQL's `pgcrypto` extension to encrypt the authors' GitHub personal access tokens
in the database (we
cache the tokens in our own database to speed up subsequent uploads and improve site reliability when the GitHub API is down).
Even the server administrators cannot recover the original access tokens from the database.
The server also ensures that the author's personal token is not too permissive by rejecting such tokens.

The `opm` tool chain and server also always perform the MD5 checksum verification upon both the
downloaded and uploaded package files, to ensure data integrity when transferred over the wire.

[Back to TOC](#table-of-contents)

Credit
======

The design of the `opm` tool gets various inspirations from various existing package management systems, including but not limited to,
Perl's `cpan` and [Dist::Zilla](http://dzil.org/), RedHat's `yum`, NodeJS's `npm`, and Mac OS X's `homebrew`.

[Back to TOC](#table-of-contents)

TODO
====

* Add `opm reinstall` command to reinstall an already installed module (at the same version).
* Add `opm doctor` command to check if there is any inconsistency in the current opm package installation tree.
* Add `opm files <package>` command to list all the files in the specified package.
* Add `opm whatprovides <package>` command to find out which package the specified file belongs to.
* Add plugin mechanisms to `opm build` (similar to Perl's [Dist::Zilla](http://dzil.org/) packaging framework).
* Turn opm.openresty.org into a full-blown web site similar to search.cpan.org.
* Add support for Lua C modules and LuaJIT FFI modules with standalone C libraries.
* Add support for 3rd-party NGINX C modules (which can be compiled as NGINX dynamic modules).
* Add (limited) support for LuaRocks via the special name space `luarocks`, for example,

```bash
opm get luarocks/foo
```

[Back to TOC](#table-of-contents)

Author
======

Yichun Zhang (agentzh) <agentzh@gmail.com>, OpenResty Inc.

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2016-2020, by Yichun "agentzh" Zhang (章亦春) <agentzh@gmail.com>, OpenResty Inc.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

