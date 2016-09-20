Name
====

opm - Official package management system for OpenResty

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
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
# account is a github account (either a github user or a github org);
# lua-resty-foo is the library name under that github account.
opm get account/lua-resty-foo
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

TODO
====

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

