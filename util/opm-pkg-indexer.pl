#!/usr/bin/env perl

# Copyright (C) Yichun Zhang (agentzh)

use strict;
use warnings;
use LWP::UserAgent;

my $version = '0.0.1';

my $api_server_host = shift || "127.0.0.1";
my $api_server_port = shift || 8080;

my $ua = LWP::UserAgent->new;
$ua->agent("opm pkg indexer" . $version);

my $req = HTTP::Request->new(
    GET => "http://$api_server_host:$api_server_port/api/incoming",
);
$req->header(Host => "opm.openresty.org");

# send request
my $res = $ua->request($req);

# check the outcome
if ($res->is_success) {
    print $res->decoded_content;

} else {
    print "Error: " . $res->status_line . "\n";
}
